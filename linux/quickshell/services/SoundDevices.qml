pragma Singleton
// The order of the sound devices, and the ones turned off, from the Control Panel (Sound).
//
// Order: speakers and headphones (and, apart, microphones) in the order to use them; the first
// one connected is used, so headphones put first take the sound when they connect and the
// speakers get it back when they go. Devices keep their place while disconnected; one seen for
// the first time goes last. Kept in settings.json as soundOrder { outputs, inputs: [{ name,
// description }] }; a device chosen by hand (quick settings) stays until one comes or goes.
//
// Turned off, as Windows' "Don't allow": no app can use them and they're never chosen for the
// sound. WirePlumber leaves them out by a rule (node.disabled) in
// ~/.config/wireplumber/wireplumber.conf.d/50-graphite-off.conf, written from settings.json's
// soundOff ([{ name, description, input }]) and read when it restarts. A Bluetooth headset's
// microphone goes by turning off the switch to its call mode (below).

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Singleton {
    id: root

    readonly property var off: (ShellSettings.values && ShellSettings.values.soundOff) || []
    readonly property var order: (ShellSettings.values && ShellSettings.values.soundOrder) || ({ outputs: [], inputs: [] })

    function describe(node) {
        return node.description || node.nickname || node.name;
    }

    // The devices there now: speakers and headphones, or microphones.
    function present(input) {
        return Array.from(Pipewire.nodes.values).filter(node => node.audio && !node.isStream && node.isSink === !input);
    }

    // In their order, connected or not: [{ name, description, node (null when not connected) }].
    function ordered(input) {
        const now = present(input);
        const kept = (input ? order.inputs : order.outputs) || [];
        const known = kept.filter(device => !off.some(gone => gone.name === device.name)).map(device => {
            const node = now.find(candidate => candidate.name === device.name) || null;
            return { name: device.name, description: node ? describe(node) : device.description, node: node };
        });
        const fresh = now.filter(node => !kept.some(device => device.name === node.name))
            .map(node => ({ name: node.name, description: describe(node), node: node }));
        return known.concat(fresh);
    }

    function setOrder(input, devices) {
        ShellSettings.update(settings => {
            const order = Object.assign({ outputs: [], inputs: [] }, settings.soundOrder || {});
            order[input ? "inputs" : "outputs"] = devices.map(device => ({ name: device.name, description: device.description }));
            settings.soundOrder = order;
        });
    }

    // One place up or down; then the sound goes where the new order says.
    function move(input, name, step) {
        const devices = ordered(input);
        const at = devices.findIndex(device => device.name === name);
        const to = at + step;
        if (at < 0 || to < 0 || to >= devices.length) return;
        devices.splice(to, 0, devices.splice(at, 1)[0]);
        setOrder(input, devices);
        Qt.callLater(() => useFirst(input));
    }

    // A disconnected device taken off the list (it goes last if it's ever connected again).
    function forget(input, name) {
        setOrder(input, ordered(input).filter(device => device.name !== name));
    }

    // The first connected device in the order becomes the one in use.
    function useFirst(input) {
        const first = ordered(input).find(device => device.node);
        if (!first) return;
        if (input && Pipewire.defaultAudioSource !== first.node) Pipewire.preferredDefaultAudioSource = first.node;
        if (!input && Pipewire.defaultAudioSink !== first.node) Pipewire.preferredDefaultAudioSink = first.node;
    }

    // When a device comes or goes (a moment later, as Bluetooth headphones settle on how they
    // connect): new ones join the order, last, and the first one connected is used.
    readonly property string connected: Pipewire.ready
        ? Array.from(Pipewire.nodes.values).filter(node => node.audio && !node.isStream).map(node => node.name).sort().join("\n") : ""
    onConnectedChanged: if (connected) settle.restart()

    Timer {
        id: settle
        interval: 1500
        onTriggered: {
            if (!ShellSettings.loaded) return;
            for (const input of [false, true]) {
                const devices = root.ordered(input);
                const kept = (input ? root.order.inputs : root.order.outputs) || [];
                if (devices.length !== kept.filter(device => !root.off.some(gone => gone.name === device.name)).length) root.setOrder(input, devices);
                root.useFirst(input);
            }
        }
    }

    // A device (a PipeWire node, or an entry of ordered()).
    function turnOff(device, input) {
        const kept = off.filter(gone => gone.name !== device.name);
        save(kept.concat([{ name: device.name, description: device.description || device.nickname || device.name, input: input }]));
    }

    function turnOn(name) {
        save(off.filter(device => device.name !== name));
    }

    function save(devices) {
        ShellSettings.set("soundOff", devices);
        const quote = text => '"' + String(text).replace(/["\\]/g, "") + '"';
        const rule = devices.length === 0 ? "" : [
            "  {",
            "    matches = [ " + devices.map(device => "{ node.name = " + quote(device.name) + " }").join(" ") + " ]",
            "    actions = { update-props = { node.disabled = true } }",
            "  }"
        ].join("\n");
        // A Bluetooth headset's microphone is a stand-in WirePlumber keeps while the headset
        // plays in full quality, to switch it to its call mode when an app wants the mic. Without
        // that switching (for every headset: there's no per-device way), it's only there while
        // the headset is put in call mode by hand.
        const headsetMic = devices.some(device => device.input && device.name.startsWith("bluez_input."));
        const text = [
            "# Written by Graphite's Control Panel (Sound): devices turned off, which no app can use.",
            "monitor.alsa.rules = [", rule, "]",
            "monitor.bluez.rules = [", rule, "]",
            headsetMic ? "wireplumber.settings = { bluetooth.autoswitch-to-headset-profile = false }" : "", ""
        ].join("\n");
        // Bluetooth headphones drop to call quality when the sound service restarts under them,
        // so the ones connected are connected again afterwards.
        writer.command = ["sh", "-c", [
            'mkdir -p "$1" && printf %s "$2" > "$1/50-graphite-off.conf" || exit 1',
            'connected=$(bluetoothctl devices Connected 2>/dev/null | awk \'{ print $2 }\')',
            "systemctl --user restart wireplumber",
            'for device in $connected; do',
            '    bluetoothctl info "$device" | grep -q "Audio Sink" || continue',
            '    bluetoothctl disconnect "$device" >/dev/null; sleep 2; bluetoothctl connect "$device" >/dev/null',
            "done"
        ].join("\n"), "sh", Quickshell.env("HOME") + "/.config/wireplumber/wireplumber.conf.d", text];
        writer.running = true;
    }

    Process { id: writer }
}
