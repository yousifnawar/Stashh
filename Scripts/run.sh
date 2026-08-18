#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
pkill -x Stash 2>/dev/null || true
./Scripts/build.sh "${1:-release}"
open build/Stash.app
echo "==> Stash launched (menu bar icon + notch shell)"
