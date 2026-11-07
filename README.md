# Manhunt

An iOS game of real-world hide and seek, written in SwiftUI.

- **Invite friends** with a link (`manhunt://join?code=ABC123`) or a 6-character code.
- When the host starts, everyone is **randomly split into two teams**: about half become **Hunters** and the rest are **Runners**.
- **Runners stay on foot.** If the phone's motion sensors (CoreMotion's accelerometer-based activity classifier, backed up by GPS speed) detect a vehicle, the Hunters are **pinged immediately** with the runner's location, and again every minute until the runner is back on foot.
- **Hunters get every Runner's location every 5 minutes** and are allowed to drive.
- **Caught = out.** Hunters tag a runner (or the runner admits it). Hunters win if every runner is caught; Runners win if time runs out.

## Project layout

```
project.yml                 XcodeGen spec (generates Manhunt.xcodeproj)
Manhunt/
  ManhuntApp.swift          App entry, invite-link handling, screen routing
  Config.swift              Supabase URL + key  ← fill these in
  Models.swift              Game / Player / Ping models
  Services/
    GameService.swift       Supabase auth, RPCs, realtime, runner/hunter logic
    LocationManager.swift   Background GPS
    MotionDetector.swift    Vehicle detection (CoreMotion + GPS speed)
    NotificationManager.swift  Local alerts for hunters/runners
  Views/                    Home, Lobby, Runner, Hunter, Caught, Game Over
supabase/migrations/        Database schema, security rules and game RPCs
```

## Setup

### 1. Backend (Supabase, free tier is fine)

1. Create a project at [supabase.com](https://supabase.com).
2. Open **SQL Editor**, paste `supabase/migrations/20261107000000_manhunt.sql` and run it
   (or `supabase link && supabase db push` with the CLI).
3. **Authentication → Sign In / Providers → enable "Anonymous sign-ins"** (players don't need accounts).
4. From **Project Settings → API**, copy the project URL and the anon/publishable key into `Manhunt/Config.swift`.

### 2. iOS app

Requires Xcode 15+ and iOS 17+.

```sh
brew install xcodegen
xcodegen            # creates Manhunt.xcodeproj and pulls supabase-swift via SPM
open Manhunt.xcodeproj
```

In Xcode, pick your team under **Signing & Capabilities**, change the bundle id if needed, and run on a real iPhone (the simulator has no motion sensors).
When prompted, allow **Location → Always**, **Motion & Fitness**, and **Notifications**.

## How it works

| Piece | Implementation |
| --- | --- |
| Team split | `start_game` RPC shuffles players server-side: `hunters = max(1, n/2)`, the rest are runners. |
| Fair reveals | Runners' positions are **never** stored continuously. The runner's phone only writes a `ping` every 5 minutes (aligned to the end of the head start) or when a vehicle is detected. Row-level security stops anyone from posting pings for someone else, and stops caught runners from posting at all. |
| Vehicle detection | `CMMotionActivityManager` reports `automotive` (classified from accelerometer data on the motion coprocessor). As a backup, 3 consecutive GPS fixes faster than 9 m/s (~32 km/h) also count. |
| Instant hunter alerts | Each phone subscribes to Supabase Realtime for its game. A new vehicle ping triggers a time-sensitive local notification + haptic on every hunter's phone. |
| Background | All players run continuous background location during a game, which keeps the app (and its realtime connection) alive with the phone locked. |
| Game end | `mark_caught` ends the game when the last runner is caught; `finish_if_expired` ends it when the clock runs out. |

## Known limitations / next steps

- **Custom-scheme invite links** (`manhunt://…`) open the app when tapped, but some apps don't make them clickable. The share message always includes the code as a fallback. For bulletproof links, add a domain with Universal Links (Associated Domains + an `apple-app-site-association` file).
- **Alerts rely on the app running.** If iOS kills a hunter's app, they'll miss the instant alert until they reopen it. For guaranteed delivery, add a Supabase Edge Function / database webhook on `pings` inserts that sends APNs pushes.
- **Catching is honour-based** (tag button / "I've been caught"). A proximity check (e.g. Nearby Interaction or Bluetooth) could automate it.
