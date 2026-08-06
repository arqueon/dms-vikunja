.pragma library

var ZERO_DATE = "0001-01-01T00:00:00Z"

function toArray(value) {
    return Array.isArray(value) ? value : []
}

function asId(value) {
    var parsed = parseInt(value)
    return isNaN(parsed) ? 0 : parsed
}

function idSet(values) {
    var result = {}
    var list = toArray(values)
    for (var i = 0; i < list.length; i++)
        result[String(asId(list[i]))] = true
    return result
}

function projectMap(projects) {
    var result = {}
    var list = toArray(projects)
    for (var i = 0; i < list.length; i++)
        result[String(asId(list[i].id))] = list[i]
    return result
}

function projectPath(project, projects) {
    if (!project)
        return "Unknown project"
    var byId = projectMap(projects)
    var seen = {}
    var parts = []
    var current = project
    while (current) {
        var currentId = String(asId(current.id))
        if (seen[currentId]) {
            parts.unshift("…")
            break
        }
        seen[currentId] = true
        parts.unshift(String(current.title || "Untitled"))
        var parentId = asId(current.parent_project_id)
        current = parentId > 0 ? byId[String(parentId)] : null
    }
    return parts.join(" › ")
}

function projectDepth(project, projects) {
    if (!project)
        return 0
    var byId = projectMap(projects)
    var seen = {}
    var depth = 0
    var parentId = asId(project.parent_project_id)
    while (parentId > 0 && byId[String(parentId)] && !seen[String(parentId)]) {
        seen[String(parentId)] = true
        depth++
        parentId = asId(byId[String(parentId)].parent_project_id)
    }
    return depth
}

function projectParentPath(project, projects) {
    if (!project)
        return ""
    var byId = projectMap(projects)
    var parentId = asId(project.parent_project_id)
    return parentId > 0 && byId[String(parentId)]
        ? projectPath(byId[String(parentId)], projects) : ""
}

function projectOptions(projects, includeArchived) {
    var list = toArray(projects).filter(function(project) {
        return asId(project.id) > 0 && (includeArchived || project.is_archived !== true)
    }).map(function(project) {
        return {
            id: asId(project.id),
            title: String(project.title || "Untitled"),
            path: projectPath(project, projects),
            parentPath: projectParentPath(project, projects),
            depth: projectDepth(project, projects),
            project: project
        }
    })
    list.sort(function(a, b) {
        return a.path.localeCompare(b.path, undefined, { sensitivity: "base" })
    })
    return list
}

function filterProjectOptions(options, query) {
    var needle = String(query || "").trim().toLowerCase()
    if (!needle)
        return toArray(options)
    return toArray(options).filter(function(option) {
        return String(option.title || "").toLowerCase().indexOf(needle) !== -1
            || String(option.path || "").toLowerCase().indexOf(needle) !== -1
    })
}

function descendantIds(projects, parentId) {
    var wanted = {}
    wanted[String(asId(parentId))] = true
    var changed = true
    var list = toArray(projects)
    while (changed) {
        changed = false
        for (var i = 0; i < list.length; i++) {
            var id = String(asId(list[i].id))
            var parent = String(asId(list[i].parent_project_id))
            if (!wanted[id] && wanted[parent]) {
                wanted[id] = true
                changed = true
            }
        }
    }
    return wanted
}

function excludedSet(projects, excludedIds) {
    var result = {}
    var explicit = toArray(excludedIds)
    for (var i = 0; i < explicit.length; i++) {
        var descendants = descendantIds(projects, explicit[i])
        for (var id in descendants)
            result[id] = true
    }
    return result
}

function labelIds(task) {
    return toArray(task && task.labels).map(function(label) { return asId(label.id) })
}

function statusLabel(done, percentDone) {
    if (done === true)
        return "Completed"
    var progress = Number(percentDone)
    if (!isFinite(progress) || progress <= 0)
        return "To do"
    var percent = Math.max(0, Math.min(100, Math.round(progress * 100)))
    return "In progress · " + percent + "%"
}

