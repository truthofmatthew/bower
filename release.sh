#!/bin/zsh
# Builds Bower and publishes Bower.zip as a GitHub release for the version in project.yml. With a Developer ID
# certificate (paid Apple Developer Program) it's also notarized, so it opens anywhere without a warning; without
# one it's signed with your Apple Development certificate and people choose Open Anyway once.
# Run it after committing; see docs/RELEASING.md.
#
#   ./release.sh                     # notes written by GitHub from the commits
#   ./release.sh path/to/notes.md    # your own release notes
#
# If the version's release already exists, only its Bower.zip is replaced.
set -euo pipefail
cd "$(dirname "$0")"

PROFILE=${NOTARY_PROFILE:-bower-notary}
IDENTITY="Developer ID Application"
NOTARIZE=1
VERSION=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
OUT=build/release
APP=$OUT/dd/Build/Products/Release/Bower.app
fail() { echo "✗ $1" >&2; exit 1; }

# Everything that can be missing is checked before anything is built.
if ! security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  IDENTITY="Apple Development"; NOTARIZE=0
  security find-identity -v -p codesigning | grep -q "$IDENTITY" || fail "No code-signing certificate. Open the project in Xcode once and sign in with your Apple ID."
  echo "! No Developer ID certificate: publishing without notarization. People choose Open Anyway once."
else
  xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
    || fail "No notarization credentials saved as \"$PROFILE\". docs/RELEASING.md, step 2."
fi
gh auth status >/dev/null 2>&1 || fail "GitHub CLI isn't signed in: gh auth login"
[[ -z "$(git status --porcelain -- Sources project.yml)" ]] || fail "Commit your changes first: a release is built from what's committed."
[[ -n "$VERSION" ]] || fail "No MARKETING_VERSION in project.yml."

echo "→ Building Bower $VERSION"
rm -rf "$OUT"
xcodegen generate --quiet
xcodebuild -project Bower.xcodeproj -scheme Bower -configuration Release -derivedDataPath "$OUT/dd" -quiet \
  CODE_SIGN_IDENTITY="$IDENTITY" OTHER_CODE_SIGN_FLAGS="--timestamp" build
codesign --verify --deep --strict "$APP"

if (( NOTARIZE )); then
  echo "→ Notarizing (usually a few minutes)"
  ditto -c -k --keepParent "$APP" "$OUT/upload.zip"
  xcrun notarytool submit "$OUT/upload.zip" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$APP"
  spctl --assess --type execute "$APP" || fail "Gatekeeper still refuses the app after notarizing."
fi

echo "→ Publishing"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/Bower.zip"
if gh release view "v$VERSION" >/dev/null 2>&1; then
  gh release upload "v$VERSION" "$OUT/Bower.zip" --clobber
else
  notes=(--generate-notes)
  [[ $# -gt 0 ]] && notes=(--notes-file "$1")
  gh release create "v$VERSION" "$OUT/Bower.zip" --target "$(git rev-parse HEAD)" --title "Bower $VERSION" "${notes[@]}"
fi
(( NOTARIZE )) && how="notarized and published" || how="published (not notarized)"
echo "✓ Bower $VERSION is $how: https://github.com/truthofmatthew/bower/releases/tag/v$VERSION"
