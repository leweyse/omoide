import QtQuick
import qs.Commons
import qs.Ui
import "../common"
import "../MemoryModel.js" as Model

// One to-do, used both inside a memory and in the archive, so the two can
// never drift apart.
//
// Two states:
//   active     a circle bound to completed_at
//   suggested  a dot, plus Add and Dismiss -- the agent inferred this one, so
//              it waits for the user rather than joining their task list
//
// The dot is not decoration: there is nothing to complete until the suggestion
// has been accepted, and a check box there would invite ticking off something
// the user never agreed to.
Item {
  id: root

  property var item: ({})
  property var service: null
  property bool dimmed: false
  // Keyboard cursor. Mouse hover deliberately does not set it: two
  // highlights at once is worse than none on the row you are not pointing at.
  property bool hasCursor: false
  signal changed()
  signal activated()

  readonly property bool suggested: !!(item && item.status === "suggested")
  readonly property bool done: !!(item && item.completedAt)
  readonly property bool overdue: {
    if (root.done || !item || !item.dueAt) return false
    var due = Model.parseDate(item.dueAt)
    return due !== null && due.getTime() < Date.now()
  }

  width: parent ? parent.width : 0
  height: Math.max(Style.space(34), layout.height + Style.spacing.sm * 2)

  function accept() {
    if (!service || !item) return
    service.call(["item", "promote", "--id", item.id],
                 function () { root.changed() })
  }

  function dismiss() {
    if (!service || !item) return
    service.call(["item", "cancel", "--id", item.id],
                 function () { root.changed() })
  }

  function toggle() {
    if (!service || !item || root.suggested) return
    service.call(["item", root.done ? "reopen" : "complete", "--id", item.id],
                 function () { root.changed() })
  }

  // An Item, not a Row. Anchors on the children of a positioner are not
  // supported, and this had a verticalCenter-anchored check box sitting next to
  // a top-aligned text Column, which is what put the two out of line.
  Item {
    id: layout
    opacity: root.done || root.dimmed ? 0.5 : 1.0
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    height: body.implicitHeight

    readonly property real slot: Style.space(18)

    // Centre of the title's FIRST line, so a to-do that wraps to two lines
    // keeps its circle beside the first line instead of floating in the middle
    // of the block.
    readonly property real firstLineCentre:
      (titleText.lineCount > 0 ? titleText.implicitHeight / titleText.lineCount
                               : titleText.implicitHeight) / 2

    Rectangle {
      id: box
      width: root.suggested ? Style.space(6) : Style.space(15)
      height: width
      x: Math.round((layout.slot - width) / 2)
      y: Math.round(layout.firstLineCentre - height / 2)
      radius: width / 2
      color: root.suggested ? (root.hasCursor ? Color.accent : Color.muted)
                            : (root.done ? Color.accent : "transparent")
      border.width: root.suggested ? 0 : 1
      // Accent on focus, so the box is what carries it. A suggestion is a 6px
      // dot with no border, so there the fill takes the accent instead.
      border.color: root.hasCursor ? Color.accent
                                   : (root.done ? Color.accent : Color.muted)

      // The inner ring, concentric because the box is a circle: radius less the
      // inset lands exactly on the smaller circle's edge.
      FocusRing {
        anchors.fill: parent
        radius: parent.width / 2
        gap: 1
        hasCursor: root.hasCursor && !root.suggested
        hot: false
      }

      MouseArea {
        anchors.fill: parent
        enabled: !root.suggested
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggle()
      }
    }

    // Accept or throw away, on the row itself, so a list of suggestions can be
    // cleared without opening any of them.
    Row {
      id: suggestActions
      visible: root.suggested
      anchors.right: parent.right
      y: Math.round(layout.firstLineCentre - height / 2)
      spacing: Style.spacing.xxs

      PanelActionButton {
        iconText: "+"
        tooltipText: "Add to your tasks"
        size: Style.space(22)
        foreground: Color.popups.text
        hoverColor: Color.accent
        fontFamily: Style.font.resolvedFamily
        onClicked: root.accept()
      }

      PanelActionButton {
        iconText: "󰩹"
        tooltipText: "Delete this suggestion"
        size: Style.space(22)
        foreground: Color.popups.text
        hoverColor: Color.urgent
        fontFamily: Style.font.resolvedFamily
        onClicked: root.dismiss()
      }
    }

    Column {
      id: body
      anchors.left: parent.left
      anchors.leftMargin: layout.slot + Style.spacing.md
      anchors.right: suggestActions.visible ? suggestActions.left : parent.right
      anchors.rightMargin: suggestActions.visible ? Style.spacing.md : 0
      anchors.top: parent.top
      spacing: 0

      Text {
        id: titleText
        width: parent.width
        // Underlined rather than boxed: the row is not a card, and a rule under
        // the words says "this one" without enclosing anything.
        font.underline: root.hasCursor
        text: root.item ? (root.item.title || "") : ""
        wrapMode: Text.WordWrap
        color: Color.popups.text
        font.family: Style.font.resolvedFamily
        font.pixelSize: Style.font.body

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.activated()
        }
      }

      Text {
        visible: text.length > 0
        text: root.item
              ? Model.formatWhen(root.item.completedAt || root.item.dueAt) : ""
        // Overdue but still open reads red, and is never auto-hidden.
        color: root.overdue ? Color.urgent : Color.muted
        font.family: Style.font.resolvedFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
