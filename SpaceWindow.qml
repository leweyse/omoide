import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "MemoryModel.js" as Model
import "views" as Views

// The Space dialog.
//
// A centered layer-shell surface rather than a desktop window: that is the
// idiom every first-party Omarchy surface uses (clipboard, emojis, image
// picker, menu), and it is what gets reliable keyboard focus, Esc handling and
// theme integration. FloatingWindow is only used by the dev-gallery tool, and
// under Hyprland it never mapped here.
//
// The reference is a phone with a bottom pill switching For you / Library. In
// a dialog that becomes a left rail with the same destinations -- the switcher
// moves, the information architecture does not. Destinations stay data-driven,
// so a later Events section is one entry in `sections`.
Item {
  id: root

  property var service: null
  property bool opened: false
  property string section: "foryou"
  property string memoryId: ""
  property string collectionName: ""

  readonly property string pageTitle: {
    if (root.section === "detail") return "Memory"
    if (root.section === "collection") return root.collectionName
    // For you states what is actually on today rather than naming itself.
    if (root.section === "foryou")
      return Model.digestLine(root.service ? root.service.index.digest : null)
    for (var i = 0; i < root.sections.length; i++)
      if (root.sections[i].id === root.section) return root.sections[i].title
    return ""
  }

  // The card's INNER radius: its outer curve less the border the
  // content sits behind. Overlays layered inside it use this so a
  // square scrim cannot paint across the corners.
  readonly property real cardRadius:
    Math.max(0, Style.cornerRadius - Math.max(1, Style.space(2)))

  readonly property var sections: [
    { id: "foryou",  label: "For you", title: "For you",       glyph: "" },
    { id: "library", label: "Library", title: "Library",       glyph: "" },
    { id: "todos",   label: "Tasks",   title: "Tasks",         glyph: "" }
  ]

  function show(payload) {
    var data = payload || ({})
    if (data.section) root.section = data.section
    if (data.id) {
      root.memoryId = data.id
      root.section = "detail"
    } else if (!data.section) {
      root.section = "foryou"
    }
    root.opened = true
    root.restoreFocus()
  }

  function openMemory(id) {
    overflowMenu.close()
    root.memoryId = id
    root.section = "detail"
  }

  // The title as the library knows it. The detail view has its own copy, but
  // the menu is owned by the window and only has the id.
  function memoryTitle(id) {
    var list = (root.service && root.service.index
                && root.service.index.memories) || []
    for (var i = 0; i < list.length; i++)
      if (list[i].id === id) return list[i].title || ""
    return ""
  }

  function openCollection(name) {
    overflowMenu.close()
    root.collectionName = name
    root.section = "collection"
    root.restoreFocus()
  }

  function openItem(id) {
    // Anywhere except the memory itself: if the capture is not already the page
    // behind this sheet, the sheet offers a way to it. Tasks was the case that
    // proved the earlier rule wrong -- you have not come from the memory there,
    // so the link is exactly what you want.
    itemEditor.showMemoryLink = (root.section !== "detail")
    itemEditor.open(id)
  }

  function requestDelete(id) {
    if (!id || !id.length) return
    confirmDelete.targetId = id
    confirmDelete.open()
  }


  function close() {
    root.opened = false
  }

  function goTo(id) {
    root.section = id
    root.restoreFocus()
  }

  // Every overlay in here takes focus onto its own key catcher when it opens,
  // and none of them can hand it back on their own -- they do not know who had
  // it. So the window takes focus back whenever one closes. Without this, using
  // any overlay once left Esc dead for the rest of the session.
  function restoreFocus() {
    Qt.callLater(function () { keys.forceActiveFocus() })
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omoide"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: Color.menu.scrim }

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(1000), panel.width * 0.88)
      height: Math.min(Style.space(720), panel.height * 0.86)
      radius: Style.cornerRadius
      // Opaque on purpose. Omarchy's menu surfaces are translucent, which suits
      // a small command palette but makes a full page of text and thumbnails
      // unreadable over whatever happens to be behind it. The scrim still dims
      // the desktop, so the dialog reads as layered without being see-through.
      color: Qt.rgba(Color.menu.background.r, Color.menu.background.g,
                     Color.menu.background.b, 1.0)
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border,
                                     Math.max(1, Style.space(2)))

      // Swallow clicks so they do not fall through to the dismiss handler.
      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keys
        anchors.fill: parent
        anchors.topMargin: card.borderTop
        anchors.rightMargin: card.borderRight
        anchors.bottomMargin: card.borderBottom
        anchors.leftMargin: card.borderLeft
        focus: true
        Keys.onPressed: function (event) {
          if (event.key === Qt.Key_Escape) {
            // Innermost surface first: the item editor, then back out of a
            // memory, then the dialog itself.
            if (itemEditor.opened) itemEditor.close()
            else if (root.section === "detail"
                     || root.section === "collection") root.section = "library"
            else root.close()
            event.accepted = true
          }
        }

        Rectangle {
          id: rail
          width: Style.space(150)
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          // A tint of the theme's foreground over the card, not the bar's own
          // colour: the rail is part of this surface, so it should read as a
          // quieter region of it rather than a slab of unrelated chrome. It
          // composites because the card behind it is opaque.
          color: Style.normalFill
          // Inside the border, so the inner curve is the card's radius less
          // the border it sits behind.
          topLeftRadius: Math.max(0, Style.cornerRadius - card.borderLeft)
          bottomLeftRadius: Math.max(0, Style.cornerRadius - card.borderLeft)

          // One padding token so the caption, the rows and the footer all line
          // up on the same inset.
          readonly property real pad: Style.spacing.lg

          // Horizontal padding inside the rail's content: the title, the rows
          // and the footer all carry it. One token because they are all 10 --
          // split it again if they ever need to differ.
          readonly property real contentPadX: Style.spacing.xl
          // The footer's TOTAL inset from the rail's edges, not an addition to
          // `pad`: it anchors to the rail itself rather than to the padded
          // Column, so this is the whole distance.
          readonly property real footerPadX: Style.spacing.xl
          // Where a row's label lands once the (currently empty) glyph slot and
          // its gap are accounted for. 4px right of the title.
          readonly property real labelInset: contentPadX + Style.spacing.sm

          // Defines the split now that the fill is subtle.
          Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: Color.menu.border
            opacity: 0.5
          }

          Column {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            // xl to match every view's outer inset, so the rail caption
            // and the page heading share a baseline.
            anchors.topMargin: Style.spacing.panelPadding
            anchors.leftMargin: rail.pad
            anchors.rightMargin: rail.pad
            spacing: Style.spacing.xs

            // The name, at the hero's weight and size but not a PanelHero:
            // with no icon the hero still applies its 14px label inset, which
            // pushed the title 6px right of every row label under it.
            //
            // 10px, the same padding the rows carry. Set explicitly rather than
            // through labelInset, because it is a chosen number here, not a
            // derived one -- change the rows' padding and the title stays put.
            Text {
              width: parent.width
              leftPadding: rail.contentPadX
              rightPadding: rail.contentPadX
              text: "Omoide"
              color: Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Item { width: 1; height: Style.spacing.sm }

            PanelSeparator {
              width: parent.width
              foreground: Color.menu.text
            }

            Item { width: 1; height: Style.spacing.sm }

            Repeater {
              model: root.sections

              delegate: CursorSurface {
                id: railRow
                required property var modelData
                readonly property bool current: root.section === modelData.id
                  || (modelData.id === "library" && root.section === "detail")

                width: rail.width - rail.pad * 2
                height: Style.spacing.popupRowHeight
                radius: Style.space(5)
                hasCursor: railRow.current
                bordered: false
                foreground: Color.menu.text

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.goTo(modelData.id)
                }

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: rail.contentPadX
                  anchors.rightMargin: rail.contentPadX
                  spacing: Style.spacing.sm

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.glyph
                    color: railRow.current ? Color.accent : Color.menu.text
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.body
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.label
                    color: railRow.current ? Color.accent : Color.menu.text
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.body
                  }
                }
              }
            }
          }

          // The mark lives down here with the count it describes. An Item, not
          // a Row, so the icon can be anchored against the text block without
          // anchoring inside a positioner.
          Item {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: rail.footerPadX
            anchors.rightMargin: rail.footerPadX
            anchors.bottomMargin: rail.pad
            height: Math.max(footerMark.height, footerText.implicitHeight)

            SpaceIcon {
              id: footerMark
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              iconSize: Style.font.iconLarge
              color: Color.menu.text
              accentColor: Color.accent
              urgentColor: Color.urgent
              // Same precedence as the bar: it is the same mark, so it must not
              // disagree with it.
              mode: root.service && root.service.enrichingCount > 0
                    ? "working"
                    : (root.service && root.service.failedCount > 0
                       ? "failed" : "idle")
            }

            // Right-aligned against the rail's inset, so the mark and the count
            // sit at the two edges of the footer rather than as one clump.
            Column {
              id: footerText
              anchors.left: footerMark.right
              anchors.leftMargin: Style.spacing.md
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.hairline

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                text: root.service
                      ? (root.service.index.memoryCount || 0) + " memories" : ""
                color: Color.muted
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                visible: root.service && root.service.enrichingCount > 0
                text: "Enriching "
                      + (root.service ? root.service.enrichingCount : 0) + "…"
                color: Color.accent
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        // Its own strip rather than floating in the corner. Anchored over the
        // content it covered whatever reached the top edge full-width -- the
        // search field ended up with a close button sitting inside it.
        Item {
          id: titleBar
          anchors.top: parent.top
          anchors.left: rail.right
          anchors.right: parent.right
          // Tall enough for both, measured independently: the title is inset
          // like the content it heads, the close button sits in the corner.
          // The gap BELOW the title belongs to the view loader, not here: a
          // view's own top inset scrolls away with its content, so relying on
          // it left the title touching whatever had scrolled up to meet it.
          height: Math.max(Style.spacing.panelPadding + pageHeading.implicitHeight,
                           titleBar.chromeInset + closeButton.height)

          // The close button's inset. Deliberately tighter than the content
          // inset so it reads as window chrome rather than as part of the page.
          readonly property real chromeInset: Style.spacing.md

          // Out of the library and into a memory or a collection is the only
          // navigation this dialog has, so it belongs beside the page title
          // rather than inside the page's own content.
          PanelActionButton {
            id: backButton
            visible: root.section === "detail" || root.section === "collection"
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.panelPadding
            anchors.verticalCenter: pageHeading.verticalCenter
            iconText: "←"
            tooltipText: "Back to the library"
            size: Style.space(26)
            foreground: Color.menu.text
            fontFamily: Style.font.resolvedFamily
            onClicked: root.goTo("library")
          }

          // Left inset matches every view's outer inset, so the title lines up
          // with the content beneath it -- unless Back is there, in which case
          // it follows the button.
          Text {
            id: pageHeading
            anchors.left: backButton.visible ? backButton.right : parent.left
            anchors.leftMargin: backButton.visible ? Style.spacing.md
                                                   : Style.spacing.panelPadding
            anchors.top: parent.top
            anchors.topMargin: Style.spacing.panelPadding
            anchors.right: closeButton.left
            anchors.rightMargin: Style.spacing.md
            text: root.pageTitle
            elide: Text.ElideRight
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.heading
          }

          PanelActionButton {
            id: closeButton
            // In the corner, not aligned to the title: equal top and right
            // insets, deliberately tighter than the content inset so it reads
            // as window chrome rather than as part of the page.
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: titleBar.chromeInset
            anchors.rightMargin: titleBar.chromeInset
            iconText: "✕"
            tooltipText: "Close  (Esc)"
            size: Style.space(22)
            foreground: Color.menu.text
            fontFamily: Style.font.menuFamily
            onClicked: root.close()
          }
        }

        ConfirmSheet {
          id: confirmDelete
          anchors.fill: parent
          scrimRadius: root.cardRadius
          z: 50
          property string targetId: ""
          onOpenedChanged: if (!opened) root.restoreFocus()
          message: "Delete this memory? Its note, screenshot and to-dos go with it."
          confirmText: "Delete"

          onCanceled: {
            opened = false
            targetId = ""
          }

          onConfirmed: {
            if (targetId.length && root.service)
              root.service.detach(["delete", "--id", targetId])
            opened = false
            targetId = ""
            // Leaving the memory's own page: it is about to stop existing.
            // The id goes too, so nothing can navigate back onto it.
            if (root.section === "detail") {
              root.memoryId = ""
              root.section = "library"
            }
          }
        }

        OverflowMenu {
          id: overflowMenu
          anchors.fill: parent
          z: 35
          onOpenedChanged: if (!opened) root.restoreFocus()
          onChose: function (action, targetId) {
            if (action === "delete") {
              root.requestDelete(targetId)
            } else if (action === "retitle") {
              renamePrompt.open("Memory title",
                                root.memoryTitle(targetId), "memory:" + targetId)
            } else if (action === "rename") {
              renamePrompt.open("Rename collection", targetId, targetId)
            } else if (action === "remove") {
              confirmRemove.targetId = targetId
              confirmRemove.opened = true
            }
          }
        }

        // Renaming a collection. Its own sheet rather than an inline field: the
        // title sits under a Back button and above a grid, and an editable
        // heading there is easy to open by accident.
        PromptSheet {
          id: renamePrompt
          anchors.fill: parent
          scrimRadius: root.cardRadius
          z: 50
          placeholder: "Collection name"
          onOpenedChanged: if (!opened) root.restoreFocus()
          onCanceled: opened = false
          // Two callers, told apart by a prefix on the target rather than by a
          // second sheet: a collection is keyed by its name, a memory by its id.
          onAccepted: function (value, targetId) {
            if (!root.service || !targetId.length) return
            if (targetId.indexOf("memory:") === 0) {
              root.service.call(["memory", "--id", targetId.slice(7),
                                 "--title", value],
                                function () { root.service.refresh() })
              return
            }
            if (value === targetId) return
            root.service.call(["collection", "rename", "--name", targetId,
                               "--to", value], function () {
              // The page is keyed on the name, so it has to follow the rename
              // or the grid empties out.
              root.collectionName = value
              root.service.refresh()
            })
          }
        }

        // Correcting the agent's own words. It writes through `block set`, which
        // marks the row edited so a later retry cannot silently overwrite it.
        BlockEditor {
          id: blockEditor
          anchors.fill: parent
          z: 50
          scrimRadius: root.cardRadius
          onOpenedChanged: if (!opened) root.restoreFocus()

          function openFor(blockId, blockType, payload) {
            var data = payload || ({})
            if (blockType === "list") {
              blockEditor.open(blockId, blockType, data.heading || "",
                               Model.itemsToLines(data.items || []))
            } else {
              blockEditor.open(blockId, blockType, "", data.text || "")
            }
          }

          onSaved: function (blockId, heading, body) {
            if (!root.service || !blockId.length) return
            var payload = blockEditor.blockType === "list"
                          ? { heading: heading, items: Model.linesToItems(body) }
                          : { text: body.trim() }
            root.service.call(["block", "set", "--id", blockId,
                               "--payload", JSON.stringify(payload)],
                              function () { root.service.refresh() })
          }
        }

        ConfirmSheet {
          id: confirmRemove
          anchors.fill: parent
          scrimRadius: root.cardRadius
          z: 50
          property string targetId: ""
          onOpenedChanged: if (!opened) root.restoreFocus()
          message: "Remove the collection “" + confirmRemove.targetId
                   + "”? The memories in it are kept — only the collection goes."
          confirmText: "Remove"
          onCanceled: { opened = false; targetId = "" }
          onConfirmed: {
            if (targetId.length && root.service)
              root.service.call(["collection", "delete", "--name", targetId],
                                function () { root.service.refresh() })
            opened = false
            targetId = ""
            // Leaving the collection's own page: it is about to stop existing.
            root.collectionName = ""
            root.section = "library"
          }
        }

        ImagePreview {
          id: imagePreview
          anchors.fill: parent
          scrimRadius: root.cardRadius
          z: 45
          onOpenedChanged: if (!opened) root.restoreFocus()
          onEditRequested: if (source.length)
            Quickshell.execDetached(["tensaku-edit", source])
        }

        ItemEditor {
          id: itemEditor
          anchors.fill: parent
          scrimRadius: root.cardRadius
          z: 40
          service: root.service
          onOpenedChanged: if (!opened) root.restoreFocus()
          onChanged: if (root.service) root.service.refresh()
          onOpenMemory: function (id) { root.openMemory(id) }
        }

        Loader {
          id: viewLoader
          anchors.top: titleBar.bottom
          // The WHOLE gap under the page title, not an addition to one. The
          // views used to carry their own top inset as well, which made the
          // space 30px at rest and 12px once scrolled -- too far and then too
          // close. Chrome owns it now, so it is the same either way.
          anchors.topMargin: Style.spacing.panelPadding
          anchors.bottom: parent.bottom
          anchors.left: rail.right
          anchors.right: parent.right

          sourceComponent: {
            switch (root.section) {
            case "library": return libraryView
            case "todos":      return archiveView
            case "detail":     return detailView
            case "collection": return collectionView
            default:        return forYouView
            }
          }
        }
      }
    }
  }

  Component {
    id: forYouView
    Views.ForYouView {
      service: root.service
      onOpenMemory: function (id) { root.openMemory(id) }
      onOpenItem: function (id) { root.openItem(id) }
      onOpenArchive: root.goTo("todos")
    }
  }

  Component {
    id: libraryView
    Views.LibraryView {
      service: root.service
      onOpenMemory: function (id) { root.openMemory(id) }
      onOpenCollection: function (name) { root.openCollection(name) }
    }
  }

  Component {
    id: archiveView
    Views.TodoArchive {
      service: root.service
      onOpenMemory: function (id) { root.openMemory(id) }
      onOpenItem: function (id) { root.openItem(id) }
    }
  }

  Component {
    id: collectionView
    Views.CollectionDetail {
      index: root.service ? root.service.index : ({ memories: [] })
      collectionName: root.collectionName
      onOpenMemory: function (id) { root.openMemory(id) }
      onMenuRequested: function (sceneX, sceneY) {
        overflowMenu.openAt(sceneX, sceneY, root.collectionName, [
          { id: "rename", label: "Edit title", glyph: "󰏫" },
          { id: "remove", label: "Remove",     glyph: "󰩹", destructive: true }
        ])
      }
    }
  }

  Component {
    id: detailView
    Views.MemoryDetail {
      service: root.service
      memoryId: root.memoryId
      onOpenMemory: function (id) { root.openMemory(id) }
      onOpenItem: function (id) { root.openItem(id) }
      onDeleteMemory: function (id) { root.requestDelete(id) }
      onPreviewImage: function (path) { imagePreview.open(path) }
      onEditBlock: function (blockId, blockType, payload) {
        blockEditor.openFor(blockId, blockType, payload)
      }
      onRetryEnrichment: function (id) {
        // Detached: the agent takes seconds and must not block the dialog. The
        // CLI marks the memory pending and pings the shell, so the page shows
        // the working state on its own.
        if (root.service) root.service.detach(["enrich", "--id", id])
      }
      onMenuRequested: function (sceneX, sceneY) {
        overflowMenu.openAt(sceneX, sceneY, root.memoryId, [
          { id: "retitle", label: "Edit title", glyph: "󰏫" },
          { id: "delete",  label: "Delete",     glyph: "󰩹", destructive: true }
        ])
      }
    }
  }
}
