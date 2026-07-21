import Foundation

enum AppConfiguration {
    // Safe client-side values only. Never place a service-role key here.
    static let supabaseURL = URL(string: "https://ticrpsnhdpncdefupsej.supabase.co")!
    static let supabasePublishableKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRpY3Jwc25oZHBuY2RlZnVwc2VqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzgyMDI1NjksImV4cCI6MjA5Mzc3ODU2OX0.x11p601XpPmOtKQ8Egwq5siP6tcs9CgT9r9gE7EizdA"
    static let websiteURL = URL(string: "https://patlaubmt.vercel.app")!

    static var isConfigured: Bool {
        !supabaseURL.absoluteString.contains("YOUR_PROJECT")
            && !supabasePublishableKey.contains("YOUR_SUPABASE")
    }
}

