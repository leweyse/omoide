import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "components"
import "dialogs"

// One icon. Left-click opens the action menu, right-click opens the library.
//
// No click captures directly. A capture is a destructive-ish, interactive thing
// -- it grabs the pointer for a region pick -- and having that on the primary
// click meant a misclick on the bar started one. The menu names every mode
// instead, so a capture is always chosen rather than triggered.
//
// The icon is a small state machine driven by the service's index cache, so
// every monitor's copy animates together without any broadcast plumbing.
BarWidget {
  id: root

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
                                 ? bar.shell.serviceFor("leweyse.omoide") : null

  readonly property string defaultAction: setting("defaultAction", "screenshot")
  readonly property int enriching: service ? service.enrichingCount : 0
  readonly property int failed: service ? service.failedCount : 0
  readonly property int todos: service ? service.openTodoCount : 0

  readonly property bool capturing: service ? service.capturing : false
  readonly property bool working: enriching > 0
  readonly property bool broken: !working && failed > 0

  // Capturing outranks everything: it is the only state the user is actively
  // waiting on. Then enrichment, then a failure worth noticing.
  readonly property string iconMode: capturing ? "capturing"
                                   : (working ? "working"
                                   : (broken ? "failed" : "idle"))

  implicitWidth: vertical ? barSize : button.implicitWidth
  implicitHeight: button.implicitHeight

  // The chooser lives on the service, the setting lives on this widget: push
  // it across whenever either side appears or the user changes it.
  function pushDefaultAction() {
    if (service) service.defaultAction = root.defaultAction
  }
  onDefaultActionChanged: pushDefaultAction()
  onServiceChanged: pushDefaultAction()
  Component.onCompleted: pushDefaultAction()

  function openMenu() {
    menu.open()
  }

  function openSpace() {
    if (service) service.showSpace({})
  }

  // Persist the default capture mode.
  //
  // Still meaningful with no click bound to it: the keybind's chooser puts
  // this mode first and focused, and `omoide capture` with no mode argument
  // falls back to it.
  //
  // Settings live inline on this widget's entry in shell.json and the shell
  // owns that file, so writing it means handing the whole entry back through
  // updateEntryInline -- the same round trip the built-in clock uses when it
  // cycles its format. Reassigning `settings` is what makes the binding on
  // defaultAction update, so the menu's marker moves immediately.
  function setDefaultAction(action) {
    if (!action || action === root.defaultAction) return

    var entry = { id: root.moduleName }
    for (var key in root.settings) {
      if (key !== "id") entry[key] = root.settings[key]
    }
    entry.defaultAction = action

    root.settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // Panel plumbing: the shell routes `summon` to a bar widget only when it
  // exposes these three.
  function open() { menu.open() }
  function close() { menu.close() }
  readonly property bool opened: menu.opened

  function tooltip() {
    if (root.capturing)
      return "Omoide — pick a region, or press Esc to cancel"
    if (root.working)
      return "Omoide — enriching " + root.enriching + " capture"
           + (root.enriching === 1 ? "" : "s")
    if (root.broken)
      return "Omoide — " + root.failed + " capture"
           + (root.failed === 1 ? "" : "s") + " could not be enriched"
    var parts = []
    if (service && service.index)
      parts.push((service.index.memoryCount || 0) + " memories")
    if (root.todos > 0)
      parts.push(root.todos + " open to-do" + (root.todos === 1 ? "" : "s"))
    return "Omoide" + (parts.length ? " — " + parts.join(", ") : "")
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // A drawn mark rather than a glyph: it carries four states, needs no icon
    // font, and takes its colours from the theme.
    iconComponent: Component {
      SpaceIcon {
        anchors.centerIn: parent
        iconSize: Style.bar.iconCanvas
        color: root.bar ? root.bar.foreground : Color.bar.text
        accentColor: Color.accent
        urgentColor: Color.urgent
        mode: root.iconMode
        marked: root.todos > 0
      }
    }
    active: root.working || root.capturing
    tooltipText: root.tooltip()

    onPressed: function (whichButton) {
      // Middle-click is deliberately unbound: it used to open the library, and
      // a paste-adjacent button doing that by accident is worse than it not
      // working at all.
      if (whichButton === Qt.RightButton)
        root.openSpace()
      else if (whichButton === Qt.LeftButton)
        root.openMenu()
    }
  }

  ActionMenu {
    id: menu
    bar: root.bar
    anchorItem: button
    service: root.service
    defaultAction: root.defaultAction
    onDefaultRequested: function (action) { root.setDefaultAction(action) }
  }
}
