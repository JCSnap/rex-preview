#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
bin_dir="$HOME/.local/bin"

cd "$root"
echo "==> Building rex-preview (release)"
swift build -c release --product rex-preview

echo "==> Installing to $bin_dir/rex-preview"
mkdir -p "$bin_dir"
install -m 755 "$root/.build/release/rex-preview" "$bin_dir/rex-preview"

echo "==> Done. Run: rex-preview <file-or-url>"
