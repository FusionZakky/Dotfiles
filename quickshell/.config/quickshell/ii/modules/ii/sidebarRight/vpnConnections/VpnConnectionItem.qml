import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.services.network
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
DialogListItem {
    id: root
    required property VpnConnection vpnConnection
    property bool editing: false
    active: vpnConnection?.active ?? false
    onClicked: {
        if (root.editing) return;
        if (root.vpnConnection.active) {
            Vpn.disconnect(root.vpnConnection);
        } else {
            Vpn.connectTo(root.vpnConnection);
        }
    }

    function saveAlias(newAlias) {
        const uuid = root.vpnConnection.uuid;
        const aliases = Config.options.vpn.aliases;
        const idx = aliases.findIndex(a => a.uuid === uuid);
        if (newAlias.length === 0) {
            if (idx !== -1) aliases.splice(idx, 1);
        } else if (idx !== -1) {
            aliases[idx] = { uuid: uuid, alias: newAlias };
        } else {
            aliases.push({ uuid: uuid, alias: newAlias });
        }
        Config.options.vpn.aliases = aliases;
        root.editing = false;
    }

    contentItem: RowLayout {
        anchors {
            fill: parent
            topMargin: root.verticalPadding
            bottomMargin: root.verticalPadding
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }
        spacing: 10
        MaterialSymbol {
            iconSize: Appearance.font.pixelSize.larger
            text: root.vpnConnection?.type === "wireguard" ? "vpn_key" : "shield_lock"
            color: Appearance.colors.colOnSurfaceVariant
        }
        StyledText {
            Layout.fillWidth: true
            visible: !root.editing
            color: Appearance.colors.colOnSurfaceVariant
            elide: Text.ElideRight
            text: root.vpnConnection?.displayName ?? Translation.tr("Unknown")
            textFormat: Text.PlainText
        }
        MaterialTextField {
            id: renameField
            Layout.fillWidth: true
            visible: root.editing
            text: root.vpnConnection?.displayName ?? ""
            onAccepted: root.saveAlias(text.trim())
            onVisibleChanged: if (visible) { forceActiveFocus(); selectAll(); }
            Keys.onEscapePressed: root.editing = false
        }
        MaterialSymbol {
            visible: root.editing
            text: "check"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSurfaceVariant
            MouseArea {
                anchors.fill: parent
                onClicked: root.saveAlias(renameField.text.trim())
            }
        }
        MaterialSymbol {
            visible: (root.vpnConnection?.active ?? false) && !root.editing
            text: "check"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSurfaceVariant
        }
        MaterialSymbol {
            visible: !root.editing
            text: "more_vert"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSurfaceVariant
            MouseArea {
                anchors.fill: parent
                onClicked: optionsMenu.open()
            }
        }
    }

    Popup {
        id: optionsMenu
        parent: root
        x: root.width - width - 8
        y: root.height
        width: 160
        padding: 4
        background: Rectangle {
            color: Appearance.colors.colLayer0
            radius: Appearance.rounding.normal
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
        }
        contentItem: ColumnLayout {
            spacing: 0
            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 36
                contentItem: StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Translation.tr("Rename")
                }
                onClicked: {
                    optionsMenu.close();
                    root.editing = true;
                }
            }
            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 36
                visible: Config.options.vpn.aliases.findIndex(a => a.uuid === root.vpnConnection.uuid) !== -1
                contentItem: StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Translation.tr("Clear alias")
                }
                onClicked: {
                    optionsMenu.close();
                    root.saveAlias("");
                }
            }
        }
    }
}
