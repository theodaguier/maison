# Maison

A native iOS app (SwiftUI, Liquid Glass) for controlling a [Home Assistant](https://www.home-assistant.io) setup: the power of Home Assistant with the simplicity of Apple Home.

- **Local first**: the app talks directly to the household's Home Assistant server; remote access goes through Tailscale.
- **Automations run on the server**, not on the iPhone.
- **Household sharing through iCloud** (CloudKit) for app-specific data.

> Personal project, work in progress. Nothing is wired to Home Assistant yet: the navigation structure and the device model are in place.

## Getting started

The Xcode project is generated from [`project.yml`](project.yml) with [XcodeGen](https://github.com/yonaskolb/XcodeGen) and is not checked in.

```sh
brew install xcodegen
xcodegen generate
open Maison.xcodeproj
```

Requires Xcode 26 or later and targets iOS 26. The base language is English, with a French localization in the string catalogs under `Maison/Resources`.

## Layout

```
Maison/
  App/            entry point, tab navigation
  Features/       Home, Rooms, Automations, Settings
  Core/Devices/   Home Assistant device kinds and their inline controls
  Resources/      asset catalog, string catalogs
MaisonTests/      tests (Swift Testing)
ci/               export options and helper scripts for GitHub Actions
```

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

Two scripts store them through `gh` without printing them:

```sh
./ci/setup-testflight.sh ~/Downloads/AuthKey_XXXX.p8 <issuer-id>
./ci/setup-signing-certificate.sh ~/Desktop/distribution.p12
```

Create the API key in App Store Connect → *Users and Access* → *Integrations* → *App Store Connect API* with the **App Manager** role. The app `com.theodaguier.maison` must exist in App Store Connect before the first upload.

The build is signed with a real Apple Distribution certificate rather than cloud-managed signing: cloud signing writes the certificate name into the code requirement with a decomposed accented character, which App Store Connect then rejects (error 90035) when the account name contains one.
