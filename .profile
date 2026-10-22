export PATH="$HOME/.local/bin:$PATH:$HOME/.config/emacs/bin"
export ELM_DISPLAY=wl
export QT_QPA_PLATFORMTHEME=gtk3
export JDK_JAVA_OPTIONS='-Dawt.useSystemAAFontSettings=on -Dswing.aatext=true -Dswing.defaultlaf=com.sun.java.swing.plaf.gtk.GTKLookAndFeel'
export JAVA_HOME=/usr/lib/jvm/default
export MPD_HOST="$XDG_RUNTIME_DIR/mpd/socket"
export _JAVA_AWT_WM_NONREPARENTING=1
export TMPDIR="$HOME/.cache/opencode-tmp"
# Start MPD
pgrep -u "$USER" -x mpd >/dev/null || mpd

[ -f "/home/arc/.ghcup/env" ] && . "/home/arc/.ghcup/env" # ghcup-env