# Maison

A native iOS app (SwiftUI, Liquid Glass) that understands your home and acts for you, on top of [Home Assistant](https://www.home-assistant.io): Home Assistant collects, Maison understands and acts. The direction is in [`ROADMAP.md`](ROADMAP.md).

- **Local first**: the app talks directly to the household's Home Assistant server. When the local address doesn't answer within a few seconds, it switches on its own to the remote one: the external URL set in Home Assistant (Tailscale, a domain), otherwise Home Assistant Cloud's remote access. The same sign-in works through both.
- **Presence**: once allowed, the iPhone registers with Home Assistant as a mobile app and reports significant location changes, so rules like "When everyone leaves" work. It can be turned off in Settings, and signing out stops it.
- **Automations run on the server**, not on the iPhone.
- **Household sharing through iCloud** (CloudKit) for app-specific data.

> Personal project, work in progress.

## Getting started

The Xcode project is generated from [`project.yml`](project.yml) with [XcodeGen](https://github.com/yonaskolb/XcodeGen) and is not checked in.

```sh
brew install xcodegen
xcodegen generate
open Maison.xcodeproj
```

Requires Xcode 26 or later and targets iOS 26.

To try the app without a server, launch it with the `-demo` argument (Scheme → Run → Arguments): it fills every screen with the sample home from the design mock-ups. The base language is English, with a French localization in the string catalogs under `Maison/Resources`.

## Layout

```
Maison/
  App/                 entry point, tab navigation
  DesignSystem/        colour tokens, typography, cards, rings, gauges
  Features/            Home, Rooms, Automations, Settings, device sheets
  Core/HomeAssistant/  discovery, OAuth, WebSocket client, registries
  Core/Analytics/      usage events; off unless a PostHog project token is set
  Core/Devices/        device kinds, inline controls, presentation
  Resources/           illustrations, colours, string catalogs
MaisonTests/      tests (Swift Testing)
ci/               export options and helper scripts for GitHub Actions
```

## Product analytics

Usage events go to PostHog in the EU (`https://eu.i.posthog.com`). The project token is not in the repo. With none set, the app records nothing, so CI and a fresh checkout keep working.

- **On your Mac:** copy [`Config/Secrets.xcconfig.example`](Config/Secrets.xcconfig.example) to `Config/Secrets.xcconfig` and set `POSTHOG_API_KEY`. That file is gitignored. Use the project token (`phc_…`) from the EU project's settings, never a personal key (`phx_…`).
- **TestFlight:** repository secret `POSTHOG_API_KEY`. The release workflow passes it to `xcodebuild`. If the secret is missing, the upload still runs and analytics stays off.

Xcode writes that setting into Info.plist as `PostHogAPIKey`. Settings → Share Usage Data is on by default and turns capture off.

## Household sharing

The household lives in a CloudKit zone (`Household`) in the owner's private database of `iCloud.com.theodaguier.maison`, shared as a whole with a zone-wide `CKShare`. It holds the household (name, server URLs) and one `MemberFavorites` record per member — never device state. A share doesn't grant Home Assistant access: everyone signs in with their own Home Assistant account.

- **Invite**: Settings → Household → Invite Someone adds the person's iCloud email or phone number to the share as Resident (`privateUser`) or Administrator (`administrator`), then hands the link to the share sheet.
- **Accept**: opening the link calls `SceneDelegate`, which accepts the share; the connect screen then offers the household's server.
- **Favourites** stay in `UserDefaults` as a fallback and are mirrored to iCloud when an account is available.

CloudKit calls go through the `HouseholdCloud` protocol; tests use an in-memory fake. Unsigned builds (`CODE_SIGNING_ALLOWED=NO`, as in CI) have no iCloud entitlement, so the app keeps everything on the device there.

The record types are created in the Development environment the first time a debug build saves them. Before a TestFlight build can use them, deploy the schema to Production in the [CloudKit Console](https://icloud.developer.apple.com) (Schema → Deploy Schema Changes).

## Continuous integration and delivery

| Workflow | Trigger | What it does |
| --- | --- | --- |
| [`CI`](.github/workflows/ci.yml) | push to `main`, pull requests | generates the project, builds, runs the tests on a simulator |
| [`TestFlight`](.github/workflows/release.yml) | `v*` tag or manual run | archives a Release build and uploads it to TestFlight |

The marketing version comes from the tag (`v0.2.0` → `0.2.0`) and the build number from the GitHub run counter.

```sh
git tag v0.1.0 && git push origin v0.1.0
```

### Secrets required for TestFlight

| Secret | Content |
| --- | --- |
| `APPLE_TEAM_ID` | Apple Developer team ID (10 characters) |
| `ASC_KEY_ID` | key ID of the App Store Connect API key |
| `ASC_ISSUER_ID` | issuer ID of the API key |
| `ASC_KEY_P8` | full content of the `AuthKey_XXXX.p8` file |
| `DIST_CERT_P12` | Apple Distribution certificate, base64-encoded `.p12` |
| `DIST_CERT_PASSWORD` | password of that `.p12` |
| `POSTHOG_API_KEY` | optional PostHog project token (`phc_…`) for the EU project. Without it the archive still uploads and analytics stays off. |

Two scripts store them through `gh` without printing them:

```sh
./ci/setup-testflight.sh ~/Downloads/AuthKey_XXXX.p8 <issuer-id>
./ci/setup-signing-certificate.sh ~/Desktop/distribution.p12
```

Create the API key in App Store Connect → *Users and Access* → *Integrations* → *App Store Connect API* with the **App Manager** role. The app `com.theodaguier.maison` must exist in App Store Connect before the first upload.

The build is signed with a real Apple Distribution certificate rather than cloud-managed signing: cloud signing writes the certificate name into the code requirement with a decomposed accented character, which App Store Connect then rejects (error 90035) when the account name contains one.