function statusState(label) {
    var value = String(label || "")
    if (value === "Completed")
        return { done: true, percentDone: 1 }
    if (value === "To do")
        return { done: false, percentDone: 0 }
    var match = value.match(/([0-9]{1,3})%/)
    var percent = match ? Math.max(0, Math.min(100, parseInt(match[1]))) : 0
    return { done: false, percentDone: percent / 100 }
}

function decodeHtmlEntities(value) {
    var named = {
        amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: " ",
        ndash: "–", mdash: "—", hellip: "…", laquo: "«", raquo: "»"
    }
    return String(value || "").replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, function(match, entity) {
        var lower = entity.toLowerCase()
        if (named[lower] !== undefined)
            return named[lower]
        var code = lower.indexOf("#x") === 0
            ? parseInt(lower.slice(2), 16) : parseInt(lower.slice(1), 10)
        if (isNaN(code) || code < 0 || code > 0x10ffff)
            return match
        if (String.fromCodePoint)
            return String.fromCodePoint(code)
        return String.fromCharCode(code)
    })
}

function escapeHtml(value) {
    return String(value || "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#39;")
}

function contentHtml(value) {
    var text = String(value || "")
    if (!text)
        return ""
    var result = ""
    var lastIndex = 0
    var urlPattern = /https?:\/\/[^\s<>"']+/gi
    var match
    while ((match = urlPattern.exec(text)) !== null) {
        result += escapeHtml(text.slice(lastIndex, match.index))
        var url = match[0]
        var escapedUrl = escapeHtml(url)
        result += "<a href=\"" + escapedUrl
            + "\" target=\"_blank\" rel=\"noopener noreferrer\">"
            + escapedUrl + "</a>"
        lastIndex = match.index + url.length
    }
    result += escapeHtml(text.slice(lastIndex))
    return result.replace(/\r?\n/g, "<br>")
}

function plainText(value) {
    var text = String(value || "")
    if (!text)
        return ""
    text = text.replace(/<(script|style)\b[^>]*>[\s\S]*?<\/\1>/gi, "")
    text = text.replace(/<br\s*\/?>/gi, "\n")
    text = text.replace(/<li\b[^>]*>/gi, "\n• ")
    text = text.replace(/<\/(p|div|h[1-6]|li|ul|ol|blockquote|section|article)>/gi, "\n")
    text = text.replace(/<[^>]+>/g, "")
    text = decodeHtmlEntities(text)
    text = text.replace(/\r/g, "").replace(/[ \t]+\n/g, "\n")
    text = text.replace(/\n[ \t]+/g, "\n").replace(/\n{2,}/g, "\n")
    return text.trim()
}

function dueTimestamp(task) {
    var raw = String(task && task.due_date || "")
    if (!raw || raw.indexOf("0001-01-01") === 0)
        return 0
    var parsed = Date.parse(raw)
    return isNaN(parsed) ? 0 : parsed
}

function dueState(task, now) {
    var due = dueTimestamp(task)
    if (!due || task.done === true)
        return "none"
    var delta = due - (now || Date.now())
    if (delta < 0)
        return "overdue"
    if (delta <= 24 * 60 * 60 * 1000)
        return "today"
    if (delta <= 7 * 24 * 60 * 60 * 1000)
        return "week"
    return "future"
}

function pad2(value) {
    return value < 10 ? "0" + value : String(value)
}

function dueInputFromDate(value) {
    var date = new Date(value)
    if (isNaN(date.getTime()))
        return ""
    return date.getFullYear() + "-" + pad2(date.getMonth() + 1) + "-" + pad2(date.getDate())
        + " " + pad2(date.getHours()) + ":" + pad2(date.getMinutes())
}

function duePresetInput(kind, now, currentValue) {
    var date = new Date(now === undefined ? Date.now() : now)
    var parsed = parseDueInput(currentValue)
    var current = parsed.ok && parsed.value !== ZERO_DATE ? new Date(parsed.value) : null
    var hours = current ? current.getHours() : 23
    var minutes = current ? current.getMinutes() : 59
    date.setSeconds(0, 0)
    if (kind === "tomorrow") {
        date.setDate(date.getDate() + 1)
    } else if (kind === "weekend") {
        date.setDate(date.getDate() + ((6 - date.getDay() + 7) % 7))
    } else if (kind === "nextweek") {
        date.setDate(date.getDate() + ((8 - date.getDay()) % 7 || 7))
    }
    date.setHours(hours, minutes, 0, 0)
    return dueInputFromDate(date)
}

function formatDue(task, now) {
    var timestamp = dueTimestamp(task)
    if (!timestamp)
        return ""
    var date = new Date(timestamp)
    var state = dueState(task, now)
    var dateText = pad2(date.getDate()) + "/" + pad2(date.getMonth() + 1)
    var timeText = pad2(date.getHours()) + ":" + pad2(date.getMinutes())
    if (state === "overdue")
        return "Overdue · " + dateText + " " + timeText
    if (state === "today")
        return "Due soon · " + dateText + " " + timeText
    return dateText + "/" + date.getFullYear() + " · " + timeText
}

function dueInput(task) {
    var timestamp = dueTimestamp(task)
    if (!timestamp)
        return ""
    return dueInputFromDate(new Date(timestamp))
}

function parseDueInput(value) {
    var text = String(value || "").trim()
    if (!text)
        return { ok: true, value: ZERO_DATE }
    var match = text.match(/^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2}))?$/)
    if (!match)
        return { ok: false, error: "Use YYYY-MM-DD or YYYY-MM-DD HH:mm" }
    var local = new Date(
        parseInt(match[1]), parseInt(match[2]) - 1, parseInt(match[3]),
        parseInt(match[4] || "23"), parseInt(match[5] || "59"), 0, 0
    )
    if (isNaN(local.getTime())
            || local.getFullYear() !== parseInt(match[1])
            || local.getMonth() !== parseInt(match[2]) - 1
            || local.getDate() !== parseInt(match[3]))
        return { ok: false, error: "The due date is not valid" }
    return { ok: true, value: local.toISOString() }
}

