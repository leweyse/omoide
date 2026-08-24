import QtQuick
import qs.Commons
import qs.Ui

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
  heading: "To-dos"

  // Nothing left to show once every item in the block has been deleted. The
  // block row itself is kept -- a newer version of the plugin must be able to
  // read it back -- but an empty card is not worth drawing.
  visible: (root.items || []).length > 0

  Column {
    width: parent.width
    spacing: Style.spacing.xs

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
