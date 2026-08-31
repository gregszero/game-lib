import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Owns every piece of state the panel renders. The heavy lifting happens in
// bin/game-library-index, a standalone script, so the shell only ever parses
// one JSON blob and never blocks on disk or network work itself.
Item {
  id: root

  property var settings: ({})

  // A third-party plugin is not told where it lives, so derive it from this
  // file's own URL. Works the same whether the plugin was cloned into
  // ~/.config/omarchy/plugins or symlinked there from a checkout.
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")

  property var index: ({})
  property bool loading: false
  property bool loadedOnce: false
  property string lastError: ""
  property string actionStatus: ""
  property double lastRefresh: 0

  readonly property var steamGames: Model.steamGames(index)
  readonly property var webGames: Model.webGames(index)
  readonly property var steamInfo: index && index.steam ? index.steam : ({})
  readonly property bool steamAvailable: steamInfo && steamInfo.available === true
  readonly property int installedCount: steamInfo && steamInfo.installedCount ? steamInfo.installedCount : 0
  readonly property int ownedCount: steamInfo && steamInfo.ownedCount ? steamInfo.ownedCount : 0
  readonly property string account: steamInfo && steamInfo.account ? steamInfo.account : ""
  readonly property int totalCount: steamGames.length + (showWeb ? webGames.length : 0)

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 300, 30, 3600)
  readonly property int recentCount: intSetting("recentCount", 5, 0, 15)
  readonly property int itchLimit: intSetting("itchLimit", 24, 0, 60)
  readonly property bool showWeb: setting("showWeb", true) === true
  readonly property bool showCovers: setting("showCovers", true) === true
  readonly property bool includeTools: setting("includeTools", false) === true
  readonly property string steamApiKey: String(setting("steamApiKey", ""))

  readonly property string indexerPath: pluginDir === "" ? "" : pluginDir + "/bin/game-library-index"
  readonly property string launcherPath: pluginDir === "" ? "" : pluginDir + "/bin/game-library-launch"

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    return Math.max(min, Math.min(max, n))
  }

  function refresh(force) {
    if (indexProcess.running || indexerPath === "") return
    loading = true
    var args = [indexerPath, "--itch-limit", String(showWeb ? itchLimit : 0)]
    if (includeTools) args.push("--include-tools")
    if (force) args.push("--refresh-itch")
    if (steamApiKey !== "") args = args.concat(["--api-key", steamApiKey])
    indexProcess.command = args
    indexProcess.running = true
  }

  function launch(entry) {
    if (!entry || launcherPath === "") return
    if (entry.kind === "steam") {
      Quickshell.execDetached([launcherPath, "steam", String(entry.appid)])
      actionStatus = "Launching " + entry.name + "…"
    } else {
      var args = [launcherPath, "web", String(entry.url)]
      if (!entry.webapp) args.push("--tab")
      Quickshell.execDetached(args)
      actionStatus = "Opening " + entry.name + "…"
    }
    statusClear.restart()
  }

  function openSteamClient() {
    if (launcherPath === "") return
    Quickshell.execDetached([launcherPath, "steam-client"])
    actionStatus = "Opening Steam…"
    statusClear.restart()
  }

  function openStorePage(entry) {
    if (!entry || entry.kind !== "steam") return
    Quickshell.execDetached(["omarchy-launch-browser",
                             "https://store.steampowered.com/app/" + entry.appid])
    actionStatus = "Opening store page…"
    statusClear.restart()
  }

  Process {
    id: indexProcess
    running: false
    command: []
    stdout: StdioCollector { id: indexOut; waitForEnd: true }
    stderr: StdioCollector { id: indexErr; waitForEnd: true }
    onExited: function (code) {
      root.loading = false
      var out = String(indexOut.text || "")
      var err = String(indexErr.text || "").trim()
      if (code !== 0 && out.trim() === "") {
        root.lastError = err !== "" ? err.split("\n").pop() : "Indexer exited with status " + code
        return
      }
      var parsed = Model.parseIndex(out)
      if (parsed.ok === false) {
        root.lastError = parsed.error || "Could not read the game index"
        return
      }
      root.index = parsed
      root.loadedOnce = true
      root.lastRefresh = Date.now()
      // Source-level problems (itch.io down, a bad API key) are reported
      // without discarding the parts of the index that did load.
      root.lastError = (parsed.errors instanceof Array && parsed.errors.length > 0)
        ? String(parsed.errors[0])
        : ""
    }
  }

  Timer {
    id: statusClear
    interval: 2500
    onTriggered: root.actionStatus = ""
  }

  Timer {
    interval: Math.max(30, root.refreshIntervalSec) * 1000
    running: root.indexerPath !== ""
    repeat: true
    onTriggered: root.refresh(false)
  }

  onIndexerPathChanged: if (indexerPath !== "") refresh(false)
  // Re-index when a setting that changes what gets indexed is edited.
  onItchLimitChanged: if (loadedOnce) refresh(false)
  onIncludeToolsChanged: if (loadedOnce) refresh(false)
  onSteamApiKeyChanged: if (loadedOnce) refresh(false)
}