function priorityLabel(value) {
    var priority = asId(value)
    if (priority <= 0) return "No priority"
    if (priority === 1) return "Low"
    if (priority === 2) return "Medium"
    if (priority === 3) return "High"
    if (priority === 4) return "Urgent"
    return "Do now"
}

function matchesTask(task, query, paths) {
    var needle = String(query || "").trim().toLowerCase()
    if (!needle)
        return true
    var labels = toArray(task.labels).map(function(label) { return label.title || "" }).join(" ")
    var haystack = [
        task.title || "",
        plainText(task.description || ""),
        task.identifier || "",
        paths[String(asId(task.project_id))] || "",
        labels
    ].join(" ").toLowerCase()
    return haystack.indexOf(needle) !== -1
}

function filterLabels(labels, query) {
    var needle = String(query || "").trim().toLowerCase()
    var result = toArray(labels).filter(function(label) {
        if (!needle)
            return true
        return String(label.title || "").toLowerCase().indexOf(needle) !== -1
            || String(label.description || "").toLowerCase().indexOf(needle) !== -1
    }).slice()
    result.sort(function(left, right) {
        return String(left.title || "").localeCompare(
            String(right.title || ""), undefined, { sensitivity: "base" })
    })
    return result
}

function compareTasks(a, b, sortMode, paths) {
    var doneDelta = (a.done === true ? 1 : 0) - (b.done === true ? 1 : 0)
    if (doneDelta !== 0)
        return doneDelta
    var mode = sortMode || "smart"
    var aDue = dueTimestamp(a)
    var bDue = dueTimestamp(b)
    var aPriority = asId(a.priority)
    var bPriority = asId(b.priority)
    if (mode === "priority" && aPriority !== bPriority)
        return bPriority - aPriority
    if ((mode === "due" || mode === "smart") && aDue !== bDue) {
        if (!aDue) return 1
        if (!bDue) return -1
        return aDue - bDue
    }
    if (mode === "smart" && aPriority !== bPriority)
        return bPriority - aPriority
    if (mode === "project") {
        var projectDelta = String(paths[String(asId(a.project_id))] || "")
            .localeCompare(String(paths[String(asId(b.project_id))] || ""), undefined, { sensitivity: "base" })
        if (projectDelta !== 0)
            return projectDelta
    }
    if (mode === "updated") {
        var updatedDelta = Date.parse(b.updated || 0) - Date.parse(a.updated || 0)
        if (!isNaN(updatedDelta) && updatedDelta !== 0)
            return updatedDelta
    }
    return String(a.title || "").localeCompare(String(b.title || ""), undefined, { sensitivity: "base" })
}

