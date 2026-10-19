function sddm-theme
    # Search locations where SDDM themes or theme packs reside
    set -l search_roots /usr/share/sddm/themes /usr/local/share/sddm/themes ~/.local/share/sddm/themes ~/Pictures/sddm ~/.dotfiles ~/sddm*

    # Find every folder containing a Main.qml file across search roots
    function __find_all_theme_paths -S -V search_roots
        for root in $search_roots
            if test -d "$root"
                find -L "$root" -maxdepth 5 -name "Main.qml" 2>/dev/null
            end
        end
    end

    # List unique theme directory names
    function __list_sddm_themes -S
        for path in (__find_all_theme_paths)
            basename (dirname "$path")
        end | sort -u
    end

    set -l selected_theme $argv[1]

    # 1. Did you forget to type a theme name?
    if test -z "$selected_theme"
        echo "❌ Error: You didn't specify a theme name."
        echo "Please choose from all discovered themes:"
        __list_sddm_themes
        return 1
    end

    # Locate the selected theme's source directory
    set -l source_path ""
    for path in (__find_all_theme_paths)
        set -l theme_dir (dirname "$path")
        if test (basename "$theme_dir") = "$selected_theme"
            set source_path "$theme_dir"
            break
        end
    end

    # 2. Does the theme actually exist?
    if test -z "$source_path"
        echo "❌ Error: Theme '$selected_theme' was not found."
        echo "Please choose from all discovered themes:"
        __list_sddm_themes
        return 1
    end

    # 3. Automatically install theme to /usr/share/sddm/themes/ if it isn't there already
    set -l system_theme_dir "/usr/share/sddm/themes/$selected_theme"
    if not test -d "$system_theme_dir"
        echo "📦 Installing '$selected_theme' to /usr/share/sddm/themes/..."
        sudo ln -s "$source_path" "$system_theme_dir"
        echo "🔗 Created symlink: $source_path -> $system_theme_dir"
    end

    # 4. Nuke conflicting files
    sudo rm -f /etc/sddm.conf
    sudo rm -f /etc/sddm.conf.d/theme.conf
    sudo rm -f /etc/sddm.conf.d/virtualkbd.conf
    sudo rm -f /etc/sddm.conf.d/99-theme.conf

    sudo mkdir -p /etc/sddm.conf.d

    # 5. Create the ultimate override file
    echo -e "[Theme]\nCurrent=$selected_theme\n\n[General]\nInputMethod=\n\n[Input]\nInputMethod=" | sudo tee /etc/sddm.conf.d/zz-override.conf > /dev/null

    echo "✅ Theme forcefully switched to: $selected_theme"
    echo "✅ Rogue configs deleted and virtual keyboard disabled"
end