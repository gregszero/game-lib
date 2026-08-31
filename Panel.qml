import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: panelRoot
  moduleName: "greg.game-lib"
  ipcTarget: "game-lib"
  manageIpc: false

  // The rendered list is one flat array of {header} and {entry} rows so the
  // keyboard cursor only ever has to walk a single index.
  property string query: ""
  property int selectedIndex: -1
  property bool cursorActive: false

  readonly property var rows: Model.buildRows(library.index, {
    query: panelRoot.query,
    showWeb: library.showWeb,
    recentCount: library.recentCount
  })
  readonly property var selectedEntry: (selectedIndex >= 0 && selectedIndex < rows.length && rows[selectedIndex].entry)
    ? rows[selectedIndex].entry : null

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color barIconColor: library.steamAvailable ? barForeground : Qt.darker(barForeground, 1.55)

  readonly property string heroMeta: {
    if (library.loading && !library.loadedOnce) return "Indexing…"
    if (!library.steamAvailable && library.totalCount === 0) return "No games found"
    var parts = []
    if (library.steamAvailable) parts.push(library.ownedCount + " Steam")
    if (library.showWeb && library.webGames.length > 0) parts.push(library.webGames.length + " web")
    return parts.join(" · ")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function resetCursor() {
    selectedIndex = Model.firstSelectableIndex(rows)
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    if (dy === 0) return
    if (selectedIndex < 0) { resetCursor(); return }
    selectedIndex = Model.nextSelectableIndex(rows, selectedIndex, dy > 0 ? 1 : -1)
    scrollCursorIntoView()
  }

  function setCursor(index) {
    cursorActive = true
    selectedIndex = index
  }

  function activateCursor() {
    if (selectedEntry) {
      library.launch(selectedEntry)
      panelRoot.close()
    }
  }

  function scrollCursorIntoView() {
    if (!listView) return
    listView.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  onQueryChanged: {
    resetCursor()
    // Enter launches the top hit, so while filtering the cursor must be
    // visible -- otherwise the panel fires at a row nothing points to.
    cursorActive = query !== ""
    if (listView) listView.positionViewAtBeginning()
  }

  onOpenedChanged: if (opened) {
    searchField.text = ""
    query = ""
    cursorActive = false
    resetCursor()
    // The index is cheap and mostly local; a stale panel is worse than a
    // 200ms refresh, so re-read whenever it is opened.
    library.refresh(false)
  }

  Service {
    id: library
    settings: panelRoot.settings
  }

  IpcHandler {
    target: panelRoot.ipcTarget
    function open(): void { panelRoot.open() }
    function close(): void { panelRoot.close() }
    function show(): void { panelRoot.open() }
    function hide(): void { panelRoot.close() }
    function toggle(): void { panelRoot.toggle() }
    function refresh(): string { library.refresh(true); return "ok" }
    function count(): string { return String(library.totalCount) }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: panelRoot.bar
    iconComponent: Component {
      Item {
        Text {
          anchors.centerIn: parent
          text: "󰊴"
          color: panelRoot.barIconColor
          font.family: panelRoot.fontFamily
          font.pixelSize: Style.font.icon
        }
      }
    }
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.RightButton) library.openSteamClient()
      else if (buttonCode === Qt.MiddleButton) library.refresh(true)
      else panelRoot.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: panelRoot
    bar: panelRoot.bar
    open: panelRoot.opened
    focusTarget: searchField
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(layout.implicitHeight, Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // The search field owns every printable key; only navigation keys are
      // intercepted here, so typing filters instead of triggering shortcuts.
      blocked: searchField.activeFocus
      onMoveRequested: function (dx, dy) { panelRoot.moveCursor(dx, dy) }
      onActivateRequested: panelRoot.activateCursor()
      onCloseRequested: panelRoot.close()
      onTabRequested: function (direction) { panelRoot.switchPanel(direction) }

      ColumnLayout {
        id: layout
        anchors.fill: parent
        spacing: Style.space(10)

        PanelHero {
          Layout.fillWidth: true
          title: "Games"
          meta: panelRoot.heroMeta
          foreground: panelRoot.foreground
          fontFamily: panelRoot.fontFamily
          iconComponent: Component {
            Text {
              text: "󰊴"
              color: panelRoot.foreground
              font.family: panelRoot.fontFamily
              font.pixelSize: Style.font.display
            }
          }
          trailingControl: Component {
            PanelActionButton {
              iconText: library.loading ? "󰑓" : "󰑐"
              foreground: panelRoot.foreground
              fontFamily: panelRoot.fontFamily
              enabled: !library.loading
              onClicked: library.refresh(true)
            }
          }
        }

        TextField {
          id: searchField
          Layout.fillWidth: true
          placeholderText: "Search your library…"
          foreground: panelRoot.foreground
          onTextChanged: panelRoot.query = text
          // Arrow keys and Enter belong to the list even while typing.
          Keys.onDownPressed: function (event) { panelRoot.moveCursor(0, 1); event.accepted = true }
          Keys.onUpPressed: function (event) { panelRoot.moveCursor(0, -1); event.accepted = true }
          Keys.onEscapePressed: function (event) {
            if (panelRoot.query !== "") { panelRoot.query = ""; text = "" }
            else panelRoot.close()
            event.accepted = true
          }
          Keys.onTabPressed: function (event) { panelRoot.switchPanel(1); event.accepted = true }
          Keys.onBacktabPressed: function (event) { panelRoot.switchPanel(-1); event.accepted = true }
          onAccepted: panelRoot.activateCursor()
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          visible: text !== ""
          text: library.actionStatus !== "" ? library.actionStatus : library.lastError
          color: library.actionStatus === "" && library.lastError !== "" ? panelRoot.urgent : panelRoot.dim
          font.family: panelRoot.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          visible: panelRoot.rows.length === 0
          text: library.loading && !library.loadedOnce
            ? "Reading your library…"
            : (panelRoot.query !== "" ? "Nothing matches “" + panelRoot.query + "”" : "No games found.")
          color: panelRoot.dim
          font.family: panelRoot.fontFamily
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
          topPadding: Style.space(16)
          bottomPadding: Style.space(16)
        }

        ListView {
          id: listView
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.preferredHeight: Math.min(contentHeight, Style.space(520))
          visible: panelRoot.rows.length > 0
          model: panelRoot.rows
          clip: true
          spacing: Style.space(2)
          boundsBehavior: Flickable.StopAtBounds
          cacheBuffer: Style.space(400)
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          // ListView reuses delegates, so onLoaded alone would leave a recycled
          // row showing whatever it held before the filter changed. Push the
          // data on every change, not just on first load.
          delegate: Loader {
            id: rowLoader
            required property var modelData
            required property int index
            width: listView.width
            sourceComponent: modelData.header !== undefined ? headerRow : gameRow

            function syncRow() {
              if (!item) return
              item.rowData = rowLoader.modelData
              item.rowIndex = rowLoader.index
            }

            onLoaded: syncRow()
            onModelDataChanged: syncRow()
            onIndexChanged: syncRow()
          }
        }
      }
    }
  }

  Component {
    id: headerRow

    Item {
      property var rowData: null
      property int rowIndex: 0
      implicitHeight: header.implicitHeight + Style.space(10)

      PanelSectionHeader {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        text: rowData && rowData.count
          ? rowData.header + "  " + rowData.count
          : (rowData ? rowData.header : "")
        foreground: panelRoot.foreground
        fontFamily: panelRoot.fontFamily
      }
    }
  }

  Component {
    id: gameRow

    CursorSurface {
      id: surface
      property var rowData: null
      property int rowIndex: 0
      readonly property var entry: rowData ? rowData.entry : null
      readonly property string coverSource: Model.coverSource(entry, library.showCovers)

      hasCursor: panelRoot.cursorActive && panelRoot.selectedIndex === rowIndex
      foreground: panelRoot.foreground
      implicitHeight: Math.max(rowContent.implicitHeight + Style.spacing.rowPaddingX,
                               library.showCovers ? Style.space(38) : 0)

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onEntered: panelRoot.setCursor(surface.rowIndex)
        onClicked: function (mouse) {
          if (mouse.button === Qt.RightButton) library.openStorePage(surface.entry)
          else { library.launch(surface.entry); panelRoot.close() }
        }
      }

      RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        spacing: Style.space(9)

        // Cover art when we have it, a glyph when we don't. Both occupy the
        // same width so titles stay on one vertical line down the list.
        Item {
          Layout.alignment: Qt.AlignVCenter
          implicitWidth: library.showCovers ? Style.space(22) : Style.space(16)
          implicitHeight: library.showCovers ? Style.space(30) : Style.space(16)

          Image {
            id: cover
            anchors.fill: parent
            visible: library.showCovers && status === Image.Ready
            source: surface.coverSource
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            sourceSize.width: Style.space(44)
            smooth: true
          }

          Text {
            anchors.centerIn: parent
            visible: !cover.visible
            text: Model.glyph(surface.entry)
            color: surface.entry && surface.entry.installed === false ? panelRoot.dim : panelRoot.foreground
            font.family: panelRoot.fontFamily
            font.pixelSize: Style.font.icon
          }
        }

        ColumnLayout {
          id: rowContent
          Layout.fillWidth: true
          spacing: Style.space(1)

          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: surface.entry ? surface.entry.name : ""
            color: panelRoot.foreground
            font.family: panelRoot.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            visible: text !== ""
            text: Model.subtitle(surface.entry)
            color: panelRoot.dim
            font.family: panelRoot.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        // A quiet marker for the two states worth calling out at a glance.
        Text {
          textFormat: Text.PlainText
          Layout.alignment: Qt.AlignVCenter
          visible: text !== ""
          text: {
            if (!surface.entry) return ""
            if (surface.entry.kind === "web") return "󰖟"
            return surface.entry.installed ? "" : "󰇚"
          }
          color: panelRoot.dim
          font.family: panelRoot.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
