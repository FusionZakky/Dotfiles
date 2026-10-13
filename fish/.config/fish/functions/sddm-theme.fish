function sddm-theme
    # 1. Did you forget to type a theme name?
    if test -z "$argv[1]"
        echo "❌ Error: You didn't specify a theme name."
        echo "Please choose from the installed themes:"
        ls -1 /usr/share/sddm/themes/
        return 1
    end
    
    set theme_dir "/usr/share/sddm/themes/$argv[1]"
    
    # 2. Does the theme actually exist?
    if not test -d "$theme_dir"
        echo "❌ Error: Theme folder '$argv[1]' does not exist."
        echo "Please choose from the installed themes:"
        ls -1 /usr/share/sddm/themes/
        return 1
    end
    
    # 3. Nuke conflicting files
    sudo rm -f /etc/sddm.conf
    sudo rm -f /etc/sddm.conf.d/theme.conf
    sudo rm -f /etc/sddm.conf.d/virtualkbd.conf
    sudo rm -f /etc/sddm.conf.d/99-theme.conf
    
    sudo mkdir -p /etc/sddm.conf.d
    
    # 4. Create the ultimate override file
    echo -e "[Theme]\nCurrent=$argv[1]\n\n[General]\nInputMethod=\n\n[Input]\nInputMethod=" | sudo tee /etc/sddm.conf.d/zz-override.conf > /dev/null
    
    echo "✅ Theme forcefully switched to: $argv[1]"
    echo "✅ Rogue configs deleted and virtual keyboard disabled"
end
