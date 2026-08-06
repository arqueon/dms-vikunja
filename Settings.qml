import QtQuick
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins
import qs.Widgets
import "./JS/vikunja.js" as Vikunja

PluginSettings {
    id: root

    pluginId: "dmsVikunja"

    property var projects: []
    readonly property var projectOptions: Vikunja.projectOptions(projects, false)
    property int defaultProjectId: 0
    property bool tokenStored: false
    property string tokenStatus: "Checking the system keyring…"
    property string connectionStatus: ""
    property bool testingConnection: false
    property string pendingToken: ""
    readonly property string helperPath: pluginService && pluginService.getPluginPath
        ? pluginService.getPluginPath(pluginId) + "/scripts/vikunja_api.py" : ""

    function loadLocalState() {
        if (!pluginService)
            return
        var cache = loadState("cache", {}) || {}
        projects = Vikunja.toArray(cache.projects)
        defaultProjectId = parseInt(loadValue("defaultProjectId", "0")) || 0
    }

    function projectPathForId(projectId) {
        for (var i = 0; i < projectOptions.length; i++) {
            if (projectOptions[i].id === parseInt(projectId))
                return projectOptions[i].path
        }
        return projectOptions.length > 0 ? projectOptions[0].path : "Sync projects first"
    }

    function setDefaultProject(path) {
        for (var i = 0; i < projectOptions.length; i++) {
            if (projectOptions[i].path === path) {
                defaultProjectId = projectOptions[i].id
                saveValue("defaultProjectId", String(defaultProjectId))
                return
            }
        }
    }

    function lookupToken() {
        if (!tokenLookup.running)
            tokenLookup.running = true
    }

    function storeToken(value) {
        var token = String(value || "").trim()
        if (!token) {
            tokenStatus = "Enter an API token before saving"
            return
        }
        pendingToken = token
        tokenStore.stdinEnabled = true
        tokenStore.running = true
    }

    function clearToken() {
        if (!tokenClear.running)
            tokenClear.running = true
    }

    function testConnection() {
        serverUrl.commit()
        var base = String(serverUrl.value || "").trim()
        if (!base) {
            connectionStatus = "Configure the Vikunja server URL first"
            return
        }
        if (!tokenStored) {
            connectionStatus = "Save an API token first"
            return
        }
        if (helperPath === "" || connectionTest.running)
            return
        testingConnection = true
        connectionStatus = "Connecting…"
        connectionTest.command = [
            "python3", helperPath,
            "--base-url", base,
            "--api-version", apiVersion.value,
            "check"
        ]
        connectionTest.running = true
    }

    Component.onCompleted: {
        Qt.callLater(loadLocalState)
        Qt.callLater(lookupToken)
    }
    onPluginServiceChanged: Qt.callLater(loadLocalState)

    Process {
        id: tokenLookup
        command: [
            "secret-tool", "lookup",
            "service", "dms-vikunja",
            "key", "api-token"
        ]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                root.tokenStored = text.trim() !== ""
                root.tokenStatus = root.tokenStored
                    ? "API token stored in the system keyring"
                    : "No API token is stored"
            }
        }

        onExited: function(exitCode) {
            if (exitCode !== 0 && !root.tokenStored)
                root.tokenStatus = "No token found, or Secret Service is unavailable"
        }
    }

    Process {
        id: tokenStore
        command: [
            "secret-tool", "store",
            "--label=DMS Vikunja API token",
            "service", "dms-vikunja",
            "key", "api-token"
        ]
        stdinEnabled: true
        running: false

        onStarted: {
            write(root.pendingToken + "\n")
            root.pendingToken = ""
            stdinEnabled = false
        }

        onExited: function(exitCode) {
            root.tokenStored = exitCode === 0
            root.tokenStatus = exitCode === 0
                ? "API token stored securely in the system keyring"
                : "Could not save the token; check that the keyring is unlocked"
            if (exitCode === 0) {
                root.saveValue("credentialsStamp", String(Date.now()))
                tokenField.text = ""
            }
        }
    }

    Process {
        id: tokenClear
        command: [
            "secret-tool", "clear",
            "service", "dms-vikunja",
            "key", "api-token"
        ]
        running: false
        onExited: function(exitCode) {
            root.tokenStored = false
            root.tokenStatus = exitCode === 0
                ? "API token removed from the system keyring"
                : "No stored token was removed"
            root.saveValue("credentialsStamp", String(Date.now()))
        }
    }

    Process {
        id: connectionTest
        running: false
        property string output: ""

        stdout: StdioCollector {
            onStreamFinished: connectionTest.output = text
        }

        onExited: function(exitCode) {
            root.testingConnection = false
            var payload = null
            try {
                payload = JSON.parse(connectionTest.output.trim())
            } catch (error) {
                payload = { ok: false, error: "Connection test returned invalid output" }
            }
            if (exitCode === 0 && payload.ok === true) {
                root.connectionStatus = "Connected as " + (payload.username || "user")
                    + " · server " + (payload.server_version || "unknown")
                    + " · API " + (payload.api_version || "unknown")
                root.saveValue("connectionStamp", String(Date.now()))
            } else {
                root.connectionStatus = "Connection failed: "
                    + String(payload.error || "unknown error")
            }
        }
    }

    StyledText {
        width: parent.width
        text: "Vikunja connection"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "dms-vikunja detects API v1 on Vikunja 2.3 and earlier, then switches to API v2 from Vikunja 2.4 onward. The API token stays in Freedesktop Secret Service, not in DMS settings."
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    StringSetting {
        id: serverUrl
        settingKey: "baseUrl"
        label: "Vikunja server"
        description: "Base URL without /api, for example https://tasks.example.org"
        placeholder: "https://tasks.example.org"
        defaultValue: ""
    }

    SelectionSetting {
        id: apiVersion
        settingKey: "apiVersion"
        label: "API version"
        description: "Auto is recommended and follows the detected Vikunja server version"
        options: [
            { label: "Auto (recommended)", value: "auto" },
            { label: "Force v1", value: "v1" },
            { label: "Force v2", value: "v2" }
        ]
        defaultValue: "auto"
    }

    StyledText {
        width: parent.width
        text: "API token"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Create a Vikunja API token with read access to projects, tasks, and labels, plus write access to tasks and task labels."
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    Row {
        width: parent.width
        spacing: Theme.spacingS

        DankTextField {
            id: tokenField
            width: parent.width - 110 - Theme.spacingS
            height: 38
            echoMode: TextInput.Password
            placeholderText: "tk_…"
        }

        DankButton {
            width: 110
            text: "Save token"
            iconName: "key"
            buttonHeight: 38
            onClicked: root.storeToken(tokenField.text)
        }
    }

    Row {
        width: parent.width
        spacing: Theme.spacingS

        StyledText {
            width: parent.width - 120 - Theme.spacingS
            text: root.tokenStatus
            font.pixelSize: Theme.fontSizeSmall
            color: root.tokenStored ? Theme.primary : Theme.surfaceVariantText
            wrapMode: Text.WordWrap
            anchors.verticalCenter: parent.verticalCenter
        }

        DankButton {
            width: 120
            text: "Remove token"
            iconName: "key_off"
            buttonHeight: 32
            enabled: root.tokenStored
            backgroundColor: Theme.withAlpha(Theme.error, 0.15)
            textColor: Theme.error
            onClicked: root.clearToken()
        }
    }

    DankButton {
        text: root.testingConnection ? "Testing…" : "Test connection"
        iconName: "network_check"
        buttonHeight: 36
        enabled: !root.testingConnection
        onClicked: root.testConnection()
    }

    StyledText {
        width: parent.width
        visible: root.connectionStatus !== ""
        text: root.connectionStatus
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.fontSizeSmall
        color: root.connectionStatus.indexOf("Connected") === 0
            ? Theme.primary : Theme.error
    }

    StyledText {
        width: parent.width
        text: "Task behavior"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingL
    }

    SelectionSetting {
        settingKey: "pollInterval"
        label: "Refresh interval"
        description: "How often the background daemon synchronizes tasks"
        options: [
            { label: "30 seconds", value: "30" },
            { label: "1 minute", value: "60" },
            { label: "5 minutes", value: "300" },
            { label: "15 minutes", value: "900" }
        ]
        defaultValue: "300"
    }

    ToggleSetting {
        settingKey: "showCompleted"
        label: "Show completed tasks"
        description: "Fetch completed tasks too, so they can be reopened from DankBar"
        defaultValue: false
    }

    SelectionSetting {
        settingKey: "sortMode"
        label: "Default sorting"
        description: "The sort can also be cycled from the task popout"
        options: [
            { label: "Smart", value: "smart" },
            { label: "Due date", value: "due" },
            { label: "Priority", value: "priority" },
            { label: "Title", value: "title" },
            { label: "Project", value: "project" },
            { label: "Recently updated", value: "updated" }
        ]
        defaultValue: "smart"
    }

    SelectionSetting {
        settingKey: "maxVisibleTasks"
        label: "Tasks shown in the popout"
        description: "Filtering still applies to the full synchronized set"
        options: [
            { label: "50", value: "50" },
            { label: "100", value: "100" },
            { label: "250", value: "250" },
            { label: "500", value: "500" }
        ]
        defaultValue: "100"
    }

    ToggleSetting {
        settingKey: "hideWhenZero"
        label: "Hide the DankBar pill at zero"
        description: "Collapse the widget when no included task remains open"
        defaultValue: false
    }

    StyledText {
        width: parent.width
        text: "Default project for quick add"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    DankDropdown {
        width: parent.width
        text: "Project"
        description: root.projectOptions.length > 0
            ? "Used when no project filter is active"
            : "Synchronize once before choosing a project"
        enabled: root.projectOptions.length > 0
        options: root.projectOptions.map(function(option) { return option.path })
        currentValue: root.projectPathForId(root.defaultProjectId)
        onValueChanged: value => root.setDefaultProject(value)
    }

    StyledText {
        width: parent.width
        text: "Project exclusions are managed in the Projects tab of the DankBar popout, where the hierarchy and task counts are visible."
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    StyledText {
        width: parent.width
        text: "Notifications"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingL
    }

    SelectionSetting {
        settingKey: "notificationMode"
        label: "Desktop notifications"
        description: "The first synchronization is silent to avoid alerting on an existing backlog"
        options: [
            { label: "Due soon and newly overdue", value: "both" },
            { label: "Due soon only", value: "due" },
            { label: "Newly overdue only", value: "overdue" },
            { label: "Disabled", value: "none" }
        ]
        defaultValue: "both"
    }

    SelectionSetting {
        settingKey: "notificationLeadMinutes"
        label: "Due-soon window"
        description: "Notify once when a task enters this window"
        options: [
            { label: "15 minutes", value: "15" },
            { label: "30 minutes", value: "30" },
            { label: "1 hour", value: "60" },
            { label: "3 hours", value: "180" },
            { label: "1 day", value: "1440" }
        ]
        defaultValue: "60"
    }

    StyledText {
        width: parent.width
        text: "Notifications are deduplicated by task, due date, and state. Changing a due date creates a new notification cycle; completing the task removes it from future alerts."
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }
}
