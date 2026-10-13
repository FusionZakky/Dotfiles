#!/bin/bash
if [ "$1" = "text" ]; then
  printf "%s" "$2" | wl-copy
elif [ "$1" = "file" ]; then
  MIME=$(file -b --mime-type "$2")
  wl-copy -t "$MIME" < "$2"
fi
