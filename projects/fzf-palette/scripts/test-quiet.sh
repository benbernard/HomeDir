#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT/scripts/test-unit.sh"
"$ROOT/scripts/test-integration.sh"
"$ROOT/scripts/test-ui.sh"
