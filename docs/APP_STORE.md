# Mac App Store / TestFlight

ClaudeWatch ships two ways. The DMG on GitHub Releases stays unsandboxed; the App Store build is sandboxed.

| | DMG (GitHub) | App Store / TestFlight |
|---|---|---|
| Bundle ID | `com.claudewatch.ClaudeWatch` | `de.linolaske.ClaudeWatch` |
| Sandbox | no | yes (`Config/ClaudeWatch-AppStore.entitlements`) |
| Signing | ad-hoc in CI, or Developer ID + notarized (below) | Apple Development, re-signed on export |
| Built by | `.github/workflows/release.yml` | `Scripts/archive-appstore.sh` |

`com.claudewatch.ClaudeWatch` is registered to another Apple team, so the App Store build overrides the bundle ID in the script; the project keeps the old one so existing DMG installs keep their settings and Keychain items.

## Upload a TestFlight build

Prerequisites: Xcode signed in to the paid developer account (Team `J2DU2P47XW`) and the app record "LAB ClaudeWatch" in App Store Connect with bundle ID `de.linolaske.ClaudeWatch`.

```sh
Scripts/archive-appstore.sh              # archive, export and upload
Scripts/archive-appstore.sh --no-upload  # archive only (build/AppStore/ClaudeWatch.xcarchive)
Scripts/archive-appstore.sh 42           # explicit build number (default: UTC timestamp YYMMDDHHMM)
```

The build shows up in TestFlight after Apple has processed it. Internal testers need to be in an internal test group. Export compliance is answered by `ITSAppUsesNonExemptEncryption=false` in `Config/ClaudeWatch-Info.plist`.

Supporting files: `Config/ExportOptions-AppStore.plist` (method `app-store-connect`, destination `upload`) and `ClaudeWatch/PrivacyInfo.xcprivacy` (no tracking, `UserDefaults` reason `CA92.1`).

## Notarized DMG

Xcode can sign and notarize with the account, without a local Developer ID certificate or `notarytool` profile:

1. `xcodebuild archive` (Release, `DEVELOPMENT_TEAM=J2DU2P47XW`, `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`).
2. `xcodebuild -exportArchive` with `method` = `developer-id` and `destination` = `upload` triggers notarization; repeat with `destination` = `export` to get the notarized app.
3. `xcrun stapler staple ClaudeWatch.app`.
4. `Scripts/make-dmg.sh ClaudeWatch.app ClaudeWatch-<version>.dmg` (the Finder layout step needs Automation permission for the terminal, so run it in a normal terminal).
5. `gh release upload <tag> ClaudeWatch-<version>-notarized.dmg` plus its `.sha256`.

The DMG itself is not separately signed or notarized; Gatekeeper checks the stapled ticket of the app inside. `release.yml` still builds ad-hoc signed DMGs only. v0.1.3 carries both variants.

## Known gaps before an App Store release

- **Name:** "Claude" in the name, bundle ID and `claudewatch://` scheme may conflict with guidelines 4.1(c)/5.2.1. Add a "not affiliated with Anthropic" notice.
- **cswap:** account discovery starts a process and looks in `~/.local/bin` etc. That does not work in the sandbox; the app falls back to "Unknown Account".
- **Entitlements** are only applied by `Scripts/archive-appstore.sh`. Archiving from the Xcode UI would be unsandboxed and rejected; a dedicated build configuration would fix that.
- **Store metadata:** privacy policy URL, support URL, description, keywords, age rating, review notes (hooks must be configured; "Send Test Event" helps) and screenshots in an allowed size (1280×800, 1440×900, 2560×1600, 2880×1800; `docs/images` is 1136×786).
- **Sandbox runtime test:** listener on `127.0.0.1:17831`, Pushover, Keychain, login item and notifications were not tested in the sandbox yet.
