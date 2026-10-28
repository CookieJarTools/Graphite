// Control Panel: Accounts. Your name, password and password hint; and the other people who
// can sign in: add one (an administrator or not), make one an administrator, remove one.
// Each change asks for an administrator's password (pkexec, through Machine).
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

ColumnLayout {
    id: page

    readonly property var me: Machine.people.find(person => person.me) || { name: "", full: "", admin: false }
    readonly property var others: Machine.people.filter(person => !person.me)
    property string form: "" // "", "name", "password", "pin", "hint" or "add"
    property string removing: ""

    spacing: 0

    function close() {
        form = "";
        for (const field of [newName, newPassword, newPasswordAgain, hintText, addFull, addShort, addPassword, pinField, pinAgain]) field.text = "";
    }

    UiText {
        Layout.fillWidth: true
        Layout.topMargin: Theme.space4
        visible: Machine.accountMessage.length > 0
        text: Machine.accountMessage
        color: Theme.inkMuted
    }

    CpSection {
        title: "You"

        CpRow {
            glyph: "avatar-default-symbolic"
            label: page.me.full || page.me.name
            hint: (page.me.admin ? "Administrator" : "Standard account") + " · Local account · signs in as " + page.me.name
        }

        CpRow {
            label: "Your name"
            hint: "Shown on the sign-in screen and in greetings"
            opens: page.form !== "name"
            onClicked: page.form = "name"

            below: [
                RowLayout {
                    Layout.fillWidth: true
                    visible: page.form === "name"
                    spacing: Theme.space2
                    FieldBox {
                        id: newName
                        Layout.fillWidth: true
                        placeholder: page.me.full
                    }
                    PillButton { text: "Cancel"; onClicked: page.close() }
                    PillButton {
                        primary: true
                        text: "Save"
                        enabled: newName.text.trim().length > 0
                        onClicked: {
                            Machine.setFullName(page.me.name, newName.text.trim());
                            page.close();
                        }
                    }
                }
            ]
        }

        CpRow {
            label: "Change your password"
            opens: page.form !== "password"
            onClicked: {
                page.form = "password";
                newPassword.focusField();
            }

            below: [
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: page.form === "password"
                    spacing: Theme.space2
                    FieldBox {
                        id: newPassword
                        Layout.fillWidth: true
                        password: true
                        placeholder: "New password"
                    }
                    FieldBox {
                        id: newPasswordAgain
                        Layout.fillWidth: true
                        password: true
                        placeholder: "Type it again"
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        UiText {
                            Layout.fillWidth: true
                            text: newPasswordAgain.text && newPassword.text !== newPasswordAgain.text ? "Those two don't match" : "It asks for your current password to make the change"
                            color: newPasswordAgain.text && newPassword.text !== newPasswordAgain.text ? Theme.danger : Theme.inkMuted
                            font.pixelSize: Theme.hintSize
                        }
                        PillButton { text: "Cancel"; onClicked: page.close() }
                        PillButton {
                            primary: true
                            text: "Change"
                            enabled: newPassword.text.length > 0 && newPassword.text === newPasswordAgain.text
                            onClicked: {
                                Machine.setPassword(page.me.name, newPassword.text);
                                page.close();
                            }
                        }
                    }
                }
            ]
        }

        CpRow {
            label: "Sign-in PIN"
            hint: Machine.hasPin ? "On: sign in and unlock with your 4-digit PIN; your password still works" : "A 4-digit PIN to sign in quickly, as on Windows"
            opens: page.form !== "pin" && !Machine.hasPin
            onClicked: {
                page.form = "pin";
                pinField.focusField();
            }

            PillButton {
                visible: Machine.hasPin && page.form !== "pin"
                text: "Change"
                onClicked: {
                    page.form = "pin";
                    pinField.focusField();
                }
            }

            PillButton {
                visible: Machine.hasPin && page.form !== "pin"
                danger: true
                text: "Remove"
                onClicked: Machine.setPin(page.me.name, "")
            }

            below: [
                RowLayout {
                    Layout.fillWidth: true
                    visible: page.form === "pin"
                    spacing: Theme.space2

                    FieldBox {
                        id: pinField
                        Layout.preferredWidth: 140
                        password: true
                        placeholder: "New PIN"
                    }
                    FieldBox {
                        id: pinAgain
                        Layout.preferredWidth: 140
                        password: true
                        placeholder: "Again"
                    }
                    UiText {
                        Layout.fillWidth: true
                        text: pinField.text && !/^[0-9]{4}$/.test(pinField.text) ? "4 digits"
                            : pinAgain.text && pinField.text !== pinAgain.text ? "Those don't match" : ""
                        color: Theme.danger
                        font.pixelSize: Theme.hintSize
                    }
                    PillButton { text: "Cancel"; onClicked: page.close() }
                    PillButton {
                        primary: true
                        text: "Save"
                        enabled: /^[0-9]{4}$/.test(pinField.text) && pinField.text === pinAgain.text
                        onClicked: {
                            Machine.setPin(page.me.name, pinField.text);
                            page.close();
                        }
                    }
                }
            ]
        }

        CpRow {
            label: "Password hint"
            hint: "Shown on the sign-in screen after three wrong tries. Don't write the password itself."
            opens: page.form !== "hint"
            onClicked: page.form = "hint"

            below: [
                RowLayout {
                    Layout.fillWidth: true
                    visible: page.form === "hint"
                    spacing: Theme.space2
                    FieldBox {
                        id: hintText
                        Layout.fillWidth: true
                        placeholder: "A hint only you would understand (empty removes it)"
                    }
                    PillButton { text: "Cancel"; onClicked: page.close() }
                    PillButton {
                        primary: true
                        text: "Save"
                        onClicked: {
                            Machine.setHint(page.me.name, hintText.text.trim());
                            page.close();
                        }
                    }
                }
            ]
        }
    }

    CpSection {
        title: "Other people"

        Repeater {
            model: page.others

            CpRow {
                id: personRow
                required property var modelData
                glyph: "avatar-default-symbolic"
                label: modelData.full
                hint: (modelData.admin ? "Administrator" : "Standard account") + " · signs in as " + modelData.name

                PillButton {
                    text: personRow.modelData.admin ? "Make standard" : "Make administrator"
                    onClicked: Machine.setAdmin(personRow.modelData.name, !personRow.modelData.admin)
                }

                PillButton {
                    danger: true
                    text: page.removing === personRow.modelData.name ? "Remove, with their files?" : "Remove"
                    onClicked: {
                        if (page.removing === personRow.modelData.name) {
                            Machine.removePerson(personRow.modelData.name);
                            page.removing = "";
                        } else page.removing = personRow.modelData.name;
                    }
                }
            }
        }

        CpRow {
            glyph: "list-add-symbolic"
            label: "Add someone"
            hint: "They get their own desktop, files and settings"
            opens: page.form !== "add"
            onClicked: {
                page.form = "add";
                addFull.focusField();
            }

            below: [
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: page.form === "add"
                    spacing: Theme.space2

                    FieldBox {
                        id: addFull
                        Layout.fillWidth: true
                        placeholder: "Their name"
                        onTextChanged: addShort.text = text.split(" ")[0].toLowerCase().replace(/[^a-z0-9]/g, "")
                    }
                    FieldBox {
                        id: addShort
                        Layout.fillWidth: true
                        placeholder: "A short name for signing in (small letters)"
                    }
                    FieldBox {
                        id: addPassword
                        Layout.fillWidth: true
                        password: true
                        placeholder: "Their password"
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space2

                        ToggleSwitch {
                            id: addAdmin
                            on: false
                            onToggled: on = !on
                        }
                        UiText {
                            Layout.fillWidth: true
                            text: "Administrator (can install apps and change settings)"
                        }
                        PillButton { text: "Cancel"; onClicked: page.close() }
                        PillButton {
                            primary: true
                            text: "Add"
                            enabled: addFull.text.trim().length > 0 && /^[a-z][a-z0-9_-]{0,30}$/.test(addShort.text) && addPassword.text.length > 0
                            onClicked: {
                                Machine.addPerson(addShort.text, addFull.text.trim(), addPassword.text, addAdmin.on);
                                page.close();
                            }
                        }
                    }
                }
            ]
        }
    }
}
