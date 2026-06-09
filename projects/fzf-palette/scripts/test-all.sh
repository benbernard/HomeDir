#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT/scripts/test-unit.sh"
"$ROOT/scripts/test-integration.sh"
"$ROOT/scripts/test-ui.sh"
"$ROOT/scripts/test-e2e.sh"
"$ROOT/scripts/test-visual-internal.sh"
"$ROOT/scripts/test-visual.sh"
"$ROOT/scripts/test-install.sh"
"$ROOT/scripts/bench.sh" smoke
