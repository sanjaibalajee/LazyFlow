# Releasing LazyFlow

LazyFlow ships as a signed, notarized `.dmg` that anyone can download, drag to
Applications, and open. `scripts/release.sh` does the whole thing:

```sh
scripts/release.sh                  # → dist/LazyFlow-1.0.dmg
scripts/release.sh --version 1.1.0  # override the version
scripts/release.sh --skip-notarize  # unsigned local test DMG
```

It archives Release, exports with Developer ID, verifies the signature, notarizes
and staples the app, builds the DMG, then signs, notarizes and staples the DMG too.

## Why not the Mac App Store

LazyFlow needs Accessibility to read the focused field and to paste at the cursor,
and it posts synthetic key events. Neither is possible inside the App Sandbox, so
the app is **not sandboxed** and Direct Distribution (Developer ID + notarization)
is the only route. That is what the script implements.

## One-time setup

Team: **Q78J7L8TLR** — Fanpit Technologies Private Limited (paid Apple Developer
Program, so both steps below are available on this account).

### 1. Developer ID Application certificate

The `Apple Development` certificates already in the keychain only work on machines
registered to the team — apps signed with them will not launch for anyone else. You
need a **Developer ID Application** certificate:

> Xcode ▸ Settings ▸ Accounts ▸ select the Fanpit team ▸ **Manage Certificates…**
> ▸ **+** ▸ **Developer ID Application**

Only the **Account Holder** or an **Admin** on the team can create one. If the button
is greyed out, your role is Developer — ask the Account Holder to create it, or to
raise your role in App Store Connect ▸ Users and Access.

Verify:

```sh
security find-identity -v -p codesigning | grep "Developer ID Application"
```

### 2. Notarization credentials

Create an app-specific password at
[account.apple.com](https://account.apple.com) ▸ Sign-In and Security ▸
App-Specific Passwords, then store it once:

```sh
xcrun notarytool store-credentials "LazyFlow-Notary" \
    --apple-id "you@example.com" \
    --team-id "Q78J7L8TLR" \
    --password "xxxx-xxxx-xxxx-xxxx"
```

The script looks for the profile name `LazyFlow-Notary` (override with
`--keychain-profile` or `$KEYCHAIN_PROFILE`).

## Per-release

1. Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in the project, or pass
   `--version` / `--build` to the script.
2. Run `scripts/release.sh`.
3. Publish:
   ```sh
   gh release create v1.0 dist/LazyFlow-1.0.dmg \
       --title "LazyFlow 1.0" --generate-notes
   ```

### What users see

A notarized DMG opens with no warning. **Un-notarized builds are not just a scary
dialog** — on macOS 15+ Gatekeeper refuses them outright and the right-click ▸ Open
workaround is gone; the user has to visit System Settings ▸ Privacy & Security and
click "Open Anyway". Always ship notarized.

First launch still prompts for Microphone and Accessibility. That is normal and the
onboarding flow walks through it.

### Troubleshooting notarization

```sh
xcrun notarytool history --keychain-profile "LazyFlow-Notary"
xcrun notarytool log <submission-id> --keychain-profile "LazyFlow-Notary"
```

Almost every failure is an unsigned or un-hardened nested binary. Check nested code
first:

```sh
codesign --verify --deep --strict --verbose=2 build/export/LazyFlow.app
```

**The Sparkle gotcha.** Sparkle ships `Autoupdate`, `Updater.app`,
`Downloader.xpc` and `Installer.xpc` **ad-hoc signed** (`flags=0x10002(adhoc,runtime)`),
and notarization rejects any ad-hoc signed executable. The release script re-signs
them with the Developer ID identity, inside-out (nested code first, containing
bundle last), and then fails the build if any ad-hoc code survives — so you find out
in seconds rather than after a five-minute round trip to Apple.

Two things that step must keep getting right, if you ever touch it:

- The outer app is re-signed **with `--entitlements`**. Re-sealing without it
  silently strips microphone and network access, and the app then fails at runtime
  rather than at build time.
- The glob is `Versions/[A-Z]`, not `Versions/*` — the latter also matches the
  `Current` symlink and signs everything twice.

Inspect what the built app actually carries:

```sh
codesign -d --entitlements - --xml build/export/LazyFlow.app | plutil -p -
codesign -d --verbose=2 build/export/LazyFlow.app 2>&1 | grep flags
```

## Auto-updates (Sparkle)

The updater is wired up (`UpdaterService`, "Check for Updates…" in the menu bar) but
**dormant until `SUFeedURL` is set** — the menu item reports it can't check and
nothing is fetched. Shipping the first DMG does not require any of this.

To turn it on:

1. Generate an EdDSA key pair (private key goes into your login keychain):
   ```sh
   ~/Library/Developer/Xcode/DerivedData/LazyFlow-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
   ```
   Put the printed **public** key in `LazyFlow/Info.plist` → `SUPublicEDKey`.

2. Set `SUFeedURL` to where the appcast will live. GitHub Pages on this repo works:
   `https://sanjaibalajee.github.io/LazyFlow/appcast.xml`.

3. Optionally flip `SUEnableAutomaticChecks` to `<true/>` for background checks
   (Sparkle asks the user's consent on first launch).

4. Per release, after building the DMG:
   ```sh
   .../Sparkle/bin/generate_appcast dist/     # signs and writes dist/appcast.xml
   ```
   Publish `appcast.xml` at the feed URL alongside the DMG.

Sparkle can update from a DMG, but a `.zip` of the stapled `.app` is the smaller and
more conventional update artifact — keep shipping the DMG for first-time downloads
either way.
