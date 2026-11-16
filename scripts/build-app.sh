#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release 2>&1 | grep -E "error|Compiling|Build complete" || true
app="$HOME/Applications/Dot.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp .build/release/WritingHelper "$app/Contents/MacOS/WritingHelper"

# macOS ties the Accessibility permission to the signature. A certificate made once on this Mac
# keeps that permission across rebuilds, and no other program can claim it by reusing the app ID.
# It lives in its own keychain, so the login keychain is never touched.
dir="$HOME/Library/Application Support/Dot/signing"
keychain="$dir/signing.keychain-db"
name="Dot Local Signing"
if [ ! -f "$keychain" ]; then
  mkdir -p "$dir" && chmod 700 "$dir"
  openssl rand -hex 24 > "$dir/password" && chmod 600 "$dir/password"
  tmp=$(mktemp -d)
  printf '[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n[dn]\nCN=%s\n[ext]\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\nbasicConstraints=critical,CA:false\n' "$name" > "$tmp/cnf"
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$tmp/key" -out "$tmp/cert" -days 3650 -config "$tmp/cnf" 2>/dev/null
  openssl pkcs12 -export -legacy -inkey "$tmp/key" -in "$tmp/cert" -out "$tmp/id.p12" -passout pass:dot
  security create-keychain -p "$(cat "$dir/password")" "$keychain"
  security unlock-keychain -p "$(cat "$dir/password")" "$keychain"
  security import "$tmp/id.p12" -k "$keychain" -P dot -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple: -s -k "$(cat "$dir/password")" "$keychain" >/dev/null
  rm -rf "$tmp"
  echo "created signing certificate in $keychain"
fi
security unlock-keychain -p "$(cat "$dir/password")" "$keychain"
codesign --force --options runtime --entitlements Resources/Dot.entitlements --keychain "$keychain" --sign "$name" "$app"
echo "built $app"
