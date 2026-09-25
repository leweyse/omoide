import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// The singleton half of the plugin.
//
// Bar widgets are instantiated once per monitor, so anything that must exist
// exactly once lives here instead: the IPC surface, the timer reconciliation,
// the compose overlay, and the Space window. Widgets reach it through
// bar.shell.serviceFor("leweyse.omoide").
Item {
  id: root

  // Injected by the shell host when the plugin loads.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  // Resolved from this file's own location, not the manifest: since Omarchy
  // 4.0.4 the shell strips `__sourceDir` from third-party manifests, and the
  // fallback to a bare "omoide" on PATH failed silently -- every capture
  // launched nothing. Bar widgets reach the CLI through this property too.
  readonly property string binPath:
    decodeURIComponent(String(Qt.resolvedUrl("bin/omoide")).replace(/^file:\/\//, ""))

  // Matches the CLI: plain XDG paths under our own name. Not .local/share/omarchy,
  // which is a symlink to the read-only package tree, and not .local/state/omarchy,
  // which is Omarchy's own namespace.
  readonly property string dataHome:
    (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share"))
    + "/omoide"
  readonly property string stateHome:
    (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
    + "/omoide"

  // Everything the bar and the Space window render comes from this cache, so
  // no QML code ever opens the database.
  property var index: ({
    version: 0, pendingCount: 0, failedCount: 0, memoryCount: 0, suggestions: [],
    digest: { events: 0, todos: 0 },
    memories: [], events: [], todos: [], collections: []
  })

  readonly property int enrichingCount: (index && index.pendingCount) || 0
  readonly property int failedCount: (index && index.failedCount) || 0
  readonly property int openTodoCount: (index && index.todos ? index.todos.length : 0)

  // Today's business: to-dos due at any point in the current day, plus anything
  // overdue and still open.
  //
  // The bar mark used to light on openTodoCount > 0, which counts what exists
  // rather than what is owed -- a single to-do due in October kept it lit
  // through August and September, so it never changed and never told anyone
  // anything.
  //
  // The whole day rather than a rolling window from now: "is there anything to
  // do today" has one answer from midnight to midnight, so the mark is lit when
  // the day starts instead of switching on partway through the afternoon as a
  // deadline drifts inside some window of the current moment.
  //
  // Overdue counts too. A to-do that slipped past its day is still pending, and
  // a cutoff that only looked forward would quietly drop it at midnight -- the
  // mark going out for the one item most likely to need attention.
  property int dueTodayCount: 0

  function refreshDueToday() {
    var todos = (root.index && root.index.todos) || []
    // The end of the local day: whoever is looking at the bar means their
    // midnight, not UTC's.
    var endOfDay = new Date()
    endOfDay.setHours(23, 59, 59, 999)
    var cutoff = endOfDay.getTime()
    var owed = 0

    for (var i = 0; i < todos.length; i++) {
      var todo = todos[i]
      if (todo.completedAt || todo.status !== "active") continue
      var due = Date.parse(todo.dueAt)
      // No due date is never today's business: that is a task, not a deadline.
      if (isNaN(due) || due > cutoff) continue
      owed++
    }

    root.dueTodayCount = owed
  }

  // No `signal indexChanged()` here: `property var index` already generates
  // one, and declaring it again is a duplicate-signal error at load time.
  signal composeRequested(var payload)
  signal spaceRequested(var payload)

  property Component cliComponent: Cli {}

  function call(args, callback) {
    return cliComponent.createObject(root, {
      command: [root.binPath].concat(args),
      callback: callback || null,
      running: true
    })
  }

  // A second capture while one is in flight cancels the first: the screenshot
  // helper opens with `pkill slurp && exit 0` so that pressing the shortcut
  // twice dismisses the picker. That makes any accidental double-invocation
  // look like "the picker closed on its own", so requests are serialised here.
  property bool capturing: false
  property string pendingMode: ""

  // Fire and forget. Use this for anything that outlives a UI interaction:
  // a tracked Process dies with its QML object, and a plugin reload destroys
  // those. call() is for short reads whose result the caller needs.
  function detach(args) {
    Quickshell.execDetached([root.binPath].concat(args))
  }

  property bool voiceTicket: false

  // Pushed by the bar widget, which owns the setting; the chooser orders its
  // entries by it. "screenshot" when no widget is in the bar to push one.
  property string defaultAction: "screenshot"

  function capture(mode) {
    if (root.capturing) return
    root.capturing = true
    root.pendingMode = mode || "screenshot"
    // One-shot ticket for auto-dictation, consumed by the next compose call.
    // The compose payload arrives over public same-user IPC, so its flags are
    // claims, not facts -- and autoDictate turns the microphone on. Only a
    // voice capture this shell launched itself has the standing to do that.
    root.voiceTicket = root.pendingMode === "voice"
    // The click that chose the action must be fully delivered and the menu
    // surface gone before slurp maps, or the release lands in the picker.
    captureLaunch.restart()
  }

  Timer {
    id: captureLaunch
    interval: 120
    onTriggered: {
      // Detached, NOT a tracked Process. A capture waits on an interactive
      // picker for as long as the user takes, and a tracked child dies with
      // its QML object -- which a plugin reload destroys. That killed the
      // picker mid-selection and left the screen frozen. The CLI reports back
      // over IPC when it is done, so there is nothing to track anyway.
      root.detach(["capture", root.pendingMode])
      captureCooldown.restart()
    }
  }

  // Held after launching, not cleared immediately: the capture is detached so
  // there is no exit to wait for, and a double-click on the bar icon would
  // otherwise fire two pickers. The CLI holds a lock too -- this just avoids
  // spawning a process that only exits again.
  Timer {
    id: captureCooldown
    interval: 1200
    onTriggered: root.capturing = false
  }



  function openSpace(payload) {
    root.showSpace(payload || ({}))
  }

  function refresh() {
    indexFile.reload()
  }

  // Must match INDEX_VERSION in bin/omoide.
  readonly property int indexVersion: 4
  property bool rebuildTried: false

  function applyIndex(text) {
    var parsed = null
    try {
      parsed = JSON.parse(text)
    } catch (e) {
      return
    }
    if (!parsed || typeof parsed !== "object")
      return

    // A plugin update can change the cache's shape. Rebuilding on a version
    // mismatch means an update self-heals instead of rendering a stale cache.
    //
    // Once only. This used to reindex on every mismatch, and since a rebuild
    // rewrites the file with the version the CLI knows, a version the shell did
    // NOT know became an endless loop: reindex, watch fires, mismatch, reindex.
    // Bumping INDEX_VERSION without touching this line was enough to trigger
    // it. Capping it at one attempt means a future skew degrades to a stale
    // cache instead of a hot loop.
    if (parsed.version !== undefined && parsed.version !== root.indexVersion) {
      if (!root.rebuildTried) {
        root.rebuildTried = true
        root.call(["reindex"], null)
        return
      }
      console.warn("omoide: index.json is v" + parsed.version + ", expected v"
                   + root.indexVersion + " -- rendering it anyway")
    }
    root.index = parsed   // emits indexChanged for anything bound to it
  }

  FileView {
    id: indexFile
    path: root.stateHome + "/index.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyIndex(text())
    onFileChanged: reload()
    onLoadFailed: root.index = ({
      version: root.indexVersion, pendingCount: 0, failedCount: 0,
      memoryCount: 0, digest: { events: 0, todos: 0 },
      memories: [], events: [], todos: [], suggestions: [], collections: [],
      alarms: []
    })
  }

  Loader {
    id: composeLoader
    active: false
    source: "surfaces/ComposeOverlay.qml"
    onLoaded: {
      item.service = root
      if (root._pendingCompose) {
        item.begin(root._pendingCompose)
        root._pendingCompose = null
      }
    }
  }

  Loader {
    id: settingsLoader
    active: false
    source: "surfaces/SettingsDialog.qml"
    onLoaded: {
      item.service = root
      item.saved.connect(function () { root.refresh() })
      if (root._pendingSettings) {
        item.open()
        root._pendingSettings = false
      }
    }
  }

  Loader {
    id: spaceWindowLoader
    active: false
    source: "surfaces/SpaceWindow.qml"
    onLoaded: {
      item.service = root
      item.show(root._pendingSpace || ({}))
      root._pendingSpace = null
    }
  }

  // The keybind's chooser is Omarchy's own menu in dmenu mode, so it is the
  // same dialog as every other picker on the system. The selection comes back
  // to this process and goes through capture(), which means the voice ticket
  // and the compose overlay's arming apply exactly as they do from the bar
  // menu. Tracked, not detached: if the plugin reloads mid-wait the waiter
  // dies and the menu is an Esc away from gone, which beats a process that
  // waits forever on a menu that was replaced.
  property var chooserProc: null

  function toggleChooser() {
    if (root.chooserProc) {
      // Second press closes. The menu cancels, the waiter exits empty.
      Quickshell.execDetached(["omarchy-shell", "shell", "hide", "omarchy.menu"])
      return
    }

    var voiceOk = !!(root.index && root.index.voiceAvailable === true)
    var all = [
      { mode: "screenshot", option: "	Screenshot" },
      { mode: "note", option: "	Quick note" },
      { mode: "voice", option: "	Voice note"
                               + (voiceOk ? "" : "	Needs Voxtype dictation") }
    ]
    // Default first, so the keybind plus Enter still runs the mode chosen in
    // the bar menu.
    var entries = all.filter(function (e) { return e.mode === root.defaultAction })
      .concat(all.filter(function (e) { return e.mode !== root.defaultAction }))

    var command = ["omarchy-menu-select", "Omoide"]
    for (var i = 0; i < entries.length; i++) command.push(entries[i].option)

    root.chooserProc = cliComponent.createObject(root, {
      command: command,
      callback: function (code, parsed, err, outText) {
        root.chooserProc = null
        if (code !== 0) return    // cancelled, or the menu was replaced
        var label = String(outText || "").trim().split("\t")[0]
        var mode = ({ "Screenshot": "screenshot",
                      "Quick note": "note",
                      "Voice note": "voice" })[label]
        if (mode) root.capture(mode)
      },
      running: true
    })
  }

  property var _pendingCompose: null
  property var _pendingSpace: null

  function showCompose(payload) {
    if (composeLoader.item) {
      composeLoader.item.begin(payload)
    } else {
      root._pendingCompose = payload
      composeLoader.active = true
    }
  }

  // Independent of the Space dialog: picking a model is not part of browsing
  // memories, so it does not drag Space open behind it.
  function showSettings() {
    if (settingsLoader.item) {
      settingsLoader.item.open()
    } else {
      root._pendingSettings = true
      settingsLoader.active = true
    }
  }

  property bool _pendingSettings: false

  function showSpace(payload) {
    if (spaceWindowLoader.item) {
      spaceWindowLoader.item.show(payload)
    } else {
      root._pendingSpace = payload
      spaceWindowLoader.active = true
    }
  }

  // Startup catch-up: deliver anything that came due while no shell was
  // running, and clear dead drafts. Deliberately late -- the index has to load
  // first, and nothing in it is urgent.
  Timer {
    interval: 2000
    running: true
    repeat: false
    onTriggered: root.call(["sweep"], function () { root.refresh() })
  }

  // The scheduler.
  //
  // No system timer. This service is keepLoaded, so it outlives every window
  // the plugin opens, and a notification needs the session up anyway -- there
  // is nowhere to draw a toast without one. index.json carries the pending
  // alarms and the FileView above watches it, so anything the CLI writes
  // re-arms this within the same tick.
  //
  // The wait is capped even when the next alarm is hours out, and that cap IS
  // the catch-up: a suspended laptop, a clock jump and a CLI that failed to
  // write all resolve on the next tick. None of them send a signal worth
  // waiting on.
  readonly property int alarmTickMs: 60000

  Timer {
    id: alarmTimer
    repeat: false
    onTriggered: root.armAlarms()
  }

  // `index` is a property var, so this is its generated change signal. Every
  // CLI mutation rewrites index.json, which lands here.
  onIndexChanged: root.armAlarms()

  function armAlarms() {
    var alarms = (root.index && root.index.alarms) || []
    var nowMs = Date.now()
    var soonest = -1

    for (var i = 0; i < alarms.length; i++) {
      var at = Date.parse(alarms[i].fireAt)
      if (isNaN(at))
        continue
      var wait = at - nowMs
      if (wait > 0) {
        if (soonest < 0 || wait < soonest)
          soonest = wait
        continue
      }
      // Due. Detached, and the CLI decides whether it is still owed, so a
      // repeated tick or a second shell costs a no-op rather than a second
      // toast. Firing rewrites index.json, which re-arms this from the top.
      root.detach(["reminder", "fire", "--id", alarms[i].id])
    }

    // Rides the alarm tick, which re-runs on every index change and at least
    // once a minute, so the roll-over into a new day lands within a minute of
    // midnight without a timer of its own.
    root.refreshDueToday()

    alarmTimer.interval = soonest < 0 ? root.alarmTickMs
                                      : Math.min(soonest, root.alarmTickMs)
    alarmTimer.restart()
  }

  Component.onCompleted: root.armAlarms()

  IpcHandler {
    target: "omoide"

    // There is deliberately no capture method here. The keybind opens the
    // chooser, and a capture starts only from a click or Enter on a surface
    // the shell drew itself -- IPC opens windows, it does not act.
    function toggleChooser(): string {
      root.toggleChooser()
      return "ok"
    }

    function compose(payloadJson: string): string {
      var payload = ({})
      try {
        payload = JSON.parse(payloadJson || "{}")
      } catch (e) {
        payload = ({})
      }
      // A crafted payload must not start the microphone: autoDictate is
      // honored only on the ticket capture() issued, and the ticket is spent
      // here whether it was used or not. A capture run straight from a
      // terminal opens the overlay with the mic off; its dictate button is
      // one click away.
      if (payload.autoDictate === true && !root.voiceTicket)
        payload.autoDictate = false
      root.voiceTicket = false
      root.showCompose(payload)
      return "ok"
    }

    function openSpace(payloadJson: string): string {
      var payload = ({})
      try {
        payload = JSON.parse(payloadJson || "{}")
      } catch (e) {
        payload = ({})
      }
      root.showSpace(payload)
      return "ok"
    }

    function closeSpace(): string {
      if (spaceWindowLoader.item)
        spaceWindowLoader.item.close()
      return "ok"
    }

    function toggleSpace(payloadJson: string): string {
      if (spaceWindowLoader.item && spaceWindowLoader.item.opened) {
        spaceWindowLoader.item.close()
        return "ok"
      }
      return openSpace(payloadJson)
    }

    function closeCompose(): string {
      if (composeLoader.item)
        composeLoader.item.dismiss()
      return "ok"
    }

    function openSettings(): string {
      root.showSettings()
      return "ok"
    }

    function refresh(): string {
      root.refresh()
      return "ok"
    }

    function state(): string {
      return JSON.stringify({
        memories: root.index.memoryCount || 0,
        enriching: root.enrichingCount,
        failed: root.failedCount,
        todos: root.openTodoCount,
        dueToday: root.dueTodayCount
      })
    }

    function ping(): string {
      return "ok"
    }
  }
}
