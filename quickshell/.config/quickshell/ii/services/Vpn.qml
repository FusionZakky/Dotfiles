pragma Singleton
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import QtQuick
import qs.services.network
import qs.modules.common.functions
/**
 * VPN service with nmcli. Lists NetworkManager VPN/WireGuard connection
 * profiles and lets you activate/deactivate them.
 */
Singleton {
    id: root
    readonly property list<VpnConnection> connections: []
    readonly property VpnConnection active: connections.find(c => c.active) ?? null
    readonly property bool connected: active !== null
    property bool busy: false
    property bool restoredOnStartup: false
    readonly property string materialSymbol: root.connected ? "vpn_lock" : "vpn_key_off"
    property string stateFilePath: ""

    Component.onCompleted: {
        root.stateFilePath = FileUtils.trimFileProtocol(`${Directories.state}/vpn_last_connection`);
        Quickshell.execDetached(["mkdir", "-p", FileUtils.trimFileProtocol(Directories.state)]);
    }

    function refresh(): void {
        getConnections.running = true;
    }
    function saveState(): void {
        stateFileView.setText(root.active ? root.active.uuid : "");
    }
    function connectTo(connection: VpnConnection): void {
        root.busy = true;
        connectProc.exec(["nmcli", "connection", "up", connection.uuid]);
    }
    function disconnect(connection: VpnConnection): void {
        root.busy = true;
        disconnectProc.exec(["nmcli", "connection", "down", connection.uuid]);
    }
    function toggle(): void {
        if (root.active) disconnect(root.active);
        else if (root.connections.length > 0) connectTo(root.connections[0]);
    }
    function tryRestoreState(): void {
        if (root.restoredOnStartup) return;
        root.restoredOnStartup = true;
        stateFileView.reload();
    }

    FileView {
        id: stateFileView
        path: root.stateFilePath
        onLoaded: {
            const savedUuid = text().trim();
            if (savedUuid.length > 0) {
                const match = root.connections.find(c => c.uuid === savedUuid);
                if (match && !match.active) root.connectTo(match);
            }
        }
        onLoadFailed: error => {
            if (error == FileViewError.FileNotFound) {
                // No saved state yet, nothing to restore
            }
        }
    }

    Process {
        id: connectProc
        stdout: SplitParser { onRead: root.refresh() }
        onExited: { root.busy = false; root.refresh(); }
    }
    Process {
        id: disconnectProc
        stdout: SplitParser { onRead: root.refresh() }
        onExited: { root.busy = false; root.refresh(); }
    }
    Process {
        id: subscriber
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser {
            onRead: root.refresh()
        }
    }
    Process {
        id: getConnections
        running: true
        command: ["nmcli", "-t", "-f", "NAME,TYPE,UUID,ACTIVE", "connection", "show"]
        environment: ({ LANG: "C", LC_ALL: "C" })
        stdout: StdioCollector {
            onStreamFinished: {
                const rep = new RegExp("\\\\:", "g");
                const PLACEHOLDER = "STRINGWHICHHOPEFULLYWONTBEUSED";
                const rep2 = new RegExp(PLACEHOLDER, "g");
                const allConnections = text.trim().split("\n").filter(l => l.length > 0).map(line => {
                    const parts = line.replace(rep, PLACEHOLDER).split(":");
                    return {
                        name: parts[0]?.replace(rep2, ":") ?? "",
                        type: parts[1] ?? "",
                        uuid: parts[2] ?? "",
                        active: parts[3] === "yes"
                    };
                }).filter(c => c.type === "vpn" || c.type === "wireguard");
                const rConnections = root.connections;
                const destroyed = rConnections.filter(rc => !allConnections.find(c => c.uuid === rc.uuid));
                for (const c of destroyed)
                    rConnections.splice(rConnections.indexOf(c), 1).forEach(n => n.destroy());
                for (const c of allConnections) {
                    const match = rConnections.find(rc => rc.uuid === c.uuid);
                    if (match) {
                        match.lastIpcObject = c;
                    } else {
                        rConnections.push(vpnComp.createObject(root, {
                            lastIpcObject: c
                        }));
                    }
                }
                root.saveState();
                root.tryRestoreState();
            }
        }
    }
    Component {
        id: vpnComp
        VpnConnection {}
    }
}
