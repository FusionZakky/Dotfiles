#!/usr/bin/env bash
# Prints every SDDM theme we can find as one JSON array (used by the picker's SDDM tab) and keeps a copy in
# ~/.cache/quickshell/sddm-scan.json so the tab can show last time's list instantly while this refreshes.
# Search roots match the sddm-theme / sddm-test fish functions.
export LC_ALL=C
exec </dev/null   # nothing below may ever read stdin
cache="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell"
out="$cache/sddm_thumbs"
caps="$cache/sddm_captures"
mkdir -p "$out" "$caps"
keep=$(mktemp)
trap 'rm -f "$keep"' EXIT

roots=(/usr/share/sddm/themes /usr/local/share/sddm/themes "$HOME/.local/share/sddm/themes" "$HOME/Pictures/sddm" "$HOME/.dotfiles")
for g in "$HOME"/sddm*; do [ -d "$g" ] && roots+=("$g"); done

active=$(grep -h '^Current=' /etc/sddm.conf.d/zz-override.conf 2>/dev/null | tail -n 1 | cut -d= -f2 | tr -d '[:space:]')
if [ -z "$active" ]; then
    active=$(cat /etc/sddm.conf /etc/sddm.conf.d/*.conf 2>/dev/null | grep '^Current=' | tail -n 1 | cut -d= -f2 | tr -d '[:space:]')
fi

# Regular files of ONE theme. Never descends into a nested theme (a sub-folder with its own Main.qml),
# so a theme can't pick up another theme's files.
theme_files() {
    find -L "$1" -mindepth 1 -maxdepth 6 \( -type d -exec test -e '{}/Main.qml' \; -prune \) -o -type f -print 2>/dev/null
}
rel() { printf '%s' "${1#"$2"/}"; }
pick() { printf '%s\n' "$files" | grep -iE "$1" | sort | head -n 1; }
largest_image() {
    printf '%s\n' "$files" | grep -iE '\.(png|jpe?g|webp|bmp|svg)$' | xargs -d '\n' -r stat -L --printf='%s\t%n\n' 2>/dev/null \
        | awk -F'\t' '$1 > 8192' | sort -rn | head -n 1 | cut -f2-
}
hit_q() { [ -n "$qmlsrc" ] && printf '%s\n' "$qmlsrc" | xargs -d '\n' -r grep -lE "$1" 2>/dev/null | head -n 1; }
has_q() { [ -n "$(hit_q "$1")" ]; }
is_dark() { # exit 0 if the image is nearly black
    local m
    m=$(magick "$1" -colorspace Gray -format '%[fx:mean]' info: 2>/dev/null </dev/null)
    [ -n "$m" ] && awk -v m="$m" 'BEGIN { exit !(m + 0 < 0.02) }'
}
thumb_key() { printf '%s' "$1|$(stat -L -c '%Y-%s' "$1" 2>/dev/null)" | md5sum | cut -c1-8; }
gen_from_image() {
    local t; t="$out/$name-$(thumb_key "$1").jpg"
    if [ ! -s "$t" ]; then
        magick "${1}[0]" -resize x420 -quality 70 "$t" 2>/dev/null </dev/null || rm -f "$t"
        [ -s "$t" ] && is_dark "$t" && : > "$t.dark"
    fi
    [ -s "$t" ] && printf '%s' "$t"
}
gen_from_video() {
    local t ss; t="$out/$name-$(thumb_key "$1").jpg"
    if [ ! -s "$t" ]; then
        for ss in 3 1 0; do   # a few seconds in, then earlier for very short clips
            ffmpeg -nostdin -y -loglevel error -ss "$ss" -i "$1" -frames:v 1 -vf scale=-2:420 "$t" 2>/dev/null </dev/null
            [ -s "$t" ] || continue
            is_dark "$t" || break
        done
        [ -s "$t" ] && is_dark "$t" && : > "$t.dark"
    fi
    [ -s "$t" ] && printf '%s' "$t"
}

img='\.(png|jpe?g|webp|svg)$'
vidre='\.(mp4|webm|mkv|mov|m4v|avi)$'
declare -A seen seenreal
result=$({
    for root in "${roots[@]}"; do
        [ -d "$root" ] || continue
        # the loop reads from fd 3, so no command inside it can swallow the list
        while IFS= read -r -u 3 main; do
            dir=$(dirname "$main")
            name=$(basename "$dir")
            real=$(readlink -f "$dir")
            [ -n "${seen["$name"]}" ] && continue
            [ -n "${seenreal["$real"]}" ] && continue
            grep -qxF -- "$name" "$HOME/.config/quickshell/ii/sddm-hidden-themes.txt" 2>/dev/null && continue
            if [ ! -f "$dir/metadata.desktop" ] && [ ! -f "$dir/theme.conf" ] && [ "$dir" != "$root" ] && [ "$(dirname "$dir")" != "$root" ]; then
                continue
            fi
            seen["$name"]=1; seenreal["$real"]=1

            files=$(theme_files "$dir" | sort)
            qmlsrc=$(printf '%s\n' "$files" | grep -iE '\.(qml|conf|js)$')

            bg=""
            if [ -f "$dir/theme.conf" ]; then
                bg=$(sed -nE 's/^[[:space:]]*[Bb]ackground[[:space:]]*=[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/p' "$dir/theme.conf" | head -n 1 | tr -d '\r')
                [ -n "$bg" ] && [ ! -f "$dir/$bg" ] && bg=""
            fi

            # ---- multi-variant themes: metadata.desktop ConfigFile names the config the greeter really uses ----
            cfg=""; cfgbg=""
            if [ -f "$dir/metadata.desktop" ]; then
                cfg=$(sed -nE 's/^[[:space:]]*ConfigFile[[:space:]]*=[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/p' "$dir/metadata.desktop" | head -n 1 | tr -d '\r')
                if [ -n "$cfg" ] && [ "$cfg" != "theme.conf" ] && [ -f "$dir/$cfg" ]; then
                    cfgbg=$(sed -nE 's/^[[:space:]]*[Bb]ackground[[:space:]]*=[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/p' "$dir/$cfg" | head -n 1 | tr -d '\r')
                    [ -n "$cfgbg" ] && [ ! -f "$dir/$cfgbg" ] && cfgbg=""
                    # the other variants' configs must not count as references of this theme
                    qmlsrc=$(printf '%s\n' "$qmlsrc" | awk -v d="$(dirname "$dir/$cfg")/" -v k="$dir/$cfg" 'index($0, d) == 1 && $0 ~ /\.conf$/ && $0 != k { next } { print }')
                else
                    cfg=""
                fi
            fi

            # ---- media kept outside the theme folder (absolute file:// paths in the QML) ----
            extimg=""
            extrefs=$(printf '%s\n' "$qmlsrc" | xargs -d '\n' -r grep -hoE 'file:///[^" ]+\.[A-Za-z0-9]+' 2>/dev/null | sed 's|^file://||' | sort -u)
            while IFS= read -r r; do
                [ -f "$r" ] || continue
                [[ "${r,,}" =~ $img ]] && [ -z "$extimg" ] && extimg="$r"
            done <<< "$extrefs"

            # ---- animation: only media the theme actually uses counts ----
            refs=$(printf '%s\n' "$qmlsrc" | xargs -d '\n' -r grep -hoiE "[^\"' =:(,]+\.(mp4|webm|mkv|mov|m4v|avi|gif|apng|webp)" 2>/dev/null | sort -u)
            rvid=""; rgif=""
            while IFS= read -r r; do
                [ -z "$r" ] && continue
                b="/${r##*/}"
                m=$(printf '%s\n' "$files" | awk -v b="$b" 'length($0) >= length(b) && substr($0, length($0) - length(b) + 1) == b { print; exit }')
                [ -z "$m" ] && continue
                if [[ "${m,,}" =~ $vidre ]]; then
                    [ -z "$rvid" ] && rvid="$m"
                elif [[ "${m,,}" =~ \.webp$ ]]; then
                    n=$(magick identify -format '%n\n' "$m" 2>/dev/null </dev/null | head -n 1)
                    [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -gt 1 ] && [ -z "$rgif" ] && rgif="$m"
                else
                    [ -z "$rgif" ] && rgif="$m"
                fi
            done <<< "$refs"

            anim=""; animType=""; evidence=""
            if [ -n "$rvid" ]; then
                anim="$rvid"; animType="video"; evidence="video used by the theme: $(rel "$rvid" "$dir")"
            elif [ -n "$rgif" ]; then
                anim="$rgif"; animType="gif"; evidence="animation used by the theme: $(rel "$rgif" "$dir")"
            else
                anyvid=$(pick "$vidre")
                anygif=$(pick '\.(gif|apng)$')
                if [ -n "$anyvid" ] && has_q 'MediaPlayer *\{|VideoOutput *\{|Video *\{'; then
                    anim="$anyvid"; animType="video"; evidence="video file + player in QML: $(rel "$anyvid" "$dir")"
                elif [ -n "$anygif" ] && has_q 'AnimatedImage *\{'; then
                    anim="$anygif"; animType="gif"; evidence="gif + AnimatedImage in QML: $(rel "$anygif" "$dir")"
                else
                    hit=$(hit_q 'VideoOutput *\{|Video *\{')
                    if [ -n "$hit" ] && ! has_q 'useVideo: *false'; then
                        animType="qml"; evidence="QML plays video: $(rel "$hit" "$dir")"
                    else
                        hit=$(hit_q 'ParticleSystem|ShaderEffect|AnimatedSprite|Animation\.Infinite')
                        [ -n "$hit" ] && { animType="qml"; evidence="QML animation: $(rel "$hit" "$dir")"; }
                    fi
                fi
            fi

            # ---- the active variant config decides the animation of multi-variant themes ----
            if [ -n "$cfgbg" ]; then
                anim=""; animType=""; evidence="active config $cfg: $cfgbg"
                if [[ "${cfgbg,,}" =~ $vidre ]]; then
                    anim="$dir/$cfgbg"; animType="video"
                elif [[ "${cfgbg,,}" =~ \.(gif|apng)$ ]]; then
                    anim="$dir/$cfgbg"; animType="gif"
                fi
            fi

            # ---- preview: most specific source first ----
            thumb=""; thumbsrc=""; why=""
            if [ -n "$cfgbg" ] && [[ "${cfgbg,,}" =~ $img ]]; then
                src="$dir/$cfgbg"; why="active config background"
            elif [ -z "$cfgbg" ]; then
                src=$(pick '/(preview|screenshot|thumbnail)[^/]*'"$img"); [ -n "$src" ] && why="named preview"
            fi
            if [ -z "$src" ] && [ -z "$cfgbg" ]; then src=$(pick '/(previews?|screenshots?)/[^/]*'"$img"); [ -n "$src" ] && why="preview folder"; fi
            if [ -z "$src" ] && [ -n "$bg" ] && [[ "${bg,,}" =~ $img ]]; then src="$dir/$bg"; why="theme.conf background"; fi
            vsrc=""
            [ -z "$src" ] && [ "$animType" = video ] && [ -n "$anim" ] && vsrc="$anim"   # a frame beats random images
            if [ -z "$src" ] && [ -z "$vsrc" ]; then src=$(pick '/(backgrounds?|assets|images?|img|wallpapers?)/[^/]*'"$img"); [ -n "$src" ] && why="background folder"; fi
            if [ -z "$src" ] && [ -z "$vsrc" ]; then src=$(largest_image); [ -n "$src" ] && why="largest image"; fi

            if [ -z "$src" ] && [ -z "$vsrc" ] && [ -n "$extimg" ]; then src="$extimg"; why="image outside the theme folder"; fi
            if [ -n "$src" ]; then
                thumb=$(gen_from_image "$src"); thumbsrc="$src"
            elif [ -n "$vsrc" ]; then
                thumb=$(gen_from_video "$vsrc"); thumbsrc="$vsrc"; why="video frame"
            fi

            c1="$caps/$name.1.png"; [ -s "$c1" ] || c1=""
            c2="$caps/$name.2.png"; [ -s "$c2" ] || c2=""
            dark=false
            [ -n "$thumb" ] && [ -e "$thumb.dark" ] && dark=true
            if [ -n "$c1" ]; then   # the idle login screen is the thumbnail; a black capture only fills in when there is nothing better
                t2=$(gen_from_image "$c1")
                if [ -n "$t2" ] && [ ! -e "$t2.dark" ]; then
                    thumb="$t2"; thumbsrc="$c1"; why="captured screenshot"; dark=false
                elif [ -n "$t2" ] && { [ -z "$thumb" ] || [ "$dark" = true ]; }; then
                    thumb="$t2"; thumbsrc="$c1"; why="captured screenshot (dark)"; dark=true
                fi
            fi
            if [ -n "$thumb" ]; then
                printf '%s\n' "$thumb" >> "$keep"
                [ -e "$thumb.dark" ] && printf '%s\n' "$thumb.dark" >> "$keep"
            fi

            # ---- stage images the theme ships itself ----
            sa=""; sb=""
            pv=$(printf '%s\n' "$files" | grep -iE '/(previews?|screenshots?)/[^/]*'"$img" | sort | head -n 2)
            if [ "$(printf '%s\n' "$pv" | grep -c .)" -ge 2 ]; then
                sa=$(printf '%s\n' "$pv" | sed -n 1p); sb=$(printf '%s\n' "$pv" | sed -n 2p)
            else
                sa=$(pick '/([^/]*[-_ ])?(lock(screen)?|splash|intro|stage[-_ ]?1|step[-_ ]?1)([-_ ][^/]*)?'"$img")
                sb=$(pick '/([^/]*[-_ ])?(login|stage[-_ ]?2|step[-_ ]?2)([-_ ][^/]*)?'"$img")
                if [ -z "$sa" ] || [ -z "$sb" ]; then sa=""; sb=""; fi
            fi

            [ -n "$cfgbg" ] && { sa=""; sb=""; }   # Previews/ of a multi-variant theme show the other variants
            tried=false
            clip="$cache/sddm_clips/$name.mp4"; [ -s "$clip" ] || clip=""
            grep -qxF -- "$name" "$cache/sddm-capture-tried.txt" 2>/dev/null && tried=true
            isactive=false
            [ "$name" = "$active" ] && isactive=true

            jq -n --arg name "$name" --arg path "$real" --arg preview "$thumb" --arg previewWhy "$why" --arg previewSrc "$thumbsrc" \
                  --arg animType "$animType" --arg anim "$anim" --arg evidence "$evidence" \
                  --arg stageA "$sa" --arg stageB "$sb" --arg capture1 "$c1" --arg capture2 "$c2" --argjson tried "$tried" --arg clip "$clip" \
                  --argjson isActive "$isactive" --argjson dark "$dark" \
                  '{name:$name, path:$path, preview:$preview, previewWhy:$previewWhy, previewSrc:$previewSrc, animType:$animType, anim:$anim, animEvidence:$evidence, stageA:$stageA, stageB:$stageB, capture1:$capture1, capture2:$capture2, captureTried:$tried, clip:$clip, dark:$dark, isActive:$isActive}'
        done 3< <(find -L "$root" -maxdepth 5 -name Main.qml 2>/dev/null | sort)
    done
} | jq -s 'sort_by(.name | ascii_downcase)')

count=$(printf '%s' "$result" | jq length 2>/dev/null)
if [ "${count:-0}" -gt 0 ]; then
    printf '%s\n' "$result" > "$cache/sddm-scan.json.tmp" && mv "$cache/sddm-scan.json.tmp" "$cache/sddm-scan.json"
    # drop thumbnails nothing refers to any more (changed sources, deleted themes)
    find "$out" -maxdepth 1 -type f | while IFS= read -r f; do grep -qxF -- "$f" "$keep" || rm -f -- "$f"; done
fi
printf '%s\n' "$result"
