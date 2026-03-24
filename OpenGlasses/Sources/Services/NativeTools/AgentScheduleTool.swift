import Foundation

/// Lets the agent manage its own scheduled tasks at runtime.
/// The agent can create, list, enable/disable, and delete tasks.
/// Tasks can call Shortcuts, run prompts, or check services.
///
/// This is how the agent self-improves: it discovers available
/// Shortcuts and creates scheduled tasks to check them periodically.
struct AgentScheduleTool: NativeTool {
    let name = "manage_schedule"
    let description = """
        Manage your own scheduled background tasks. You can:
        - List current tasks and their status
        - Create new scheduled tasks (prompts that run on an interval)
        - Enable or disable existing tasks
        - Delete tasks you no longer need

        Use this to set up recurring checks (email, messages, news), \
        periodic reminders, or any background work. Tasks run automatically \
        and only notify the user when there's something worth reporting.

        You can also create tasks that call Siri Shortcuts by including \
        "Run the shortcut 'ShortcutName'" in the prompt.
        """

    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "action": [
                "type": "string",
                "description": "What to do: 'list', 'create', 'enable', 'disable', 'delete'",
                "enum": ["list", "create", "enable", "disable", "delete"]
            ],
            "task_id": [
                "type": "string",
                "description": "Task ID (for enable/disable/delete)"
            ],
            "task_name": [
                "type": "string",
                "description": "Display name for new task (for create)"
            ],
            "task_prompt": [
                "type": "string",
                "description": "The prompt to run on each execution (for create). Include tool calls the agent should make."
            ],
            "interval_minutes": [
                "type": "number",
                "description": "How often to run, in minutes (for create). 0 = once daily."
            ],
            "speak_result": [
                "type": "boolean",
                "description": "Whether to speak the result to the user (for create). Default true."
            ]
        ],
        "required": ["action"]
    ]

    func execute(args: [String: Any]) async throws -> String {
        guard let action = args["action"] as? String else {
            return "Specify an action: list, create, enable, disable, delete"
        }

        var tasks = await MainActor.run { AgentScheduler.savedTasks() }

        switch action {
        case "list":
            if tasks.isEmpty {
                return "No scheduled tasks. Create one with action 'create'."
            }
            var lines: [String] = ["Scheduled tasks:"]
            for task in tasks {
                let status = task.enabled ? "enabled" : "disabled"
                let interval = task.intervalMinutes == 0 ? "once daily" : "every \(task.intervalMinutes) min"
                let lastRun = task.lastRun.map { "last ran \($0.formatted())" } ?? "never run"
                lines.append("- [\(task.id)] \(task.name) (\(status), \(interval), \(lastRun))")
            }
            return lines.joined(separator: "\n")

        case "create":
            guard let taskName = args["task_name"] as? String, !taskName.isEmpty else {
                return "Provide a task_name for the new task."
            }
            guard let prompt = args["task_prompt"] as? String, !prompt.isEmpty else {
                return "Provide a task_prompt — what should the agent do on each run?"
            }
            let interval = args["interval_minutes"] as? Int ?? 30
            let speak = args["speak_result"] as? Bool ?? true

            let id = taskName.lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .filter { $0.isLetter || $0.isNumber || $0 == "-" }

            let newTask = AgentScheduler.ScheduledTask(
                id: id,
                name: taskName,
                prompt: prompt,
                intervalMinutes: interval,
                enabled: true,
                speakResult: speak
            )

            tasks.append(newTask)
            await MainActor.run { AgentScheduler.saveTasks(tasks) }
            return "Created task '\(taskName)' (ID: \(id), every \(interval) min, speak: \(speak)). It will run on the next scheduler cycle."

        case "enable":
            guard let taskId = args["task_id"] as? String else {
                return "Provide the task_id to enable."
            }
            if let idx = tasks.firstIndex(where: { $0.id == taskId }) {
                tasks[idx].enabled = true
                await MainActor.run { AgentScheduler.saveTasks(tasks) }
                return "Enabled task '\(tasks[idx].name)'."
            }
            return "Task '\(taskId)' not found."

        case "disable":
            guard let taskId = args["task_id"] as? String else {
                return "Provide the task_id to disable."
            }
            if let idx = tasks.firstIndex(where: { $0.id == taskId }) {
                tasks[idx].enabled = false
                await MainActor.run { AgentScheduler.saveTasks(tasks) }
                return "Disabled task '\(tasks[idx].name)'."
            }
            return "Task '\(taskId)' not found."

        case "delete":
            guard let taskId = args["task_id"] as? String else {
                return "Provide the task_id to delete."
            }
            if let idx = tasks.firstIndex(where: { $0.id == taskId }) {
                let name = tasks[idx].name
                tasks.remove(at: idx)
                await MainActor.run { AgentScheduler.saveTasks(tasks) }
                return "Deleted task '\(name)'."
            }
            return "Task '\(taskId)' not found."

        default:
            return "Unknown action '\(action)'. Use: list, create, enable, disable, delete."
        }
    }
}
