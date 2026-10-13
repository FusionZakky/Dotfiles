function sddm-test
    set -l sddm_dir "/usr/share/sddm/themes"

    if test (count $argv) -eq 0
        # No argument passed: read current theme from override config
        set -l active_theme (grep "^Current=" /etc/sddm.conf.d/zz-override.conf | cut -d'=' -f2)
        echo "🔍 Previewing active theme: $active_theme"
        sddm-greeter-qt6 --test-mode --theme "$sddm_dir/$active_theme"
    else
        # Argument passed: check if theme exists before testing
        set -l theme_name $argv[1]
        set -l theme_path "$sddm_dir/$theme_name"

        if test -d "$theme_path"
            echo "🔍 Previewing theme: $theme_name"
            sddm-greeter-qt6 --test-mode --theme "$theme_path"
        else
            echo "❌ Error: Theme '$theme_name' does not exist in $sddm_dir" >&2
            return 1
        end
    end
end
