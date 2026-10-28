#!/usr/bin/env bash
# Lists the properties, signals and methods of Quickshell types (by name) from its installed
# type files, into api.txt next to this script.
out="$(dirname "$0")/api.txt"
: > "$out"
for type in "$@"; do
    echo "===== $type" >> "$out"
    grep -rl --include=*.qmltypes "exports: \[\"[^\"]*/$type " /usr/lib/qt6/qml/Quickshell 2>/dev/null | head -1 | while read -r file; do
        awk -v t="$type" '
            /^    Component \{/ { block = ""; inside = 1 }
            inside { block = block $0 "\n" }
            /^    \}/ && inside { if (block ~ ("/" t " ")) print block; inside = 0 }
        ' "$file" | grep -E 'Property \{|Signal \{|Method \{|name: |exports' | grep -E 'name: |exports' >> "$out"
    done
done
