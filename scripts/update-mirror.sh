#!/usr/bin/env bash
set -euo pipefail

base_url="https://www.lua.org/ftp"

listing="$(curl -fsSL "$base_url/")"

targets="$(
    printf '%s\n' "$listing" \
        | awk '
            /CLASS="name"/ {
                name = ""
                if (match($0, /lua-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz/)) {
                    name = substr($0, RSTART, RLENGTH)
                }
                next
            }
            /CLASS="sum"/ && name != "" {
                if (match($0, /[0-9a-f]{64}/)) {
                    print name, substr($0, RSTART, RLENGTH)
                }
                name = ""
            }
        ' \
        | sort -k1,1V \
        | awk '
            {
                version = $1
                sub(/^lua-/, "", version)
                sub(/\.tar\.gz$/, "", version)
                split(version, parts, ".")
                if (parts[1] + 0 != 5 || parts[2] + 0 < 1) {
                    next
                }
                latest[parts[1] "." parts[2]] = $0
            }
            END {
                for (minor in latest) {
                    print latest[minor]
                }
            }
        '
)"

if [[ -z "$targets" ]]; then
    echo "could not parse the Lua source listing" >&2
    exit 1
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

while read -r name sum; do
    if [[ -f "$name" ]] && [[ "$(sha256sum "$name" | cut -d' ' -f1)" == "$sum" ]]; then
        continue
    fi
    curl -fsSL "$base_url/$name" -o "$tmp"
    actual="$(sha256sum "$tmp" | cut -d' ' -f1)"
    if [[ "$actual" != "$sum" ]]; then
        printf 'checksum mismatch for %s: expected %s, got %s\n' "$name" "$sum" "$actual" >&2
        exit 1
    fi
    mv "$tmp" "$name"
    printf 'added %s\n' "$name"
done <<< "$targets"
