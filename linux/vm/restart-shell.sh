# Restarts the shell inside the desktop (the shared folder sends no file-change events, so
# the shell doesn't reload by itself when files change from Windows).
qs -c graphite kill >/dev/null 2>&1; sleep 1
hyprctl dispatch 'hl.dsp.exec_cmd("qs -c graphite --no-duplicate")' >/dev/null; sleep 7
qs -c graphite log 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "WARN|ERROR" | grep -vE "qt.qpa|textinput|portal|bluez|objectmanager" | head -20
