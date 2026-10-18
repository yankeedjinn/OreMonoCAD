#!/bin/sh
#
#  check_tool_help.sh – OhMyCAD
#
#  RULE: every tool must have help (a summary + short usage instructions).
#  The script runs on every build (the “Check Tool Help” phase) and, for every tool
#  in `enum DrawingTool` that has no entry in `DrawingTool.help`, prints an Xcode warning.
#  The build does not fail – only a yellow warning appears, linking to the tool's line.
#

FILE="${SRCROOT}/OhMyCAD/EditorView.swift"

if [ ! -f "$FILE" ]; then
    echo "warning: Tool help check: ${FILE} not found"
    exit 0
fi

# Tool names (the “    case …” lines directly in enum DrawingTool) with their line numbers
awk '
    /^enum DrawingTool/ { inside = 1; next }
    inside && /^}/      { inside = 0 }
    inside && /^    case / {
        text = $0
        sub(/^    case /, "", text)
        sub(/\/\/.*/, "", text)
        count = split(text, names, ",")
        for (i = 1; i <= count; i++) {
            name = names[i]
            gsub(/[ \t]/, "", name)
            if (name != "") print NR, name
        }
    }
' "$FILE" | while read -r LINE TOOL; do
    if ! grep -Eq "^[[:space:]]+\.${TOOL}:[[:space:]]*\(" "$FILE"; then
        echo "${FILE}:${LINE}: warning: Tool '${TOOL}' has no hover help – add its summary and usage to DrawingTool.help"
    fi
done

exit 0
