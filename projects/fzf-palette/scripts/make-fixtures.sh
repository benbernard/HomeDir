#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/fixtures/generated"

rm -rf "$OUT"
mkdir -p "$OUT/tiny" "$OUT/medium" "$OUT/large"

make_rows() {
  local count="$1"
  local file="$2"
  : > "$file"
  for ((i = 0; i < count; i++)); do
    printf 'src/module-%03d/file-%06d.swift\n' "$((i % 100))" "$i" >> "$file"
  done
}

make_rows 100 "$OUT/tiny/files.txt"
make_rows 10000 "$OUT/medium/files.txt"
make_rows 100000 "$OUT/large/files.txt"

cat > "$OUT/engine-parity-sample.txt" <<'EOF'
src/FzfPaletteApp/AppDelegate.swift
src/FzfPaletteCore/Profile.swift
docs/performance.md
docs/testing.md
hello world.txt
EOF

echo "$OUT"
