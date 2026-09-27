import QtQuick
import qs.Commons
import qs.Ui
import "../components"

// A titled card of task rows.
//
// One instance per section: accepted tasks are one, suggestions are another.
// They are kept apart rather than concatenated because they are different
// things: one is the user's list, the other the agent's proposal awaiting a
// verdict. Keyboard Tab also jumps between them as sibling regions.
//
// `label` is optional. The tab already names what the first card holds, so only
// the secondary section needs a heading.
Column {
  id: root

  property var rows: []
  property var service: null
  // Empty for the tab's primary card, which the tab itself already names.
  property string label: ""
  // Index of the keyboard cursor, or -1 for none. The page owns it, because it
  // is the page that knows which keys arrived and which card they were meant for.
  property int cursor: -1

  signal changed()
  signal openItem(string id)

  // So the page can scroll a row into view. Rows wrap to two lines, so only the
  // Repeater knows a row's real geometry.
  function itemAt(i) { return rep.itemAt(i) }

  spacing: Style.spacing.md
  visible: (root.rows || []).length > 0

  PanelSectionHeader {
    visible: root.label.length > 0
    text: root.label
    foreground: Color.muted
    fontFamily: Style.font.resolvedFamily
  }

  BorderSurface {
    width: parent.width
    // md * 2, not md: the inner column is inset from the top by md, so a single
    // allowance leaves the last row sitting on the border.
    height: inner.implicitHeight + Style.spacing.lg * 2
    radius: Style.cornerRadius
    color: Color.popups.background
    borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, 1)

    Column {
      id: inner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.spacing.lg
      spacing: Style.spacing.sm

      Repeater {
        id: rep
        model: root.rows || []

        delegate: TodoRow {
          required property var modelData
          required property int index
          width: inner.width
          item: modelData
          service: root.service
          hasCursor: root.cursor === index
          dimmed: modelData.completedAt !== null
                  && modelData.completedAt !== undefined
          onChanged: root.changed()
          onActivated: root.openItem(modelData.id)
        }
      }
    }
  }
}
