import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins
import qs.Services
import "./JS/vikunja.js" as Vikunja

PluginComponent {
    id: root

    property var popoutService: null

    readonly property string baseUrl: String(pluginData.baseUrl || "").trim()
    readonly property string apiPreference: String(pluginData.apiVersion || "auto")
    readonly property int pollSeconds: Math.max(30, parseInt(pluginData.pollInterval || "300"))
    readonly property bool includeDone: pluginData.showCompleted === true
    readonly property string notificationMode: String(pluginData.notificationMode || "both")
    readonly property int notificationLeadMinutes: Math.max(5, parseInt(pluginData.notificationLeadMinutes || "60"))
    readonly property var excludedProjectIds: Vikunja.toArray(pluginData.excludedProjectIds)
    readonly property bool configured: baseUrl !== ""
    readonly property string configurationContext: baseUrl + "|" + apiPreference
    readonly property string helperPath: pluginService && pluginService.getPluginPath
        ? pluginService.getPluginPath(pluginId) + "/scripts/vikunja_api.py" : ""

    property var tasks: []
    property var projects: []
    property var labels: []
    property bool stateLoaded: false
    property bool isLoading: false
    property bool isMutating: false
    property string errorMessage: ""
    property string operationMessage: ""
    property string detectedApiVersion: ""
    property string serverVersion: ""
    property double lastUpdated: 0
    property int requestSequence: 0
    property string loadedContext: ""
    property var notificationKeys: ({})
    property bool notificationsPrimed: false

    pluginId: "dmsVikunja"
    pluginService: PluginService

    function publishRuntime() {
        if (!pluginService)
            return
        pluginService.setGlobalVar(pluginId, "tasks", tasks)
        pluginService.setGlobalVar(pluginId, "projects", projects)
        pluginService.setGlobalVar(pluginId, "labels", labels)
        pluginService.setGlobalVar(pluginId, "configured", configured)
        pluginService.setGlobalVar(pluginId, "loading", isLoading)
        pluginService.setGlobalVar(pluginId, "mutating", isMutating)
        pluginService.setGlobalVar(pluginId, "errorMessage", errorMessage)
        pluginService.setGlobalVar(pluginId, "operationMessage", operationMessage)
        pluginService.setGlobalVar(pluginId, "lastUpdated", lastUpdated)
        pluginService.setGlobalVar(pluginId, "apiVersion", detectedApiVersion)
        pluginService.setGlobalVar(pluginId, "serverVersion", serverVersion)
    }

    function loadState() {
        if (!pluginService || !pluginId || stateLoaded)
            return
        var saved = pluginService.loadPluginState(pluginId, "cache", {}) || {}
        loadedContext = String(saved.context || "")
        if (loadedContext === configurationContext) {
            tasks = Vikunja.toArray(saved.tasks)
            projects = Vikunja.toArray(saved.projects)
            labels = Vikunja.toArray(saved.labels)
            lastUpdated = parseInt(saved.lastUpdated) || 0
            detectedApiVersion = String(saved.apiVersion || "")
            serverVersion = String(saved.serverVersion || "")
            notificationKeys = saved.notificationKeys && typeof saved.notificationKeys === "object"
                ? saved.notificationKeys : ({})
            notificationsPrimed = saved.notificationsPrimed === true
        }
        stateLoaded = true
        publishRuntime()
        if (configured)
            initialSyncTimer.restart()
    }

    function persistState() {
        if (!pluginService)
            return
        pluginService.savePluginState(pluginId, "cache", {
            context: configurationContext,
            tasks: tasks,
            projects: projects,
            labels: labels,
            lastUpdated: lastUpdated,
            apiVersion: detectedApiVersion,
            serverVersion: serverVersion,
            notificationKeys: notificationKeys,
            notificationsPrimed: notificationsPrimed
        })
    }

    function parseBridge(stdout, exitCode) {
        var payload = null
        try {
            payload = JSON.parse(String(stdout || "").trim())
        } catch (error) {
            return {
                ok: false,
                error: exitCode === 0
                    ? "The Vikunja bridge returned invalid JSON"
                    : "The Vikunja bridge failed with exit code " + exitCode
            }
        }
        if (exitCode !== 0 || payload.ok !== true)
            return { ok: false, error: String(payload.error || "Vikunja request failed") }
        return payload
    }

    function helperArguments(commandArgs) {
        var args = [
            "python3", helperPath,
            "--base-url", baseUrl,
            "--api-version", apiPreference
        ]
        var commands = commandArgs || []
        for (var i = 0; i < commands.length; i++)
            args.push(String(commands[i]))
        return args
    }

    function refresh() {
        if (!stateLoaded || !configured || isLoading || isMutating || helperPath === "")
            return false
        isLoading = true
        errorMessage = ""
        operationMessage = ""
        publishRuntime()
        var command = ["sync"]
        if (includeDone)
            command.push("--include-done")
        Proc.runCommand(
            "dmsVikunja.sync." + (++requestSequence),
            helperArguments(command),
            (stdout, exitCode) => {
                isLoading = false
                var payload = parseBridge(stdout, exitCode)
                if (!payload.ok) {
                    errorMessage = payload.error
                    publishRuntime()
                    return
                }
                var nextTasks = Vikunja.toArray(payload.tasks)
                var nextProjects = Vikunja.toArray(payload.projects)
                processNotifications(nextTasks, nextProjects)
                tasks = nextTasks
                projects = nextProjects
                labels = Vikunja.toArray(payload.labels)
                detectedApiVersion = String(payload.api_version || "")
                serverVersion = String(payload.server_version || "")
                lastUpdated = Date.now()
                loadedContext = configurationContext
                errorMessage = ""
                persistState()
                publishRuntime()
            },
            0,
            120000
        )
        return true
    }

    function processNotifications(nextTasks, nextProjects) {
        if (notificationMode === "none") {
            notificationsPrimed = true
            notificationKeys = ({})
            return
        }
        var graceMinutes = Math.max(60, Math.ceil(pollSeconds / 60) * 2)
        var candidates = Vikunja.notificationCandidates(
            nextTasks,
            nextProjects,
            excludedProjectIds,
            Date.now(),
            notificationLeadMinutes,
            notificationMode,
            graceMinutes
        )
        var nextKeys = {}
        for (var i = 0; i < candidates.length; i++) {
            var candidate = candidates[i]
            nextKeys[candidate.key] = true
            if (!notificationsPrimed || notificationKeys[candidate.key])
                continue
            var task = candidate.task
            var project = null
            for (var j = 0; j < nextProjects.length; j++) {
                if (parseInt(nextProjects[j].id) === parseInt(task.project_id)) {
                    project = nextProjects[j]
                    break
                }
            }
            var summary = candidate.kind === "overdue"
                ? "Vikunja · Task overdue" : "Vikunja · Task due soon"
            var body = String(task.title || "Untitled task")
            if (project)
                body += "\n" + Vikunja.projectPath(project, nextProjects)
            var dueText = Vikunja.formatDue(task, Date.now())
            if (dueText)
                body += "\n" + dueText
            var args = ["notify-send", "--app-name=dms-vikunja", "--icon=task_alt"]
            if (candidate.kind === "overdue")
                args.push("--urgency=critical")
            args.push(summary, body)
            Quickshell.execDetached(args)
        }
        notificationKeys = nextKeys
        notificationsPrimed = true
    }

    function executeMutation(command, successMessage) {
        if (!configured || isLoading || isMutating || helperPath === "")
            return false
        isMutating = true
        errorMessage = ""
        operationMessage = ""
        publishRuntime()
        Proc.runCommand(
            "dmsVikunja.mutate." + (++requestSequence),
            helperArguments(command),
            (stdout, exitCode) => {
                isMutating = false
                var payload = parseBridge(stdout, exitCode)
                if (!payload.ok) {
                    errorMessage = payload.error
                    operationMessage = ""
                    ToastService?.showError("Vikunja", payload.error)
                    publishRuntime()
                    return
                }
                detectedApiVersion = String(payload.api_version || detectedApiVersion)
                serverVersion = String(payload.server_version || serverVersion)
                operationMessage = successMessage
                ToastService?.showInfo("Vikunja", successMessage)
                publishRuntime()
                refreshDelay.restart()
            },
            0,
            120000
        )
        return true
    }

    function setDone(taskId, done) {
        return executeMutation(
            ["save-task", taskId, JSON.stringify({
                done: done === true,
                percent_done: done === true ? 1 : 0
            })],
            done ? "Task completed" : "Task reopened"
        )
    }

    function saveTask(taskId, patchJson, labelIds) {
        return executeMutation(
            ["save-task", taskId, patchJson, labelIds],
            "Task updated"
        )
    }

    function createTask(projectId, title, dueDate, priority, labelIds) {
        return executeMutation(
            ["create-task", projectId, title, dueDate, priority, labelIds],
            "Task created"
        )
    }

    function deleteTask(taskId) {
        return executeMutation(["delete-task", taskId], "Task deleted")
    }

    function uploadAttachments(taskId, fileUrlsJson) {
        if (!configured || isLoading || isMutating || helperPath === "")
            return false
        isMutating = true
        errorMessage = ""
        operationMessage = "Uploading attachments…"
        publishRuntime()
        Proc.runCommand(
            "dmsVikunja.attachments." + (++requestSequence),
            helperArguments(["upload-attachments", taskId, fileUrlsJson]),
            (stdout, exitCode) => {
                isMutating = false
                var payload = parseBridge(stdout, exitCode)
                if (!payload.ok) {
                    errorMessage = payload.error
                    operationMessage = ""
                    ToastService?.showError("Vikunja", payload.error)
                    publishRuntime()
                    return
                }
                var uploaded = Vikunja.toArray(payload.uploaded)
                var failures = Vikunja.toArray(payload.errors)
                var details = []
                for (var i = 0; i < failures.length; i++)
                    details.push(String(failures[i].message || "Unknown upload error"))
                if (uploaded.length === 0 && failures.length > 0) {
                    errorMessage = details.join("\n")
                    operationMessage = "No attachments uploaded"
                    ToastService?.showError("Vikunja", errorMessage)
                } else if (failures.length > 0) {
                    operationMessage = "Uploaded " + uploaded.length
                        + "; " + failures.length + " failed"
                    ToastService?.showWarning("Vikunja", operationMessage
                        + "\n" + details.join("\n"))
                } else {
                    operationMessage = uploaded.length === 1
                        ? "Attachment uploaded"
                        : uploaded.length + " attachments uploaded"
                    ToastService?.showInfo("Vikunja", operationMessage)
                }
                detectedApiVersion = String(payload.api_version || detectedApiVersion)
                serverVersion = String(payload.server_version || serverVersion)
                publishRuntime()
                if (uploaded.length > 0)
                    refreshDelay.restart()
            },
            0,
            600000
        )
        return true
    }

    IpcHandler {
        target: "dmsVikunja"
        enabled: true

        function refresh(): string {
            return root.refresh() ? "QUEUED" : "BUSY_OR_NOT_CONFIGURED"
        }

        function setDone(taskId: string, done: string): string {
            return root.setDone(parseInt(taskId), done === "true")
                ? "QUEUED" : "BUSY_OR_NOT_CONFIGURED"
        }

        function saveTask(taskId: string, patchJson: string, labelIds: string): string {
            return root.saveTask(parseInt(taskId), patchJson, labelIds)
                ? "QUEUED" : "BUSY_OR_NOT_CONFIGURED"
        }

        function createTask(projectId: string, title: string, dueDate: string,
                            priority: string, labelIds: string): string {
            return root.createTask(parseInt(projectId), title, dueDate,
                                   parseInt(priority), labelIds)
                ? "QUEUED" : "BUSY_OR_NOT_CONFIGURED"
        }

        function deleteTask(taskId: string): string {
            return root.deleteTask(parseInt(taskId))
                ? "QUEUED" : "BUSY_OR_NOT_CONFIGURED"
        }

        function uploadAttachments(taskId: string, fileUrlsJson: string): string {
            return root.uploadAttachments(parseInt(taskId), fileUrlsJson)
                ? "QUEUED" : "BUSY_OR_NOT_CONFIGURED"
        }
    }

    Timer {
        id: pollTimer
        interval: root.pollSeconds * 1000
        repeat: true
        running: root.stateLoaded && root.configured
        onTriggered: root.refresh()
    }

    Timer {
        id: initialSyncTimer
        interval: 1200
        repeat: false
        onTriggered: root.refresh()
    }

    Timer {
        id: refreshDelay
        interval: 350
        repeat: false
        onTriggered: root.refresh()
    }

    Connections {
        target: pluginService
        function onPluginDataChanged(changedId) {
            if (changedId !== root.pluginId || !root.stateLoaded)
                return
            if (root.loadedContext !== root.configurationContext) {
                root.tasks = []
                root.projects = []
                root.labels = []
                root.notificationKeys = ({})
                root.notificationsPrimed = false
                root.lastUpdated = 0
                root.loadedContext = root.configurationContext
                root.publishRuntime()
            }
            initialSyncTimer.restart()
        }
    }

    Component.onCompleted: {
        if (pluginService && pluginId) {
            var instances = Object.assign({}, pluginService.pluginInstances)
            instances[pluginId] = root
            pluginService.pluginInstances = instances
        }
        Qt.callLater(loadState)
    }

    onPluginServiceChanged: Qt.callLater(loadState)

    Component.onDestruction: {
        if (pluginService && pluginService.pluginInstances[pluginId] === root) {
            var instances = Object.assign({}, pluginService.pluginInstances)
            delete instances[pluginId]
            pluginService.pluginInstances = instances
        }
    }
}
