import QtQuick
import qs.Commons
import qs.Ui

// The ⋯ dropdown, owned by the window.
//
// It lives here rather than under the button it hangs from because a child
// positioned outside its parent's bounds renders but is never hit-tested -- a
// dropdown below a one-line row could be seen and not clicked. Filling the
// card means the menu is always inside something that contains it.
//
// Entries in, one signal out. It was hardcoded to a memory's Delete; a
// collection needs Edit and Remove, and a second near-identical file would
// have drifted the first time either changed.
// A FocusScope, not a plain Item.
//
// A scope keeps activeFocus when the child holding it disappears or declines a
// key: focus falls back to the scope instead of vanishing. Without that, a
// focused control being hidden or a field swallowing Escape left NOTHING
// focused, and with nothing focused no Keys handler in the dialog could fire.
//
// Being the root also puts it on the parent chain of every control inside, so
// the Escape handler sees keys wherever focus actually sits.
FocusScope {
  id: root

  property bool opened: false
  // Whatever the caller needs handed back with the choice.
  property string targetId: ""
  property real anchorX: 0
  property real anchorY: 0

  // [{ id, label, glyph, destructive }]
  property var entries: []

  signal chose(string action, string targetId)

  function openAt(sceneX, sceneY, id, list) {
    var local = root.mapFromItem(null, sceneX, sceneY)
    root.anchorX = local.x
    root.anchorY = local.y
    root.targetId = id
    root.entries = list || []
    root.opened = true
  }

  function close() {
    root.opened = false
    root.targetId = ""
  }

  visible: opened

  // Escape, on the scope root so it catches the key however deep focus is.
  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_Escape) {
      // Only on a real press: holding Escape auto-repeats, and each
      // repeat would dismiss another layer.
      if (!event.isAutoRepeat) root.opened = false
      event.accepted = true
    }
  }

  // Click anywhere else to dismiss. Safe here: the menu is a child of this
  // same item, so it is hit-tested above the dismiss area.
  MouseArea {
    anchors.fill: parent
    onClicked: root.close()
  }

  BorderSurface {
    id: card
    width: Style.space(150)
    height: items.implicitHeight + Style.spacing.sm * 2
    // Kept inside the surface, so a button near an edge does not push the menu
    // out of view.
    x: Math.max(Style.spacing.md,
                Math.min(root.width - width - Style.spacing.md, root.anchorX - width))
    y: Math.max(Style.spacing.md,
                Math.min(root.height - height - Style.spacing.md,
                         root.anchorY + Style.spacing.xs))
    radius: Style.cornerRadius
    color: Qt.rgba(Color.menu.background.r, Color.menu.background.g,
                   Color.menu.background.b, 1.0)
    borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, 1)

    MouseArea { anchors.fill: parent; onClicked: {} }

    Column {
      id: items
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.spacing.sm
      spacing: 0

      Repeater {
        model: root.entries

        delegate: CursorSurface {
          id: entryRow
          required property var modelData
          readonly property color tint: modelData.destructive ? Color.urgent
                                                              : Color.menu.text

          width: parent.width
          height: Style.spacing.popupRowHeight
          radius: Style.space(4)
          hasCursor: hover.containsMouse
          bordered: false
          foreground: Color.menu.text
          accent: entryRow.tint
          // Tinted at the SELECTED alpha: the hover alpha this theme ships
          // (0.08) is invisible against the menu's own background.
          fill: Style.selectedFillFor(entryRow.tint, entryRow.tint, entryRow.tint)
          // Only the fill changes under the cursor. CursorSurface applies its
          // hover-cursor border whenever hasCursor is set, and `bordered:
          // false` governs the resting state only.
          borderSpec: Border.none()

          MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              var action = modelData.id
              var id = root.targetId
              root.close()
              root.chose(action, id)
            }
          }

          // Sized and aligned rather than anchored: anchors on the children of
          // a positioner fight it.
          Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: Style.spacing.sm
            spacing: Style.spacing.sm

            Text {
              // Fixed-width slot, so every label starts at the same x whatever
              // its icon is.
              width: Style.space(16)
              height: parent.height
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              text: modelData.glyph || ""
              color: entryRow.tint
              font.family: Style.font.resolvedFamily
              font.pixelSize: Style.font.body
            }

            Text {
              height: parent.height
              verticalAlignment: Text.AlignVCenter
              text: modelData.label || ""
              color: entryRow.tint
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
            }
          }
        }
      }
    }
  }
}
