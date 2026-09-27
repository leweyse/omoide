import QtQuick
import qs.Commons
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

  // No list edit button on this card. Adding, renaming and deleting to-dos is a
  // list operation, so it belongs on the card rather than on a row. TodosEditor
  // and the manageRequested chain are wired: a `trailing: Component` with a
  // PanelActionButton calling manageRequested(root.blockId, root.items) turns
  // it on, the same shape SummaryBlock and ListBlock use for editRequested.
  // A single to-do's date and reminders open from its title.

  // Hidden once every item in the block is deleted. The block row itself is
  // kept, so a newer version of the plugin can read it back.
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
