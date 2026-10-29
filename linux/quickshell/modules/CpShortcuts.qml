// Control Panel: Shortcuts. Every keyboard shortcut, each changeable: pick the keys to hold
// (Windows, Ctrl, Alt, Shift) and press the key. Shortcuts that open an app can be added too.
// The keys are chosen this way, rather than by pressing the whole shortcut, because a shortcut
// that's already in use would go off instead of being typed here.
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services

ColumnLayout {
    id: page

    property string editing: ""   // the shortcut being changed, "new-app" while adding one
    property string newApp: ""

    readonly property var apps: Array.from(DesktopEntries.applications.values).filter(entry => !entry.noDisplay).sort((first, second) => first.name.localeCompare(second.name))

    spacing: 0

    CpSection {
        CpRow {
            glyph: "preferences-desktop-keyboard-shortcuts-symbolic"
            label: "Keyboard shortcuts"
            hint: "Change shortcuts or add your own"

            PillButton {
                text: "Reset all"
                onClicked: Hotkeys.resetAll()
            }
        }
    }

    CpSection {
        title: "Desktop"

        Repeater {
            model: Hotkeys.actions

            CpRow {
                id: actionRow
                required property var modelData
                readonly property string keys: Hotkeys.keysFor(modelData)
                label: modelData.label

                UiText {
                    text: Hotkeys.shown(actionRow.keys)
                    color: actionRow.keys ? Theme.ink : Theme.inkMuted
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.identifierSize
                }

                PillButton {
                    visible: page.editing !== actionRow.modelData.id
                    text: "Change"
                    onClicked: page.editing = actionRow.modelData.id
                }

                below: [
                    KeyEditor {
                        visible: page.editing === actionRow.modelData.id
                        Layout.fillWidth: true
                        start: actionRow.keys
                        owner: actionRow.modelData.id
                        defaultKeys: actionRow.modelData.keys
                        onSaved: keys => {
                            Hotkeys.set(actionRow.modelData.id, keys);
                            page.editing = "";
                        }
                        onCancelled: page.editing = ""
                    }
                ]
            }
        }
    }

    CpSection {
        title: "Apps"

        Repeater {
            model: Hotkeys.appShortcuts

            CpRow {
                id: appRow
                required property var modelData
                label: "Open " + modelData.name

                UiText {
                    text: Hotkeys.shown(appRow.modelData.keys)
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.identifierSize
                }

                PillButton {
                    danger: true
                    text: "Remove"
                    onClicked: Hotkeys.removeApp(appRow.modelData.id)
                }
            }
        }

        CpRow {
            glyph: "list-add-symbolic"
            label: "Add a shortcut to open an app"
            opens: page.editing !== "new-app"
            onClicked: {
                page.newApp = "";
                page.editing = "new-app";
            }

            below: [
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: page.editing === "new-app"
                    spacing: Theme.space2

                    RowLayout {
                        Layout.fillWidth: true
                        UiText {
                            Layout.fillWidth: true
                            text: "App"
                        }
                        CpChoice {
                            value: page.newApp
                            options: page.apps.map(entry => ({ value: entry.id, label: entry.name }))
                            onPicked: value => page.newApp = value
                        }
                    }

                    KeyEditor {
                        Layout.fillWidth: true
                        visible: page.newApp.length > 0
                        start: ""
                        owner: page.newApp
                        defaultKeys: ""
                        onSaved: keys => {
                            const entry = page.apps.find(candidate => candidate.id === page.newApp);
                            if (keys && entry) Hotkeys.addApp(keys, entry.id, entry.name);
                            page.editing = "";
                        }
                        onCancelled: page.editing = ""
                    }
                }
            ]
        }
    }

    CpSection {
        title: "Fixed shortcuts"

        Repeater {
            model: Hotkeys.fixed

            CpRow {
                id: fixedRow
                required property var modelData
                label: modelData.label

                UiText {
                    text: Hotkeys.shown(fixedRow.modelData.keys)
                    color: Theme.inkMuted
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.identifierSize
                }
            }
        }
    }

    // Choosing keys: the keys to hold, then the key itself (typed into the box).
    component KeyEditor: ColumnLayout {
        id: editor

        property string start
        property string owner
        property string defaultKeys
        signal saved(string keys)
        signal cancelled()

        property var mods: []
        property string key: ""
        readonly property string keys: key ? mods.concat([key]).join(" + ") : ""
        readonly property string clash: keys ? Hotkeys.takenBy(keys, owner) : ""

        onVisibleChanged: if (visible) {
            const parts = start ? start.split(" + ") : [];
            mods = parts.filter(part => ["SUPER", "CTRL", "ALT", "SHIFT"].includes(part));
            key = parts.filter(part => !["SUPER", "CTRL", "ALT", "SHIFT"].includes(part))[0] || "";
            capture.forceActiveFocus();
        }

        spacing: Theme.space2

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space2

            Repeater {
                model: [{ id: "SUPER", label: "Windows" }, { id: "CTRL", label: "Ctrl" }, { id: "ALT", label: "Alt" }, { id: "SHIFT", label: "Shift" }]

                Rectangle {
                    id: modChip
                    required property var modelData
                    readonly property bool on: editor.mods.includes(modelData.id)
                    implicitWidth: modText.implicitWidth + Theme.space3 * 2
                    implicitHeight: 32
                    radius: Theme.radiusSm
                    color: on ? Theme.accentSoft : modMouse.containsMouse ? Theme.surface300 : Theme.surface100
                    border.color: on ? Theme.accent : Theme.line
                    border.width: 1

                    UiText {
                        id: modText
                        anchors.centerIn: parent
                        text: modChip.modelData.label
                        font.weight: modChip.on ? Font.DemiBold : Font.Normal
                    }

                    MouseArea {
                        id: modMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            const order = ["SUPER", "CTRL", "ALT", "SHIFT"];
                            const next = modChip.on ? editor.mods.filter(mod => mod !== modChip.modelData.id) : editor.mods.concat([modChip.modelData.id]);
                            editor.mods = order.filter(mod => next.includes(mod));
                            capture.forceActiveFocus();
                        }
                    }
                }
            }

            UiText { text: "+" }

            // The key: press it while this box is selected.
            Rectangle {
                id: capture
                implicitWidth: 140
                implicitHeight: 32
                radius: Theme.radiusSm
                color: Theme.surface100
                border.color: activeFocus ? Theme.accent : Theme.line
                border.width: 1
                activeFocusOnTab: true

                UiText {
                    anchors.centerIn: parent
                    text: editor.key ? Hotkeys.shown(editor.key) : "Press a key"
                    color: editor.key ? Theme.ink : Theme.inkMuted
                    font.family: editor.key ? Theme.fontMono : Theme.fontSans
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: capture.forceActiveFocus()
                }

                Keys.onPressed: event => {
                    const special = {
                        [Qt.Key_Return]: "Return", [Qt.Key_Enter]: "Return", [Qt.Key_Escape]: "Escape", [Qt.Key_Tab]: "Tab",
                        [Qt.Key_Space]: "space", [Qt.Key_Print]: "Print", [Qt.Key_Left]: "left", [Qt.Key_Right]: "right",
                        [Qt.Key_Up]: "up", [Qt.Key_Down]: "down", [Qt.Key_Delete]: "Delete", [Qt.Key_Home]: "Home",
                        [Qt.Key_End]: "End", [Qt.Key_PageUp]: "Prior", [Qt.Key_PageDown]: "Next", [Qt.Key_Backspace]: "BackSpace"
                    };
                    let name = special[event.key] || "";
                    if (!name && event.key >= Qt.Key_F1 && event.key <= Qt.Key_F12) name = "F" + (event.key - Qt.Key_F1 + 1);
                    if (!name && event.key >= Qt.Key_A && event.key <= Qt.Key_Z) name = String.fromCharCode(event.key);
                    if (!name && event.key >= Qt.Key_0 && event.key <= Qt.Key_9) name = String.fromCharCode(event.key);
                    if (!name && event.text && event.text.trim()) name = event.text.trim();
                    if (name) editor.key = name;
                    event.accepted = true;
                }
            }

            Item { Layout.fillWidth: true }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space2

            UiText {
                Layout.fillWidth: true
                text: editor.clash ? "Already used for " + editor.clash : editor.keys ? Hotkeys.shown(editor.keys) : ""
                color: editor.clash ? Theme.danger : Theme.inkMuted
                font.pixelSize: Theme.hintSize
            }

            PillButton {
                visible: editor.defaultKeys.length > 0
                text: "Default"
                onClicked: editor.saved(editor.defaultKeys)
            }

            PillButton {
                visible: editor.defaultKeys.length > 0
                text: "None"
                onClicked: editor.saved("")
            }

            PillButton {
                text: "Cancel"
                onClicked: editor.cancelled()
            }

            PillButton {
                primary: true
                text: "Save"
                enabled: editor.keys.length > 0 && !editor.clash
                onClicked: editor.saved(editor.keys)
            }
        }
    }
}
