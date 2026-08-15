import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property color badgeColor: Color.urgent
  property bool crossed: false
  property bool warning: false

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  readonly property real stroke: Math.max(1.6, iconSize * 0.12)
  readonly property real pad: iconSize * 0.08

  Rectangle {
    id: ring
    anchors.fill: parent
    anchors.margins: root.pad
    radius: width / 2
    color: "transparent"
    border.color: root.color
    border.width: root.stroke
  }

  Rectangle {
    width: root.stroke
    height: ring.height * 0.62
    radius: width / 2
    color: root.color
    anchors.horizontalCenter: ring.horizontalCenter
    anchors.verticalCenter: ring.verticalCenter
  }

  Rectangle {
    width: ring.width * 0.62
    height: root.stroke
    radius: height / 2
    color: root.color
    anchors.horizontalCenter: ring.horizontalCenter
    anchors.verticalCenter: ring.verticalCenter
  }

  Rectangle {
    visible: root.crossed
    anchors.centerIn: parent
    width: parent.width * 1.22
    height: Math.max(2, parent.height * 0.14)
    radius: height / 2
    color: root.color
    rotation: -45
  }

  BorderSurface {
    visible: root.warning
    width: Math.max(7, parent.width * 0.42)
    height: width
    radius: width / 2
    color: root.badgeColor
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    borderSpec: Border.flat(Color.popups.background, 1)

    Text {
      anchors.centerIn: parent
      text: "!"
      color: Color.background
      font.family: Style.font.family
      font.pixelSize: Math.max(6, parent.height * 0.72)
      font.bold: true
    }
  }
}
