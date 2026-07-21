# PatLau for iOS

Native SwiftUI companion app for the PatLau badminton management system. It connects to the same Supabase project and uses the existing deployed PatLau API for server-only operations.

Included workflows cover role-aware login, all four programmes, students, attendance, payments, 1-1 scheduling, makeup records, coach polls, parent-support chats, chatbot knowledge, announcements, reports, profile photos and password changes.

## Open on a Mac

1. Install Xcode 16 or newer on a Mac.
2. Install XcodeGen (`brew install xcodegen`).
3. Edit `PatLau/Core/AppConfiguration.swift` and set your Supabase project URL and publishable/anon key.
4. In this folder run `python3 Scripts/validate_project.py`, then `xcodegen generate`.
5. Open `PatLau.xcodeproj` in Xcode.
6. Select your Apple Development team under Signing & Capabilities.
7. Run on an iPhone simulator, then on a real iPhone.

The Supabase service-role key, Telegram tokens, OpenAI key, and webhook secrets must never be added to this app. Those remain only on Vercel/server-side.

The project is validated with its structural checker, Xcode builds, unit tests, and navigation UI tests. A signed build and the credential-dependent checklist must still be completed with disposable test accounts before release.

## Mobile design

- A native Home, Operations, and Account tab structure with role-aware navigation.
- Programme tiles open a small native directory first. Students, attendance, payments, 1-1 scheduling, makeup, coach polls, chats, and reports use adaptive cards and sheets instead of desktop tables.
- Password reset stays inside the app and signs the recovered account into the native interface. The shared account avatar immediately reflects profile-photo changes.
- Quick Access holds up to five role-authorised tools and supports adding, deleting, and drag-to-reorder customisation.
- Profile photos, password changes, user administration, search, notices, and logout are native SwiftUI experiences.
- Primary actions use a minimum 50-point touch target.
- Search, status badges, pull-to-refresh, confirmation dialogs, and dismissible notices are shared throughout.
- Server-only features—including Telegram chat replies, payment notices, and coach polls—call the same authenticated PatLau endpoints as the website.
- A clearly labelled Full Website button remains available as an in-app fallback for authorised website tools.

## Supabase

The app uses the authenticated Supabase Data API. Existing RLS policies remain the authority. Only the project URL and publishable/anon key belong in `AppConfiguration.swift`; all privileged secrets remain server-side.

## Verification

Run these commands after changing Swift sources or `project.yml`:

```sh
python3 Scripts/validate_project.py
xcodegen generate
xcodebuild -project PatLau.xcodeproj -scheme PatLau -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Then run Product → Test in Xcode and complete `MANUAL_TEST_CHECKLIST.md` with non-production test accounts.
