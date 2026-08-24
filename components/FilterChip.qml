import QtQuick
import qs.Commons
import qs.Ui
import "../common"

// One filter chip: label, count, selected state.
BorderSurface {
  id: root

  property string label: ""
  property string icon: ""
  property int count: 0
  property bool selected: false
  property bool hasCursor: false
  signal picked()

  // Hover only, never focus. A fill on focus lowers contrast against the
  // label; the accent border and the inner ring already carry it. Selection
  // keeps its own fill, so the two states stay distinguishable.
  readonly property bool hot: mouse.containsMouse

  implicitWidth: content.implicitWidth + Style.spacing.md * 2
  implicitHeight: Style.space(24)
  width: implicitWidth
  height: implicitHeight
  radius: height / 2
  color: root.selected
         ? Style.selectedFillFor(Color.popups.text, Color.accent, Color.urgent)
         : (root.hot ? Style.hoverFillFor(Color.popups.text, Color.accent, Color.urgent)
                     : "transparent")
  // The keyboard cursor gets a full-strength accent border, the same as a badge
  // on the memory page. Everything else keeps the kit's state ramp.
  borderSpec: root.hasCursor
              ? Border.flat(Color.accent, Math.max(1, Style.space(1)))
              : Border.controlSpec(root.selected ? "selected"
                                   : (root.hot ? "hover-cursor" : "normal"),
                                   Color.popups.text, Color.accent, Color.urgent)

  // Concentric with the pill: radius is height/2, so a ring inset by 2 lands on
  // (height - 4) / 2 -- the same curve one step in.
  FocusRing {
    sideBars: true
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
    onClicked: root.picked()
  }

  Row {
    id: content
    anchors.centerIn: parent
    spacing: Style.spacing.sm

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.icon.length > 0
      text: root.icon
      color: root.selected ? Color.accent : Color.muted
      font.family: Style.font.resolvedFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      // Facet labels are tags, which the model writes. Never markup.
      textFormat: Text.PlainText
      text: root.label
      // The label alone, not the count: a rule running under both reads as one
      // long line rather than as emphasis on the name.
      font.underline: root.selected
      color: root.selected ? Color.accent : Color.popups.text
      font.family: Style.font.resolvedFamily
      font.pixelSize: Style.font.caption
    }

    // Level with the label, not raised. It was offset up as a superscript,
    // copying the reference UI, which at 8px against a 10px label just read as
    // misaligned rather than as typography.
    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.count > 0
      text: root.count
      color: Color.muted
      font.family: Style.font.resolvedFamily
      font.pixelSize: Math.max(8, Style.font.caption - 2)
    }
  }
}
