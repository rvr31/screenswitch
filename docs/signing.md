# Signing and notarization

Releases are signed ad hoc until five repository secrets exist. Once they do, the Release workflow signs the app and the CLI with a Developer ID, sends both to Apple for notarization and staples the ticket to the app. A notarized download opens without the "Apple could not verify" warning.

This setup happens once, on the Mac that holds the Apple Developer account. Steps marked **you** involve passwords or Apple's web pages. Do those by hand, not through an agent.

## What the workflow expects

| Secret | Value |
| --- | --- |
| `MACOS_CERT_P12` | The Developer ID Application certificate and its private key, as a base64 `.p12` |
| `MACOS_CERT_PASSWORD` | The password you gave the `.p12` on export |
| `APPLE_ID` | The Apple ID email of the developer account |
| `APPLE_APP_PASSWORD` | An app-specific password for that Apple ID |
| `APPLE_TEAM_ID` | The 10-character team ID |

With `MACOS_CERT_P12` empty, the workflow skips signing and notarization. With the certificate set but notarization failing, the run fails and publishes nothing; the log shows Apple's reason.

## Steps

1. Get the repo and check that `gh` is logged in as `rvr31`:

   ```bash
   gh repo clone rvr31/screenswitch && cd screenswitch && gh auth status
   ```

2. Find the certificate:

   ```bash
   security find-identity -v -p codesigning
   ```

   You need a line with `Developer ID Application: <name> (<TEAMID>)`. The part in parentheses is `APPLE_TEAM_ID`. An `Apple Development` certificate does not work for this.

   No Developer ID line? **You:** in Xcode, open Settings > Accounts, select the team, click Manage Certificates, then + > Developer ID Application. Only the account holder can create one.

3. **You:** export the certificate. Open Keychain Access, go to login > My Certificates, right-click `Developer ID Application: …` (expand it to check a private key sits under it), choose Export, save as `~/Desktop/developer-id.p12` and set a password.

4. **You:** create an app-specific password at [account.apple.com](https://account.apple.com) under Sign-In and Security > App-Specific Passwords. Name it `screenswitch-notarize`.

5. **You:** store the secrets. Each `gh secret set` without a value prompts for it, so nothing lands in shell history:

   ```bash
   base64 -i ~/Desktop/developer-id.p12 | gh secret set MACOS_CERT_P12 -R rvr31/screenswitch
   ```

   ```bash
   gh secret set MACOS_CERT_PASSWORD -R rvr31/screenswitch
   ```

   ```bash
   gh secret set APPLE_ID -R rvr31/screenswitch
   ```

   ```bash
   gh secret set APPLE_APP_PASSWORD -R rvr31/screenswitch
   ```

   ```bash
   gh secret set APPLE_TEAM_ID -R rvr31/screenswitch
   ```

6. Delete the exported file:

   ```bash
   rm ~/Desktop/developer-id.p12
   ```

7. Start a release and watch it. A manual run publishes the next patch version, the same as a push to `main`:

   ```bash
   gh secret list -R rvr31/screenswitch
   ```

   ```bash
   gh workflow run release.yml -R rvr31/screenswitch
   ```

   ```bash
   gh run watch -R rvr31/screenswitch --exit-status "$(gh run list -R rvr31/screenswitch --limit 1 --json databaseId --jq '.[0].databaseId')"
   ```

   The Import Developer ID certificate and Notarize steps should run, not show as skipped. Notarization usually takes one to five minutes.

8. Check the published app:

   ```bash
   mkdir -p /tmp/ss-check && cd /tmp/ss-check && gh release download -R rvr31/screenswitch --pattern 'ScreenSwitch-*.zip' --clobber && ditto -x -k ScreenSwitch-*.zip . && spctl -a -vv ScreenSwitch.app && xcrun stapler validate ScreenSwitch.app
   ```

   `spctl` should print `accepted` and `source=Notarized Developer ID`. Then download the zip in a browser, open the app, and confirm macOS asks at most "downloaded from the internet, open?" instead of blocking it.

9. Remove the quarantine step from Install in `README.md`, since a notarized app no longer needs it. Pushing that change to `main` publishes the next notarized release.

## When it fails

- `MACOS_CERT_P12 holds no Developer ID Application identity`: the `.p12` has the wrong certificate or no private key. Export again from My Certificates, not from Certificates.
- `security import` fails with a password error: `MACOS_CERT_PASSWORD` does not match the export password.
- notarytool `401` or `Invalid credentials`: check `APPLE_ID`, `APPLE_APP_PASSWORD` and `APPLE_TEAM_ID`. App-specific passwords stop working when the Apple ID password changes.
- Notarization `Invalid`: the run prints Apple's log. The usual cause is a binary without the hardened runtime or a secure timestamp; `build-app.sh` and the workflow add both when `SIGN_IDENTITY` is set.
- The certificate expires after five years. Repeat steps 3, 5 and 6 with the new one.
