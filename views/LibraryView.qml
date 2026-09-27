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
  readonly property var facets: (index && index.facets) || []

  // Search narrows the same grid rather than living on its own page: the
  // library already shows captures well, and a chip on top of a query is a
  // more useful combination than either alone.
  property string query: ""            // what is in the field, right now
  property string appliedQuery: ""     // what `results` actually belongs to
  property var results: []
  property bool awaiting: false
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
    var wanted = root.query.trim()
    if (!wanted.length) {
      root.results = []
      root.appliedQuery = ""
      root.awaiting = false
      // Explicit, because assigning a property its existing value emits nothing:
      // after a search that returned nothing, `results` is already [] and
      // clearing the field leaves it [], so refreshView would never run and the
      // grid would keep showing the empty result set.
      root.refreshView()
      return
    }
    root.awaiting = true
    service.call(["search", "--q", wanted], function (code, json) {
      // Drop a stale answer: two searches can overlap, and the slower one
      // must not overwrite the newer one's results.
      if (wanted !== root.query.trim()) return
      root.results = (json && json.results) || []
      root.appliedQuery = wanted
      root.awaiting = false
    })
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
    root.results = []
    root.awaiting = false
  }

  // "" means All; otherwise a chip id, which the CLI filters by.
  property string facet: ""

  function matchesFacet(memory) {
    if (!root.facet.length) return true
    return root.facetMatches(memory, root.facet)
  }

  // The set a search has narrowed to, before any chip is applied. Chip counts
  // are computed over this, not over the fully filtered list -- otherwise
  // picking one facet would show every other as zero.
  function baseMemories() {
    return root.searching ? root.results : (root.index.memories || [])
  }

  function visibleMemories() {
    var all = root.baseMemories()
    if (!root.facet.length) return all
    var out = []
    for (var i = 0; i < all.length; i++)
      if (root.matchesFacet(all[i])) out.push(all[i])
    return out
  }

  function facetMatches(memory, facetId) {
    var parts = facetId.split(":")
    var group = parts[0]
    var value = parts.slice(1).join(":")
    if (group === "kind") return (memory.kind || "note") === value
    if (group === "source") return (memory.domain || "") === value
    if (group === "tag") return (memory.tags || []).indexOf(value) !== -1
    if (group === "collection")
      return (memory.collections || []).indexOf(value) !== -1
    return false
  }

  // Chips carry counts for what is actually on screen. The index supplies the
  // vocabulary and the labels -- it knows that x.com is "X" -- while the counts
  // are recomputed here, so a chip can never claim more than the grid holds.
  // Facets with nothing left in the current set drop out entirely.
  // Recomputed explicitly whenever anything it depends on moves, and read
  // directly by the grid and the chips.
  property var shownMemories: []
  property var shownFacets: []

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

  function refreshView() {
    root.shownFacets = root.computeFacets()

    // Drop a filter the chip row no longer offers. It matches nothing, and with
    // no chip on screen there is nothing left to click to undo it -- the grid
    // reads as empty and broken. Clearing re-enters through onFacetChanged and
    // falls straight through this branch the second time.
    //
    // Only while NOT searching: a query that narrows the set can legitimately
    // leave a facet with no matches, and a facet on top of a query is a
    // combination worth keeping rather than silently discarding.
    if (!root.searching && root.facet.length > 0
        && !root.facetOffered(root.facet)) {
      root.facet = ""
      return
    }

    root.shownMemories = root.visibleMemories()
    // The grid's columns derive from shownMemories, so a first-item focus that
    // ran before the index landed had no card to sit on. Seed it now.
    if (root.filterCursor < 0) {
      if (root.nameOf(root.region) === "captures" && grid.cursorId.length === 0)
        grid.focusColumn(0)
      else if (root.nameOf(root.region) === "collections"
               && root.collectionCursor < 0
               && (root.index.collections || []).length > 0)
        root.collectionCursor = 0
    }
  }

  onFacetChanged: refreshView()
  // `searching` is derived from searchOpen, and it decides whether the grid
  // reads the index or the result set. Nothing recomputed when it flipped.
  onSearchOpenChanged: refreshView()
  onResultsChanged: refreshView()
  onAppliedQueryChanged: refreshView()
  Component.onCompleted: refreshView()

  Connections {
    target: root.service
    function onIndexChanged() { root.refreshView() }
  }

  function computeFacets() {
    var base = root.baseMemories()
    var out = []
    for (var i = 0; i < root.facets.length; i++) {
      var facet = root.facets[i]
      var n = 0
      for (var j = 0; j < base.length; j++)
        if (root.facetMatches(base[j], facet.id)) n++
      if (n > 0)
        out.push({ id: facet.id, label: facet.label, group: facet.group, count: n })
    }
    return out
  }

  // Bottom inset only. The gap above belongs to the window's view
  // loader, so it is chrome and survives scrolling.
  contentHeight: layout.implicitHeight + Style.spacing.panelPadding
  clip: true
  boundsBehavior: Flickable.StopAtBounds

  // Flickable's built-in wheel step is tuned for touch flicking and crawls with
  // a mouse or touchpad, which is painful on a page this tall. One notch moves
  // a readable chunk instead, clamped so it cannot overscroll.
  WheelHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: function (event) {
      if (event.angleDelta.y === 0) return
      // The filter strip owns the wheel while the pointer is over it.
      if (stripHover.hovered) return
      // So does the collections row, but only while it has somewhere to go --
      // otherwise a pointer resting on it would deaden the page's own scroll.
      if (collectionsHover.hovered && collectionsRow.overflowing) return
      var notches = event.angleDelta.y / 120
      var limit = Math.max(0, root.contentHeight - root.height)
      root.contentY = Math.max(0, Math.min(limit,
                                           root.contentY - notches * Style.space(140)))
    }
  }

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
        id: collectionsClip
        readonly property real bleed: Math.max(1, Style.space(1))
        x: -bleed
        width: parent.width + bleed * 2
        height: Style.space(112)
        clip: true

        // Tiles are sized from the row, the same way the captures grid derives its
        // columns: a whole number fits exactly and the remainder scrolls.
        //
        // Fixed-width tiles ended the row mid-card at every width that was not a
        // multiple of the tile pitch -- which is most of them, since the dialog
        // is a fraction of whatever screen it opens on. A sliced card reads as a
        // rendering fault, not as "there is more this way".
        ListView {
          id: collectionsRow
          x: collectionsClip.bleed
          width: collectionsClip.width - collectionsClip.bleed * 2
          // A horizontal ListView forces its delegates' height, so this IS the
          // tile height -- CollectionTile's own is only a fallback.
          height: parent.height
          orientation: ListView.Horizontal
          spacing: Style.spacing.lg
          model: root.index.collections || []

          // The narrowest a tile may be. Above it tiles stretch to close the
          // remainder; below it one fewer fits.
          readonly property real tileMin: Style.space(216)
          readonly property int tileColumns:
            Math.max(1, Math.floor((width + spacing) / (tileMin + spacing)))
          // Floored, not rounded: rounding up overshoots the row by a pixel per
          // tile and slices the last one again, which is the whole bug.
          //
          // Fewer collections than columns just leaves the remainder empty. Two
          // tiles do not stretch to half the dialog each -- a column width is a
          // rule about the row, not about how many things happen to be in it.
          readonly property real tileWidth:
            Math.floor((width - spacing * (tileColumns - 1)) / tileColumns)

          // The scroll, in the view's own coordinates. originX is NOT 0 here --
          // followCursor explains why -- so every bound is measured from it, and
          // the span is computed from the tiles rather than read off contentWidth,
          // which is stale in the frame right after a resize.
          readonly property real stride: tileWidth + spacing
          readonly property real span: count > 0 ? count * stride - spacing : 0
          // Functions, not bindings: followCursor runs from onOriginXChanged, and
          // whether a binding ON originX has re-evaluated by the time that
          // property's own change handler runs is undefined. Read as bindings
          // there, both bounds came from the PREVIOUS origin and clamped the row
          // straight back onto the second tile.
          function minX() { return originX }
          function maxX() { return originX + Math.max(0, span - width) }
          readonly property bool overflowing: span > width + 0.5

          // Keep the keyboard cursor on screen, and keep the row anchored to its
          // own start otherwise. Every tile is the same width, so where a given
          // index sits is arithmetic -- which is worth doing by hand here, because
          // neither of the mechanisms that would normally do it survives this
          // row's startup:
          //
          // Delegates are created before the row has its width, at tileWidth 0,
          // and grow when it arrives. A ListView answers that resize by shifting
          // its content ORIGIN rather than its items -- originX ended up at -864 --
          // and left contentX one whole tile past it, so the row opened on the
          // second collection with the cursor on the first. positionViewAtIndex
          // during construction lands somewhere equally arbitrary, and
          // ApplyRange never re-applied once the origin had moved.
          //
          // So: everything is measured FROM originX, and clamped to it.
          function followCursor() {
            if (count === 0 || width <= 0 || tileWidth <= 0) return
            var x = Math.max(minX(), Math.min(maxX(), contentX))
            var left = originX + Math.max(0, root.collectionCursor) * stride
            if (left < x) x = left
            else if (left + tileWidth > x + width) x = left + tileWidth - width
            contentX = Math.max(minX(), Math.min(maxX(), x))
          }

          onWidthChanged: collectionsRow.followCursor()
          onCountChanged: collectionsRow.followCursor()
          // The shift itself, caught directly: it is what leaves contentX
          // pointing at the wrong tile, and it happens after both of the above.
          onOriginXChanged: collectionsRow.followCursor()

          Connections {
            target: root
            function onCollectionCursorChanged() { collectionsRow.followCursor() }
            // Coming back to the row after the wheel left it somewhere else: the
            // cursor has not moved, so nothing else here would fire.
            function onRegionNameChanged() { collectionsRow.followCursor() }
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
            // Opens the collection as its own page. It used to toggle a facet on
            // this grid, which meant a collection had no place of its own and no
            // way to be renamed or removed.
            onActivated: root.openCollection(modelData.name)
          }

          // A vertical wheel over the row scrolls it sideways, the same bargain
          // the chip strip makes. Now that the tiles fit the width there is no
          // half-card left hinting at an overflow, so reaching it must not depend
          // on owning a horizontal wheel.
          WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: function (event) {
              // Nothing to scroll: leave the event alone so the page still moves
              // under a pointer that happens to be resting here.
              if (!collectionsRow.overflowing) return
              var delta = event.angleDelta.y !== 0 ? event.angleDelta.y
                                                   : event.angleDelta.x
              if (delta === 0) return
              // One whole tile per notch, so the row lands on tile boundaries
              // rather than part-way across one. Clamped to the row's own bounds,
              // which start at originX -- clamping to 0 would throw the row past
              // its end, since the origin here is a long way negative.
              collectionsRow.contentX =
                Math.max(collectionsRow.minX(),
                         Math.min(collectionsRow.maxX(),
                                  collectionsRow.contentX
                                  - delta / 120 * collectionsRow.stride))
              event.accepted = true
            }
          }

          // Which handler gets a wheel is decided by hover, not by hoping the
          // accepted flag propagates between two independent handlers.
          HoverHandler { id: collectionsHover }
        }
      }
    }

    Column {
      width: parent.width
      spacing: Style.spacing.md

      PanelSectionHeader {
        text: root.awaiting
              ? "SEARCHING…"
              : (root.searching
                 ? root.shownMemories.length + (root.shownMemories.length === 1
                                                ? " RESULT" : " RESULTS")
                 : "CAPTURES")
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
              count: root.searching ? root.results.length
                                    : ((root.index.memories || []).length)
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

          // A vertical wheel over the strip scrolls it sideways: nobody expects
          // to hunt for a horizontal wheel.
          //
          // The step is a fraction of the visible width rather than a fixed
          // pixel count, so it covers the same proportion of the strip on any
          // dialog size -- roughly two thirds of a screenful per notch.
          WheelHandler {
            id: stripWheel
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: function (event) {
              var delta = event.angleDelta.y !== 0 ? event.angleDelta.y
                                                   : event.angleDelta.x
              if (delta === 0) return
              var limit = Math.max(0, strip.contentWidth - strip.width)
              var step = Math.max(Style.space(240), strip.width * 0.66)
              strip.contentX = Math.max(0, Math.min(limit,
                                        strip.contentX - delta / 120 * step))
              // Claim it, or the page's own handler scrolls vertically at the
              // same time and the sideways movement is hard to even see.
              event.accepted = true
            }
          }

          // Which handler gets a wheel is decided by hover, not by hoping the
          // accepted flag propagates between two independent handlers.
          HoverHandler { id: stripHover }
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
      }

      Text {
        visible: root.shownMemories.length === 0 && !root.awaiting
        text: (root.index.memories || []).length === 0
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
