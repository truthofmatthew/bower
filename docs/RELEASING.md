# Releasing Bower

`./release.sh` builds Bower, signs it with your Developer ID, has Apple notarize it, staples the ticket and publishes
`Bower.zip` as a GitHub release, so it opens on anyone's Mac without the "Open Anyway" step. It needs two things set
up once on your Mac; after that a release is one command.

## Once: 1. A Developer ID certificate

This needs a paid [Apple Developer Program](https://developer.apple.com/programs/) membership, and the team's
Account Holder role (Bower's team is `3GHX277DW6`).

1. Open Xcode › Settings › Accounts, choose your Apple ID, then the team.
2. Click **Manage Certificates…**, then **+**, then **Developer ID Application**.
3. Check it's there: `security find-identity -v -p codesigning` lists "Developer ID Application: …".

## Once: 2. Notarization credentials

1. At [account.apple.com](https://account.apple.com) › Sign-In and Security › **App-Specific Passwords**, make one
   called "Bower notarization" and copy it.
2. In Terminal, run the command below with your Apple ID. It asks for that password and keeps it in your keychain
   as `bower-notary`; nothing is written to the repo.

```bash
xcrun notarytool store-credentials bower-notary --apple-id YOUR_APPLE_ID --team-id 3GHX277DW6
```

## Every release

1. Set `MARKETING_VERSION` (and bump `CURRENT_PROJECT_VERSION`) in `project.yml`, update What's New in
   `Sources/Lessons.swift`, and commit.
2. Run `./release.sh`, or `./release.sh notes.md` with your own release notes.
   - If that version's release already exists, only its `Bower.zip` is replaced. Running it now re-publishes 1.2,
     notarized.
3. People who turned on "Check for updates automatically" (Settings › General › Updates) hear about it within a
   day; anyone can choose Help › Check for Updates in Bower's menu.

The download link everyone uses never changes:
`https://github.com/truthofmatthew/bower/releases/latest/download/Bower.zip`

Once a notarized release is out, the "Open Anyway" step can come off the site, the README and the release notes.
