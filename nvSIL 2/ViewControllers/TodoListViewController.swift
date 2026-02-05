import Cocoa

protocol TodoListViewControllerDelegate: AnyObject {
    func todoListDidSelectTodo(_ todo: TodoItem)
    func todoListDidClose()
}

class TodoListViewController: NSViewController {
    weak var delegate: TodoListViewControllerDelegate?

    private var outlineView: NSOutlineView!
    private var scrollView: NSScrollView!
    private var headerView: NSView!
    private var titleLabel: NSTextField!
    private var closeButton: NSButton!
    private var filterButton: NSPopUpButton!
    private var emptyStateLabel: NSTextField!

    private var groupedTodos: [(note: Note, todos: [TodoItem])] = []
    private var showCompleted: Bool = false  // Default to hiding completed TODOs

    override func loadView() {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 500))
        containerView.wantsLayer = true

        // Header
        headerView = NSView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = NSColor(calibratedWhite: 0.95, alpha: 1.0).cgColor

        titleLabel = NSTextField(labelWithString: "TODOs")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)

        closeButton = NSButton(title: "Close", target: self, action: #selector(closeClicked))
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.bezelStyle = .inline
        closeButton.font = NSFont.systemFont(ofSize: 11)

        filterButton = NSPopUpButton()
        filterButton.translatesAutoresizingMaskIntoConstraints = false
        filterButton.font = NSFont.systemFont(ofSize: 11)
        filterButton.addItems(withTitles: ["All Tasks", "Active Only"])
        filterButton.selectItem(at: 1)  // Default to "Active Only" (hide completed)
        filterButton.target = self
        filterButton.action = #selector(filterChanged)

        headerView.addSubview(titleLabel)
        headerView.addSubview(filterButton)
        headerView.addSubview(closeButton)

        // Outline view for todos
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true

        outlineView = NSOutlineView()
        outlineView.headerView = nil
        outlineView.rowHeight = 24
        outlineView.indentationPerLevel = 16
        outlineView.usesAlternatingRowBackgroundColors = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("TodoColumn"))
        column.width = 380
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        outlineView.delegate = self
        outlineView.dataSource = self

        scrollView.documentView = outlineView

        // Empty state label
        emptyStateLabel = NSTextField(labelWithString: "No TODOs found")
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.font = NSFont.systemFont(ofSize: 13)
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.alignment = .center
        emptyStateLabel.isHidden = true

        containerView.addSubview(headerView)
        containerView.addSubview(scrollView)
        containerView.addSubview(emptyStateLabel)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: containerView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            filterButton.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            filterButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            closeButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12),
            closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            emptyStateLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])

        self.view = containerView
    }

    func loadTodos(from notes: [Note]) {
        let allTodos = TodoParser.shared.parseAllTodos(from: notes)
        let filteredTodos = showCompleted ? allTodos : allTodos.filter { !$0.isCompleted }
        groupedTodos = TodoParser.shared.groupTodosByNote(filteredTodos)

        outlineView.reloadData()

        // Expand all groups
        for index in 0..<groupedTodos.count {
            outlineView.expandItem(index)
        }

        // Update title with count
        let totalCount = groupedTodos.reduce(0) { $0 + $1.todos.count }
        titleLabel.stringValue = "TODOs (\(totalCount))"

        // Show/hide empty state
        emptyStateLabel.isHidden = !groupedTodos.isEmpty
        scrollView.isHidden = groupedTodos.isEmpty
    }

    @objc private func closeClicked() {
        delegate?.todoListDidClose()
    }

    @objc private func filterChanged() {
        showCompleted = filterButton.indexOfSelectedItem == 0
        // Trigger reload - the parent controller should call loadTodos again
        NotificationCenter.default.post(name: .notesDidChange, object: nil)
    }
}

// MARK: - NSOutlineViewDataSource

extension TodoListViewController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return groupedTodos.count
        } else if let index = item as? Int {
            return groupedTodos[index].todos.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return item is Int
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return index
        } else if let parentIndex = item as? Int {
            return groupedTodos[parentIndex].todos[index]
        }
        return NSNull()
    }
}

// MARK: - NSOutlineViewDelegate

extension TodoListViewController: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("TodoCell")
        var cellView = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView

        if cellView == nil {
            cellView = NSTableCellView()
            cellView?.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            cellView?.addSubview(textField)
            cellView?.textField = textField

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor),
            ])
        }

        if let index = item as? Int {
            // Note header
            let group = groupedTodos[index]
            cellView?.textField?.stringValue = "\(group.note.title) (\(group.todos.count))"
            cellView?.textField?.font = NSFont.boldSystemFont(ofSize: 12)
            cellView?.textField?.textColor = .labelColor
        } else if let todo = item as? TodoItem {
            // Todo item
            let checkbox = todo.isCompleted ? "☑" : "☐"
            let priority = todo.priority.map { "(\($0.rawValue)) " } ?? ""
            var displayText = "\(checkbox) \(priority)\(todo.text)"

            // Add due date if present
            if let dueDate = todo.dueDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                displayText += " [due: \(formatter.string(from: dueDate))]"
            }

            cellView?.textField?.stringValue = displayText
            cellView?.textField?.font = NSFont.systemFont(ofSize: 11)

            // Style based on completion and due date
            if todo.isCompleted {
                cellView?.textField?.textColor = .secondaryLabelColor
            } else if let dueDate = todo.dueDate, dueDate < Date() {
                cellView?.textField?.textColor = .systemRed
            } else {
                cellView?.textField?.textColor = .labelColor
            }
        }

        return cellView
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let selectedItem = outlineView.item(atRow: outlineView.selectedRow)
        if let todo = selectedItem as? TodoItem {
            delegate?.todoListDidSelectTodo(todo)
        }
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        if item is Int {
            return 28 // Note header rows
        }
        return 22 // Todo item rows
    }
}
