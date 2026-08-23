import QtQuick
import qs.Commons
import qs.Ui
import "../blocks" as Blocks

// A card of task rows.
//
// One instance per tab, now that Anytime and Suggested fold into Upcoming
// rather than getting headings of their own. It stays a component because the
// card has real structure -- a bordered surface, an inset column, a per-row
// delegate -- and folding that back into the page buys nothing.
Column {
  id: root

  property var rows: []
  property var service: null

  signal changed()
  signal openItem(string id)

  spacing: Style.spacing.sm
  visible: (root.rows || []).length > 0

  BorderSurface {
    width: parent.width
    // md * 2, not md: the inner column is inset from the top by md, so a single
    // allowance leaves the last row sitting on the border.
    height: inner.implicitHeight + Style.spacing.md * 2
    radius: Style.cornerRadius
    color: Color.popups.background
    borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, 1)

    Column {
      id: inner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.spacing.md
      spacing: Style.spacing.xs

      Repeater {
        model: root.rows || []

        delegate: Blocks.TodoRow {
          required property var modelData
          width: inner.width
          item: modelData
          service: root.service
          dimmed: modelData.completedAt !== null
                  && modelData.completedAt !== undefined
          onChanged: root.changed()
          onActivated: root.openItem(modelData.id)
        }
      }
    }
  }
}