function pathsById(projects) {
    var result = {}
    var list = toArray(projects)
    for (var i = 0; i < list.length; i++)
        result[String(asId(list[i].id))] = projectPath(list[i], projects)
    return result
}

function filterAndSortTasks(tasks, projects, options) {
    var opts = options || {}
    var excluded = excludedSet(projects, opts.excludedProjectIds)
    var activeProjects = asId(opts.projectId) > 0
        ? descendantIds(projects, opts.projectId) : null
    var paths = pathsById(projects)
    var activeLabel = asId(opts.labelId)
    var result = toArray(tasks).filter(function(task) {
        var projectId = String(asId(task.project_id))
        if (excluded[projectId]) return false
        if (activeProjects && !activeProjects[projectId]) return false
        if (!opts.showCompleted && task.done === true) return false
        if (activeLabel > 0 && labelIds(task).indexOf(activeLabel) === -1) return false
        return matchesTask(task, opts.query, paths)
    })
    result.sort(function(a, b) { return compareTasks(a, b, opts.sortMode, paths) })
    return result
}

function openCount(tasks, projects, excludedIds) {
    var excluded = excludedSet(projects, excludedIds)
    var count = 0
    var list = toArray(tasks)
    for (var i = 0; i < list.length; i++) {
        if (list[i].done !== true && !excluded[String(asId(list[i].project_id))])
            count++
    }
    return count
}

function dueCount(tasks, projects, excludedIds, now) {
    var excluded = excludedSet(projects, excludedIds)
    var count = 0
    var list = toArray(tasks)
    for (var i = 0; i < list.length; i++) {
        if (excluded[String(asId(list[i].project_id))])
            continue
        var state = dueState(list[i], now)
        if (state === "overdue" || state === "today")
            count++
    }
    return count
}

function labelCount(tasks, labelId, projects, excludedIds, showCompleted) {
    return filterAndSortTasks(tasks, projects, {
        labelId: labelId,
        excludedProjectIds: excludedIds,
        showCompleted: showCompleted === true,
        sortMode: "title"
    }).length
}

function notificationKey(task, kind) {
    return String(asId(task.id)) + "|" + String(task.due_date || "") + "|" + kind
}

function notificationCandidates(tasks, projects, excludedIds, now, leadMinutes, mode, graceMinutes) {
    var excluded = excludedSet(projects, excludedIds)
    var current = now || Date.now()
    var lead = Math.max(1, asId(leadMinutes)) * 60 * 1000
    var grace = Math.max(1, asId(graceMinutes || 60)) * 60 * 1000
    var result = []
    var list = toArray(tasks)
    for (var i = 0; i < list.length; i++) {
        var task = list[i]
        if (task.done === true || excluded[String(asId(task.project_id))])
            continue
        var due = dueTimestamp(task)
        if (!due)
            continue
        var delta = due - current
        var kind = ""
        if ((mode === "both" || mode === "due") && delta > 0 && delta <= lead)
            kind = "due"
        else if ((mode === "both" || mode === "overdue") && delta <= 0 && delta >= -grace)
            kind = "overdue"
        if (kind)
            result.push({ task: task, kind: kind, key: notificationKey(task, kind) })
    }
    return result
}

function labelColor(label) {
    var value = String(label && label.hex_color || "").replace(/^#/, "")
    return /^[0-9a-fA-F]{6}$/.test(value) ? "#" + value : ""
}
