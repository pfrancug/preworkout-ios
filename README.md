# PreWorkout for iOS

Native SwiftUI client for **PreWorkout**, a personal training and nutrition tracker:
body weight and macros, calendar activities, training plans, workout logs and an
exercise library. The app talks to the existing PreWorkout API (`/api/*`) and uses
the same data as the web app; there is no separate backend.

## Features

| Tab | Available now | Planned |
| --- | --- | --- |
| **Workouts** | Workout log grouped by month, details, create / edit / delete sessions with exercises and sets (reps, hold, distance / time, added kg, assistance, RPE, RIR, rest, warm-up, notes) | Live workout (clock, rest timer, Live Activity), starting a session from a plan day |
| **Exercises** | Library with full-text search and filters, details (muscles, equipment, aliases, progression chain, variants, description, sources), alias editing, custom exercises: create, edit, archive, delete | Muscle map |
| **Profile** | Person switch, profile editing, language shortcut, server and version info, sign-out | Preferences |

Dashboard, diary, calendar, training plans and AI features are not in the app yet.

UI language: Polish (development language) and English, from a String Catalog
(`Localizable.xcstrings`). The app follows the iOS per-app language setting
(**Settings › PreWorkout › Language**); there is no in-app switch.

## Tech stack

- Swift, SwiftUI, Observation; iOS 17+, iPhone
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): the Xcode project is generated from `project.yml` and not committed
- `URLSession` + `Codable` API client; sign-in with the web app password, session kept as the server's signed httpOnly cookie
- No third-party runtime dependencies
- GitHub Actions for compile checks and TestFlight uploads

## Project structure

```
project.yml                  XcodeGen spec (target, Info.plist, build settings)
ci/ExportOptions.plist       App Store Connect export / upload options
.github/workflows/ios.yml    compile check or signed TestFlight upload
PreWorkout/
  App/                       entry point, AppState (session, people, active person), tab bar
  Core/API/                  APIClient, typed endpoints, server address
  Core/Models/               Codable models matching the API
  Core/Components/           exercise store and picker, form fields, Markdown text
  Core/Util/                 formatting, enum labels, loading state view
  Features/
    Auth/                    sign-in
    Workouts/                workout list, details, editor
    Exercises/               library, details, editor, aliases
    Profile/                 profile, person switch, app info
  Resources/                 assets, Localizable.xcstrings, InfoPlist.strings
tools/build_xcstrings.py     regenerates the String Catalog from tools/strings_en.py
```

## Configuration

The API address is not stored in the repository. It is read from the build setting
`API_BASE_URL` (written to `Info.plist` as `APIBaseURL`):

- CI sets it from the `API_BASE_URL` repository secret.
- Local builds: pass it to `xcodebuild` or set it in the generated project.
- Without it, the sign-in screen asks for the server address; an address entered
  there overrides the built-in one.

## Building locally

Requirements: Xcode 26 (iOS 26 SDK) and XcodeGen (`brew install xcodegen`).

```sh
xcodegen generate
open PreWorkout.xcodeproj
```

Select your development team in Signing & Capabilities, set `API_BASE_URL` if you
want a default server, and run on a device or simulator.

## Translations

Strings are written in Polish in the code (`Text("Zapisz")`,
`String(localized: …)`). English lives in `tools/strings_en.py`;
`python3 tools/build_xcstrings.py` checks that every localizable literal has a
translation and rewrites `PreWorkout/Resources/Localizable.xcstrings`. Strings can
also be edited directly in Xcode's String Catalog editor.

## CI and releases

The `iOS` workflow runs only when started on purpose; pushes and pull requests do
not trigger it:

- **Actions → iOS → Run workflow**, `upload` unchecked: unsigned compile check.
- **Run workflow** with `upload` checked, or **push a tag `vX.Y.Z`**: signed archive
  and upload to TestFlight. The version comes from the tag, the build number from
  the workflow run number.

Signing uses Xcode automatic signing with an App Store Connect API key. Required
secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `APPLE_TEAM_ID`, `BUNDLE_ID`,
`API_BASE_URL`.

## Roadmap

- **0.1**: sign-in and read-only screens
- **0.2**: workouts, exercise library and profile with editing; Polish / English
- **0.3**: live workout with timers, haptics and a Live Activity for the rest timer
- **0.4**: training plans (list, editor, activation), diary, calendar
- **0.5**: dashboard charts, offline cache
- **Later**: muscle map, AI features when enabled on the server, widgets, HealthKit

## License

Copyright (c) 2026 Piotr Francug. All rights reserved. The source is visible for
reference only; copying, modifying, distributing or using it is not permitted.
See [LICENSE](LICENSE).
