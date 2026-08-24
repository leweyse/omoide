import QtQuick
import qs.Commons
import qs.Ui
import "../components"

// "To-dos" is a label the renderer owns, never something the model writes.
BlockCard {
  id: root
  property var payload: ({})
  property var items: []
  property var service: null
  // Which row the drill-in is on, or -1 when the card itself holds focus.
  property int cursor: -1
  signal changed()
  signal openItem(var item)
  // The card asks; the window owns the dialog. Same shape as editBlock.
  signal manageRequested(string blockId, var items)
  heading: "To-dos"

  // No edit affordance in v1. Adding, renaming and deleting to-dos is a list
  // operation, so it belongs on the card rather than on any one row -- but the
  // card is not carrying it yet. TodosEditor and the manageRequested chain
  // below it are intact; restoring the pencil is a `trailing: Component` with
  // a PanelActionButton calling manageRequested(root.blockId, root.items),
  // the same shape SummaryBlock and ListBlock use for editRequested.
  //
  // A single to-do's date and reminders are still editable -- click its title.

  // Nothing left to show once every item in the block has been deleted. The
  // block row itself is kept -- a newer version of the plugin must be able to
  // read it back -- but an empty card is not worth drawing.
  visible: (root.items || []).length > 0

  Column {
    width: parent.width
    spacing: Style.spacing.sm

    Repeater {
      model: root.items || []

      delegate: TodoRow {
        required property var modelData
        required property int index
        hasCursor: root.cursor === index
        width: parent.width
        item: modelData
        service: root.service
        onChanged: root.changed()
        onActivated: root.openItem(modelData)
      }
    }
  }
}
