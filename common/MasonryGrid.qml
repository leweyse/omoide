import QtQuick
import qs.Commons
import "../MemoryModel.js" as Model

// QML has no masonry layout, and round-robin leaves ragged columns once
// thumbnails vary in height. Each item goes to the shortest column instead.
Item {
  id: root

  property var items: []
  property int columns: 3
  property int spacing: Style.spacing.lg
  property Component delegate: null

  // The focused card, addressed by memory id rather than by index. The grid
  // reflows when the column count changes, so an index would move the cursor to
  // a different card on a window resize.
  property string cursorId: ""
  // Whether the cursor should be PAINTED. The grid keeps its place when focus
  // moves to a sibling region, but must stop showing a ring: two highlights on
  // screen at once is how "Up did nothing" looks, because the eye stays on the
  // big card instead of the tile that just took focus.
  property bool cursorActive: true
  // The cell holding the cursor, so the page can scroll it into view. Set by the
  // cell itself: the inner Repeater is not reachable from out here, and walking
  // the tree for it would break the moment this layout changed.
  property var cursorCell: null

  // Fires after the cursor lands somewhere new. The grid has no idea what it is
  // inside, so scrolling is the page's job.
  signal cursorMoved()

  // Returns whether the key was used, so the page can hand an unused one on --
  // that is how Left at the first column reaches the sidebar.
  function moveCursor(dx, dy) {
    var next = Model.stepGrid(root.buckets, root.cursorId, dx, dy)
    if (next === null) return false
    root.cursorId = next
    root.cursorMoved()
    return true
  }

  // Focus the top of a column, for crossing down into the grid from above.
  function focusColumn(col) {
    var b = root.buckets
    if (!b || !b.length) return false
    var i = Math.max(0, Math.min(b.length - 1, col))
    // Walk outward if that column happens to be empty, so a sparse grid still
    // catches the cursor instead of swallowing the keypress.
    for (var step = 0; step < b.length; step++) {
      var left = i - step, right = i + step
      if (right < b.length && (b[right] || []).length) { i = right; break }
      if (left >= 0 && (b[left] || []).length) { i = left; break }
    }
    if (!(b[i] || []).length) return false
    root.cursorId = b[i][0].id
    root.cursorMoved()
    return true
  }

  // A chip, a query or a rename can filter out the focused card. Leaving the id
  // set would hold a highlight on nothing and make the next key jump.
  onItemsChanged: {
    if (!root.cursorId.length) return
    for (var i = 0; i < (root.items || []).length; i++)
      if (root.items[i].id === root.cursorId) return
    root.cursorId = ""
  }

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
    var text = Style.spacing.lg * 2
                 + Style.space(20)
                 + (item && item.lede ? Style.space(30) : 0)
                 + (item && ((item.tags && item.tags.length) || item.openTodos)
                    ? Style.space(18) : 0)
    return art + text + root.spacing
  }

  readonly property var buckets: Model.balanceColumns(items, columns, estimate)

  // What the columns actually came out at, not what estimate() guessed. The
  // guess decides which column an item lands in, and it is allowed to be wrong
  // about pixels -- but the page adds its bottom inset to THIS number, so an
  // estimate that ran short took the inset with it and left the last card
  // sitting on the bottom edge of the dialog.
  implicitHeight: columnsRow.implicitHeight

  Row {
    id: columnsRow
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: root.spacing

    Repeater {
      model: root.buckets

      delegate: Column {
        required property var modelData
        width: root.columnWidth
        spacing: root.spacing
        // A column can genuinely be empty -- balanceColumns leaves one
        // spare when there are fewer captures than columns, which is why
        // stepGrid steps over them. An empty Column is zero-width but still
        // claims a spacing slot in the Row, leaving a double gap.
        visible: (modelData || []).length > 0

        Repeater {
          model: parent.modelData
          // An Item wrapping the cell, so the exclusion ring can sit BESIDE the
          // loaded card rather than inside it. A ShaderEffectSource pointing at
          // an ancestor recurses, so the ring can never be a child of the thing
          // it samples.
          delegate: Loader {
            id: cell
            required property var modelData
            width: root.columnWidth
            sourceComponent: root.delegate
            onLoaded: if (item) item.memory = modelData

            readonly property bool isCursor:
              root.cursorActive && root.cursorId.length > 0 && cell.modelData
              && cell.modelData.id === root.cursorId

            onIsCursorChanged: if (cell.isCursor) root.cursorCell = cell

            // A Binding, not an assignment in onLoaded: that fires once, so the
            // highlight would freeze at whatever it was when the card loaded.
            Binding {
              target: cell.item
              property: "hasCursor"
              value: cell.isCursor
              when: cell.item !== null
            }
          }
        }
      }
    }
  }
}
