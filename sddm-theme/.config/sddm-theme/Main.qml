import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: "#0f0f0f"

    // TOGGLE MEDIA TYPE HERE
    // Set to 'true' to load current_video.mp4, or 'false' for current_wallpaper.jpg
    property bool useVideo: false

    // 1. VIDEO PLAYER (Reads from ~/Pictures/sddm_media/current_video.mp4)
    Item {
        anchors.fill: parent
        visible: root.useVideo

        MediaPlayer {
            id: player
            source: "file:///home/zakkaria/Pictures/sddm_media/current_video.mp4"
            audioOutput: AudioOutput { muted: true }
            videoOutput: videoOut
            loops: MediaPlayer.Infinite
            Component.onCompleted: {
                if (root.useVideo) player.play()
            }
        }

        VideoOutput {
            id: videoOut
            anchors.fill: parent
            fillMode: VideoOutput.PreserveAspectCrop
        }
    }

    // 2. STATIC WALLPAPER (Reads from ~/Pictures/sddm_media/current_wallpaper.jpg)
    Image {
        id: bgImage
        anchors.fill: parent
        visible: !root.useVideo
        source: "file:///home/zakkaria/Pictures/sddm_media/current_wallpaper.jpg"
        fillMode: Image.PreserveAspectCrop
    }

    // 3. LOGIN BOX OVERLAY
    Rectangle {
        anchors.centerIn: parent
        width: 320
        height: 240
        color: "#1a1a26"
        radius: 12
        opacity: 0.95

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 12
            width: parent.width - 40

            Text {
                text: "HYPRLAND LOG-IN"
                color: "#c0caf5"
                font.bold: true
                font.pixelSize: 16
                Layout.alignment: Qt.AlignHCenter
            }

            TextField {
                id: username
                placeholderText: "Username"
                text: userModel.lastUser
                Layout.fillWidth: true
                font.pixelSize: 14
            }

            TextField {
                id: password
                placeholderText: "Password"
                echoMode: TextInput.Password
                Layout.fillWidth: true
                font.pixelSize: 14
                focus: true

                onAccepted: sddm.login(username.text, password.text, sessionIndex)
            }

            Button {
                text: "Login"
                Layout.fillWidth: true
                onClicked: sddm.login(username.text, password.text, sessionIndex)
            }
        }
    }
}
