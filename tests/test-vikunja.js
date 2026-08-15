const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")
const path = require("node:path")

const source = fs.readFileSync(path.join(__dirname, "..", "JS", "vikunja.js"), "utf8")
    .replace(/^\.pragma library\s*/m, "")
const context = { console, Date }
vm.createContext(context)
vm.runInContext(source, context)

const projects = [
    { id: 1, title: "Work", parent_project_id: 0 },
    { id: 2, title: "Release", parent_project_id: 1 },
    { id: 3, title: "Home", parent_project_id: 0 }
]
const tasks = [
    { id: 10, project_id: 2, title: "Ship", priority: 4, done: false,
      due_date: "2026-08-05T18:00:00Z", labels: [{ id: 7, title: "urgent" }] },
    { id: 11, project_id: 3, title: "Water plants", priority: 1, done: false,
      due_date: "0001-01-01T00:00:00Z", labels: [], is_favorite: true },
    { id: 12, project_id: 1, title: "Closed", priority: 5, done: true,
      due_date: "2026-08-01T18:00:00Z", labels: [] }
]

assert.equal(context.projectPath(projects[1], projects), "Work › Release")
assert.equal(context.projectDepth(projects[1], projects), 1)
assert.deepEqual(Object.keys(context.descendantIds(projects, 1)).sort(), ["1", "2"])

const projectOptions = context.projectOptions(projects, false)
const releaseOption = projectOptions.find(option => option.id === 2)
assert.equal(releaseOption.title, "Release")
assert.equal(releaseOption.parentPath, "Work")
assert.deepEqual(
    Array.from(context.filterProjectOptions(projectOptions, "work"), option => option.id),
    [1, 2]
)
assert.deepEqual(
    Array.from(context.filterProjectOptions(projectOptions, "release"), option => option.id),
    [2]
)

let filtered = context.filterAndSortTasks(tasks, projects, {
    projectId: 1, showCompleted: false, sortMode: "smart"
})
assert.deepEqual(Array.from(filtered, task => task.id), [10])

filtered = context.filterAndSortTasks(tasks, projects, {
    labelId: 7, showCompleted: false, sortMode: "priority"
})
assert.deepEqual(Array.from(filtered, task => task.id), [10])

filtered = context.filterAndSortTasks(tasks, projects, {
    excludedProjectIds: [1], showCompleted: true, sortMode: "title"
})
assert.deepEqual(Array.from(filtered, task => task.id), [11])

filtered = context.filterAndSortTasks(tasks, projects, {
    viewPreset: "due", now: Date.parse("2026-08-05T17:00:00Z"),
    showCompleted: false, sortMode: "smart"
})
assert.deepEqual(Array.from(filtered, task => task.id), [10])

filtered = context.filterAndSortTasks(tasks, projects, {
    viewPreset: "favorites", showCompleted: false, sortMode: "title"
})
assert.deepEqual(Array.from(filtered, task => task.id), [11])

assert.equal(context.openCount(tasks, projects, [1]), 1)
assert.equal(context.labelCount(tasks, 7, projects, [], false), 1)

assert.equal(context.statusLabel(false, 0), "To do")
assert.equal(context.statusLabel(false, 0.3), "In progress · 30%")
assert.equal(context.statusLabel(true, 0.4), "Completed")
assert.equal(context.statusState("To do").done, false)
assert.equal(context.statusState("In progress · 75%").percentDone, 0.75)
assert.equal(context.statusState("Completed").done, true)

const parsed = context.parseDueInput("2026-08-05 17:30")
assert.equal(parsed.ok, true)
assert.match(parsed.value, /^2026-08-05T/)
assert.equal(context.parseDueInput("2026-02-30").ok, false)
assert.equal(context.parseDueInput("").value, context.ZERO_DATE)

const presetBase = new Date(2026, 7, 6, 12, 0, 0, 0)
assert.equal(context.duePresetInput("today", presetBase, ""), "2026-08-06 23:59")
assert.equal(context.duePresetInput("tomorrow", presetBase, ""), "2026-08-07 23:59")
assert.equal(context.duePresetInput("weekend", presetBase, ""), "2026-08-08 23:59")
assert.equal(context.duePresetInput("nextweek", presetBase, ""), "2026-08-10 23:59")
assert.equal(
    context.duePresetInput("nextweek", presetBase, "2026-08-09 14:35"),
    "2026-08-10 14:35"
)

assert.equal(
    context.plainText("<h2>Contexto</h2><ul><li><strong>Channel:</strong> Our Space 🔥</li><li>Proyecto: Personales</li></ul>"),
    "Contexto\n• Channel: Our Space 🔥\n• Proyecto: Personales"
)
assert.equal(context.plainText("Tom &amp; Jerry&nbsp;—&#32;ok"), "Tom & Jerry — ok")
assert.equal(context.plainText("Keep &#99999999; unchanged"), "Keep &#99999999; unchanged")
assert.equal(
    context.contentHtml("See https://example.com?a=1&b=2\nNext <step>"),
    "See <a href=\"https://example.com?a=1&amp;b=2\" target=\"_blank\" rel=\"noopener noreferrer\">https://example.com?a=1&amp;b=2</a><br>Next &lt;step&gt;"
)
assert.equal(
    context.plainText(context.contentHtml("See https://example.com\nNext")),
    "See https://example.com\nNext"
)

const labels = [
    { id: 2, title: "Seguimiento" },
    { id: 1, title: "Personal", description: "Casa" },
    { id: 3, title: "Urgente" }
]
assert.deepEqual(Array.from(context.filterLabels(labels, "per"), label => label.id), [1])
assert.deepEqual(Array.from(context.filterLabels(labels, ""), label => label.id), [1, 2, 3])

const candidates = context.notificationCandidates(
    tasks, projects, [], Date.parse("2026-08-05T17:30:00Z"), 60, "both", 60
)
assert.deepEqual(Array.from(candidates, entry => entry.task.id), [10])

console.log("vikunja.js tests passed")
