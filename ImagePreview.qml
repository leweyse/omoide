import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// A capture at full size.
//
// Clicking a screenshot used to jump straight to tensaku, which is an editor --
// a heavy answer to "let me see that properly". This shows the image, and
// offers the editor as one of the things you can then do with it.
// A FocusScope, not a plain Item.
//
// A scope keeps activeFocus when the child holding it disappears or declines a
// key: focus falls back to the scope instead of vanishing. Without that, a
// focused control being hidden -- a reminder row removed by its own delete
// button -- or a field swallowing Escape left NOTHING focused, and with nothing
// focused no Keys handler in the dialog could fire. The keyboard died and no
// number of Escapes brought it back.
//
// Being the root also puts it on the parent chain of every control inside, so
// the Escape handler below sees keys wherever focus actually sits.
FocusScope {
  id: root

  property string source: ""
  property bool opened: false

  // 0 when this covers a whole screen; the card's inner radius when it
  // is layered inside one.
  property real scrimRadius: 0

  signal editRequested()

  function open(path) {
    if (!path || !path.length) return
    root.source = path
    root.opened = true
    Qt.callLater(function () { keys.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.source = ""
  }

  visible: opened

  // Escape, on the scope root so it catches the key however deep focus is.
  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_Escape) {
      // Only on a real press: holding Escape auto-repeats, and each
      // repeat would dismiss another layer.
      if (!event.isAutoRepeat) root.close()
      event.accepted = true
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Color.menu.scrim
    // Matches the curve of whatever this is layered over. Anchored inside the
    // Space card, a square scrim paints across the card's rounded corners and
    // the dialog looks like it has square ones.
    radius: root.scrimRadius
    MouseArea { anchors.fill: parent; onClicked: root.close() }
  }

  Item {
    id: keys
    anchors.fill: parent
    focus: root.opened
    Keys.onPressed: function (event) {
      if (event.key === Qt.Key_Escape) {
        if (!event.isAutoRepeat) root.close()
        event.accepted = true
      }
    }

    RoundedImage {
      id: shot
      anchors.centerIn: parent
      // Fits the dialog with room to breathe, at the image's own aspect ratio
      // so nothing is cropped -- the point here is seeing all of it.
      readonly property real maxWidth: parent.width - Style.spacing.panelPadding * 2
      readonly property real maxHeight: parent.height - Style.space(70)
      width: shot.sourceAspect > 0
             ? Math.min(maxWidth, maxHeight * shot.sourceAspect)
             : maxWidth
      height: shot.sourceAspect > 0 ? width / shot.sourceAspect : maxHeight
      source: root.source ? "file://" + root.source : ""
      fillMode: Image.PreserveAspectFit

      // Swallow clicks so the image itself does not dismiss.
      MouseArea { anchors.fill: parent; onClicked: {} }
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: shot.bottom
      anchors.topMargin: Style.spacing.md
      spacing: Style.spacing.controlGap

      Button {
        text: "Edit"
        tooltipText: "Crop or annotate in tensaku"
        foreground: Color.menu.text
        background: Color.menu.background
        fontFamily: Style.font.menuFamily
        onClicked: {
          root.editRequested()
          root.close()
        }
      }

      Button {
        text: "Close"
        foreground: Color.menu.text
        background: Color.menu.background
        fontFamily: Style.font.menuFamily
        onClicked: root.close()
      }
    }
  }
}
