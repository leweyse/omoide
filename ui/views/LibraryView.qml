import QtQuick
import qs.Commons
import qs.Ui
import "../common"
import "../components"
import "../MemoryModel.js" as Model

Flickable {
  id: root

  // Whether this page holds the keyboard. The window gives it to the rail or
  // the page, never both, so the page draws its cursor only while it holds it.
  // Otherwise a highlighted card looks ready for Enter while the keys still go
  // to the sidebar.
  property bool hasKeyboard: true

  property var service: null
  signal openMemory(string id)
  signal openCollection(string name)

  readonly property var index: service ? service.index : ({})

  // The captures on screen, a page at a time. A chip and a search narrow the
  // query itself, so what is loaded is always what is shown.
  PagedMemories {
    id: pages
    service: root.service
    args: root.searching ? ["search", "--q", root.appliedQuery] : ["list"]
    facet: root.facet
    pageSize: root.pageSize
  }

  // Enough cards to fill the viewport twice over, so a scroll that is already
  // moving when a page lands still has cards under it.
  readonly property int pageSize: {
    var cardHeight = grid.columnWidth / 1.6 + Style.space(100)
    var rows = Math.ceil(root.height / Math.max(1, cardHeight))
    return Math.max(12, Math.min(60, grid.columns * rows * 2))
  }

  // The next page is asked for while a viewport of cards is still below.
  function maybeLoadMore() {
    if (root.contentY + root.height * 2 >= root.contentHeight)
      pages.loadMore()
  }

  onContentYChanged: root.maybeLoadMore()
  onContentHeightChanged: root.maybeLoadMore()

  // The unfiltered size of a search, for the "All" chip, kept while a chip
  // narrows the results.
  property int searchTotal: 0

  // Search narrows the same grid rather than living on its own page: the
  // library already shows captures well, and a chip on top of a query is a
  // more useful combination than either alone.
  property string query: ""            // what is in the field, right now
  property string appliedQuery: ""     // what the grid is showing results for
  readonly property bool awaiting: root.query.trim() !== root.appliedQuery
                                   || (pages.loading && !pages.loaded)
  // Hidden until asked for: the grid is the point of this page, and a field
  // sitting above it permanently costs a row of captures for something used
  // occasionally.
  property bool searchOpen: false

  // Derived from appliedQuery, NOT from the live field. Keyed off the field,
  // the grid would switch to the result set on the first keystroke, while those
  // results still belong to the previous query, and show "0 RESULTS" until the
  // debounce catches up.
  readonly property bool searching: searchOpen && appliedQuery.length > 0

  function runSearch() {
    if (!service) return
    root.appliedQuery = root.query.trim()
  }

  function focusInput() {
    root.searchOpen = true
    Qt.callLater(function () { field.forceActiveFocus() })
  }

  function closeSearch() {
    root.searchOpen = false
    field.text = ""
    root.query = ""
    root.appliedQuery = ""
  }

  // "" means All; otherwise a chip id, which the CLI filters by.
  property string facet: ""

  // Chips carry counts for what the view holds: `facets` counts within the
  // search, if there is one, and leaves out a chip with nothing in it.
  readonly property var shownMemories: pages.memories
  property var shownFacets: []
  property int facetsToken: 0

  // --- keyboard ------------------------------------------------------------
  //
  // Two Tab regions, Collections then Captures, plus the filter chips, which
  // are a drill-in reached with "f" and left with Esc rather than a Tab
  // sibling. They are page state you toggle while watching the grid change, not
  // a place you pass through on the way somewhere.

  readonly property bool hasCollections:
    !root.searching && (root.index.collections || []).length > 0

  // Named, not numbered: region 0 is Collections when there are any and
  // Captures when there are not, which an integer alone does not say.
  readonly property var regionNames:
    root.hasCollections ? ["collections", "captures"] : ["captures"]
  readonly property int regionCount: root.regionNames.length
  property int region: 0
  readonly property string regionName:
    root.regionNames[Math.min(root.region, root.regionCount - 1)]

  // Cursor within the collections row. The grid keeps its own, by memory id.
  property int collectionCursor: -1
  // Cursor within the filter chips, or -1 when the chips do not have focus.
  //
  // Indexes filterChips, NOT shownFacets: the "All" chip is drawn before the
  // facet Repeater, and a cursor over shownFacets alone could never reach it.
  property int filterCursor: -1

  readonly property var filterChips:
    [{ id: "", label: "All" }].concat(root.shownFacets)

  // Takes the index explicitly instead of reading `regionName`.
  //
  // `regionName` is a binding on `region`, and the order between a binding
  // updating and that property's own change handler running is not defined.
  // Read from inside onRegionChanged it can be STALE, and the handler would seed
  // the wrong region. `regionNames` depends on hasCollections, not on region, so
  // resolving through it here is safe.
  function nameOf(i) {
    var names = root.regionNames
    return names[Math.max(0, Math.min(i, names.length - 1))]
  }

  // Seeds the cursor for whichever region just took focus. Entering Captures
  // starts at column 0; a caller that wants a different column (crossing down
  // from a tile) sets the region first and then moves it.
  function enterRegion(i) {
    root.filterCursor = -1
    if (root.nameOf(i) === "collections")
      root.collectionCursor = (root.index.collections || []).length > 0 ? 0 : -1
    else
      grid.focusColumn(0)
  }

  onRegionChanged: root.enterRegion(root.region)

  function focusFirst() {
    root.region = 0
    // Explicitly, not via the change handler: entering the page when region is
    // already 0 fires nothing at all.
    root.enterRegion(0)
  }

  function pageKey(event) {
    // The chips own every key while they have focus, so nothing here can steal
    // one out from under them.
    if (root.filterCursor >= 0) return root.filterKey(event)

    // Search's second Esc rung. The field itself takes the first one and blurs
    // to the page; this one puts the bar away. The dialog only gets the third.
    if (event.key === Qt.Key_Escape && root.searchOpen) {
      if (event.isAutoRepeat) return true
      root.closeSearch()
      return true
    }

    if (event.text === "f" && root.shownFacets.length > 0) {
      // 0 is "All", the leftmost chip: the same first-item rule as everywhere.
      root.filterCursor = 0
      return true
    }

    if (root.regionName === "collections") return root.collectionsKey(event)
    return root.capturesKey(event)
  }

  function filterKey(event) {
    var chips = root.filterChips
    if (event.key === Qt.Key_Right || event.key === Qt.Key_Left) {
      var moved = Model.stepList(chips.length, root.filterCursor,
                                 event.key === Qt.Key_Right ? 1 : -1)
      // Left off the first chip drops focus back to where it came from rather
      // than escaping to the sidebar: the chips are a drill-in, one level deep.
      if (moved === null) {
        if (event.key === Qt.Key_Left) root.filterCursor = -1
        return true
      }
      root.filterCursor = moved
      return true
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      var chip = chips[root.filterCursor]
      // "All" carries an empty id, so toggling it off would be a no-op. Clear.
      if (chip) root.facet = (chip.id.length === 0 || root.facet === chip.id)
                             ? "" : chip.id
      return true
    }
    // Esc leaves the chips. Handled here so it never reaches the dialog's
    // unwind and closes the whole window instead.
    if (event.key === Qt.Key_Escape) {
      if (!event.isAutoRepeat) root.filterCursor = -1
      return true
    }
    return true
  }

  function collectionsKey(event) {
    var all = root.index.collections || []
    if (event.key === Qt.Key_Right || event.key === Qt.Key_Left) {
      var moved = Model.stepList(all.length, root.collectionCursor,
                                 event.key === Qt.Key_Right ? 1 : -1)
      // Left off the first tile is not consumed: the dialog takes it and
      // returns to the sidebar.
      if (moved === null) return event.key === Qt.Key_Right
      root.collectionCursor = moved
      return true
    }
    if (event.key === Qt.Key_Down) {
      // Cross into the grid under the current tile, not at the first card. The
      // stride comes from the live delegate rather than a constant, so it cannot
      // drift from the tile's real width.
      var first = collectionsRow.itemAtIndex(0)
      var tileW = first ? first.width : collectionsRow.tileWidth
      var stride = tileW + collectionsRow.spacing
      var centre = root.collectionCursor * stride + stride / 2
      var col = Model.columnAt(centre, grid.columns, grid.columnWidth, grid.spacing)
      if (root.regionCount > 1) {
        root.region = root.regionNames.indexOf("captures")
        // After the region change, so this wins over its column-0 default.
        grid.focusColumn(col)
        root.collectionCursor = -1
      }
      return true
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      var one = all[root.collectionCursor]
      if (one) root.openCollection(one.name)
      return true
    }
    return false
  }

  function capturesKey(event) {
    if (event.key === Qt.Key_Left || event.key === Qt.Key_Right
        || event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
      var dx = event.key === Qt.Key_Right ? 1 : (event.key === Qt.Key_Left ? -1 : 0)
      var dy = event.key === Qt.Key_Down ? 1 : (event.key === Qt.Key_Up ? -1 : 0)
      if (grid.moveCursor(dx, dy)) return true
      // Nothing that way. Up out of the grid goes back to the collections row;
      // Left at the first column falls through so the dialog can take it.
      if (dy < 0 && root.regionCount > 1) {
        root.region = root.regionNames.indexOf("collections")
        return true
      }
      return event.key !== Qt.Key_Left
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (grid.cursorId.length) root.openMemory(grid.cursorId)
      return true
    }
    return false
  }

  // Content coordinates, via the layout Column: a card sits inside a column
  // inside the grid, so its own y says nothing about where it is on the page.
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

  function facetOffered(id) {
    for (var i = 0; i < root.shownFacets.length; i++)
      if (root.shownFacets[i].id === id) return true
    return false
  }

  function loadFacets() {
    if (!service) return
    var mine = ++root.facetsToken
    var scoped = root.searching
    var command = scoped ? ["facets", "--q", root.appliedQuery] : ["facets"]
    service.call(command, function (code, json) {
      if (!root || mine !== root.facetsToken) return
      root.shownFacets = (code === 0 && json && json.facets) || []
      // Drop a filter the chip row does not offer. It matches nothing, and with
      // no chip on screen there is nothing to click to undo it, so the grid
      // would read as empty and broken. Not while searching: a query can
      // legitimately leave a chip with no matches, and a chip on top of a query
      // is a combination worth keeping.
      if (!scoped && root.facet.length > 0 && !root.facetOffered(root.facet))
        root.facet = ""
    })
  }

  // The grid's columns derive from what is loaded, so a first-item focus that
  // ran before the first page arrived had no card to sit on. Seed it here.
  function seedCursor() {
    if (root.filterCursor >= 0) return
    if (root.nameOf(root.region) === "captures" && grid.cursorId.length === 0)
      grid.focusColumn(0)
    else if (root.nameOf(root.region) === "collections"
             && root.collectionCursor < 0
             && (root.index.collections || []).length > 0)
      root.collectionCursor = 0
  }

  // The library changed somewhere: what is on screen again, and the chips.
  function refreshView() {
    pages.refreshLoaded()
    root.loadFacets()
  }

  // The loader restarts itself when its query changes; the chips follow the
  // search scope here.
  onSearchingChanged: root.loadFacets()
  onAppliedQueryChanged: if (root.searching) root.loadFacets()
  Component.onCompleted: root.loadFacets()

  Connections {
    target: pages
    function onMemoriesChanged() { root.seedCursor() }
    function onLoadedChanged() {
      if (pages.loaded && root.searching && root.facet.length === 0)
        root.searchTotal = pages.total
      root.maybeLoadMore()
    }
  }

  Connections {
    target: root.service
    function onIndexChanged() { root.refreshView() }
  }

  // Bottom inset only. The gap above belongs to the window's view
  // loader, so it is chrome and survives scrolling.
  contentHeight: layout.implicitHeight + Style.spacing.panelPadding
  clip: true
  boundsBehavior: Flickable.StopAtBounds

  // Vertical swipes scroll the page wherever the pointer is; the sideways rows
  // take only sideways ones.
  PageWheel { page: root }

  Column {
    id: layout
    x: Style.spacing.panelPadding
    y: 0
    width: root.width - Style.spacing.panelPadding * 2
    spacing: Style.spacing.xxxl

    Timer {
      id: searchDebounce
      interval: 180
      onTriggered: root.runSearch()
    }

    Item { id: focusSink }

  // Wraps the shared card so the grid can hand it a memory and hear the click.
  Component {
    id: skeletonDelegate
    SkeletonCard {}
  }

  Component {
    id: cardDelegate

    MemoryCard {
      // No modelData here: MasonryGrid assigns `memory` on the loaded item, so
      // a required modelData is never set and the card fails to create.
      onActivated: root.openMemory(memory.id)
    }
  }

    Column {
      width: parent.width
      spacing: Style.spacing.md
      // Collections are about browsing, so they step aside while searching.
      visible: !root.searching && (root.index.collections || []).length > 0

      PanelSectionHeader {
        text: "COLLECTIONS"
        foreground: Color.muted
        fontFamily: Style.font.resolvedFamily
      }

      // The clip that lets the row scroll, held a pixel OUTSIDE the tiles.
      //
      // A focused tile draws its accent border on the device pixel that rounds
      // just outside its own bounds, so a clip on that line cuts the first
      // tile's border. Clipping a pixel wider keeps the border and still cuts a
      // scrolled tile before it shows. Above and below too: where the tiles'
      // top and bottom pixel rows land against a clip that fits them exactly
      // varies from frame to frame, so a scrolled row loses its top edge. The
      // wrapper holds the row's own height, so the layout does not grow. The row
      // itself keeps its position, so the tiles line up with the captures below.
      Item {
        width: parent.width
        height: Style.space(112)

        Item {
          id: collectionsClip
          readonly property real bleed: Math.max(1, Style.space(1))
          x: -bleed
          y: -bleed
          width: parent.width + bleed * 2
          height: parent.height + bleed * 2
          clip: true

          // Tiles are sized from the row, the same way the captures grid derives its
          // columns: a whole number fits exactly and the remainder scrolls. A fixed
          // tile width would end the row mid-card at most widths, and a sliced card
          // reads as a rendering fault, not as "there is more this way".
          ListView {
            id: collectionsRow
            x: collectionsClip.bleed
            y: collectionsClip.bleed
            width: collectionsClip.width - collectionsClip.bleed * 2
            // A horizontal ListView forces its delegates' height, so this IS the
            // tile height. CollectionTile's own is only a fallback.
            height: parent.height - collectionsClip.bleed * 2
            orientation: ListView.Horizontal
            spacing: Style.spacing.lg
            // No tiles until their width is known. Created at width 0, they grow
            // when it arrives, and a ListView answers that by shifting its content
            // origin, which leaves the row a tile off its start.
            model: collectionsRow.tileWidth > 0 ? (root.index.collections || []) : []

            // The narrowest a tile may be. Above it tiles stretch to close the
            // remainder; below it one fewer fits.
            readonly property real tileMin: Style.space(216)
            readonly property int tileColumns:
              Math.max(1, Math.floor((width + spacing) / (tileMin + spacing)))
            // Floored, not rounded: rounding up overshoots the row by a pixel per
            // tile and slices the last one.
            //
            // Fewer collections than columns leaves the remainder empty. Two tiles
            // do not stretch to half the dialog each: a column width is a rule
            // about the row, not about how many things happen to be in it.
            readonly property real tileWidth:
              Math.floor((width - spacing * (tileColumns - 1)) / tileColumns)

            // The scroll, in the view's own coordinates. originX can move off 0
            // (the model says why), so every bound is measured from it, and
            // the span is computed from the tiles rather than read off contentWidth,
            // which is stale in the frame right after a resize.
            readonly property real stride: tileWidth + spacing
            readonly property real span: count > 0 ? count * stride - spacing : 0
            // Functions, not bindings: followCursor runs from onOriginXChanged, and
            // whether a binding ON originX has re-evaluated by the time that
            // property's own change handler runs is undefined. As bindings, both
            // bounds can still hold the PREVIOUS origin and clamp the row back onto
            // the wrong tile.
            function minX() { return originX }
            function maxX() { return originX + Math.max(0, span - width) }
            readonly property bool overflowing: span > width + 0.5

            // Bring the cursor's tile on screen when `chase` is set and the row
            // holds the keyboard; otherwise only keep the row inside its bounds.
            // Every tile is the same width, so where a given index sits is
            // arithmetic, done by hand because neither positionViewAtIndex nor
            // ApplyRange survives this row's startup. Only a keyboard move chases:
            // a row scrolled by the wheel stays where the wheel left it.
            function followCursor(chase) {
              if (count === 0 || width <= 0 || tileWidth <= 0) return
              var x = Math.max(minX(), Math.min(maxX(), contentX))
              if (chase && root.hasKeyboard && root.regionName === "collections") {
                var left = originX + Math.max(0, root.collectionCursor) * stride
                if (left < x) x = left
                else if (left + tileWidth > x + width) x = left + tileWidth - width
              }
              contentX = Math.max(minX(), Math.min(maxX(), x))
            }

            onWidthChanged: collectionsRow.followCursor(true)
            onCountChanged: collectionsRow.followCursor(false)
            onOriginXChanged: collectionsRow.followCursor(false)

            Connections {
              target: root
              function onCollectionCursorChanged() { collectionsRow.followCursor(true) }
              // Coming back to the row after the wheel left it somewhere else: the
              // cursor has not moved, so nothing else here would fire.
              function onRegionNameChanged() { collectionsRow.followCursor(true) }
            }

            // Wrapped so the exclusion ring is a SIBLING of the tile: a
            // ShaderEffectSource pointing at an ancestor recurses.
            delegate: CollectionTile {
              required property var modelData
              required property int index
              width: collectionsRow.tileWidth
              collection: modelData
              hasCursor: root.hasKeyboard && root.regionName === "collections"
                         && root.filterCursor < 0
                         && root.collectionCursor === index
              // Opens the collection as its own page, where it is renamed or
              // removed.
              onActivated: root.openCollection(modelData.name)
            }

            // A sideways swipe scrolls the row; a vertical one passes to the page.
            PageWheel {
              page: collectionsRow
              horizontal: true
              outer: root
              minPos: collectionsRow.minX()
              maxPos: collectionsRow.maxX()
            }
          }
        }
      }
    }

    Column {
      width: parent.width
      spacing: Style.spacing.md

      PanelSectionHeader {
        // A label, not a progress indicator: the count joins it once the
        // results are in, and the grid below shows what is still loading.
        text: !root.searching ? "CAPTURES"
              : (pages.loaded ? pages.total + (pages.total === 1 ? " RESULT" : " RESULTS")
                              : "RESULTS")
        foreground: Color.muted
        fontFamily: Style.font.resolvedFamily
      }

      // Smart filters. The kinds are derived from what a capture holds, the
      // sources from its link, and the rest are the tags the model assigned.
      //
      // One horizontally scrollable strip rather than a wrapping block, so the
      // row height stays constant however many facets exist and the captures
      // stay on the page.
      Item {
        width: parent.width
        // Trailing air of its own, so the chips read as a control strip above
        // the grid rather than as the grid's first row.
        height: searchToggle.height + Style.spacing.xl
        visible: root.shownFacets.length > 0 || root.searchOpen

        // Pinned outside the strip: a control you cannot reach because it
        // scrolled away is worse than one that costs a little width.
        FilterChip {
          id: searchToggle
          anchors.right: parent.right
          anchors.top: parent.top
          label: root.searchOpen ? "Close" : "Search"
          // The glyphs are embedded literally: QML has no \U escape, so a
          // codepoint above FFFF written that way renders as its own text.
          icon: root.searchOpen ? "×" : "󰍉"
          selected: root.searchOpen
          onPicked: root.searchOpen ? root.closeSearch() : root.focusInput()
        }

        Flickable {
          id: strip
          anchors.left: parent.left
          anchors.right: searchToggle.left
          // Search is a different kind of control from the facets, so it gets
          // real separation rather than the gap between two neighbouring chips.
          anchors.rightMargin: Style.spacing.panelPadding * 2
          anchors.top: parent.top
          height: chips.height
          contentWidth: chips.width
          contentHeight: height
          clip: true
          flickableDirection: Flickable.HorizontalFlick
          boundsBehavior: Flickable.StopAtBounds

          Row {
            id: chips
            spacing: Style.spacing.md

            FilterChip {
              hasCursor: root.hasKeyboard && root.filterCursor === 0
              label: "All"
              count: root.searching ? root.searchTotal : (root.index.memoryCount || 0)
              selected: root.facet.length === 0
              onPicked: root.facet = ""
            }

            Repeater {
              model: root.shownFacets

              delegate: FilterChip {
                required property var modelData
                required property int index
                // +1 for the "All" chip ahead of this Repeater.
                hasCursor: root.hasKeyboard && root.filterCursor === index + 1
                label: modelData.label
                count: modelData.count
                selected: root.facet === modelData.id
                // Picking the active chip clears it, so a filter is always one
                // click from being undone.
                onPicked: root.facet = (root.facet === modelData.id ? "" : modelData.id)
              }
            }
          }

          // A sideways swipe scrolls the strip; a vertical one passes to the page.
          PageWheel {
            page: strip
            horizontal: true
            outer: root
            minPos: 0
            maxPos: Math.max(0, strip.contentWidth - strip.width)
          }
        }
      }

      // Under the chips, not above them: the chips are how you narrow the
      // library at a glance, and the field is the fallback when they cannot
      // express what you are after. Reading order should match that.
      Item {
        width: parent.width
        // Trailing air of its own when open, the same way the chip strip
        // carries its own, so the field reads as a control above the grid rather
        // than as its first row. Zero when closed.
        height: root.searchOpen ? field.height + Style.spacing.xl : 0
        visible: root.searchOpen

        AccentField {

          ringBackdrop: Color.popups.background
          id: field
          anchors.left: parent.left
          anchors.right: parent.right
          foreground: Color.popups.text
          accent: Color.accent
          font.family: Style.font.resolvedFamily
          font.pixelSize: Style.font.title
          placeholderText: "Search memories, notes and screenshot text…"
          rightPadding: Style.space(30)
          onTextChanged: {
            root.query = text
            searchDebounce.restart()
          }
          Keys.onEscapePressed: function (event) {
            // Only on a real press. Holding Escape auto-repeats, and each repeat
            // would dismiss another layer.
            if (event.isAutoRepeat) { event.accepted = true; return }
            // First Esc leaves the field, a second closes search entirely, the
            // same one-rung unwind as everywhere else.
            focusSink.forceActiveFocus()
            event.accepted = true
          }
        }

        PanelActionButton {
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          visible: field.text.length > 0
          iconText: "×"
          tooltipText: "Clear"
          size: Style.space(20)
          foreground: Color.popups.text
          fontFamily: Style.font.resolvedFamily
          onClicked: {
            field.text = ""
            field.forceActiveFocus()
          }
        }
      }


      MasonryGrid {
        id: grid
        width: parent.width
        items: root.shownMemories
        cursorActive: root.regionName === "captures" && root.filterCursor < 0
        onCursorMoved: root.ensureVisible()
        columns: Math.max(2, Math.floor(width / Style.space(230)))
        delegate: cardDelegate
        // Cards on their way: two rows for an empty grid, one while the next
        // page loads.
        placeholderRows: pages.fetchingNew ? (root.shownMemories.length ? 1 : 2) : 0
        placeholder: skeletonDelegate
      }

      Text {
        visible: pages.loaded && root.shownMemories.length === 0 && !root.awaiting
        text: (root.index.memoryCount || 0) === 0
              ? "Nothing captured yet. Press the bar icon to make your first memory."
              : (root.searching ? "No memories match that search."
                                : "Nothing matches this filter.")
        color: Color.muted
        font.family: Style.font.resolvedFamily
        font.pixelSize: Style.font.subtitle
      }
    }
  }
}
