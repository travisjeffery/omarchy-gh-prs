import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// GitHub PRs: your open pull requests and whether their checks pass.
//
// The bar shows a count of PRs with failing checks (or failing and running,
// by setting); the panel lists every open PR, grouped by the org or user that
// owns the repository, with a dot for its checks and a word saying where they
// are. A click opens the PR in the browser.
//
// `bin/gh-prs` does the GitHub side through the user's own `gh` login, so
// nothing here holds a token.
//
// Titles, owners and repository names are whatever someone typed on GitHub,
// so every Text carries `textFormat: Text.PlainText`. Left on the default
// AutoText, Qt decides for itself that a string looks like markup and renders
// it as rich text, and rich text loads `<img src="http://...">`.
//
// Glyphs are \u escapes rather than literal characters, so the source
// survives editors and patches that mangle private-use codepoints.
Panel {
  id: root

  moduleName: "io.github.travisjeffery.gh-prs"
  ipcTarget: "io.github.travisjeffery.gh-prs"

  readonly property string script:
    Qt.resolvedUrl("bin/gh-prs").toString().replace(/^file:\/\//, "")

  // nf-oct-git_pull_request
  readonly property string iconPr: ""
  readonly property string iconDot: ""

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  // Omarchy themes carry no green or yellow, and "passing" and "running" are
  // green and yellow on every CI page there is. Borrowing the accent for
  // either would make the two read alike, which is the one distinction this
  // panel exists to draw, so these are picked rather than themed.
  readonly property color passing: "#5FA46B"
  readonly property color running: "#D7A63A"
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // ------------------------------------------------------------- settings

  // What the badge counts: "failing", "active" (failing and running) or
  // "none". Drafts stay out of it unless asked for: a draft is work you have
  // already said is not ready, and its red check is not news.
  readonly property string badgeMode: {
    var m = String(setting("badge", "failing"))
    return m === "active" || m === "none" ? m : "failing"
  }
  readonly property bool badgeDrafts: setting("badgeDrafts", false) === true
  readonly property int intervalSeconds:
    Math.max(30, Number(setting("interval", 60)) || 60)
  readonly property string query: String(setting("query", ""))

  // ---------------------------------------------------------------- state

  property var payload: null
  property var rows: []
  property bool reachable: true
  property string errorText: ""
  property bool loading: false
  property int cursor: -1

  readonly property int badgeCount: {
    if (!payload || badgeMode === "none") return 0
    var b = payload.badge || {}
    var n = b.failing || 0
    if (badgeDrafts) n += b.failingDrafts || 0
    if (badgeMode === "active") {
      n += b.running || 0
      if (badgeDrafts) n += b.runningDrafts || 0
    }
    return n
  }
  readonly property bool badgeAlarm: {
    if (!payload) return false
    var b = payload.badge || {}
    return (b.failing || 0) + (badgeDrafts ? (b.failingDrafts || 0) : 0) > 0
  }

  // See the herdr widget this one is modelled on: the bar hands a Panel zero
  // width unless it is computed here, from content, never from a child.
  readonly property int badgeWidth: badgeCount > 0
    ? Math.max(Style.space(12), String(badgeCount).length * Style.space(6) + Style.space(8))
    : 0
  readonly property int barContentWidth: Style.bar.iconFont + badgeWidth + Style.space(5)
  readonly property int barSlot: barContentWidth + Style.space(10)

  readonly property real openPanelIndicatorWidth: barContentWidth
  readonly property real openPanelIndicatorHeight: barContentWidth
  implicitWidth: bar && bar.vertical ? (bar ? bar.barSize : Style.bar.sizeHorizontal) : barSlot
  implicitHeight: bar && bar.vertical ? barSlot : (bar ? bar.barSize : Style.bar.sizeHorizontal)

  // --------------------------------------------------------------- helpers

  // Only a PR page on some GitHub host is ever handed to xdg-open. The URL
  // came from GitHub, but it still leaves this process as an argument.
  function validUrl(url) {
    return /^https:\/\/[A-Za-z0-9.-]+\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\/pull\/[0-9]+$/.test(String(url))
  }

  function plain(s) {
    return String(s || "").replace(/[<>]/g, "")
  }

  function refresh() {
    if (listProc.running) return
    loading = true
    listProc.command = [root.script, "list", root.query]
    listProc.running = true
  }

  function openPr(pr) {
    if (!pr || !validUrl(pr.url)) return
    Util.execArgv(["xdg-open", pr.url])
    close()
  }

  // Owner headings and PR rows in one flat list, so one ListView scrolls the
  // lot and the cursor can step over the headings.
  function flatten(groups) {
    var out = []
    for (var i = 0; i < groups.length; i++) {
      var g = groups[i]
      out.push({ kind: "owner", owner: g.owner, count: g.prs.length, failing: g.failing })
      for (var j = 0; j < g.prs.length; j++) {
        var pr = g.prs[j]
        pr.kind = "pr"
        out.push(pr)
      }
    }
    return out
  }

  function isPr(i) {
    return i >= 0 && i < rows.length && rows[i].kind === "pr"
  }

  function moveCursor(delta) {
    var next = cursor
    for (var step = 0; step < rows.length; step++) {
      next += delta
      if (next < 0 || next >= rows.length) return
      if (isPr(next)) break
    }
    if (!isPr(next)) return
    cursor = next
    list.positionViewAtIndex(next, ListView.Contain)
  }

  function activateCursor() {
    if (isPr(cursor)) openPr(rows[cursor])
  }

  function stateColor(pr) {
    if (!pr) return root.foreground
    if (pr.state === "failing") return root.urgent
    if (pr.state === "running") return root.running
    if (pr.state === "passing") return root.passing
    return Qt.darker(root.foreground, 1.9)
  }

  function reviewColor(review) {
    if (review === "approved") return root.passing
    if (review === "changes requested") return root.urgent
    return Qt.darker(root.foreground, 1.9)
  }

  function subtitleFor(pr) {
    if (!pr) return ""
    var s = pr.repo + " #" + pr.number
    if (pr.draft) s += "  ·  draft"
    return s
  }

  function ago(seconds) {
    if (seconds < 90) return "just now"
    var m = Math.round(seconds / 60)
    if (m < 90) return m + " min ago"
    return Math.round(m / 60) + " h ago"
  }

  function titleText() {
    if (!payload) return "Pull requests"
    var parts = [payload.total + " open"]
    if (payload.failing > 0) parts.push(payload.failing + " failing")
    if (payload.running > 0) parts.push(payload.running + " running")
    return "Pull requests (" + parts.join(", ") + ")"
  }

  function tooltipText() {
    if (!payload) return reachable ? "GitHub PRs: loading" : "GitHub PRs: " + errorText
    var parts = [payload.total + (payload.total === 1 ? " open PR" : " open PRs")]
    if (payload.failing > 0) parts.push(payload.failing + " failing")
    if (payload.running > 0) parts.push(payload.running + " running")
    if (!reachable) parts.push("stale: " + errorText)
    return parts.join(", ")
  }

  // A failed refresh keeps the last good list on screen: a dropped Wi-Fi
  // connection is not a reason to forget forty PRs. The error says why it is
  // stale and how stale.
  function applyPayload(text) {
    loading = false
    try {
      var data = JSON.parse(text)
      reachable = data.ok === true
      errorText = data.error || ""
      if (!reachable) return
      payload = data
      rows = flatten(data.groups || [])
      if (!isPr(cursor)) cursor = -1
    } catch (e) {
      reachable = false
      errorText = "unexpected output from gh-prs"
    }
  }

  function errorLine() {
    var s = errorText !== "" ? errorText : "Could not reach GitHub."
    if (payload && payload.fetchedAt)
      s += "  ·  from " + ago(Date.now() / 1000 - payload.fetchedAt)
    return s
  }

  // Opening the panel refreshes it, unless the list is only seconds old: a
  // refresh takes several seconds with a hundred PRs, and the one the timer
  // just finished is as good as the one this would start.
  onOpenedChanged: {
    if (opened && !(payload && Date.now() / 1000 - payload.fetchedAt < 15)) refresh()
    else cursor = -1
  }

  Process {
    id: listProc
    stdout: StdioCollector {
      onStreamFinished: root.applyPayload(text)
    }
  }

  Timer {
    interval: root.intervalSeconds * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    opacity: root.reachable ? 1 : 0.5
    slotSize: root.barSlot
    opticalSize: root.barContentWidth
    tooltipText: root.plain(root.tooltipText())

    iconComponent: Component {
      Item {
        Row {
          anchors.centerIn: parent
          spacing: Style.space(5)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.iconPr
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: Style.bar.iconFont
            renderType: Text.NativeRendering
            color: root.opened ? root.accent : root.foreground
          }

          // Red when anything counted is failing, the running colour when
          // the count is only checks still going.
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.badgeCount > 0
            height: Style.space(12)
            width: root.badgeWidth
            radius: height / 2
            color: root.badgeAlarm ? root.urgent : root.running

            Text {
              anchors.centerIn: parent
              text: root.badgeCount
              textFormat: Text.PlainText
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              renderType: Text.NativeRendering
              color: Color.background
            }
          }
        }
      }
    }

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(480))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveCursor(dy) }
      onActivateRequested: root.activateCursor()
      onTextKey: function(t) {
        if (t === "o") root.activateCursor()
        else if (t === "r") root.refresh()
      }

      Column {
        id: content
        anchors.fill: parent
        spacing: Style.space(6)

        // ------------------------------------------------------- header

        PanelSectionHeader {
          width: parent.width
          text: root.titleText() + (root.loading ? "  …" : "")
          textFormat: Text.PlainText
          elide: Text.ElideRight
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        PanelSeparator { width: parent.width }

        Item {
          width: parent.width
          height: root.reachable ? 0 : staleWarning.implicitHeight + Style.space(6)
          visible: !root.reachable

          Text {
            id: staleWarning
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            text: root.errorLine()
            textFormat: Text.PlainText
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            color: root.urgent
          }
        }

        // --------------------------------------------------------- list

        ListView {
          id: list
          width: parent.width
          visible: root.rows.length > 0
          clip: true
          model: root.rows
          spacing: Style.space(1)
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          readonly property int cap: {
            var chrome = Style.space(80)
            if (!root.reachable) chrome += Style.space(24)
            return Math.max(Style.space(140),
                            panel.availableCardHeight - panel.verticalContentInset - chrome)
          }
          height: Math.min(contentHeight, cap)

          delegate: Item {
            id: row
            required property var modelData
            required property int index

            readonly property bool isOwner: modelData.kind === "owner"
            readonly property bool active: !isOwner
              && (root.cursor === row.index || rowMouse.containsMouse)

            width: list.width - (list.interactive ? Style.space(10) : 0)
            height: isOwner
              ? ownerLabel.implicitHeight + Style.space(row.index === 0 ? 4 : 10)
              : prContent.implicitHeight + Style.space(10)

            // Owner heading: the org or user, and how many PRs sit under it.
            Text {
              id: ownerLabel
              visible: row.isOwner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.leftMargin: Style.space(6)
              text: row.isOwner ? row.modelData.owner + "  ·  " + row.modelData.count : ""
              textFormat: Text.PlainText
              elide: Text.ElideRight
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              color: Qt.darker(root.foreground, 1.5)
            }

            Rectangle {
              visible: !row.isOwner
              anchors.fill: parent
              radius: Style.cornerRadius
              color: row.active
                ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                : "transparent"

              Behavior on color { ColorAnimation { duration: 80 } }
            }

            MouseArea {
              id: rowMouse
              enabled: !row.isOwner
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onContainsMouseChanged: if (containsMouse) root.cursor = row.index
              onClicked: root.openPr(row.modelData)
            }

            // A draft is drawn at reduced strength throughout: it is yours,
            // it is open, and you have already said it is not ready.
            Row {
              id: prContent
              visible: !row.isOwner
              opacity: row.modelData.draft ? 0.5 : 1
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              spacing: Style.space(7)

              Item {
                width: Style.space(14)
                height: Style.space(14)
                anchors.top: parent.top
                anchors.topMargin: Style.space(1)

                Text {
                  anchors.centerIn: parent
                  text: root.iconDot
                  textFormat: Text.PlainText
                  font.family: root.fontFamily
                  font.pixelSize: Style.space(7)
                  color: root.stateColor(row.modelData)
                }
              }

              Column {
                width: parent.width - Style.space(14) - prContent.spacing
                spacing: Style.space(2)

                Item {
                  width: parent.width
                  height: title.implicitHeight

                  Text {
                    id: title
                    anchors.left: parent.left
                    anchors.right: status.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.isOwner ? "" : row.modelData.title
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    color: row.active ? root.foreground : Qt.darker(root.foreground, 1.15)
                  }

                  Text {
                    id: status
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.isOwner ? "" : row.modelData.label
                    textFormat: Text.PlainText
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: row.modelData.state === "failing"
                    color: row.modelData.state === "none"
                      ? Qt.darker(root.foreground, 1.9)
                      : root.stateColor(row.modelData)
                  }
                }

                Item {
                  width: parent.width
                  height: subtitle.implicitHeight

                  Text {
                    id: subtitle
                    anchors.left: parent.left
                    anchors.right: review.left
                    anchors.rightMargin: Style.space(8)
                    text: row.isOwner ? "" : root.subtitleFor(row.modelData)
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    color: Qt.darker(root.foreground, 1.9)
                  }

                  Text {
                    id: review
                    anchors.right: parent.right
                    text: row.isOwner ? "" : (row.modelData.review || "")
                    textFormat: Text.PlainText
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    color: root.reviewColor(row.modelData.review)
                  }
                }
              }
            }
          }
        }

        // -------------------------------------------------------- empty

        Item {
          width: parent.width
          height: root.rows.length === 0 && root.reachable
            ? empty.implicitHeight + Style.space(16) : 0
          visible: height > 0

          Text {
            id: empty
            anchors.centerIn: parent
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.payload ? "No open pull requests" : "Loading…"
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            color: Qt.darker(root.foreground, 1.8)
          }
        }
      }
    }
  }
}
