import QtQuick
import qs.Commons
import qs.Ui
import "../common"

// One collection: its own page, laid out like a memory's.
//
// Header of Back / title / ⋯, then the same grid the Library uses. Collections
// used to filter the Library's grid instead, which left them nowhere to be
// renamed or removed from.
Flickable {
  id: root

  property var index: ({ memories: [] })
  property string collectionName: ""

  signal openMemory(string id)
  signal menuRequested(real sceneX, real sceneY)

  // Filtered here rather than in the CLI: every card in index.json already
  // carries the collections it belongs to, so this needs no round trip.
  readonly property var memories: {
    var all = (root.index && root.index.memories) || []
    var out = []
    for (var i = 0; i < all.length; i++) {
      var names = all[i].collections || []
      if (names.indexOf(root.collectionName) >= 0) out.push(all[i])
    }
    return out
  }

  contentWidth: width
  // Bottom inset only. The gap above belongs to the window's view loader, so it
  // is chrome and survives scrolling.
  // --- keyboard ------------------------------------------------------------
  //
  // One region: the captures grid. The walk itself belongs to MasonryGrid, so
  // this page only says what opening a card means and where to scroll.

  readonly property int regionCount: 1
  property int region: 0

  function focusFirst() { grid.focusColumn(0) }

  function pageKey(event) {
    if (event.key === Qt.Key_Left || event.key === Qt.Key_Right
        || event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
      var dx = event.key === Qt.Key_Right ? 1 : (event.key === Qt.Key_Left ? -1 : 0)
      var dy = event.key === Qt.Key_Down ? 1 : (event.key === Qt.Key_Up ? -1 : 0)
      if (grid.moveCursor(dx, dy)) return true
      // Left at the first column falls through so the dialog can take it.
      return event.key !== Qt.Key_Left
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (grid.cursorId.length) root.openMemory(grid.cursorId)
      return true
    }
    return false
  }

  function ensureVisible() {
    var cell = grid.cursorCell
    if (!cell) return
    var top = cell.mapToItem(layout, 0, 0).y
    var bottom = top + cell.height
    // The page's own edge inset, the same one contentHeight adds below the
    // last row: scrolling something into view should leave the gap the page
    // already keeps at its edges, not a second, smaller one of its own.
    var pad = Style.spacing.panelPadding
    var limit = Math.max(0, root.contentHeight - root.height)
    if (top - pad < root.contentY)
      root.contentY = Math.max(0, top - pad)
    else if (bottom + pad > root.contentY + root.height)
      root.contentY = Math.min(limit, bottom + pad - root.height)
  }

  contentHeight: layout.implicitHeight + Style.spacing.panelPadding
  clip: true
  boundsBehavior: Flickable.StopAtBounds

  // Floating, at the top right, OUTSIDE the column, so it adds no height and
  // cannot shift the page. On this page there is no capture above the title, so
  // it lands level with it.
  //
  // The menu itself is owned by the window rather than hung off this button: a
  // child positioned outside its parent's bounds renders but is never
  // hit-tested. Scene coordinates go up with the request.
  PanelActionButton {
    id: overflow
    x: root.width - width - Style.spacing.panelPadding
    y: 0
    z: 2
    iconText: "⋯"
    tooltipText: "More"
    size: Style.space(26)
    foreground: Color.popups.text
    fontFamily: Style.font.resolvedFamily
    onClicked: {
      var corner = overflow.mapToItem(null, overflow.width, overflow.height)
      root.menuRequested(corner.x, corner.y)
    }
  }

  Column {
    id: layout
    x: Style.spacing.panelPadding
    y: 0
    width: root.width - Style.spacing.panelPadding * 2
    spacing: Style.spacing.xxxl

    Item {
      id: titleRow
      width: parent.width
      height: titleGroup.implicitHeight

      Column {
        id: titleGroup
        anchors.left: parent.left
        anchors.right: parent.right
        // The floating actions sit alongside the title on this page, since
        // there is no capture above to separate them.
        anchors.rightMargin: overflow.width + Style.spacing.lg
        anchors.top: parent.top
        spacing: Style.spacing.sm

        Text {
          id: nameText
          width: parent.width
          text: root.collectionName
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          color: Color.popups.text
          font.family: Style.font.resolvedFamily
          font.pixelSize: Style.font.heading
        }

        Text {
          width: parent.width
          text: root.memories.length
                + (root.memories.length === 1 ? " memory" : " memories")
          color: Color.muted
          font.family: Style.font.resolvedFamily
          font.pixelSize: Style.font.subtitle
        }
      }
    }

    MasonryGrid {
      id: grid
      width: parent.width
      items: root.memories
      onCursorMoved: root.ensureVisible()
      columns: Math.max(2, Math.floor(width / Style.space(230)))
      delegate: cardDelegate
    }

    Text {
      visible: root.memories.length === 0
      width: parent.width
      text: "Nothing in this collection yet. Add a memory to it from its own page."
      wrapMode: Text.WordWrap
      color: Color.muted
      font.family: Style.font.resolvedFamily
      font.pixelSize: Style.font.subtitle
    }
  }

  Component {
    id: cardDelegate

    MemoryCard {
      // No modelData here: MasonryGrid assigns `memory` on the loaded item, so
      // a required modelData would never be set and the card would fail to
      // create -- which showed up as an empty grid.
      onActivated: root.openMemory(memory.id)
    }
  }
}
