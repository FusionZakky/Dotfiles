#!/usr/bin/env bash
# Rebuilds reveal.frag.qsb from reveal.frag (needs qt6-shadertools). Run after editing reveal.frag.
cd "$(dirname "${BASH_SOURCE[0]}")" && /usr/lib/qt6/bin/qsb --qt6 -o reveal.frag.qsb reveal.frag
