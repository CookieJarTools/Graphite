#!/usr/bin/env bash
# Screenshots and screen recordings, for the Snipping Tool (services/Capture.qml): pictures go
# in Pictures/Screenshots and are copied too, ready to paste; videos go in Videos/Screen
# Recordings. xdg-user-dir answers the home folder itself when a folder isn't set up.
#
#   screenshot.sh still OUTPUT FILE          the screen OUTPUT as it is now, for the tool to show
#   screenshot.sh cut STILL X Y W H          a part of that still (in its own pixels) saved
#   screenshot.sh take "X,Y WxH"             a part of the screens as they are now saved
#   screenshot.sh record output NAME | area "X,Y WxH"
#                                            records until stopped (SIGINT), with wf-recorder or
#                                            else gpu-screen-recorder; prints the file's path first
#   screenshot.sh recorded FILE              says where a finished recording went
#   screenshot.sh screen | area              the whole screen, or an area dragged out with slurp
folder() {
    local dir
    dir="$(xdg-user-dir "$1" 2>/dev/null)"
    [ -n "$dir" ] && [ "$dir" != "$HOME" ] || dir="$HOME/$2"
    mkdir -p "$dir/$3"
    echo "$dir/$3"
}

picture() {
    echo "$(folder PICTURES Pictures Screenshots)/Screenshot $(date '+%Y-%m-%d %H.%M.%S').png"
}

saved() {
    wl-copy --type image/png < "$1"
    notify-send -a "Graphite" -i "$1" -h string:sound-name:screen-capture "Screenshot saved" "Saved to Pictures > Screenshots and copied, so you can paste it."
}

case "${1:-screen}" in
    still)
        grim -t ppm -o "$2" "$3"
        ;;
    cut)
        file="$(picture)"
        if command -v ffmpeg >/dev/null; then
            ffmpeg -loglevel error -y -i "$2" -vf "crop=$5:$6:$3:$4" -frames:v 1 "$file" || exit 1
        else
            exit 1
        fi
        saved "$file"
        ;;
    take)
        file="$(picture)"
        grim -g "$2" "$file" || exit 1
        saved "$file"
        ;;
    record)
        file="$(folder VIDEOS Videos "Screen Recordings")/Screen Recording $(date '+%Y-%m-%d %H.%M.%S').mp4"
        echo "$file"
        # yuv420p: the colours every player takes. Software encoding (libx264): safe on any GPU.
        if command -v wf-recorder >/dev/null; then
            if [ "$2" = output ]; then
                exec wf-recorder -y -x yuv420p -o "$3" -f "$file" </dev/null
            else
                exec wf-recorder -y -x yuv420p -g "$3" -f "$file" </dev/null
            fi
        elif command -v gpu-screen-recorder >/dev/null; then
            if [ "$2" = output ]; then
                exec gpu-screen-recorder -w "$3" -f 60 -o "$file"
            else
                # "X,Y WxH" as gpu-screen-recorder writes it: WxH+X+Y.
                read -r place size <<< "$3"
                exec gpu-screen-recorder -w region -region "$size+${place%,*}+${place#*,}" -f 60 -o "$file"
            fi
        fi
        exit 3
        ;;
    recorded)
        [ -s "$2" ] || exit 0
        notify-send -a "Graphite" -i video-x-generic -h string:sound-name:completion-success "Recording saved" "Saved to Videos > Screen Recordings: $(basename "$2")"
        ;;
    area)
        area="$(slurp -d)" || exit 0 # Escape: no screenshot
        file="$(picture)"
        grim -g "$area" "$file" || exit 1
        saved "$file"
        ;;
    *)
        file="$(picture)"
        grim "$file" || exit 1
        saved "$file"
        ;;
esac
