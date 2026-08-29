import "Model.js" as Model
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Omaspeedmeter bar widget: CPU / memory / network / temperature / GPU /
// process-count stats in the bar row, with a click popup to toggle each
// metric and tweak the underlying settings (refresh interval, GPU vendor,
// temperature source, network interface).
Panel {
    id: root

    // Omarchy's own bar widgets (WidgetButton) each carry an 8.5px scaled
    // horizontal margin either side; with zero spacing between modules in
    // the bar row, two adjacent widgets end up 17px apart. Using that same
    // raw value here (then run through Style.space() below, same as a
    // user-entered gap) reproduces that spacing and keeps it theme-scaled.
    readonly property var resolved: Model.resolvedSettings(root.settings, {
        "gap": 17
    })
    property var stats: null
    readonly property var segments: Model.buildSegments(root.settings, root.stats)
    // Model.METRICS re-ordered to match the persisted `order` setting, for
    // the popup's METRICS list — kept in sync with root.resolved.order so
    // the move-up/move-down buttons there always reflect the saved order.
    readonly property var orderedMetrics: root.resolved.order.map(function (key) {
        for (var i = 0; i < Model.METRICS.length; i++)
            if (Model.METRICS[i].key === key)
                return Model.METRICS[i];
        return null;
    }).filter(function (m) {
        return m !== null;
    })
    property string currentSection: ""
    property var netIfaceOptions: [
        {
            "value": "auto",
            "label": "auto"
        }
    ]
    property var tempZoneOptions: [
        {
            "value": "auto",
            "label": "auto"
        }
    ]
    // The plugin's own directory, so the polling script can be found no
    // matter where this plugin checkout/symlink lives.
    readonly property string pluginDir: {
        var u = Qt.resolvedUrl(".").toString();
        return u.indexOf("file://") === 0 ? u.substring(7) : u;
    }
    // Hand-editable mirror of the settings above, kept in sync both ways:
    // popup changes get written out here, and external edits get relayed
    // through setSetting()/setSection() (see writeConfigFile/
    // reconcileConfigFile below).
    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omaspeedmeter"
    readonly property string configPath: root.configDir + "/config.json"
    // Text we last wrote to (or reconciled from) config.json, so our own
    // setText() triggering onFileChanged doesn't bounce back into another
    // round of reconciliation.
    property string lastSyncedConfigText: ""

    // Merges a single metric script's JSON output into root.stats, creating
    // the object on first arrival. Reassigns (rather than mutates) so the
    // `segments` binding above picks up the change.
    function mergeStats(patch) {
        var merged = {};
        for (var k in root.stats)
            merged[k] = root.stats[k];
        for (var k2 in patch)
            merged[k2] = patch[k2];
        root.stats = merged;
    }

    function refresh() {
        if (root.resolved.cpu && !cpuProc.running)
            cpuProc.running = true;

        if (root.resolved.mem && !memProc.running)
            memProc.running = true;

        if (root.resolved.swap && !swapProc.running)
            swapProc.running = true;

        if (root.resolved.net && !netProc.running)
            netProc.running = true;

        if (root.resolved.temp && !tempProc.running)
            tempProc.running = true;

        if (root.resolved.gpu && !gpuProc.running)
            gpuProc.running = true;

        if (root.resolved.procs && !procsProc.running)
            procsProc.running = true;
    }

    // Queued rather than fired directly at setSettingProc: resetSettings()
    // below calls this once per setting in the same tick, and reassigning
    // `command`/`running` on an already-running Process drops everything
    // but the first call, since `running = true` is a no-op when it's
    // already true.
    property var settingQueue: []

    function setSetting(key, value, isJson) {
        var args = ["bar", "set", root.moduleName, key, String(value)];
        if (isJson)
            args.push("--json");

        root.settingQueue.push(["omarchy"].concat(args));
        root.pumpSettingQueue();
    }

    function pumpSettingQueue() {
        if (setSettingProc.running || root.settingQueue.length === 0)
            return;

        setSettingProc.command = root.settingQueue.shift();
        setSettingProc.running = true;
    }

    function toggleMetric(key) {
        root.setSetting(key, !root.resolved[key], true);
    }

    // Swaps `key` with its neighbor one step toward `direction` (-1 = up,
    // +1 = down) in the metric order and persists the result. Operates on
    // the full metric list (root.resolved.order), not just enabled ones, so
    // the popup's METRICS list stays reorderable regardless of what's shown.
    function moveMetric(key, direction) {
        var order = root.resolved.order.slice();
        var from = order.indexOf(key);
        var to = from + direction;
        if (from === -1 || to < 0 || to >= order.length)
            return;

        var tmp = order[to];
        order[to] = order[from];
        order[from] = tmp;

        root.setSetting("order", order.join(","), false);
    }

    // Restores every setting (toggles, netSplit, labels, interval, gap,
    // gpuVendor, netIface, tempZone, segment order) to its manifest default.
    function resetSettings() {
        var defaults = Model.defaultSettings();
        for (var key in defaults) {
            var value = defaults[key];
            if (key === "order")
                root.setSetting(key, value.join(","), false);
            else if (typeof value === "boolean" || typeof value === "number")
                root.setSetting(key, value, true);
            else
                root.setSetting(key, value, false);
        }
    }

    // Opens the configured system monitor (btop/htop) in a floating
    // terminal, or focuses it if already running.
    function launchSystemMonitor() {
        if (!root.bar)
            return;

        const whitelist = ["btop", "htop"];
        const monitor = String(root.resolved.systemMonitor || "btop").trim();
        if (whitelist.indexOf(monitor) === -1)
            return;

        root.bar.run("omarchy-launch-or-focus-tui " + monitor);
    }

    function refreshSection() {
        if (!sectionProc.running)
            sectionProc.running = true;
    }

    function setSection(section) {
        root.currentSection = section;
        moveSectionProc.command = ["omarchy", "bar", "move", root.moduleName, "--section", section];
        moveSectionProc.running = true;
    }

    // Serializes the current settings + bar section to config.json.
    // Triggered (debounced) by onResolvedChanged/onCurrentSectionChanged,
    // so it fires for both popup-driven changes and changes relayed here
    // from an external config.json edit — no call site elsewhere needs to
    // know this file exists.
    function writeConfigFile() {
        var defaults = Model.defaultSettings();
        var payload = {};
        for (var key in defaults)
            payload[key] = root.resolved[key];
        payload.section = root.currentSection;

        var text = JSON.stringify(payload, null, 4) + "\n";
        if (text === root.lastSyncedConfigText)
            return;

        root.lastSyncedConfigText = text;
        configFile.setText(text);
    }

    // Applies an externally-edited config.json to the live settings by
    // replaying each differing key through the same setSetting()/
    // setSection() path a popup click would use, so omarchy bar set (and
    // therefore Omarchy's own shell.json) stays in sync too.
    function applyConfigFromFile(parsed) {
        if (!parsed)
            return;

        var defaults = Model.defaultSettings();
        var validKeys = Model.METRICS.map(function (m) {
            return m.key;
        });

        for (var key in defaults) {
            if (!(key in parsed))
                continue;

            var value = parsed[key];
            if (key === "order") {
                if (!Array.isArray(value))
                    continue;
                var sanitized = Model.sanitizeOrder(value, validKeys);
                if (sanitized.join(",") !== root.resolved.order.join(","))
                    root.setSetting("order", sanitized.join(","), false);
            } else if (value !== root.resolved[key]) {
                var isJson = typeof defaults[key] === "boolean" || typeof defaults[key] === "number";
                root.setSetting(key, value, isJson);
            }
        }

        if (typeof parsed.section === "string" && parsed.section !== root.currentSection && ["left", "center", "right"].indexOf(parsed.section) !== -1)
            root.setSection(parsed.section);
    }

    function reconcileConfigFile(text) {
        if (text === root.lastSyncedConfigText)
            return;

        root.lastSyncedConfigText = text;
        root.applyConfigFromFile(Model.parseConfigFile(text));
    }

    moduleName: "mt-shihab26.omaspeedmeter"
    ipcTarget: moduleName
    implicitWidth: row.implicitWidth + Style.space(16)
    implicitHeight: bar ? bar.barSize : 26
    onOpenedChanged: {
        if (!opened)
            return;

        root.refreshSection();
        if (!netIfacesProc.running)
            netIfacesProc.running = true;

        if (!tempZonesProc.running)
            tempZonesProc.running = true;
    }
    // refreshSection() is also called eagerly here (not just on popup open)
    // so the very first config.json write includes the real bar section
    // instead of the "" currentSection starts as.
    onResolvedChanged: configWriteDebounce.restart()
    onCurrentSectionChanged: configWriteDebounce.restart()
    Component.onCompleted: {
        refresh();
        refreshSection();
        ensureConfigDirProc.running = true;
    }

    Process {
        id: ensureConfigDirProc

        command: ["mkdir", "-p", root.configDir]
        onExited: configFile.reload()
    }

    // No eager write on onLoadFailed (first run: the file doesn't exist
    // yet): the implicit preload FileView does as soon as `path` resolves
    // can race ensureConfigDirProc, and an eager write attempted before the
    // directory exists would silently fail while still marking that text as
    // "already synced" — leaving the file never actually created. Instead
    // the file gets created lazily by the first real onResolvedChanged/
    // onCurrentSectionChanged write below, by which point mkdir -p has long
    // since finished (same approach notifications/Service.qml uses).
    FileView {
        id: configFile

        path: root.configPath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onLoaded: root.reconcileConfigFile(text())
        onFileChanged: reload()
    }

    Timer {
        id: configWriteDebounce

        interval: 200
        onTriggered: root.writeConfigFile()
    }

    Process {
        id: setSettingProc

        stdout: StdioCollector {
            waitForEnd: true
        }
        onExited: root.pumpSettingQueue()
    }

    Process {
        id: sectionProc

        command: ["omarchy-shell", "shell", "listShellConfig"]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.currentSection = Model.findSection(text, root.moduleName) || root.currentSection
        }
    }

    Process {
        id: moveSectionProc

        stdout: StdioCollector {
            waitForEnd: true
        }
    }

    Process {
        id: netIfacesProc

        command: ["bash", "-c", "ls /sys/class/net 2>/dev/null"]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.netIfaceOptions = Model.parseNetIfaces(text)
        }
    }

    Process {
        id: tempZonesProc

        command: ["bash", "-c", "for f in /sys/class/thermal/thermal_zone*/type; do p=\"${f%/type}/temp\"; echo \"$p|$(cat \"$f\" 2>/dev/null)\"; done 2>/dev/null"]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.tempZoneOptions = Model.parseTempZones(text)
        }
    }

    Timer {
        interval: Math.max(1, root.resolved.interval) * 1000
        // Don't wake the shell process on an interval when every metric is
        // disabled — refresh() would immediately become a no-op each tick.
        running: root.resolved.cpu || root.resolved.mem || root.resolved.swap
            || root.resolved.net || root.resolved.temp || root.resolved.gpu
            || root.resolved.procs
        repeat: true
        triggeredOnStart: false
        onTriggered: root.refresh()
    }

    Process {
        id: cpuProc

        command: [root.pluginDir + "bin/omaspeedmeter-cpu"]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.mergeStats(Model.parseStats(text) || {})
        }
    }

    Process {
        id: memProc

        command: [root.pluginDir + "bin/omaspeedmeter-mem"]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.mergeStats(Model.parseStats(text) || {})
        }
    }

    Process {
        id: swapProc

        command: [root.pluginDir + "bin/omaspeedmeter-swap"]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.mergeStats(Model.parseStats(text) || {})
        }
    }

    Process {
        id: netProc

        command: [root.pluginDir + "bin/omaspeedmeter-net", "--iface", root.resolved.netIface]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.mergeStats(Model.parseStats(text) || {})
        }
    }

    Process {
        id: tempProc

        command: [root.pluginDir + "bin/omaspeedmeter-temp", "--zone", root.resolved.tempZone]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.mergeStats(Model.parseStats(text) || {})
        }
    }

    Process {
        id: gpuProc

        command: [root.pluginDir + "bin/omaspeedmeter-gpu", "--vendor", root.resolved.gpuVendor]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.mergeStats(Model.parseStats(text) || {})
        }
    }

    Process {
        id: procsProc

        command: [root.pluginDir + "bin/omaspeedmeter-procs"]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.mergeStats(Model.parseStats(text) || {})
        }
    }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: Style.space(root.resolved.gap)

        Repeater {
            model: root.segments

            Text {
                required property var modelData

                text: modelData.text
                color: root.bar ? root.bar.foreground : Color.foreground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
            }
        }

        // Shown when every metric is disabled, so the widget stays clickable
        // instead of collapsing to nothing.
        Text {
            visible: root.segments.length === 0
            text: "omaspeedmeter"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function (mouse) {
            if (mouse.button === Qt.RightButton)
                root.launchSystemMonitor();
            else
                root.toggle();
        }
    }

    KeyboardPanel {
        id: panel

        anchorItem: root
        owner: root
        bar: root.bar
        open: root.opened
        // Same fittedContentWidth pattern Omarchy's own panels use (e.g. the
        // agents/AI widget's KeyboardPanel) — fixed at 360 in practice, only
        // capped down on a screen too narrow to fit it.
        contentWidth: panel.fittedContentWidth(Style.space(360))
        contentHeight: panel.fittedContentHeight(settingsColumn.implicitHeight, Style.space(480))

        Flickable {
            anchors.fill: parent
            contentWidth: width
            contentHeight: settingsColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: settingsColumn

                width: parent.width
                spacing: Style.space(10)

                Item {
                    width: settingsColumn.width
                    height: titleText.implicitHeight

                    Text {
                        id: titleText

                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Omaspeedmeter"
                        color: root.bar ? root.bar.foreground : Color.foreground
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.title
                        font.bold: true
                    }

                    PanelActionButton {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        iconText: "↺"
                        tooltipText: "Reset all settings to default"
                        foreground: root.bar ? root.bar.foreground : Color.foreground
                        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                        onClicked: root.resetSettings()
                    }
                }

                PanelSeparator {
                    foreground: root.bar ? root.bar.foreground : Color.foreground
                }

                PanelSectionHeader {
                    text: "METRICS"
                    foreground: root.bar ? root.bar.foreground : Color.foreground
                    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                }

                Repeater {
                    model: root.orderedMetrics

                    Row {
                        id: metricRow

                        required property var modelData
                        required property int index

                        width: settingsColumn.width
                        spacing: Style.space(4)

                        Toggle {
                            width: metricRow.width - upBtn.width - downBtn.width - metricRow.spacing * 2
                            label: metricRow.modelData.icon + "  " + metricRow.modelData.label
                            description: metricRow.modelData.description || ""
                            checked: root.resolved[metricRow.modelData.key] === true
                            foreground: root.bar ? root.bar.foreground : Color.foreground
                            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                            onClicked: root.toggleMetric(metricRow.modelData.key)
                        }

                        PanelActionButton {
                            id: upBtn

                            anchors.verticalCenter: parent.verticalCenter
                            iconText: "▲"
                            tooltipText: "Move up"
                            foreground: root.bar ? root.bar.foreground : Color.foreground
                            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                            enabled: metricRow.index > 0
                            onClicked: root.moveMetric(metricRow.modelData.key, -1)
                        }

                        PanelActionButton {
                            id: downBtn

                            anchors.verticalCenter: parent.verticalCenter
                            iconText: "▼"
                            tooltipText: "Move down"
                            foreground: root.bar ? root.bar.foreground : Color.foreground
                            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                            enabled: metricRow.index < root.orderedMetrics.length - 1
                            onClicked: root.moveMetric(metricRow.modelData.key, 1)
                        }
                    }
                }

                Toggle {
                    width: settingsColumn.width
                    label: "Split network up/down"
                    description: "Separate download and upload"
                    checked: root.resolved.netSplit === true
                    foreground: root.bar ? root.bar.foreground : Color.foreground
                    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                    onClicked: root.toggleMetric("netSplit")
                }

                Toggle {
                    width: settingsColumn.width
                    label: "Show word labels"
                    description: "Show label instead of icon"
                    checked: root.resolved.labels === true
                    foreground: root.bar ? root.bar.foreground : Color.foreground
                    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                    onClicked: root.toggleMetric("labels")
                }

                PanelSeparator {
                    foreground: root.bar ? root.bar.foreground : Color.foreground
                }

                PanelSectionHeader {
                    text: "SETTINGS"
                    foreground: root.bar ? root.bar.foreground : Color.foreground
                    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                }

                Column {
                    width: settingsColumn.width
                    spacing: Style.space(4)

                    Text {
                        text: "Bar position"
                        color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.caption
                    }

                    ButtonGroup {
                        options: ["left", "center", "right"]
                        value: root.currentSection
                        foreground: root.bar ? root.bar.foreground : Color.foreground
                        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                        onChanged: function (v) {
                            root.setSection(v);
                        }
                    }
                }

                NumberField {
                    label: "Refresh interval (seconds)"
                    value: root.resolved.interval
                    from: 1
                    to: 60
                    stepSize: 1
                    foreground: root.bar ? root.bar.foreground : Color.foreground
                    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                    onModified: function (v) {
                        root.setSetting("interval", v, true);
                    }
                }

                NumberField {
                    label: "Segment spacing (pixels)"
                    value: root.resolved.gap
                    from: 0
                    to: 40
                    stepSize: 1
                    foreground: root.bar ? root.bar.foreground : Color.foreground
                    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                    onModified: function (v) {
                        root.setSetting("gap", v, true);
                    }
                }

                Dropdown {
                    label: "GPU vendor"
                    width: settingsColumn.width
                    value: root.resolved.gpuVendor
                    options: ["auto", "nvidia", "amd", "intel", "none"]
                    foreground: root.bar ? root.bar.foreground : Color.foreground
                    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                    onChanged: function (v) {
                        root.setSetting("gpuVendor", v, false);
                    }
                }

                Dropdown {
                    label: "Network interface"
                    width: settingsColumn.width
                    value: root.resolved.netIface
                    options: root.netIfaceOptions
                    foreground: root.bar ? root.bar.foreground : Color.foreground
                    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                    onChanged: function (v) {
                        root.setSetting("netIface", v, false);
                    }
                }

                Dropdown {
                    label: "Temperature source"
                    width: settingsColumn.width
                    value: root.resolved.tempZone
                    options: root.tempZoneOptions
                    foreground: root.bar ? root.bar.foreground : Color.foreground
                    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                    onChanged: function (v) {
                        root.setSetting("tempZone", v, false);
                    }
                }

                Dropdown {
                    label: "System monitor (right-click)"
                    width: settingsColumn.width
                    value: root.resolved.systemMonitor
                    options: ["btop", "htop"]
                    foreground: root.bar ? root.bar.foreground : Color.foreground
                    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                    onChanged: function (v) {
                        root.setSetting("systemMonitor", v, false);
                    }
                }

                Item {
                    width: 1
                    height: Style.space(4)
                }
            }
        }
    }
}
