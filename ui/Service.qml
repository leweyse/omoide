import QtQuick
import Quickshell
import Quickshell.Io

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

  // The plugin's root, one up from ui/. Resolved from this file's own location,
  // not the manifest: the host strips `__sourceDir` from a third-party manifest.
  readonly property string pluginDir:
    decodeURIComponent(String(Qt.resolvedUrl("..")).replace(/^file:\/\//, "")).replace(/\/$/, "")

  // The CLI is built into the cache, never the checkout: a file written there
  // blocks `omarchy plugin update`'s fast-forward pull. binPath is a stable
  // symlink to the build for the current source.
  readonly property string cacheHome: xdg("XDG_CACHE_HOME", "/.cache")
  readonly property string binDir: cacheHome + "/omoide/bin"
  readonly property string binPath: binDir + "/omoide"

  // As xdg() in cli/src/paths.c: a variable counts only when it is absolute,
  // so QML and the CLI always agree on where the files are.
  function xdg(name, fallback) {
    var value = Quickshell.env(name) || ""
    return /^\//.test(value) ? value : Quickshell.env("HOME") + fallback
  }

  // Everything the bar and the Space window render comes from this snapshot,
  // pulled from the CLI by refresh(), so no QML code ever opens the database.
  property var index: ({
    version: 0, pendingCount: 0, failedCount: 0, memoryCount: 0, eventCount: 0,
    todoCounts: { upcoming: 0, past: 0, completed: 0, suggested: 0 },
    digest: { events: 0, todos: 0 }, collections: [], alarms: []
  })

  readonly property int enrichingCount: (index && index.pendingCount) || 0
  readonly property int failedCount: (index && index.failedCount) || 0
  // Counted by the CLI over every item, never from a list; the lists
  // themselves are paged by the views that show them.
  readonly property int openTodoCount:
    (index && index.todoCounts ? (index.todoCounts.upcoming || 0) + (index.todoCounts.past || 0) : 0)

  // Lit by what is owed today, not by what exists: open to-dos due before
  // local midnight, overdue included. The CLI counts it when the index is
  // pulled, and the alarm tick pulls again once the local day changes.
  readonly property int dueTodayCount: (index && index.digest && index.digest.todos) || 0
  property string indexDay: ""

  // No `signal indexChanged()` here: `property var index` already generates
  // one, and declaring it again is a duplicate-signal error at load time.
  signal composeRequested(var payload)
  signal spaceRequested(var payload)

  property Component cliComponent: Cli {}

  function call(args, callback) {
    if (!root.cliReady) {
      root.cliQueue.push({ args: args, callback: callback || null, detached: false })
      return
    }
    cliComponent.createObject(root, {
      command: [root.binPath].concat(args),
      callback: callback || null,
      running: true
    })
  }

  // One capture at a time. `capturing` is held until captureCooldown ends,
  // because a detached capture has no exit to wait for.
  property bool capturing: false
  property string pendingMode: ""

  // Fire and forget. Use this for anything that outlives a UI interaction:
  // a tracked Process dies with its QML object, and a plugin reload destroys
  // those. call() is for short reads whose result the caller needs.
  function detach(args) {
    if (!root.cliReady) {
      root.cliQueue.push({ args: args, callback: null, detached: true })
      return
    }
    Quickshell.execDetached([root.binPath].concat(args))
  }

  // --- building the CLI ------------------------------------------------------
  //
  // .agents/docs/reference/cli-build.md describes the design. Every step is an
  // argv, never a shell string. cliSources is everything the binary compiles or
  // embeds; a file embedded from any other path must be added here, or an
  // update that changes only that file keeps running the old build.
  readonly property var cliSources: ["cli", "sql", "manifest.json"]
  property bool cliReady: false
  property var cliQueue: []

  function cliStep(command, callback, workingDirectory) {
    var props = { command: command, callback: callback, running: true }
    if (workingDirectory) props.workingDirectory = workingDirectory
    cliComponent.createObject(root, props)
  }

  function buildCli() {
    var revs = ["git", "-C", root.pluginDir, "rev-parse"]
      .concat(root.cliSources.map(function (p) { return "HEAD:" + p }))
    root.cliStep(revs, function (code, parsed, err, out) {
      if (code !== 0) { root.compileCli("local"); return }
      var id = Qt.md5(out).slice(0, 12)
      var status = ["git", "-C", root.pluginDir, "status", "--porcelain", "--"]
        .concat(root.cliSources)
      root.cliStep(status, function (code2, parsed2, err2, out2) {
        if (code2 !== 0 || String(out2 || "").trim() !== "") {
          root.compileCli("local")
          return
        }
        var target = root.binDir + "/omoide-" + id
        root.cliStep(["test", "-x", target], function (code3) {
          if (code3 === 0) root.linkCli(target)
          else root.compileCli(id)
        })
      })
    })
  }

  // clang is in Omarchy's base package list and pulls in gcc; cc covers a
  // system that has neither under those names.
  readonly property var compilers: ["/usr/bin/clang", "/usr/bin/gcc", "/usr/bin/cc"]

  function compileCli(id, attempt) {
    var i = attempt || 0
    if (i >= root.compilers.length) {
      root.cliBuildFailed("no C compiler found: install clang (omarchy pkg add clang)")
      return
    }
    root.cliStep(["test", "-x", root.compilers[i]], function (found) {
      if (found !== 0) { root.compileCli(id, i + 1); return }
      var target = root.binDir + "/omoide-" + id
      // Built beside the target and renamed into place, so a reload that kills
      // the compiler part-way leaves a stray temp file, never a broken binary.
      var temp = target + ".tmp" + Date.now()
      root.cliStep(["mkdir", "-p", root.binDir], function () {
        var cc = [root.compilers[i], "@build.rsp",
                  "-DOMOIDE_SRC_ID=\"" + id + "\"", "-o", temp]
        root.cliStep(cc, function (code, parsed, err) {
          if (code !== 0) {
            root.cliStep(["rm", "-f", temp], function () {})
            root.cliBuildFailed(err)
            return
          }
          root.cliStep(["mv", "-f", temp, target], function (moved) {
            if (moved !== 0) root.cliBuildFailed("could not install " + target)
            else root.linkCli(target)
          })
        }, root.pluginDir + "/cli")
      })
    })
  }

  function linkCli(target) {
    root.cliStep(["ln", "-sfn", target, root.binPath], function (code, parsed, err) {
      if (code !== 0) { root.cliBuildFailed(err); return }
      // Builds for other sources, and temp files a killed build left behind.
      var name = target.slice(target.lastIndexOf("/") + 1)
      root.cliStep(["find", root.binDir, "-maxdepth", "1", "-name", "omoide-*",
                    "!", "-name", name, "-delete"], function () {})
      root.cliReady = true
      var queued = root.cliQueue
      root.cliQueue = []
      for (var i = 0; i < queued.length; i++) {
        if (queued[i].detached) root.detach(queued[i].args)
        else root.call(queued[i].args, queued[i].callback)
      }
    })
  }

  function cliBuildFailed(message) {
    var text = String(message || "").trim()
    console.warn("omoide: could not build the CLI: " + text)
    Quickshell.execDetached(["omarchy-notification-send", "-u", "critical",
                             "Omoide could not build its helper",
                             text.split("\n")[0].slice(0, 300)])
    // Answer the waiting callers rather than leave them waiting for good.
    var queued = root.cliQueue
    root.cliQueue = []
    for (var i = 0; i < queued.length; i++) {
      if (queued[i].callback) queued[i].callback(127, null, text, "")
    }
  }

  property bool voiceTicket: false

  // Pushed by the bar widget, which owns the setting; the chooser orders its
  // entries by it. "screenshot" when no widget is in the bar to push one.
  property string defaultAction: "screenshot"

  function capture(mode) {
    if (root.capturing) return
    root.capturing = true
    root.pendingMode = mode || "screenshot"
    // One-shot ticket for auto-dictation, spent by the next compose call. The
    // compose payload arrives over same-user IPC, so its flags are claims, and
    // autoDictate turns the microphone on. Only a voice capture this shell
    // launched itself may do that.
    root.voiceTicket = root.pendingMode === "voice"
    // The click that chose the action must be fully delivered and the menu
    // surface gone before slurp maps, or the release lands in the picker.
    captureLaunch.restart()
  }

  Timer {
    id: captureLaunch
    interval: 120
    onTriggered: {
      // Detached, not a tracked Process. A capture waits on an interactive
      // picker for as long as the user takes, and a tracked child dies when a
      // plugin reload destroys its QML object, killing the picker with the
      // screen still frozen. The CLI reports back over IPC.
      root.detach(["capture", root.pendingMode])
      captureCooldown.restart()
    }
  }

  // Held after launching, because a detached capture has no exit to wait for.
  // The CLI's capture lock also refuses a second picker; this saves spawning a
  // process that only exits again.
  Timer {
    id: captureCooldown
    interval: 1200
    onTriggered: root.capturing = false
  }



  function openSpace(payload) {
    root.showSpace(payload || ({}))
  }

  // The index is pulled, never read from disk: `omoide index` prints it, and
  // every CLI command that changes something ends by calling `refresh` over
  // IPC. One pull runs at a time, and a refresh that arrives during it queues
  // exactly one more, so a burst of changes costs two pulls, not one each.
  property bool indexPulling: false
  property bool indexStale: false
  property bool libraryTooNew: false

  function refresh() {
    if (root.indexPulling) {
      root.indexStale = true
      return
    }
    root.indexPulling = true
    root.call(["index"], function (code, parsed) {
      root.indexPulling = false
      // Exit 3 is a library written by a newer build: nothing can be read
      // until the plugin is updated, and the surfaces say so rather than show
      // an empty library. Any other failure keeps the last index.
      if (code === 0) {
        root.libraryTooNew = false
        root.applyIndex(parsed)
      } else if (code === 3) {
        root.libraryTooNew = true
      }
      if (root.indexStale) {
        root.indexStale = false
        root.refresh()
      }
    })
  }

  // Must match INDEX_VERSION in cli/src/omoide.h. The CLI is built from this
  // checkout, so a mismatch means the two were changed apart.
  readonly property int indexVersion: 6

  function applyIndex(parsed) {
    if (!parsed || typeof parsed !== "object")
      return
    if (parsed.version !== root.indexVersion)
      console.warn("omoide: the CLI's index is v" + parsed.version + ", expected v"
                   + root.indexVersion + " -- rendering it anyway")
    root.index = parsed   // emits indexChanged for anything bound to it
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

  // The keybind's chooser is Omarchy's own menu in dmenu mode. The selection
  // comes back here and goes through capture(), so the voice ticket and the
  // compose overlay apply exactly as they do from the bar menu. Tracked, not
  // detached: if the plugin reloads mid-wait the waiter dies and the menu is
  // an Esc away from gone, rather than a process waiting forever on a menu
  // that was replaced.
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
  // running, and clear dead drafts. Deliberately late, because the index loads
  // first and nothing in the sweep is urgent.
  Timer {
    interval: 2000
    running: true
    repeat: false
    onTriggered: root.call(["sweep"], null)   // it signals refresh itself
  }

  // The scheduler; .agents/docs/reference/reminders.md describes the split
  // with the CLI. It relies on this service being keepLoaded.
  //
  // The wait is capped even when the next alarm is hours out, and the cap is
  // the catch-up: a suspend, a clock jump or a CLI that failed to write all
  // resolve on the next tick, and none of them sends a signal to wait on.
  readonly property int alarmTickMs: 60000

  Timer {
    id: alarmTimer
    repeat: false
    onTriggered: root.armAlarms()
  }

  // `index` is a property var, so this is its generated change signal. Every
  // CLI change signals refresh, and the pull that follows lands here.
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
      // toast. Firing signals refresh, and the pull re-arms this from the top.
      root.detach(["reminder", "fire", "--id", alarms[i].id])
    }

    // Rides the alarm tick, which re-runs on every index change and at least
    // once a minute, so the roll-over into a new day lands within a minute of
    // midnight without a timer of its own: a new day pulls a new index, whose
    // counts are for that day.
    var today = new Date().toDateString()
    if (root.indexDay !== today) {
      if (root.indexDay !== "") root.refresh()
      root.indexDay = today
    }

    alarmTimer.interval = soonest < 0 ? root.alarmTickMs
                                      : Math.min(soonest, root.alarmTickMs)
    alarmTimer.restart()
  }

  Component.onCompleted: {
    root.buildCli()
    root.refresh()   // queued until the CLI is ready
    root.armAlarms()
  }

  IpcHandler {
    target: "omoide"

    // No capture method, deliberately: IPC opens windows, it does not act.
    // The keybind opens the chooser, and a capture starts only from a click
    // or Enter on a surface the shell drew itself.
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
