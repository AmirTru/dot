#!/usr/bin/env bash
# Installs or updates Dot: downloads the latest source, builds it on this Mac, and opens it.
#   curl -fsSL https://raw.githubusercontent.com/AmirTru/dot/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/AmirTru/dot/main/install.sh | bash -s -- --uninstall
# Building on the Mac it runs on means macOS doesn't block it, and the local signing certificate
# keeps the Accessibility permission across updates.
set -euo pipefail

# Everything runs inside main, so a download cut off halfway can't run half a script.
main() {
  local repo="${DOT_REPO:-AmirTru/dot}"
  local branch="${DOT_BRANCH:-main}"
  local support="$HOME/Library/Application Support/Dot"
  local app="$HOME/Applications/Dot.app"

  if [[ "${1:-}" == "--uninstall" ]]; then
    uninstall "$support" "$app"
    return
  fi

  say "Installing Dot"
  [[ "$(uname -s)" == "Darwin" ]] || fail "Dot runs on macOS only."
  [[ "$(uname -m)" == "arm64" ]] || fail "Dot needs a Mac with Apple silicon."
  local major
  major="$(sw_vers -productVersion | cut -d. -f1)"
  (( major >= 27 )) || fail "Dot needs macOS 27 or later (this Mac has $(sw_vers -productVersion))."
  if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
    xcode-select --install >/dev/null 2>&1 || true
    fail "Dot is built with Apple's Command Line Tools. A window to install them just opened; when it finishes, run this command again."
  fi

  # Script-wide, not local: the cleanup runs after main has returned.
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  if [[ -n "${DOT_SOURCE:-}" ]]; then
    say "Using local source at $DOT_SOURCE"
    cp -R "$DOT_SOURCE/." "$work/dot"
    rm -rf "$work/dot/.build"
  else
    say "Downloading the latest version"
    curl -fsSL "https://codeload.github.com/$repo/tar.gz/refs/heads/$branch" -o "$work/dot.tar.gz"
    mkdir "$work/dot"
    tar -xzf "$work/dot.tar.gz" -C "$work/dot" --strip-components 1
  fi

  say "Building (about a minute the first time)"
  (cd "$work/dot" && scripts/build-app.sh >"$work/build.log" 2>&1) || {
    tail -20 "$work/build.log"
    fail "The build failed. The lines above show why."
  }

  if pgrep -x WritingHelper >/dev/null; then
    pkill -x WritingHelper || true
    sleep 1
  fi
  open "$app"
  say "Done. Dot is in your menu bar; the welcome window walks you through the rest."
  say "To update later, run the same command again."
}

uninstall() {
  local support="$1" app="$2"
  say "Removing Dot"
  pkill -x WritingHelper 2>/dev/null || true
  rm -rf "$app" "$support"
  defaults delete local.dot.app >/dev/null 2>&1 || true
  rm -f "$HOME/Library/Logs/WritingHelper.log"
  say "Dot is removed. To also remove its permission, open System Settings > Privacy & Security > Accessibility and delete Dot."
}

say() { printf '\033[1m==>\033[0m %s\n' "$1"; }
fail() { printf '\033[31mError:\033[0m %s\n' "$1" >&2; exit 1; }

main "$@"
