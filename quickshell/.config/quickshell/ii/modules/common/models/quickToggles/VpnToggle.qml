import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("VPN")
    statusText: Vpn.connected ? (Vpn.active?.displayName ?? "") : Translation.tr("Not connected")
    tooltipText: Translation.tr("%1 | Click to pick a connection").arg(statusText)
    icon: Vpn.materialSymbol

    toggled: Vpn.connected
    mainAction: () => Vpn.toggle()
    hasMenu: true
}
