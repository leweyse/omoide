import QtQuick
import qs.Commons
import qs.Ui
import "../blocks" as Blocks

// Upcoming / Past / Anytime / Completed.
//
// Grouping is derived from the item's own due date and completion, never from
// a reminder's state: an alarm that already fired says nothing about whether
// the to-do is done, so overdue items stay in Past until ticked off.
Flickable {
  id: root

  property var service: null
  signal openMemory(string id)
  signal openItem(string id)

  property var groups: ({ suggested: [], upcoming: [], past: [], completed: [] })
  // Which tab is showing. Upcoming, because that is what you came to look at.
  property string tab: "upcoming"

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
    if (!service) return
    service.call(["archive"], function (code, json) {
      if (json) root.groups = json
    })
  }

  Component.onCompleted: reload()

  // The item editor is a separate surface, so a delete or a completion made
  // there has to reach this list somehow. Every mutation rewrites index.json
  // and pings the service, so its index changing is the general "data moved"
  // signal -- no direct wiring between the two surfaces needed.
  Connections {
    target: root.service
    function onIndexChanged() { root.reload() }
  }


  Column {
    id: layout
    x: Style.spacing.panelPadding
    y: 0
    width: root.width - Style.spacing.panelPadding * 2
    spacing: Style.spacing.xxl

    // Buttons, not chips: a chip is a filter you add to a set, a tab is a
    // switch between whole views, and at chip size it read as neither.
    Row {
      width: parent.width
      spacing: Style.spacing.controlGap

      Repeater {
        model: [
          { key: "upcoming",  label: "Upcoming" },
          { key: "past",      label: "Past" },
          { key: "completed", label: "Completed" }
        ]

        delegate: Button {
          required property var modelData
          readonly property int count: {
            var n = (root.groups[modelData.key] || []).length
            // Upcoming shows the suggestions too, so its count includes them
            // or the tab under-reports what it holds.
            if (modelData.key === "upcoming")
              n += (root.groups.suggested || []).length
            return n
          }

          text: modelData.label + (count > 0 ? "   " + count : "")
          selected: root.tab === modelData.key
          foreground: Color.popups.text
          background: Color.popups.background
          accent: Color.accent
          fontFamily: Style.font.resolvedFamily
          onClicked: root.tab = modelData.key
        }
      }
    }

    // One card per tab, no sub-headings. Suggestions come after the accepted
    // tasks in Upcoming rather than in a titled section of their own: a row
    // already reads as a suggestion from its dot and its two buttons, so the
    // heading was saying twice what the rows say once.
    TaskGroup {
      width: parent.width
      rows: root.tab === "upcoming"
            ? (root.groups.upcoming || []).concat(root.groups.suggested || [])
            : (root.groups[root.tab] || [])
      service: root.service
      onChanged: { root.reload(); if (root.service) root.service.refresh() }
      onOpenItem: function (id) { root.openItem(id) }
    }

    Text {
      visible: (root.tab === "upcoming"
                ? (root.groups.upcoming || []).length
                  + (root.groups.suggested || []).length
                : (root.groups[root.tab] || []).length) === 0
      width: parent.width
      text: root.tab === "upcoming" ? "Nothing coming up."
            : (root.tab === "past" ? "Nothing overdue."
                                   : "Nothing completed yet.")
      color: Color.muted
      font.family: Style.font.resolvedFamily
      font.pixelSize: Style.font.body
    }

  }
}
