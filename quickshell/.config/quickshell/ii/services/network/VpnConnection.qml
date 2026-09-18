import QtQuick
import qs.modules.common

QtObject {
    property var lastIpcObject: ({})
    readonly property string name: lastIpcObject.name ?? ""
    readonly property string type: lastIpcObject.type ?? ""
    readonly property string uuid: lastIpcObject.uuid ?? ""
    readonly property bool active: lastIpcObject.active ?? false
    readonly property string displayName: {
        const entry = Config.options.vpn.aliases.find(a => a.uuid === uuid);
        return entry ? entry.alias : name;
    }
}
