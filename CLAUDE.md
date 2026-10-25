# Maison

Rules for coding agents. The direction is in [`ROADMAP.md`](ROADMAP.md); how the app runs today is in [`README.md`](README.md).

Native iOS app, SwiftUI, Liquid Glass. It targets iOS 26 and Swift 6, and needs Xcode 26. The Xcode project is generated from `project.yml` and is not checked in.

## V1

V1 is three scores — Comfort, Energy, Network — and housekeeping, room by room, behind one abstract, brand-agnostic source boundary. Home Assistant is the first connector, not the product, and for now the only one. No screen reads a source directly: every source goes through the intelligence layer. Today's screens still read `HomeStore` directly; that gap is known, so do not widen a change to fix it.

Documents in V1 are only energy and box documents: an energy bill, an internet-box bill, an energy contract, a box contract. They feed Energy or Network. Nothing else on paper is in V1.

Housekeeping tasks belong to a room and follow its type (living room, kitchen, bedroom, bathroom, entrance, office, laundry, outdoor, other). Never a task for an object: an oven, a fridge or a mattress waits with the inventory.

Objects and consumables are parked. Do not build them, including where the roadmap still describes an inventory. That means durables and consumables, the replacement cycle and its reminders, an emoji chosen for an object, warranties, manuals, insurance, leases, and scan-from-object or scan-from-home matching. See [`ROADMAP.md`](ROADMAP.md).

Keep the scope tight. Do not add a feature that is not asked for.

## Sources

Every feature works with no special hardware, and improves when a compatible source exists. No "not supported", no empty screen.

The same capability is provided by interchangeable sources:

- **iPhone only**
- **Common sources**
- **Specialised sources**: a box, a router, a meter, reached through their Home Assistant integration

Do not write a connector for a brand (a Freebox, a Linky, a Netatmo). The source boundary stays generic: no type, name or screen outside the Home Assistant connector depends on Home Assistant or on a brand.

A value the person enters is a starting point. A sensor replaces it on its own when one appears.

## Storage

Use GRDB, not SwiftData. The intelligence layer is one Swift package for iOS and for the Linux add-on, and SwiftData does not build on Linux. Neither library is in the tree yet.

The package produces structured facts — a kind, values, units, the entities involved — never sentences. Wording and translation stay on the iPhone.

## Documents and numbers

Read a document on the device only, with Apple Intelligence (`FoundationModels`), in any language. Do not send a document, a summary, or a rule to a cloud model.

The model only words a text. The code validates every value and tags its origin: measured, estimated, or entered. `GroundedNumbers` rejects a number that is not in the facts; `RuleDraft.proposal` checks every value in a rule. Follow that. When the on-device model cannot run — it is off, or it does not support the language (`Intelligence.isAvailable`) — keep a short written form. Do not drop the value.

## Interface

SF Symbols for every control and status (`Image(systemName:)`, `Label` with `systemImage:`). An emoji only identifies an object, and object identity is parked, so V1 has none.

## Data

Local first. CloudKit (`iCloud.com.theodaguier.maison`, zone `Household`) is only for what the household shares: its name, the server's addresses, favourites, and the plan. Never a device's state or history. Home Assistant credentials stay in the keychain. The one exception is the first sign-in of someone invited (`MemberAccess`): a one-time password, end-to-end encrypted, replaced on the server and cleared once used. Unsigned builds (`CODE_SIGNING_ALLOWED=NO`, as in CI) have no iCloud entitlement; tests use the in-memory `HouseholdCloud` fake.

## Changes

Every change comes with unit tests in `MaisonTests` (Swift Testing). CI must pass. The check is **Tests unitaires**, the `unit` job in [`.github/workflows/tests.yml`](.github/workflows/tests.yml).

Work on a branch and open a pull request. Never push to `main`.

## Build and test

The test workflow runs on `macos-26`. It selects Xcode 26 with `./ci/select-xcode.sh`, generates the project, then runs the unit tests:

```sh
export HOMEBREW_NO_AUTO_UPDATE=1
brew install xcodegen xcbeautify
xcodegen generate
UDID="$(./ci/simulator-udid.sh)"
mkdir -p build
set -o pipefail
xcodebuild test \
  -project Maison.xcodeproj \
  -scheme Maison \
  -destination "id=$UDID" \
  -derivedDataPath DerivedData \
  -resultBundlePath build/Tests.xcresult \
  -only-testing:MaisonTests \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee build/xcodebuild.log | xcbeautify --renderer github-actions
```

To open the app after `xcodegen generate`: `open Maison.xcodeproj`. The `-demo` launch argument fills the screens with the sample home.
