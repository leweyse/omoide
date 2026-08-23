import QtQuick
import qs.Commons
import qs.Ui
import ".." as Root
import "../MemoryModel.js" as Model

Flickable {
  id: root

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

  // Derived from appliedQuery, NOT from the live field. Keyed off the field it
  // flipped the grid to the results set on the first keystroke -- while those
  // results still belonged to the previous query -- so typing showed "0
  // RESULTS" and an empty page until the debounce caught up.
  readonly property bool searching: searchOpen && appliedQuery.length > 0

  function runSearch() {
    if (!service) return
    var wanted = root.query.trim()
    if (!wanted.length) {
      root.results = []
      root.appliedQuery = ""
      root.awaiting = false
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

  // "" means All. Filtering happens here rather than in the CLI: index.json
  // already carries every card's kind, domain and tags, so a chip is a local
  // predicate and switching one is instant.
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

  function refreshView() {
    root.shownMemories = root.visibleMemories()
    root.shownFacets = root.computeFacets()
  }

  onFacetChanged: refreshView()
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
    spacing: Style.spacing.xxl

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
      // a required modelData would never be set and the card would fail to
      // create -- which showed up as an empty grid.
      onActivated: root.openMemory(memory.id)
    }
  }

    Column {
      width: parent.width
      spacing: Style.spacing.sm
      // Collections are about browsing, so they step aside while searching.
      visible: !root.searching && (root.index.collections || []).length > 0

      PanelSectionHeader {
        text: "COLLECTIONS"
        foreground: Color.muted
        fontFamily: Style.font.resolvedFamily
      }

      ListView {
        width: parent.width
        height: Style.space(112)
        orientation: ListView.Horizontal
        spacing: Style.spacing.md
        clip: true
        model: root.index.collections || []

        delegate: Root.CollectionTile {
          required property var modelData
          collection: modelData
          // Opens the collection as its own page. It used to toggle a facet on
          // this grid, which meant a collection had no place of its own and no
          // way to be renamed or removed.
          onActivated: root.openCollection(modelData.name)
        }
      }
    }

    Column {
      width: parent.width
      spacing: Style.spacing.sm

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
      // One horizontally scrollable strip rather than a wrapping block: wrapped,
      // two dozen chips took five rows and pushed the captures off the page.
      // A strip keeps the row height constant however many facets exist.
      Item {
        width: parent.width
        // Trailing air of its own, so the chips read as a control strip above
        // the grid rather than as the grid's first row.
        height: searchToggle.height + Style.spacing.lg
        visible: root.shownFacets.length > 0 || root.searchOpen

        // Pinned outside the strip: a control you cannot reach because it
        // scrolled away is worse than one that costs a little width.
        Root.FilterChip {
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
            spacing: Style.spacing.sm

            Root.FilterChip {
              label: "All"
              count: root.searching ? root.results.length
                                    : ((root.index.memories || []).length)
              selected: root.facet.length === 0
              onPicked: root.facet = ""
            }

            Repeater {
              model: root.shownFacets

              delegate: Root.FilterChip {
                required property var modelData
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
        // carries its own -- so the field reads as a control above the grid
        // rather than as its first row. Zero when closed, so it costs nothing
        // while unused.
        height: root.searchOpen ? field.height + Style.spacing.lg : 0
        visible: root.searchOpen

        TextField {
          id: field
          anchors.left: parent.left
          anchors.right: parent.right
          foreground: Color.popups.text
          accent: Color.accent
          font.family: Style.font.resolvedFamily
          font.pixelSize: Style.font.subtitle
          placeholderText: "Search memories, notes and screenshot text…"
          rightPadding: Style.space(30)
          onTextChanged: {
            root.query = text
            searchDebounce.restart()
          }
          Keys.onEscapePressed: function (event) {
            // First Esc leaves the field, a second closes search entirely --
            // consistent with how Esc unwinds everywhere else.
            focusSink.forceActiveFocus()
            event.accepted = true
          }
        }

        PanelActionButton {
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.sm
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


      Root.MasonryGrid {
        width: parent.width
        items: root.shownMemories
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
        font.pixelSize: Style.font.body
      }
    }
  }
}
