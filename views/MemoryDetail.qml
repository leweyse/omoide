import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../blocks"
import "../common"
import "../components"
import "../MemoryModel.js" as Model

// Blocks, then three fixed sections in the reference's order: Related
// captures, Collections, and the accuracy disclaimer. Those are page
// furniture, not blocks: the model never emits them and cannot reorder them.
Flickable {
  id: root

  // Whether this page holds the keyboard. The window gives it to the rail or
  // the page, never both, so the page draws its cursor only while it holds it.
  // Otherwise a highlighted card looks ready for Enter while the keys still go
  // to the sidebar.
  property bool hasKeyboard: true

  property var service: null
  property string memoryId: ""
  property var memory: ({ blocks: [], items: [], collections: [] })
  property var siblings: []          // the link set, for prev/next
  signal openMemory(string id)
  signal openItem(string id)
  signal deleteMemory(string id)
  signal previewImage(string path)
  signal menuRequested(real sceneX, real sceneY)
  signal editBlock(string blockId, string blockType, var payload)
  signal retryEnrichment(string id)
  // The window owns both dialogs; this page only asks for them.
  signal linkRequested()
  signal collectionRequested()
  // The to-dos card asks to manage its list.
  signal manageTodos(string blockId, var items)

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
      var notches = event.angleDelta.y / 120
      var limit = Math.max(0, root.contentHeight - root.height)
      root.contentY = Math.max(0, Math.min(limit,
                                           root.contentY - notches * Style.space(140)))
    }
  }

  function reload() {
    if (!service || !memoryId) return
    service.call(["show", "--id", memoryId], function (code, json) {
      if (json) root.memory = json
    })
  }

  onMemoryIdChanged: reload()

  // The item editor is a separate surface, so a delete or a completion made
  // there has to reach this list somehow. Every mutation makes the service pull
  // a new index, so its index changing is the general "data moved" signal. The two surfaces need no direct wiring.
  Connections {
    target: root.service
    function onIndexChanged() { root.reload() }
  }


  function step(direction) {
    var list = related.linked || []
    if (!list.length) return
    root.openMemory(list[direction > 0 ? 0 : list.length - 1].id)
  }

  // Collections this memory looks like it belongs in: the agent's tags matched
  // against names that already exist. OFFERED, never applied: a collection
  // records a decision, and a guess written into one is indistinguishable from
  // a deliberate filing afterwards.
  // --- keyboard ------------------------------------------------------------
  //
  // Three regions: the block cards, the related captures, then the badge row of
  // collections and links. Arrows walk the cards, which is also how this page
  // scrolls, so EVERY card takes the cursor, including the ones Enter does
  // nothing on.

  // The blocks in the order they are drawn, not the order they are stored: the
  // image is hoisted above the title and the event above the rest, matching the
  // three BlockRenderer instances below. A cursor that walked stored order would
  // jump around the page.
  // A function of the memory rather than a binding read from elsewhere, so it can
  // be called with the value that just arrived. Read inside memory's own change
  // handler, the `orderedBlocks` binding can still hold the PREVIOUS ordering,
  // which is empty on first load.
  function orderBlocks(mem) {
    var all = (mem && mem.blocks) || []
    var img = [], evt = [], rest = []
    for (var i = 0; i < all.length; i++) {
      var b = all[i]
      if (!Model.isRenderable(b.type)) continue
      if (b.type === "image") img.push(b)
      else if (b.type === "event") evt.push(b)
      else rest.push(b)
    }
    return img.concat(evt).concat(rest)
  }

  readonly property var orderedBlocks: root.orderBlocks(root.memory)

  // related.linked, not `siblings`: nothing assigns that property. The section
  // loads its own link set.
  readonly property var relatedRows: related.linked || []

  readonly property int regionCount: 3
  property int region: 0
  // Focused block, by id. The blocks live in three renderers, so an index would
  // mean nothing.
  property string blockCursor: ""
  property int relatedCursor: -1
  property int badgeCursor: -1

  // Drilled into a to-dos card: the rows take the arrows and Esc comes back out.
  property int todoCursor: -1

  readonly property int mineCount:
    ((root.memory && root.memory.collections) || []).length
  readonly property bool badgeFocused: root.region === 2 && root.badgeCursor >= 0

  readonly property var badges: {
    var out = []
    var mine = (root.memory && root.memory.collections) || []
    for (var i = 0; i < mine.length; i++) out.push({ kind: "collection", name: mine[i] })
    for (var j = 0; j < root.suggestedCollections.length; j++)
      out.push({ kind: "suggest", name: root.suggestedCollections[j] })
    out.push({ kind: "add" })
    return out
  }

  function blockAt(i) {
    var list = root.orderedBlocks
    return (i >= 0 && i < list.length) ? list[i] : null
  }

  function blockIndex() {
    var list = root.orderedBlocks
    for (var i = 0; i < list.length; i++)
      if (list[i].id === root.blockCursor) return i
    return -1
  }

  // Explicit index rather than reading a region-derived binding: the order
  // between a binding updating and its own property's change handler is
  // undefined, and reading one in here can return the region just left.
  function enterRegion(i) {
    root.todoCursor = -1
    root.blockCursor = ""
    root.relatedCursor = -1
    root.badgeCursor = -1
    if (i === 0) {
      var first = root.blockAt(0)
      root.blockCursor = first ? first.id : ""
    } else if (i === 1) {
      root.relatedCursor = 0
      Qt.callLater(function () { root.scrollTo(related) })
    } else {
      root.badgeCursor = root.badges.length > 0 ? 0 : -1
      Qt.callLater(function () { root.scrollTo(collectionsSection) })
    }
  }

  onRegionChanged: root.enterRegion(root.region)

  // The page's blocks arrive from the CLI after it is on screen, so entering it
  // can happen while there is nothing to focus yet. Seed the cursor when they
  // land, and recover if a reload dropped the block it was sitting on.
  //
  // Skipped while drilled into a to-dos card: ticking a row reloads the memory,
  // and re-seeding there would throw the cursor back out to the card.
  onMemoryChanged: {
    if (root.region !== 0 || root.todoCursor >= 0) return
    // Ordered from the memory in hand. blockIndex() reads the binding, which is
    // stale in here, so the check is done against the fresh list too.
    var fresh = root.orderBlocks(root.memory)
    var held = false
    for (var i = 0; i < fresh.length; i++)
      if (fresh[i].id === root.blockCursor) { held = true; break }
    if (!held) root.blockCursor = fresh.length > 0 ? fresh[0].id : ""
  }

  function focusFirst() {
    root.region = 0
    root.enterRegion(0)
  }

  function pageKey(event) {
    // The two inline drill-ins are rungs of their own on the Esc stack, and they
    // have to be taken before the dialog's unwind sees the key.
    if (root.todoCursor >= 0) return root.todoKey(event)

    var down = event.key === Qt.Key_Down
    var up = event.key === Qt.Key_Up

    // One continuous column. Down runs off the last block into Related, off
    // Related into Collections, and Up walks back. The page reads as a single
    // scroll, so a vertical key must not stop dead at a section boundary.
    if (down || up) {
      if (root.region === 0) {
        var moved = Model.stepList(root.orderedBlocks.length, root.blockIndex(),
                                   down ? 1 : -1)
        if (moved !== null) {
          var b = root.blockAt(moved)
          root.blockCursor = b ? b.id : ""
          root.ensureBlockVisible()
          return true
        }
        if (down) root.region = 1
        return true
      }
      if (root.region === 1) {
        if (down) root.region = 2
        else root.toLastBlock()
        return true
      }
      if (up) root.region = 1
      return true
    }

    if (root.region === 0) {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        root.activateBlock(root.blockAt(root.blockIndex()))
        return true
      }
      return false
    }

    // +1 for the section's own "Link a memory" chip, which sits after the cards.
    if (root.region === 1) return root.rowKey(event, root.relatedRows.length + 1,
                                              "relatedCursor")
    return root.rowKey(event, root.badges.length, "badgeCursor")
  }

  // Coming up out of Related lands on the LAST block, not the first: the column
  // has to feel continuous in both directions. Region first, so enterRegion's
  // first-block default is applied and then overridden.
  function toLastBlock() {
    root.region = 0
    var last = root.blockAt(root.orderedBlocks.length - 1)
    root.blockCursor = last ? last.id : ""
    root.ensureBlockVisible()
  }

  // The rows of a to-dos card, once Enter has drilled in.
  function todoKey(event) {
    var block = root.blockAt(root.blockIndex())
    var rows = block ? root.itemsOf(block) : []
    if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
      var moved = Model.stepList(rows.length, root.todoCursor,
                                 event.key === Qt.Key_Down ? 1 : -1)
      if (moved !== null) root.todoCursor = moved
      return true
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      var one = rows[root.todoCursor]
      if (one) root.openItem(one.id)
      return true
    }

    if (event.key === Qt.Key_Space) {
      var args = Model.todoAction(rows[root.todoCursor])
      if (args && root.service)
        root.service.call(args, function () {
          root.reload()
          root.service.refresh()
        })
      return true
    }
    // Back out to the card, one rung, exactly as the Esc stack says.
    if (event.key === Qt.Key_Escape) {
      if (!event.isAutoRepeat) root.todoCursor = -1
      return true
    }
    return true
  }

  function itemsOf(block) {
    var ids = (block && block.payload && block.payload.item_ids) || []
    var all = (root.memory && root.memory.items) || []
    var out = []
    for (var i = 0; i < ids.length; i++)
      for (var j = 0; j < all.length; j++)
        if (all[j].id === ids[i]) out.push(all[j])
    return out
  }

  // What Enter means depends on the card, because only some block types have
  // an editor. An inert card is still focusable, as part of the scroll path, so
  // Enter there simply does nothing.
  function activateBlock(block) {
    if (!block) return
    var t = block.type
    if (t === "summary" || t === "list"
        || t === "text" || t === "quote" || t === "code") {
      root.editBlock(block.id, t, block.payload || ({}))
    } else if (t === "event") {
      // The ITEM editor, not the block editor. An event block's payload is only
      // an item_id, with no prose in it. Its date, place and reminders live on
      // the item, which is also where the card's own pencil goes, so the keyboard
      // and the mouse agree.
      var ev = (block.payload && block.payload.item_id) || ""
      if (ev.length) root.openItem(ev)
    } else if (t === "image") {
      var path = (block.payload && block.payload.path) || ""
      if (path.length) root.previewImage(path)
    } else if (t === "source") {
      var url = (block.payload && block.payload.url) || ""
      if (url.length) Quickshell.execDetached(["omarchy", "launch", "browser", url])
    } else if (t === "todos") {
      // Drill in. Esc comes back to the card.
      root.todoCursor = root.itemsOf(block).length > 0 ? 0 : -1
    }
    // "note" falls through: verbatim user text, and there is no editor for it.
  }

  // Shared by the two flat rows. `field` names the cursor property so one
  // function serves both instead of two near-identical copies.
  function rowKey(event, count, field) {
    if (event.key === Qt.Key_Right || event.key === Qt.Key_Left) {
      var moved = Model.stepList(count, root[field],
                                 event.key === Qt.Key_Right ? 1 : -1)
      // Left off the first one is not consumed, so the dialog can take it and
      // return to the sidebar.
      if (moved === null) return event.key === Qt.Key_Right
      root[field] = moved
      return true
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.activateRow(field, root[field])
      return true
    }
    return false
  }

  function activateRow(field, i) {
    if (field === "relatedCursor") {
      if (i === root.relatedRows.length) { root.linkRequested(); return }
      var sib = root.relatedRows[i]
      if (sib) root.openMemory(sib.id || sib)
      return
    }
    var badge = root.badges[i]
    if (!badge) return
    // A collection this memory is already in is a plain label with no click
    // handler, so Enter does nothing there either. The keyboard must not invent
    // an action the mouse does not have.
    if (badge.kind === "suggest") root.fileInto(badge.name)
    else if (badge.kind === "add") root.collectionRequested()
  }

  // Real geometry, from whichever of the three renderers holds the card, so a
  // page only a little taller than the viewport still scrolls to it.
  function ensureBlockVisible() {
    var id = root.blockCursor
    if (!id.length) return
    var cell = imageBlocks.cellFor(id) || eventBlocks.cellFor(id)
                                       || restBlocks.cellFor(id)
    root.scrollTo(cell)
  }

  function scrollTo(it) {
    if (!it) return
    var top = it.mapToItem(layout, 0, 0).y
    var bottom = top + it.height
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

  readonly property var suggestedCollections: {
    var index = root.service ? root.service.index : null
    var all = []
    var list = (index && index.collections) || []
    for (var i = 0; i < list.length; i++) all.push(list[i].name)
    var mine = []
    var current = root.memory.collections || []
    for (var j = 0; j < current.length; j++) mine.push(current[j].name)
    return Model.suggestCollections(root.memory.tags || [], all, mine)
  }

  function fileInto(name) {
    if (!root.service || !name.length) return
    root.service.call(["collection", "add", "--name", name,
                       "--memory", root.memoryId], function () { root.reload() })
  }

  Item { id: focusSink }

  Keys.onLeftPressed: root.step(-1)
  Keys.onRightPressed: root.step(1)

  // Floating, at the top right, OUTSIDE the column, so it adds no height and
  // cannot shift anything. It scrolls with the content.
  //
  // The menu itself is owned by the window rather than hung off this button: a
  // child positioned outside its parent's bounds renders but is never
  // hit-tested, so a dropdown below a one-line row could be seen and not
  // clicked. Scene coordinates go up with the request.
  Row {
    id: pageActions
    x: root.width - width - Style.spacing.panelPadding
    y: 0
    z: 2
    spacing: Style.spacing.sm

    Row {
      spacing: Style.spacing.sm
      visible: (related.linked || []).length > 0

      PanelActionButton {
        iconText: "‹"
        tooltipText: "Previous linked capture"
        size: Style.space(26)
        foreground: Color.popups.text
        fontFamily: Style.font.resolvedFamily
        onClicked: root.step(-1)
      }

      PanelActionButton {
        iconText: "›"
        tooltipText: "Next linked capture"
        size: Style.space(26)
        foreground: Color.popups.text
        fontFamily: Style.font.resolvedFamily
        onClicked: root.step(1)
      }
    }

    PanelActionButton {
      id: overflow
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
  }

  Column {
    id: layout
    x: Style.spacing.panelPadding
    y: 0
    width: root.width - Style.spacing.panelPadding * 2
    spacing: Style.spacing.xxxl

    // The capture itself, first. It is the thing you recognise.
    BlockRenderer {
      id: imageBlocks
      width: parent.width
      memory: root.memory
      service: root.service
      cursorId: root.blockCursor
      cursorActive: root.region === 0 && root.todoCursor < 0
      rowCursor: root.todoCursor
      only: ["image"]
      // The action buttons float over this block's top-right corner, so the
      // capture keeps clear of them. Both sides, so the picture stays centred
      // on the page rather than sliding left by half a gutter.
      imageGutter: pageActions.width + Style.spacing.lg
      onChanged: { root.reload(); if (root.service) root.service.refresh() }
      onOpenItem: function (item) { if (item) root.openItem(item.id) }
      onManageTodos: function (blockId, items) {
        root.manageTodos(blockId, items)
      }
      onPreviewImage: function (path) { root.previewImage(path) }
      onEditBlock: function (blockId, blockType, payload) {
        root.editBlock(blockId, blockType, payload)
      }
    }

    // Extra air above and below, on top of the page's own spacing. The title
    // is the hinge between the capture and what was made of it, and at the
    // stack's default gap it reads as just another row.
    Item {
      id: titleRow
      width: parent.width
      height: titleGroup.implicitHeight + Style.spacing.xxl * 2

      Column {
        id: titleGroup
        anchors.left: parent.left
        anchors.right: parent.right
        // Room for the floating actions only when they would actually be
        // alongside -- which is when there is no capture above to separate them.
        anchors.rightMargin: imageBlocks.visible
                             ? 0 : pageActions.width + Style.spacing.lg
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.sm

        Text {
          id: titleText
          width: parent.width
          textFormat: Text.PlainText
          text: root.memory.title || ""
          wrapMode: Text.WordWrap
          color: Color.popups.text
          font.family: Style.font.resolvedFamily
          font.pixelSize: Style.font.heading
        }

        Text {
          visible: !!root.memory.lede
          width: parent.width
          textFormat: Text.PlainText
          text: root.memory.lede || ""
          wrapMode: Text.WordWrap
          color: Color.muted
          font.family: Style.font.resolvedFamily
          font.pixelSize: Style.font.subtitle
        }
      }
    }

    // The event, before everything else. When a capture is about something
    // happening at a time, that is what the user came back for, ahead of the
    // note, the source and the summary. Hoisted here rather than reordered in
    // the database, so the stored positions stay as the agent wrote them.
    BlockRenderer {
      id: eventBlocks
      width: parent.width
      memory: root.memory
      service: root.service
      cursorId: root.blockCursor
      cursorActive: root.region === 0 && root.todoCursor < 0
      rowCursor: root.todoCursor
      only: ["event"]
      onChanged: { root.reload(); if (root.service) root.service.refresh() }
      onOpenItem: function (item) { if (item) root.openItem(item.id) }
      onManageTodos: function (blockId, items) {
        root.manageTodos(blockId, items)
      }
      onPreviewImage: function (path) { root.previewImage(path) }
      onEditBlock: function (blockId, blockType, payload) {
        root.editBlock(blockId, blockType, payload)
      }
    }

    // Everything else, in the order the agent chose. The image is drawn above
    // the title and the event above this, so both are excluded. The note comes
    // first among what is left: the CLI inserts it before any agent block.
    BlockRenderer {
      id: restBlocks
      width: parent.width
      memory: root.memory
      service: root.service
      cursorId: root.blockCursor
      cursorActive: root.region === 0 && root.todoCursor < 0
      rowCursor: root.todoCursor
      except: ["image", "event"]
      onChanged: { root.reload(); if (root.service) root.service.refresh() }
      onOpenItem: function (item) { if (item) root.openItem(item.id) }
      onManageTodos: function (blockId, items) {
        root.manageTodos(blockId, items)
      }
      onPreviewImage: function (path) { root.previewImage(path) }
      onEditBlock: function (blockId, blockType, payload) {
        root.editBlock(blockId, blockType, payload)
      }
    }

    RelatedCaptures {
      id: related
      cursor: root.region === 1 ? root.relatedCursor : -1
      // The chip inside this section asks; the page relays to the window, which
      // owns the dialog.
      onLinkRequested: root.linkRequested()
      width: parent.width
      service: root.service
      memoryId: root.memoryId
      onOpenMemory: function (id) { root.openMemory(id) }
    }

    Column {
      id: collectionsSection
      width: parent.width
      spacing: Style.spacing.md

      PanelSectionHeader {
        text: "Collections"
        foreground: Color.muted
        fontFamily: Style.font.resolvedFamily
      }

      Flow {
        width: parent.width
        spacing: Style.spacing.md

        Repeater {
          model: root.memory.collections || []

          delegate: Chip {
            required property var modelData
            required property int index
            label: modelData.name
            hasCursor: root.hasKeyboard && root.badgeFocused && root.badgeCursor === index
          }
        }

        // Outlined, not filled: an offer has to look different from a
        // collection this memory is actually in, or the two read as the same
        // thing and tapping one feels like undoing the other.
        Repeater {
          model: root.suggestedCollections

          delegate: Chip {
            required property var modelData
            required property int index
            hasCursor: root.hasKeyboard && root.badgeFocused
                       && root.badgeCursor === root.mineCount + index
            label: "+  " + modelData
            tint: Color.accent
            outlined: true
            interactive: true
            onClicked: root.fileInto(modelData)
          }
        }

        Chip {
          hasCursor: root.hasKeyboard && root.badgeFocused
                     && root.badgeCursor === root.badges.length - 1
          label: "+  Add to collection"
          tint: Color.muted
          outlined: true
          interactive: true
          onClicked: root.collectionRequested()
        }
      }

    }

    // The enriched content is a model's reading of a screenshot. Saying so
    // once, quietly, at the bottom of the page is the honest place for it.
    Text {
      visible: root.memory.aiStatus === "ok"
      width: parent.width
      text: "The information above was generated from this capture and may contain inaccuracies."
      wrapMode: Text.WordWrap
      color: Color.muted
      font.family: Style.font.resolvedFamily
      font.pixelSize: Style.font.body
      opacity: 0.8
    }

    Column {
      width: parent.width
      visible: root.memory.aiStatus === "failed"
      spacing: Style.spacing.lg

      Text {
        width: parent.width
        // With the reason, when there is one. An unexplained failure tells the
        // user nothing they can act on.
        textFormat: Text.PlainText
        text: (root.memory.aiError && root.memory.aiError.length)
              ? "Enrichment failed: " + root.memory.aiError
                + ". Your note and screenshot are intact."
              : "Enrichment failed for this capture — your note and screenshot are intact."
        wrapMode: Text.WordWrap
        color: Color.urgent
        font.family: Style.font.resolvedFamily
        font.pixelSize: Style.font.body
      }

      // A reason with nothing to do about it is just bad news. Anything corrected
      // by hand survives the retry, because the block editor sets `edited`.
      Chip {
        label: "Try again"
        tint: Color.accent
        outlined: true
        interactive: true
        onClicked: root.retryEnrichment(root.memoryId)
      }
    }
  }
}
