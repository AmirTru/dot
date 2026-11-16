#!/usr/bin/env bash
# Gets the newest Dot: pulls, tests, rebuilds and restarts it. Stops on any failure, so a broken build never replaces a working one.
set -euo pipefail
cd "$(dirname "$0")/.."
git pull --ff-only
scripts/test.sh
scripts/build-app.sh
pkill -x WritingHelper || true
sleep 1
open "$HOME/Applications/Dot.app"
echo "Dot is up to date"
