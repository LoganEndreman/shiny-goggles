-- Manhunt backend schema.
-- Run this in the Supabase SQL editor (or `supabase db push`), then enable
-- Authentication → Providers → Anonymous sign-ins.

-- ─── Tables ────────────────────────────────────────────────────────────────

create table public.games (
  id                    uuid primary key default gen_random_uuid(),
  code                  text not null unique,
  host_id               uuid not null references auth.users (id) on delete cascade,
  status                text not null default 'lobby' check (status in ('lobby', 'active', 'ended')),
  duration_minutes      int  not null default 60  check (duration_minutes between 5 and 600),
  head_start_minutes    int  not null default 5   check (head_start_minutes between 0 and 60),
  ping_interval_seconds int  not null default 300 check (ping_interval_seconds between 30 and 3600),
  started_at            timestamptz,
  ends_at               timestamptz,
  winner                text check (winner in ('runners', 'hunters')),  -- null + ended = cancelled
  created_at            timestamptz not null default now()
);

create table public.players (
  game_id   uuid not null references public.games (id) on delete cascade,
  user_id   uuid not null references auth.users (id) on delete cascade,
  name      text not null check (char_length(name) between 1 and 24),
  role      text check (role in ('runner', 'hunter')),
  caught_at timestamptz,
  joined_at timestamptz not null default now(),
  primary key (game_id, user_id)
);

-- Runner locations are ONLY stored as pings: one every 5 minutes, plus an
-- immediate one whenever the runner's phone detects they are in a vehicle.
create table public.pings (
  id         bigint generated always as identity primary key,
  game_id    uuid not null references public.games (id) on delete cascade,
  runner_id  uuid not null references auth.users (id) on delete cascade,
  latitude   double precision not null,
  longitude  double precision not null,
  kind       text not null check (kind in ('scheduled', 'vehicle')),
  created_at timestamptz not null default now()
);
create index pings_game_created_idx on public.pings (game_id, created_at desc);

-- ─── Helpers ───────────────────────────────────────────────────────────────

create or replace function public.is_member(p_game_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from players where game_id = p_game_id and user_id = auth.uid());
$$;

create or replace function public.generate_game_code()
returns text language plpgsql set search_path = public as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';  -- no 0/O/1/I
  result text;
begin
  loop
    result := '';
    for i in 1..6 loop
      result := result || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from games where code = result);
  end loop;
  return result;
end $$;

-- ─── Row level security ────────────────────────────────────────────────────
-- Clients can only READ games they belong to. All writes except pings go
-- through the security-definer RPCs below.

alter table public.games   enable row level security;
alter table public.players enable row level security;
alter table public.pings   enable row level security;

create policy "members read games"   on public.games   for select using (public.is_member(id));
create policy "members read players" on public.players for select using (public.is_member(game_id));
create policy "members read pings"   on public.pings   for select using (public.is_member(game_id));

create policy "active runners post pings" on public.pings for insert with check (
  runner_id = auth.uid()
  and exists (
    select 1 from public.players p join public.games g on g.id = p.game_id
    where p.game_id = pings.game_id
      and p.user_id = auth.uid()
      and p.role = 'runner'
      and p.caught_at is null
      and g.status = 'active'
  )
);

-- ─── RPCs ──────────────────────────────────────────────────────────────────

create or replace function public.create_game(p_name text, p_duration int, p_head_start int)
returns public.games language plpgsql security definer set search_path = public as $$
declare g games;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  insert into games (code, host_id, duration_minutes, head_start_minutes)
  values (generate_game_code(), auth.uid(), p_duration, p_head_start)
  returning * into g;
  insert into players (game_id, user_id, name) values (g.id, auth.uid(), trim(p_name));
  return g;
end $$;

create or replace function public.join_game(p_code text, p_name text)
returns public.games language plpgsql security definer set search_path = public as $$
declare g games;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  select * into g from games where code = upper(trim(p_code));
  if not found then raise exception 'No game with code %', upper(trim(p_code)); end if;
  if exists (select 1 from players where game_id = g.id and user_id = auth.uid()) then
    return g;  -- rejoining
  end if;
  if g.status <> 'lobby' then raise exception 'That game has already started'; end if;
  insert into players (game_id, user_id, name) values (g.id, auth.uid(), trim(p_name));
  return g;
