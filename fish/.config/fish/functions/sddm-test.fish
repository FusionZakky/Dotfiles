function sddm-test
    set -l search_roots /usr/share/sddm/themes /usr/local/share/sddm/themes ~/.local/share/sddm/themes ~/Pictures/sddm ~/.dotfiles ~/sddm*

    set -l theme_name $argv[1]
    if test -z "$theme_name"
        set theme_name (grep "^Current=" /etc/sddm.conf.d/zz-override.conf 2>/dev/null | cut -d'=' -f2)
    end

    if test -z "$theme_name"
        echo "❌ Error: No theme specified and no active theme found." >&2
        return 1
    end

    set -l theme_path ""
    for root in $search_roots
        if test -d "$root"
            set -l match (find -L "$root" -maxdepth 5 -name "Main.qml" 2>/dev/null | grep -E "/$theme_name/Main.qml\$" | head -n 1)
            if test -n "$match"
                set theme_path (dirname "$match")
                break
            end
        end
    end

    if test -n "$theme_path"
        echo "🔍 Previewing theme: $theme_name ($theme_path)"
        sddm-greeter-qt6 --test-mode --theme "$theme_path"
    else
        echo "❌ Error: Theme '$theme_name' was not found in any search directories." >&2
        return 1
    end
end