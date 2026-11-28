#!/usr/bin/env bash
set -e

INPUT_LOG="/tmp/vfiotrace.log"
OUTPUT_FILE="$HOME/vfiotrace.nvram.txt"

sudo awk '
  index($0, "region2+0x26c960, 0xa5a5a5a5, 4)") { capture=1 }
  capture { print }
  index($0, "region2+0x26c978, 0x0, 4)") && capture {
    capture=0
    # Uncomment "exit" on the next line if you only want the first matching chunk:
    # exit
  }
' "$INPUT_LOG" > "$OUTPUT_FILE"

echo "Saved $(wc -l < "$OUTPUT_FILE") lines to $OUTPUT_FILE"
