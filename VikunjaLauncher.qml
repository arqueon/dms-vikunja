import QtQuick
import qs.Services

Item {
    id: root

    property var pluginService: null
    property string pluginId: "dmsVikunja"
    property string trigger: "vt"

    signal itemsChanged()

    function daemonInstance() {
        if (!pluginService || !pluginService.pluginDaemonInstances)
            return null
        return pluginService.pluginDaemonInstances[pluginId] || null
    }

    function defaultProjectId() {
        if (!pluginService || !pluginService.loadPluginData)
            return 0
        return parseInt(pluginService.loadPluginData(pluginId, "defaultProjectId", 0) || 0)
    }

    function projectLabel(projectId) {
        var daemon = daemonInstance()
        var projects = daemon && daemon.projects ? daemon.projects : []
        for (var i = 0; i < projects.length; i++) {
            if (parseInt(projects[i].id) === projectId)
                return String(projects[i].title || "Default project")
        }
        return projectId > 0 ? "Default project" : "Choose a default project in Settings"
    }

    function getItems(query) {
        var title = String(query || "").trim()
        var projectId = defaultProjectId()
        if (!title) {
            return [{
                name: "Quick add to Vikunja",
                icon: "material:add_task",
                comment: "Type vt followed by the task title",
                action: "help",
                categories: ["Vikunja"]
            }]
        }
        return [{
            name: "Create “" + title + "”",
            icon: "material:add_task",
            comment: projectLabel(projectId),
            action: "create",
            taskTitle: title,
            projectId: projectId,
            categories: ["Vikunja"]
        }]
    }

    function executeItem(item) {
        if (item.action !== "create")
            return
        if (parseInt(item.projectId) <= 0) {
            ToastService.showError("Vikunja", "Choose a default quick-add project in plugin settings")
            return
        }
        var daemon = daemonInstance()
        if (!daemon || !daemon.createTask(
                parseInt(item.projectId), String(item.taskTitle || ""), "", 0, ""))
            ToastService.showError("Vikunja", "Quick add is unavailable or busy")
    }
}
