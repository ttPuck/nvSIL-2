import Foundation

struct TodoItem: Identifiable {
    let id: UUID
    let text: String
    let priority: Priority?
    let contexts: [String]
    let projects: [String]
    let dueDate: Date?
    let creationDate: Date?
    let completionDate: Date?
    let isCompleted: Bool
    let sourceNote: Note
    let lineNumber: Int
    let rawLine: String

    enum Priority: String, Comparable, CaseIterable {
        case A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z

        static func < (lhs: Priority, rhs: Priority) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }

    init(from line: String, sourceNote: Note, lineNumber: Int) {
        self.id = UUID()
        self.rawLine = line
        self.sourceNote = sourceNote
        self.lineNumber = lineNumber

        var workingLine = line.trimmingCharacters(in: .whitespaces)

        // Check completion status
        var completed = false

        // TODO.txt format: starts with "x "
        if workingLine.hasPrefix("x ") || workingLine.hasPrefix("X ") {
            completed = true
            workingLine = String(workingLine.dropFirst(2))
        }

        // Handle markdown checkbox format
        if workingLine.hasPrefix("- [x]") || workingLine.hasPrefix("- [X]") ||
           workingLine.hasPrefix("* [x]") || workingLine.hasPrefix("* [X]") {
            completed = true  // Markdown checked checkbox = completed
            workingLine = String(workingLine.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        } else if workingLine.hasPrefix("- [ ]") || workingLine.hasPrefix("* [ ]") ||
                  workingLine.hasPrefix("- []") || workingLine.hasPrefix("* []") {
            let dropCount = workingLine.hasPrefix("- [ ]") || workingLine.hasPrefix("* [ ]") ? 5 : 4
            workingLine = String(workingLine.dropFirst(dropCount)).trimmingCharacters(in: .whitespaces)
        }

        self.isCompleted = completed

        // Handle TODO: and FIXME: prefixes
        if workingLine.uppercased().hasPrefix("TODO:") {
            workingLine = String(workingLine.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        } else if workingLine.uppercased().hasPrefix("FIXME:") {
            workingLine = String(workingLine.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        }

        // Parse priority (A)-(Z)
        var parsedPriority: Priority? = nil
        let priorityPattern = #"^\(([A-Z])\)\s*"#
        if let regex = try? NSRegularExpression(pattern: priorityPattern),
           let match = regex.firstMatch(in: workingLine, range: NSRange(workingLine.startIndex..., in: workingLine)),
           let range = Range(match.range(at: 1), in: workingLine) {
            parsedPriority = Priority(rawValue: String(workingLine[range]))
            if let fullRange = Range(match.range, in: workingLine) {
                workingLine = workingLine.replacingCharacters(in: fullRange, with: "")
            }
        }
        self.priority = parsedPriority

        // Parse dates (YYYY-MM-DD format)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let datePattern = #"\d{4}-\d{2}-\d{2}"#
        var dates: [Date] = []
        if let regex = try? NSRegularExpression(pattern: datePattern) {
            let matches = regex.matches(in: workingLine, range: NSRange(workingLine.startIndex..., in: workingLine))
            for match in matches.prefix(2) {
                if let range = Range(match.range, in: workingLine),
                   let date = dateFormatter.date(from: String(workingLine[range])) {
                    dates.append(date)
                }
            }
        }

        // Assign completion and creation dates based on TODO.txt spec
        if completed && dates.count >= 1 {
            self.completionDate = dates[0]
            self.creationDate = dates.count >= 2 ? dates[1] : nil
        } else {
            self.completionDate = nil
            self.creationDate = dates.first
        }

        // Parse due date (due:YYYY-MM-DD)
        var parsedDueDate: Date? = nil
        let dueDatePattern = #"due:(\d{4}-\d{2}-\d{2})"#
        if let regex = try? NSRegularExpression(pattern: dueDatePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: workingLine, range: NSRange(workingLine.startIndex..., in: workingLine)),
           let range = Range(match.range(at: 1), in: workingLine) {
            parsedDueDate = dateFormatter.date(from: String(workingLine[range]))
        }
        self.dueDate = parsedDueDate

        // Parse contexts (@context)
        var parsedContexts: [String] = []
        let contextPattern = #"@(\S+)"#
        if let regex = try? NSRegularExpression(pattern: contextPattern) {
            let matches = regex.matches(in: workingLine, range: NSRange(workingLine.startIndex..., in: workingLine))
            for match in matches {
                if let range = Range(match.range(at: 1), in: workingLine) {
                    parsedContexts.append(String(workingLine[range]))
                }
            }
        }
        self.contexts = parsedContexts

        // Parse projects (+project)
        var parsedProjects: [String] = []
        let projectPattern = #"\+(\S+)"#
        if let regex = try? NSRegularExpression(pattern: projectPattern) {
            let matches = regex.matches(in: workingLine, range: NSRange(workingLine.startIndex..., in: workingLine))
            for match in matches {
                if let range = Range(match.range(at: 1), in: workingLine) {
                    parsedProjects.append(String(workingLine[range]))
                }
            }
        }
        self.projects = parsedProjects

        // Extract task text (remove metadata)
        var taskText = workingLine
        taskText = taskText.replacingOccurrences(of: #"\d{4}-\d{2}-\d{2}"#, with: "", options: .regularExpression)
        taskText = taskText.replacingOccurrences(of: #"@\S+"#, with: "", options: .regularExpression)
        taskText = taskText.replacingOccurrences(of: #"\+\S+"#, with: "", options: .regularExpression)
        taskText = taskText.replacingOccurrences(of: #"due:\S+"#, with: "", options: [.regularExpression, .caseInsensitive])
        taskText = taskText.trimmingCharacters(in: .whitespaces)
        // Clean up multiple spaces
        while taskText.contains("  ") {
            taskText = taskText.replacingOccurrences(of: "  ", with: " ")
        }
        self.text = taskText
    }
}

extension TodoItem: Hashable {
    static func == (lhs: TodoItem, rhs: TodoItem) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
