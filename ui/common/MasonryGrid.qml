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

  // Rows of cards still loading, drawn with `placeholder`, which is given its
  // `aspect`. Every column gets one per row, after a column shorter than the
  // tallest is first topped up to it, so no column stands empty while a page
  // is on its way. The cursor never lands on one.
  property int placeholderRows: 0
  property Component placeholder: null

  // A few capture shapes, cycled, so a row of placeholders reads as a grid.
  readonly property var placeholderAspects: [1.6, 1.0, 0.8, 1.9, 1.3]

  // The focused card, addressed by memory id rather than by index. The grid
  // reflows when the column count changes, so an index would move the cursor to
  // a different card on a window resize.
  property string cursorId: ""
  // Whether the cursor is painted. The grid keeps its place when focus moves to
  // a sibling region but stops showing a ring, so only one highlight is ever on
  // screen.
  property bool cursorActive: true
  // The cell holding the cursor, so the page can scroll it into view. Set by
  // the cell itself, because the inner Repeater is not reachable from here.
  property var cursorCell: null

  // Fires after the cursor lands somewhere new. The grid has no idea what it is
  // inside, so scrolling is the page's job.
  signal cursorMoved()

  // Returns whether the key was used, so the page can hand an unused one on.
  // That is how Left at the first column reaches the sidebar.
  function moveCursor(dx, dy) {
    var next = Model.stepGrid(root.cardBuckets, root.cursorId, dx, dy)
    if (next === null) return false
    root.cursorId = next
    root.cursorMoved()
    return true
  }

  // Focus the top of a column, for crossing down into the grid from above.
  function focusColumn(col) {
    var b = root.cardBuckets
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
    // the card clamps to, then the padded text block. Only the ratios matter,
    // because this picks a column, not a drawn height.
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

  readonly property var buckets: {
    var cols = Model.balanceColumns(root.items, root.columns, root.estimate)
    if (root.placeholderRows <= 0) return cols
    var heights = cols.map(function (column) {
      return column.reduce(function (sum, entry) { return sum + root.estimate(entry) }, 0)
    })
    var tallest = Math.max.apply(null, heights)
    var n = 0
    function add(c) {
      var entry = { placeholder: true, key: "~" + n, thumb: true, lede: true, tags: [true],
                    aspect: root.placeholderAspects[n % root.placeholderAspects.length] }
      n++
      cols[c].push(entry)
      heights[c] += root.estimate(entry)
    }
    for (var c = 0; c < cols.length; c++) {
      add(c)
      while (heights[c] < tallest) add(c)
    }
    for (var r = 1; r < root.placeholderRows; r++)
      for (c = 0; c < cols.length; c++) add(c)
    return cols
  }
  // The columns without placeholders, for the cursor. Placeholders come after
  // every item, so each card keeps its row here.
  readonly property var cardBuckets: root.buckets.map(function (column) {
    return column.filter(function (entry) { return !entry.placeholder })
  })

  // What the columns actually came out at, not what estimate() guessed. The
  // page adds its bottom inset to this number, so it has to be the real height.
  implicitHeight: columnsRow.implicitHeight

  // Every entry by its key: a memory's id, or a placeholder's "~n". A cell
  // looks its entry up here, so a re-fetch that hands the same card back as a
  // new object updates the card in place.
  readonly property var byKey: {
    var map = {}
    for (var c = 0; c < root.buckets.length; c++)
      for (var i = 0; i < root.buckets[c].length; i++) {
        var entry = root.buckets[c][i]
        map[entry.placeholder ? entry.key : entry.id] = entry
      }
    return map
  }

  Row {
    id: columnsRow
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: root.spacing

    Repeater {
      model: root.columns

      delegate: Column {
        id: column
        required property int index
        width: root.columnWidth
        spacing: root.spacing
        // A column is empty when there are fewer captures than columns. An
        // empty Column is zero-width but still claims a spacing slot in the
        // Row, leaving a double gap.
        visible: keys.count > 0

        // The column's cells by key, changed only past the part that stayed
        // the same. A new page appends below the cards already there, and a
        // model replaced wholesale would rebuild every card above it, images
        // and all.
        ListModel { id: keys }

        function sync() {
          var want = (root.buckets[column.index] || []).map(function (entry) {
            return entry.placeholder ? entry.key : entry.id
          })
          var keep = 0
          while (keep < keys.count && keep < want.length && keys.get(keep).key === want[keep])
            keep++
          if (keys.count > keep) keys.remove(keep, keys.count - keep)
          for (var i = keep; i < want.length; i++) keys.append({ key: want[i] })
        }

        Component.onCompleted: column.sync()
        Connections {
          target: root
          function onBucketsChanged() { column.sync() }
        }

        Repeater {
          model: keys
          // One Loader per cell, instantiating the page's delegate for each
          // memory and driving its cursor.
          delegate: Loader {
            id: cell
            required property string key
            readonly property var entry: root.byKey[cell.key] || null
            readonly property bool isPlaceholder: cell.key.charAt(0) === "~"
            width: root.columnWidth
            sourceComponent: cell.isPlaceholder ? root.placeholder : root.delegate

            readonly property bool isCursor:
              root.cursorActive && root.cursorId.length > 0 && cell.key === root.cursorId

            onIsCursorChanged: if (cell.isCursor) root.cursorCell = cell

            // Bindings, not assignments in onLoaded: that fires once, so the
            // card would freeze at the data and highlight it loaded with.
            Binding {
              target: cell.item
              property: cell.isPlaceholder ? "aspect" : "memory"
              value: cell.entry ? (cell.isPlaceholder ? cell.entry.aspect : cell.entry) : null
              when: cell.item !== null && cell.entry !== null
            }
            Binding {
              target: cell.item
              property: "hasCursor"
              value: cell.isCursor
              when: cell.item !== null && !cell.isPlaceholder
            }
          }
        }
      }
    }
  }
}
