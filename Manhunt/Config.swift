import Foundation

enum Config {
    /// Your Supabase project URL (Project Settings → API).
    static let supabaseURL = URL(string: "https://YOUR-PROJECT-REF.supabase.co")!
    /// Your Supabase anon / publishable key (Project Settings → API).
    static let supabaseAnonKey = "YOUR-SUPABASE-ANON-KEY"

    /// Custom URL scheme used for invite links: manhunt://join?code=ABC123
    static let urlScheme = "manhunt"

    /// A runner in a vehicle re-broadcasts their location at most this often.
    static let vehiclePingCooldown: TimeInterval = 60
}
