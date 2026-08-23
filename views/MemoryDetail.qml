import QtQuick
import qs.Commons
import qs.Ui
import ".." as Root
import "../MemoryModel.js" as Model

// Blocks, then three fixed sections in the reference's order: Related
// captures, Collections, and the accuracy disclaimer. Those are page
// furniture, not blocks -- the model never emits them and cannot reorder them.
Flickable {
  id: root

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
  // there has to reach this list somehow. Every mutation rewrites index.json
  // and pings the service, so its index changing is the general "data moved"
  // signal -- no direct wiring between the two surfaces needed.
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
  // against names that already exist. OFFERED, never applied -- a collection
  // records a decision, and a guess written into one is indistinguishable from
  // a deliberate filing afterwards. `links` was removed from this plugin for
  // exactly that reason.
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

  // Floating, at the top right, OUTSIDE the column. In the column it was a
  // 26px header row that pushed the whole page down; here it adds no height and
  // cannot shift anything. It scrolls with the content, which is where it was
  // before.
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
    spacing: Style.spacing.xs

    Row {
      spacing: Style.spacing.xs
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
    spacing: Style.spacing.xxl

    // The capture itself, first. It is the thing you recognise.
    Root.BlockRenderer {
      id: imageBlocks
      width: parent.width
      memory: root.memory
      service: root.service
      only: ["image"]
      onChanged: { root.reload(); if (root.service) root.service.refresh() }
      onOpenItem: function (item) { if (item) root.openItem(item.id) }
      onPreviewImage: function (path) { root.previewImage(path) }
      onEditBlock: function (blockId, blockType, payload) {
        root.editBlock(blockId, blockType, payload)
      }
    }

    // Extra air above and below, on top of the page's own spacing. The title
    // is the hinge between the capture and what was made of it, and at the
    // stack's default gap it read as just another row.
    Item {
      id: titleRow
      width: parent.width
      height: titleGroup.implicitHeight + Style.spacing.xl * 2

      Column {
        id: titleGroup
        anchors.left: parent.left
        anchors.right: parent.right
        // Room for the floating actions only when they would actually be
        // alongside -- which is when there is no capture above to separate them.
        anchors.rightMargin: imageBlocks.visible
                             ? 0 : pageActions.width + Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xs

        Text {
          id: titleText
          width: parent.width
          text: root.memory.title || ""
          wrapMode: Text.WordWrap
          color: Color.popups.text
          font.family: Style.font.resolvedFamily
          font.pixelSize: Style.font.heading
        }

        Text {
          visible: !!root.memory.lede
          width: parent.width
          text: root.memory.lede || ""
          wrapMode: Text.WordWrap
          color: Color.muted
          font.family: Style.font.resolvedFamily
          font.pixelSize: Style.font.body
        }
      }
    }

    // The event, before everything else. When a capture is about something
    // happening at a time, that is the thing you came back for -- ahead of the
    // note, the source and the summary. Hoisted here rather than reordered in
    // the database, so the stored positions stay as the agent wrote them.
    Root.BlockRenderer {
      width: parent.width
      memory: root.memory
      service: root.service
      only: ["event"]
      onChanged: { root.reload(); if (root.service) root.service.refresh() }
      onOpenItem: function (item) { if (item) root.openItem(item.id) }
      onPreviewImage: function (path) { root.previewImage(path) }
      onEditBlock: function (blockId, blockType, payload) {
        root.editBlock(blockId, blockType, payload)
      }
    }

    // Everything else, in the order the agent chose. The image is drawn above
    // the title and the event above this, so both are excluded. The note comes
    // first among what is left: the CLI inserts it before any agent block.
    Root.BlockRenderer {
      width: parent.width
      memory: root.memory
      service: root.service
      except: ["image", "event"]
      onChanged: { root.reload(); if (root.service) root.service.refresh() }
      onOpenItem: function (item) { if (item) root.openItem(item.id) }
      onPreviewImage: function (path) { root.previewImage(path) }
      onEditBlock: function (blockId, blockType, payload) {
        root.editBlock(blockId, blockType, payload)
      }
    }

    Root.RelatedCaptures {
      id: related
      width: parent.width
      service: root.service
      memoryId: root.memoryId
      onOpenMemory: function (id) { root.openMemory(id) }
    }

    Column {
      width: parent.width
      spacing: Style.spacing.sm

      PanelSectionHeader {
        text: "Collections"
        foreground: Color.muted
        fontFamily: Style.font.resolvedFamily
      }

      Flow {
        width: parent.width
        spacing: Style.spacing.sm

        Repeater {
          model: root.memory.collections || []

          delegate: Root.Chip {
            required property var modelData
            label: modelData.name
          }
        }

        // Outlined, not filled: an offer has to look different from a
        // collection this memory is actually in, or the two read as the same
        // thing and tapping one feels like undoing the other.
        Repeater {
          model: root.suggestedCollections

          delegate: Root.Chip {
            required property var modelData
            label: "+  " + modelData
            tint: Color.accent
            outlined: true
            interactive: true
            onClicked: root.fileInto(modelData)
          }
        }

        Root.Chip {
          label: "+  Add to collection"
          tint: Color.muted
          outlined: true
          interactive: true
          onClicked: collectionPrompt.visible = true
        }
      }

      Row {
        id: collectionPrompt
        visible: false
        width: parent.width
        spacing: Style.spacing.sm

        TextField {
          id: collectionName
          width: Style.space(220)
          foreground: Color.popups.text
          accent: Color.accent
          font.family: Style.font.resolvedFamily
          placeholderText: "Collection name"
          onAccepted: addToCollection.clicked()
          Keys.onEscapePressed: function (event) {
            focusSink.forceActiveFocus()
            event.accepted = true
          }
        }

        Button {
          id: addToCollection
          text: "Add"
          foreground: Color.popups.text
          background: Color.popups.background
          fontFamily: Style.font.resolvedFamily
          onClicked: {
            if (!collectionName.text.trim().length || !root.service) return
            root.service.call(["collection", "add", "--name", collectionName.text.trim(),
                               "--memory", root.memoryId], function () { root.reload() })
            collectionName.text = ""
            collectionPrompt.visible = false
          }
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
      font.pixelSize: Style.font.caption
      opacity: 0.8
    }

    Column {
      width: parent.width
      visible: root.memory.aiStatus === "failed"
      spacing: Style.spacing.md

      Text {
        width: parent.width
        // With the reason, when there is one. An unexplained failure tells the
        // user nothing they can act on, and until schema v5 nothing recorded it.
        text: (root.memory.aiError && root.memory.aiError.length)
              ? "Enrichment failed: " + root.memory.aiError
                + ". Your note and screenshot are intact."
              : "Enrichment failed for this capture — your note and screenshot are intact."
        wrapMode: Text.WordWrap
        color: Color.urgent
        font.family: Style.font.resolvedFamily
        font.pixelSize: Style.font.caption
      }

      // A reason with nothing to do about it is just bad news. Anything you
      // have corrected by hand survives the retry -- that is what the block
      // editor's `edited` flag buys.
      Root.Chip {
        label: "Try again"
        tint: Color.accent
        outlined: true
        interactive: true
        onClicked: root.retryEnrichment(root.memoryId)
      }
    }
  }
}
