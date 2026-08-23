import QtQuick
import qs.Commons
import "MemoryModel.js" as Model

// QML has no masonry layout, and round-robin leaves ragged columns once
// thumbnails vary in height. Each item goes to the shortest column instead.
Item {
  id: root

  property var items: []
  property int columns: 3
  property int spacing: Style.spacing.md
  property Component delegate: null

  readonly property real columnWidth: columns > 0
    ? (width - spacing * (columns - 1)) / columns : width

  function estimate(item) {
    // Cheap proxy for rendered height, kept in step with MemoryCard: a
    // full-bleed thumbnail at the capture's own aspect within the same bounds
    // the card clamps to, then the padded text block. Only the ratios matter --
    // this decides which column an item lands in, not how tall it draws.
    var aspect = item && item.aspect > 0 ? item.aspect : 1.6
    var art = item && item.thumb
              ? Math.max(root.columnWidth * 0.34,
                  Math.min(root.columnWidth * 1.25, root.columnWidth / aspect))
              : 0
    var text = Style.spacing.md * 2
                 + Style.space(20)
                 + (item && item.lede ? Style.space(30) : 0)
                 + (item && ((item.tags && item.tags.length) || item.openTodos)
                    ? Style.space(18) : 0)
    return art + text + root.spacing
  }

  readonly property var buckets: Model.balanceColumns(items, columns, estimate)

  implicitHeight: {
    var tallest = 0
    for (var i = 0; i < buckets.length; i++) {
      var total = 0
      for (var j = 0; j < buckets[i].length; j++) total += estimate(buckets[i][j])
      if (total > tallest) tallest = total
    }
    return tallest
  }

  Row {
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: root.spacing

    Repeater {
      model: root.buckets

      delegate: Column {
        required property var modelData
        width: root.columnWidth
        spacing: root.spacing

        Repeater {
          model: parent.modelData
          delegate: Loader {
            required property var modelData
            width: root.columnWidth
            sourceComponent: root.delegate
            onLoaded: if (item) item.memory = modelData
          }
        }
      }
    }
  }
}
