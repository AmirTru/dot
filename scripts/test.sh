#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Without Xcode, `swift test` can't find the Swift Testing macro plugin on its own.
plugins=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
if [[ "$(xcode-select -p)" == *CommandLineTools* && -d "$plugins" ]]; then
  exec swift test -Xswiftc -plugin-path -Xswiftc "$plugins" "$@"
fi
exec swift test "$@"
