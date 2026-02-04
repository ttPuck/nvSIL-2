import Foundation

class TodoParser {
    static let shared = TodoParser()

    private init() {}

    // Patterns that indicate a TODO line
    private let todoPatterns: [(pattern: String, options: NSRegularExpression.Options)] = [
        (#"^x\s"#, [.caseInsensitive]),                    // Completed task (TODO.txt)
        (#"^\([A-Z]\)\s"#, []),                            // Priority task (TODO.txt)
        (#"^\d{4}-\d{2}-\d{2}\s"#, []),                    // Date-prefixed task
        (#"^-\s*\[\s*\]"#, []),                            // Markdown unchecked: - [ ]
        (#"^-\s*\[x\]"#, [.caseInsensitive]),              // Markdown checked: - [x]
        (#"^\*\s*\[\s*\]"#, []),                           // Markdown unchecked: * [ ]
        (#"^\*\s*\[x\]"#, [.caseInsensitive]),             // Markdown checked: * [x]
        (#"^TODO:\s"#, [.caseInsensitive]),                // TODO: prefix
        (#"^FIXME:\s"#, [.caseInsensitive]),               // FIXME: prefix
        (#"^HACK:\s"#, [.caseInsensitive]),                // HACK: prefix
        (#"^XXX:\s"#, [.caseInsensitive]),                 // XXX: prefix
    ]

    func parseTodos(from note: Note) -> [TodoItem] {
        let plainText = note.content.plainText()
        let lines = plainText.components(separatedBy: .newlines)

        var todos: [TodoItem] = []

        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if isTodoLine(trimmedLine) {
                let todo = TodoItem(from: trimmedLine, sourceNote: note, lineNumber: index + 1)
                todos.append(todo)
            }
        }

        return todos
    }

    func parseAllTodos(from notes: [Note]) -> [TodoItem] {
        return notes.flatMap { parseTodos(from: $0) }
    }

    func groupTodosByNote(_ todos: [TodoItem]) -> [(note: Note, todos: [TodoItem])] {
        var grouped: [UUID: (note: Note, todos: [TodoItem])] = [:]

        for todo in todos {
            let noteId = todo.sourceNote.id
            if grouped[noteId] == nil {
                grouped[noteId] = (note: todo.sourceNote, todos: [])
            }
            grouped[noteId]?.todos.append(todo)
        }

        return grouped.values
            .sorted { $0.note.title.localizedCaseInsensitiveCompare($1.note.title) == .orderedAscending }
    }

    func groupTodosByPriority(_ todos: [TodoItem]) -> [(priority: TodoItem.Priority?, todos: [TodoItem])] {
        var grouped: [String: (priority: TodoItem.Priority?, todos: [TodoItem])] = [:]

        for todo in todos {
            let key = todo.priority?.rawValue ?? "None"
            if grouped[key] == nil {
                grouped[key] = (priority: todo.priority, todos: [])
            }
            grouped[key]?.todos.append(todo)
        }

        return grouped.values.sorted { lhs, rhs in
            switch (lhs.priority, rhs.priority) {
            case (.some(let l), .some(let r)): return l < r
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return false
            }
        }
    }

    func groupTodosByProject(_ todos: [TodoItem]) -> [(project: String, todos: [TodoItem])] {
        var grouped: [String: [TodoItem]] = [:]

        for todo in todos {
            if todo.projects.isEmpty {
                if grouped["No Project"] == nil {
                    grouped["No Project"] = []
                }
                grouped["No Project"]?.append(todo)
            } else {
                for project in todo.projects {
                    if grouped[project] == nil {
                        grouped[project] = []
                    }
                    grouped[project]?.append(todo)
                }
            }
        }

        return grouped.map { (project: $0.key, todos: $0.value) }
            .sorted { $0.project.localizedCaseInsensitiveCompare($1.project) == .orderedAscending }
    }

    func filterTodos(_ todos: [TodoItem], showCompleted: Bool = true, priority: TodoItem.Priority? = nil) -> [TodoItem] {
        var filtered = todos

        if !showCompleted {
            filtered = filtered.filter { !$0.isCompleted }
        }

        if let priority = priority {
            filtered = filtered.filter { $0.priority == priority }
        }

        return filtered
    }

    func sortTodos(_ todos: [TodoItem], by sortMethod: TodoSortMethod) -> [TodoItem] {
        switch sortMethod {
        case .priority:
            return todos.sorted { lhs, rhs in
                switch (lhs.priority, rhs.priority) {
                case (.some(let l), .some(let r)): return l < r
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return lhs.text < rhs.text
                }
            }
        case .dueDate:
            return todos.sorted { lhs, rhs in
                switch (lhs.dueDate, rhs.dueDate) {
                case (.some(let l), .some(let r)): return l < r
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return lhs.text < rhs.text
                }
            }
        case .alphabetical:
            return todos.sorted { $0.text.localizedCaseInsensitiveCompare($1.text) == .orderedAscending }
        case .noteTitle:
            return todos.sorted { $0.sourceNote.title.localizedCaseInsensitiveCompare($1.sourceNote.title) == .orderedAscending }
        }
    }

    private func isTodoLine(_ line: String) -> Bool {
        for (pattern, options) in todoPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: options),
               regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                return true
            }
        }
        return false
    }
}

enum TodoSortMethod {
    case priority
    case dueDate
    case alphabetical
    case noteTitle
}
