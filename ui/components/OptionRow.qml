import QtQuick
import qs.Commons
import qs.Ui
import "../common/Radii.js" as Radii

// A labelled segmented choice: a section name, one outlined control holding a
// segment per option, and a caption for the picked option. While the owner's arrow keys act on the row, the name
// and the control's border take the accent.
//
// `options` is a list of { value, label, enabled }. A disabled option is shown
// dimmed and ignores clicks rather than being hidden.
Column {
  id: root

  property string label: ""
  property bool active: false
  property var options: []
  property string value: ""
  property string caption: ""

  signal picked(string value)

  spacing: Style.spacing.xl

  readonly property real borderWidth: Math.max(1, Style.space(1))

  Text {
    text: root.label
    color: root.active ? Color.accent : Color.muted
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.body
    font.capitalization: Font.AllUppercase
  }

  // The same width in both states, so focusing never moves the segments.
  BorderSurface {
    id: control
    width: segments.implicitWidth + root.borderWidth * 2
    height: segments.implicitHeight + root.borderWidth * 2
    radius: Style.cornerRadius
    color: "transparent"
    borderSpec: root.active
                ? Border.flat(Color.accent, root.borderWidth)
                : Border.controlSpec("normal", Color.menu.text, Color.accent)

    Row {
      id: segments
      x: root.borderWidth
      y: root.borderWidth

      Repeater {
        model: root.options

        delegate: Rectangle {
          required property var modelData
          readonly property bool picked: root.value === modelData.value

          width: segmentLabel.implicitWidth + Style.spacing.controlPaddingX * 2
          height: Style.spacing.controlHeight
          radius: Radii.nested(Style.cornerRadius, root.borderWidth)
          color: picked ? Style.selectedFillFor(Color.menu.text, Color.accent)
                 : (mouse.containsMouse && modelData.enabled
                    ? Style.hoverFillFor(Color.menu.text, Color.accent) : "transparent")
          opacity: modelData.enabled ? 1.0 : 0.45

          Text {
            id: segmentLabel
            anchors.centerIn: parent
            text: modelData.label
            color: parent.picked ? Color.accent : Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.subtitle
          }

          MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: modelData.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (modelData.enabled) root.picked(modelData.value)
          }
        }
      }
    }
  }

  Text {
    width: root.width
    text: root.caption
    wrapMode: Text.WordWrap
    color: Color.muted
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.body
  }
}