end $$;

-- Host starts the game: everyone is shuffled and auto-split into two teams.
-- Hunters = floor(n / 2) (at least 1), the rest are runners.
create or replace function public.start_game(p_game_id uuid)
returns public.games language plpgsql security definer set search_path = public as $$
declare
  g games;
  n int;
  hunter_count int;
begin
  select * into g from games where id = p_game_id for update;
  if not found then raise exception 'Game not found'; end if;
  if g.host_id <> auth.uid() then raise exception 'Only the host can start the game'; end if;
  if g.status <> 'lobby' then raise exception 'Game already started'; end if;

  select count(*) into n from players where game_id = p_game_id;
  if n < 2 then raise exception 'You need at least 2 players'; end if;
  hunter_count := greatest(1, n / 2);

  with shuffled as (
    select user_id, row_number() over (order by random()) as rn
    from players where game_id = p_game_id
  )
  update players p
     set role = case when s.rn <= hunter_count then 'hunter' else 'runner' end
    from shuffled s
   where p.game_id = p_game_id and p.user_id = s.user_id;

  update games
     set status = 'active',
         started_at = now(),
         ends_at = now() + make_interval(mins => head_start_minutes + duration_minutes)
   where id = p_game_id
  returning * into g;
  return g;
end $$;

-- A hunter tags a runner, or a runner admits they were caught.
create or replace function public.mark_caught(p_game_id uuid, p_runner_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  g games;
  caller_role text;
begin
  select * into g from games where id = p_game_id for update;
  if not found or g.status <> 'active' then raise exception 'Game is not active'; end if;

  select role into caller_role from players where game_id = p_game_id and user_id = auth.uid();
  if caller_role is null then raise exception 'You are not in this game'; end if;
  if p_runner_id <> auth.uid() and caller_role <> 'hunter' then
    raise exception 'Only hunters can tag runners';
  end if;

  update players set caught_at = now()
   where game_id = p_game_id and user_id = p_runner_id and role = 'runner' and caught_at is null;
  if not found then raise exception 'That runner is not in play'; end if;

  if not exists (select 1 from players where game_id = p_game_id and role = 'runner' and caught_at is null) then
    update games set status = 'ended', winner = 'hunters' where id = p_game_id;
  end if;
end $$;

-- Any member may call this; it only ends the game once time has run out.
create or replace function public.finish_if_expired(p_game_id uuid)
returns void language sql security definer set search_path = public as $$
  update games set status = 'ended', winner = 'runners'
   where id = p_game_id and status = 'active' and ends_at <= now() and is_member(p_game_id);
$$;

-- Leaving only matters in the lobby. If the host leaves, the game is cancelled.
create or replace function public.leave_game(p_game_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare g games;
begin
  select * into g from games where id = p_game_id for update;
  if not found or g.status <> 'lobby' then return; end if;
  if g.host_id = auth.uid() then
    update games set status = 'ended', winner = null where id = p_game_id;
  else
    delete from players where game_id = p_game_id and user_id = auth.uid();
  end if;
end $$;

revoke all on function public.generate_game_code() from public, anon, authenticated;
revoke all on function public.create_game(text, int, int)    from public, anon;
revoke all on function public.join_game(text, text)          from public, anon;
revoke all on function public.start_game(uuid)               from public, anon;
revoke all on function public.mark_caught(uuid, uuid)        from public, anon;
revoke all on function public.finish_if_expired(uuid)        from public, anon;
revoke all on function public.leave_game(uuid)               from public, anon;
grant execute on function public.create_game(text, int, int) to authenticated;
grant execute on function public.join_game(text, text)       to authenticated;
grant execute on function public.start_game(uuid)            to authenticated;
grant execute on function public.mark_caught(uuid, uuid)     to authenticated;
grant execute on function public.finish_if_expired(uuid)     to authenticated;
grant execute on function public.leave_game(uuid)            to authenticated;

-- ─── Realtime ──────────────────────────────────────────────────────────────
alter publication supabase_realtime add table public.games, public.players, public.pings;
