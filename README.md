# PreWorkout for iOS

Native SwiftUI client for **PreWorkout**, a personal training and nutrition tracker:
body weight and macros, calendar activities, training plans, workout logs and an
exercise library. The app talks to the existing PreWorkout API (`/api/*`) and uses
the same data as the web app; there is no separate backend.

## Features

| Tab | Available now | Planned |
| --- | --- | --- |
| **Dashboard** | Weight, nutrition and training stats for 7 / 28 / 90 days | Charts, today overview, live workout card |
| **Diary** | Daily weight, kcal and macros (read-only) | Adding and editing entries |
| **Training** | Workout log with sets, training plans with targets | Live workout (clock, rest timer, set entry, Live Activity), workout and plan editors |
| **Calendar** | Day view: activities, logged workouts, day note | Month grid, adding and editing entries |
| **More** | Person switch, exercise library search and details, calorie calculator with saving the daily goal, profile editing, activity categories, sign-out | Muscle map, preferences, custom exercises |

UI language: Polish (source) and English.

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
  Core/Util/                 date / number formatting, loading state view
  Features/
    Auth/                    sign-in
    Dashboard/               stats
    Diary/                   weight and macros
    Training/                workouts, plans, live workout
    Calendar/                day view
    More/                    exercises, muscles, calculator, profile, categories
  Resources/                 assets (app icon, accent color), localizations
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

- **0.1**: sign-in and read-only screens, profile, calculator, daily goal
- **0.2**: native polish, charts, complete Polish / English strings
- **0.3**: live workout with timers, haptics and a Live Activity for the rest timer
- **0.4**: diary editing, workout editor, calendar month view
- **0.5**: plan editor, custom exercises, offline cache
- **Later**: muscle map, AI features when enabled on the server, widgets, HealthKit

## License

Copyright (c) 2026 Piotr Francug. All rights reserved. The source is visible for
reference only; copying, modifying, distributing or using it is not permitted.
See [LICENSE](LICENSE).
