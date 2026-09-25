import QtQuick
import qs.Commons
import "../MemoryModel.js" as Model

// type -> delegate. A block whose type this build does not know renders as
// nothing rather than erroring, so a memory written by a newer version of the
// plugin still opens.
Column {
  id: renderer

  property var memory: ({})
  property var service: null
  signal changed()
  signal openItem(var item)
  signal previewImage(string path)
  // The block the user wants to correct, handed up whole: the page owns the
  // editor, so it needs the id, the type and the current payload.
  signal editBlock(string blockId, string blockType, var payload)
  // The to-dos card asks to manage its list; the page relays upward.
  signal manageTodos(string blockId, var items)

  // Which block types this instance draws, so a page can put some blocks above
  // its title and the rest below without reordering stored rows. `only` empty
  // means everything; `except` always wins.
  property var only: []
  property var except: []

  // The focused block, by id. The page owns the cursor because the blocks are
  // split across three renderers -- image above the title, event next, the rest
  // below -- and only the page knows the order they read in.
  property string cursorId: ""
  // Whether to PAINT it. The page keeps its place when focus moves to a sibling
  // region but must stop showing a ring, or two highlights sit on screen.
  property bool cursorActive: true
  // Row cursor for a to-dos card that has been drilled into, or -1. Applies to
  // whichever card holds cursorId -- only the focused one can be drilled into.
  property int rowCursor: -1

  // How much width an image block must leave free on each side. A page that
  // floats controls over its first block sets this; the block itself has no way
  // to know what is drawn on top of it.
  property real imageGutter: 0

  readonly property var shownBlocks: {
    var all = (renderer.memory && renderer.memory.blocks) || []
    var out = []
    for (var i = 0; i < all.length; i++) {
      var type = all[i].type
      if (renderer.only.length > 0 && renderer.only.indexOf(type) < 0) continue
      if (renderer.except.indexOf(type) >= 0) continue
      out.push(all[i])
    }
    return out
  }

  // An empty Column still claims a spacing slot from its parent, so an
  // instance with nothing to draw has to be invisible, not merely zero-height.
  visible: renderer.shownBlocks.length > 0

  spacing: Style.spacing.xxl

  function itemById(id) {
    var items = (memory && memory.items) || []
    for (var i = 0; i < items.length; i++)
      if (items[i].id === id) return items[i]
    return null
  }

  function itemsFor(block) {
    var ids = (block.payload && block.payload.item_ids) || []
    var out = []
    for (var i = 0; i < ids.length; i++) {
      var found = renderer.itemById(ids[i])
      if (found) out.push(found)
    }
    return out
  }

  // The loaded cell for a block id, or null. Only the Repeater knows a card's
  // real geometry, and cards vary in height by a factor of ten here.
  function cellFor(id) {
    for (var i = 0; i < rep.count; i++) {
      var cell = rep.itemAt(i)
      if (cell && cell.modelData && cell.modelData.id === id) return cell
    }
    return null
  }

  Repeater {
    id: rep
    model: renderer.shownBlocks

    delegate: Loader {
      id: slot
      required property var modelData
      width: renderer.width
      active: Model.isRenderable(modelData.type)

      sourceComponent: {
        switch (modelData.type) {
        case "source":  return sourceCard
        case "image":   return imageCard
        case "note":    return noteCard
        case "summary": return summaryCard
        case "list":    return listCard
        case "todos":   return todosCard
        case "event":   return eventCard
        case "text":
        case "quote":
        case "code":    return textCard
        default:        return null
        }
      }

      // Bindings, not assignments in onLoaded. onLoaded fires once per load, so
      // anything pushed there is frozen at that moment: ticking a to-do
      // reloaded the memory and reassigned `renderer.memory`, but the block kept
      // the item array it was handed when it first appeared, so the check box
      // never filled in.
      //
      // A Binding applies itself when the target appears AND whenever the value
      // changes, which is what a re-read needs. Each reads renderer.memory
      // explicitly so the dependency is unambiguous.
      Binding {
        target: slot.item
        property: "payload"
        value: slot.modelData.payload || ({})
      }

      Binding {
        target: slot.item
        property: "blockId"
        value: slot.modelData.id || ""
      }

      Binding {
        target: slot.item
        property: "blockType"
        value: slot.modelData.type || ""
      }

      Binding {
        target: slot.item
        property: "service"
        value: renderer.service
      }

      Binding {
        target: slot.item
        property: "sideGutter"
        when: slot.modelData.type === "image"
        value: renderer.imageGutter
      }

      Binding {
        target: slot.item
        property: "cursor"
        when: slot.modelData.type === "todos"
        value: slot.modelData.id === renderer.cursorId ? renderer.rowCursor : -1
      }

      Binding {
        target: slot.item
        property: "hasCursor"
        value: renderer.cursorActive && renderer.cursorId.length > 0
               && slot.modelData.id === renderer.cursorId
      }

      Binding {
        target: slot.item
        property: "items"
        when: slot.modelData.type === "todos"
        value: renderer.memory ? renderer.itemsFor(slot.modelData) : []
      }

      Binding {
        target: slot.item
        property: "item"
        when: slot.modelData.type === "event"
        value: renderer.memory
               ? renderer.itemById((slot.modelData.payload || {}).item_id) : null
      }
    }
  }

  Component { id: sourceCard;  SourceBlock {} }
  Component {
    id: imageCard
    ImageBlock {
      onPreviewRequested: function (path) { renderer.previewImage(path) }
    }
  }
  Component { id: noteCard;    NoteBlock {} }
  Component {
    id: summaryCard
    SummaryBlock {
      onEditRequested: renderer.editBlock(blockId, blockType, payload)
    }
  }
  Component {
    id: listCard
    ListBlock {
      onEditRequested: renderer.editBlock(blockId, blockType, payload)
    }
  }
  Component {
    id: textCard
    TextBlock {
      onEditRequested: renderer.editBlock(blockId, blockType, payload)
    }
  }

  Component {
    id: todosCard
    TodosBlock {
      onChanged: renderer.changed()
      onOpenItem: function (item) { renderer.openItem(item) }
      onManageRequested: function (blockId, items) {
          renderer.manageTodos(blockId, items)
        }
    }
  }

  Component {
    id: eventCard
    EventBlock {
      onChanged: renderer.changed()
      onOpenItem: function (item) { renderer.openItem(item) }
    }
  }
}
