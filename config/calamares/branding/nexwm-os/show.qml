import QtQuick 2.0;
import calamares.slideshow 1.0;

// Installer slideshow for NexWM OS. Text-only slides so the slideshow stays
// readable on every panel and needs no extra image assets.
Presentation
{
    id: presentation

    Timer {
        interval: 18000
        running: true
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    Slide {
        Image {
            id: logo1
            source: "logo.png"
            width: 160
            height: 160
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 60
            fillMode: Image.PreserveAspectFit
        }
        Text {
            id: title1
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: logo1.bottom
            anchors.topMargin: 30
            horizontalAlignment: Text.AlignHCenter
            font.pointSize: 20
            color: "#FFFFFF"
            text: qsTr("Welcome to NexWM OS.")
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: title1.bottom
            anchors.topMargin: 26
            horizontalAlignment: Text.AlignHCenter
            font.pointSize: 13
            color: "#C8C8D8"
            text: qsTr("A desktop experience built from the NexWM window manager") + "\n" +
                  qsTr("and the Hyggshi Desktop Environment, on an Ubuntu foundation.") + "\n\n" +
                  qsTr("Installing proceeds in the background while this slideshow plays.")
        }
    }

    Slide {
        Column {
            anchors.centerIn: parent
            width: parent.width * 0.86
            spacing: 24

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                font.pointSize: 16
                color: "#FFFFFF"
                text: qsTr("Start menu with three layouts.")
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                font.pointSize: 12
                color: "#C8C8D8"
                text: qsTr("Modern (Cinnamon-style), Kickoff (Plasma-style) or a small classic menu.") + "\n" +
                      qsTr("Press the Super key and simply type to search. Everything lives in Settings.")
            }
        }
    }

    Slide {
        Column {
            anchors.centerIn: parent
            width: parent.width * 0.86
            spacing: 24

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                font.pointSize: 16
                color: "#FFFFFF"
                text: qsTr("Control Center, battery and notifications.")
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                font.pointSize: 12
                color: "#C8C8D8"
                text: qsTr("Wi-Fi, Bluetooth, volume, brightness, power modes and notifications,") + "\n" +
                      qsTr("all reachable from the panel. Screenshot, lock screen and idle rules are built in.")
            }
        }
    }

    Slide {
        Column {
            anchors.centerIn: parent
            width: parent.width * 0.86
            spacing: 24

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                font.pointSize: 16
                color: "#FFFFFF"
                text: qsTr("Your window manager: NexWM.")
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                font.pointSize: 12
                color: "#C8C8D8"
                text: qsTr("EWMH/ICCCM over XCB with frames, workspaces, snapping and panel struts,") + "\n" +
                      qsTr("plus a Wayland compositor side. Switch window managers live in Settings.") + "\n\n" +
                      qsTr("https://github.com/Hyggshi-OS-Research-Technology/NexWM")
            }
        }
    }
}
