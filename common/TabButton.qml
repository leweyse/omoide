import QtQuick
import qs.Commons
import qs.Ui

// A tab trigger: a button-sized control whose LABEL can be underlined when
// selected, with its count kept separate.
//
// Not qs.Ui Button, which takes its label as one `text` string and exposes no
// handle on the Text that renders it -- so there is no way to underline from
// outside, and no way to underline the name without dragging the count into the
// rule with it. The chrome here is deliberately the kit's: the same fills, the
// same control paddings, so a tab still reads as a button next to one.
BorderSurface {
  id: root

  property string label: ""
  property int count: 0
  property bool selected: false
  property bool hasCursor: false

  property color foreground: Color.popups.text
  property color background: Color.popups.background
  property color accent: Color.accent
  property string fontFamily: Style.font.resolvedFamily

  signal clicked()

  readonly property bool hot: mouse.containsMouse || root.hasCursor

  implicitWidth: content.implicitWidth + Style.spacing.controlPaddingX * 2
  implicitHeight: Style.spacing.controlHeight
  width: implicitWidth
  height: implicitHeight
  radius: Style.cornerRadius

  // The kit's own state precedence, so this cannot drift from a real Button.
  color: mouse.pressed ? Style.pressedFillFor(root.foreground, root.accent)
         : root.hot ? Style.hoverFillFor(root.foreground, root.accent)
         : root.selected ? Style.selectedFillFor(root.foreground, root.accent)
         : root.background

  borderSpec: root.hasCursor
              ? Border.flat(Color.accent, Math.max(1, Style.space(1)))
              : Border.none()

  Behavior on color { ColorAnimation { duration: 120 } }

  FocusRing {
    diagonalCorners: true
    anchors.fill: parent
    radius: root.radius
    gap: 1
    hasCursor: root.hasCursor
    hot: false
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }

  Row {
    id: content
    anchors.centerIn: parent
    spacing: Style.spacing.lg

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.label
      // The name only. A rule running under the count too reads as one long
      // line rather than as emphasis on the tab.
      font.underline: root.selected
      color: root.selected ? Color.accent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.subtitle
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.count > 0
      text: root.count
      color: Color.muted
      font.family: root.fontFamily
      font.pixelSize: Math.max(8, Style.font.subtitle - 2)
    }
  }
}
