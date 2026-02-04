
import Cocoa
import UniformTypeIdentifiers

class MainViewController: NSViewController {
    private var searchField: NSSearchField!
    private var tabContainerView: TabContainerView!
    private var splitView: NSSplitView!
    private var noteListContainer: NSView!
    private var editorContainer: NSView!

    private var noteListViewController: NoteListViewController!
    private var editorViewController: EditorViewController!
    private var todoListViewController: TodoListViewController?
    private var currentSearchQuery = ""
    private var isUpdatingSearchFieldProgrammatically = false
    private var isUserActivelySearching = false  // True only when user types in search field
    private var isTodoViewVisible = false
    private var selectedSubfolder: Folder?

    override func loadView() {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        searchField = NSSearchField()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search or Create"

        // Create tab container view
        tabContainerView = TabContainerView()
        tabContainerView.translatesAutoresizingMaskIntoConstraints = false
        tabContainerView.delegate = self

        splitView = NSSplitView()
        splitView.isVertical = false  // false = vertical stacking (top/bottom)
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false

        noteListContainer = NSView()
        noteListContainer.translatesAutoresizingMaskIntoConstraints = false

        editorContainer = NSView()
        editorContainer.translatesAutoresizingMaskIntoConstraints = false

        splitView.addArrangedSubview(noteListContainer)
        splitView.addArrangedSubview(editorContainer)

        containerView.addSubview(searchField)
        containerView.addSubview(tabContainerView)
        containerView.addSubview(splitView)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            searchField.heightAnchor.constraint(equalToConstant: 32),

            tabContainerView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 4),
            tabContainerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            tabContainerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            tabContainerView.heightAnchor.constraint(equalToConstant: 32),

            splitView.topAnchor.constraint(equalTo: tabContainerView.bottomAnchor, constant: 4),
            splitView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            noteListContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
            noteListContainer.heightAnchor.constraint(equalToConstant: 300).withPriority(.defaultLow)
        ])

        self.view = containerView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupChildViewControllers()
        setupSearchField()
        setupNotifications()
        setupFolderObservers()
        setupSplitView()
        initializeTabContainer()
        loadNotes()
    }

    private func initializeTabContainer() {
        tabContainerView.setCurrentFolder(NoteManager.shared.currentFolder)
        restoreTabOrder()
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        if let fieldEditor = searchField.window?.fieldEditor(true, for: searchField) as? NSTextView {
            fieldEditor.isAutomaticTextCompletionEnabled = false
        }

        restoreSplitViewPosition()

        view.window?.setFrameAutosaveName("MainWindow")
    }

    private func setupSplitView() {
        splitView.delegate = self
    }

    private func restoreSplitViewPosition() {
        let savedPosition = Preferences.shared.splitViewDividerPosition
        let totalHeight = splitView.bounds.height

        if totalHeight > 0 && savedPosition > 0 && savedPosition < 1 {
            let dividerPosition = totalHeight * savedPosition
            splitView.setPosition(dividerPosition, ofDividerAt: 0)
        }
    }

    private func saveSplitViewPosition() {
        let totalHeight = splitView.bounds.height
        guard totalHeight > 0 else { return }

        let dividerPosition = noteListContainer.frame.height
        let proportion = dividerPosition / totalHeight
        Preferences.shared.splitViewDividerPosition = proportion
    }

    private func setupChildViewControllers() {
        noteListViewController = NoteListViewController()
        addChild(noteListViewController)
        noteListContainer.addSubview(noteListViewController.view)
        noteListViewController.view.frame = noteListContainer.bounds
        noteListViewController.view.autoresizingMask = [.width, .height]

        noteListViewController.onNoteSelected = { [weak self] note in
            self?.displayNote(note)
            if let note = note {
                self?.isUpdatingSearchFieldProgrammatically = true
                self?.searchField.stringValue = note.title
                self?.isUpdatingSearchFieldProgrammatically = false
            }
        }

        noteListViewController.onTagClicked = { [weak self] tag in
            self?.filterByTag(tag)
        }

        editorViewController = EditorViewController()
        addChild(editorViewController)
        editorContainer.addSubview(editorViewController.view)
        editorViewController.view.frame = editorContainer.bounds
        editorViewController.view.autoresizingMask = [.width, .height]

        editorViewController.onContentChanged = { [weak self] note, content in
            self?.saveNote(note, content: content)
        }

        editorViewController.onWikiLinkClicked = { [weak self] linkTarget in
            self?.navigateToOrCreateNote(titled: linkTarget)
        }
    }

    private func setupSearchField() {
        searchField.delegate = self


        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false

        searchField.isAutomaticTextCompletionEnabled = false
        if let fieldEditor = searchField.window?.fieldEditor(true, for: searchField) as? NSTextView {
            fieldEditor.isAutomaticTextCompletionEnabled = false
        }

        if let searchCell = searchField.cell as? NSSearchFieldCell {
            searchCell.cancelButtonCell?.target = self
            searchCell.cancelButtonCell?.action = #selector(clearSearch(_:))
        }
    }

    @objc private func clearSearch(_ sender: Any?) {
        searchField.stringValue = ""
        currentSearchQuery = ""
        isUserActivelySearching = false

        loadNotes()

        editorViewController.clearEditor()

        noteListViewController.selectNote(nil)
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(notesDidChange),
            name: .notesDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(noteWasUpdated(_:)),
            name: .noteWasUpdated,
            object: nil
        )
    }

    private func setupFolderObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(currentFolderDidChange),
            name: .currentFolderDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(folderStructureDidChange),
            name: .folderStructureDidChange,
            object: nil
        )
    }

    @objc private func currentFolderDidChange(_ notification: Notification) {
        tabContainerView.setCurrentFolder(NoteManager.shared.currentFolder)
        restoreTabOrder()
        selectedSubfolder = nil
        loadNotes()
    }

    @objc private func folderStructureDidChange(_ notification: Notification) {
        tabContainerView.displayedSubfolders = NoteManager.shared.currentSubfolders
    }

    private func loadNotes() {
        let allNotes = NoteManager.shared.notes

        // Filter notes based on current folder selection
        let filteredNotes: [Note]
        if let subfolder = selectedSubfolder {
            // Show notes from selected subfolder
            filteredNotes = allNotes.filter { $0.parentFolderURL == subfolder.url }
        } else if let currentFolder = NoteManager.shared.currentFolder {
            // Show notes from current folder only (not subfolders)
            filteredNotes = allNotes.filter { $0.parentFolderURL == currentFolder.url }
        } else {
            filteredNotes = allNotes
        }

        noteListViewController?.updateNotes(filteredNotes)

        // Update TODO view if visible
        if isTodoViewVisible {
            todoListViewController?.loadTodos(from: filteredNotes)
        }
    }

    @objc private func notesDidChange() {
        // Only filter if user is actively searching, otherwise show all notes
        if isUserActivelySearching && !currentSearchQuery.isEmpty {
            performSearch()
        } else {
            loadNotes()
        }
    }

    @objc private func noteWasUpdated(_ notification: Notification) {
        // If a note was renamed and it's currently selected, update the search field
        guard let updatedNote = notification.userInfo?["note"] as? Note,
              let selectedNote = noteListViewController.selectedNote,
              updatedNote.id == selectedNote.id else {
            return
        }
        // Update search field with new note title (but don't trigger filtering)
        isUpdatingSearchFieldProgrammatically = true
        searchField.stringValue = updatedNote.title
        isUpdatingSearchFieldProgrammatically = false
    }

    private func performSearch() {
        let query = currentSearchQuery.lowercased()
        let notes = NoteManager.shared.notes

        if query.isEmpty {
            noteListViewController.updateNotes(notes)
            return
        }

        if query.hasPrefix("#") {
            let tagQuery = String(query.dropFirst())
            let filtered: [Note]
            if tagQuery.isEmpty {
                // If just "#", show all notes that have any tags
                filtered = notes.filter { !$0.tags.isEmpty }
            } else {
                // Otherwise, filter by tag content
                filtered = notes.filter { note in
                    note.tags.contains { $0.lowercased().contains(tagQuery) }
                }
            }
            noteListViewController.filterNotes(filtered, searchQuery: "")
            return
        }

        let filtered = notes.filter { note in
            note.title.lowercased().contains(query) ||
            note.content.lowercased().contains(query) ||
            note.tags.contains { $0.lowercased().contains(query) }
        }

        noteListViewController.filterNotes(filtered, searchQuery: currentSearchQuery)
    }

    private func filterByTag(_ tag: String) {
        isUpdatingSearchFieldProgrammatically = true
        searchField.stringValue = "#\(tag)"
        isUpdatingSearchFieldProgrammatically = false
        currentSearchQuery = "#\(tag)"
        performSearch()
    }

    private func displayNote(_ note: Note?) {
        editorViewController.displayNote(note)
    }

    private func saveNote(_ note: Note, content: String) {
        NoteManager.shared.updateNote(note, content: content)
    }

    private func navigateToOrCreateNote(titled title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }

        if let existingNote = NoteManager.shared.notes.first(where: { $0.title.lowercased() == trimmedTitle.lowercased() }) {
            // Navigate to existing note
            noteListViewController.selectNote(existingNote)
            displayNote(existingNote)
        } else {
            if let newNote = NoteManager.shared.createNote(withTitle: trimmedTitle, content: "") {
                noteListViewController.selectNote(newNote)
                displayNote(newNote)
                // Focus editor for immediate editing
                view.window?.makeFirstResponder(editorViewController.textView)
            }
        }

        isUpdatingSearchFieldProgrammatically = true
        searchField.stringValue = trimmedTitle
        isUpdatingSearchFieldProgrammatically = false
    }

    private func createNoteFromSearch() {
        let title = currentSearchQuery.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

        if let note = NoteManager.shared.createNote(withTitle: title, content: "") {
            noteListViewController.selectNote(note)
            displayNote(note)
            view.window?.makeFirstResponder(editorViewController.textView)
        }
    }
}

extension MainViewController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let searchField = obj.object as? NSSearchField else { return }

        guard !isUpdatingSearchFieldProgrammatically else { return }

        // User is actively typing in the search field
        isUserActivelySearching = true
        currentSearchQuery = searchField.stringValue
        performSearch()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textMovement = obj.userInfo?["NSTextMovement"] as? Int,
              textMovement == NSReturnTextMovement else { return }

        let query = currentSearchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }

        let titleMatch = NoteManager.shared.notes.first { $0.title.lowercased() == query.lowercased() }

        if let match = titleMatch {
            noteListViewController?.selectNote(match)
        } else {
            createNoteFromSearch()
        }
    }
}

extension MainViewController {
    var filteredNotes: [Note] {
        return noteListViewController?.filteredNotes ?? []
    }
}

extension MainViewController {
    @IBAction func renameSelectedNote(_ sender: Any?) {
        guard noteListViewController?.selectedNote != nil else { return }
        noteListViewController.startRenamingSelectedNote()
    }

    @IBAction func tagSelectedNote(_ sender: Any?) {
        guard noteListViewController?.selectedNote != nil else { return }
        noteListViewController.startEditingTagsForSelectedNote()
    }

    @IBAction func deleteSelectedNote(_ sender: Any?) {
        guard let note = noteListViewController?.selectedNote else { return }

        if Preferences.shared.confirmNoteDeletion {
            let alert = NSAlert()
            alert.messageText = "Delete Note"
            alert.informativeText = "Are you sure you want to delete \"\(note.title)\"? This cannot be undone."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")

            if alert.runModal() == .alertFirstButtonReturn {
                NoteManager.shared.deleteNote(note)
            }
        } else {
            NoteManager.shared.deleteNote(note)
        }
    }

    @IBAction func focusSearchField(_ sender: Any?) {
        view.window?.makeFirstResponder(searchField)
    }

    @IBAction func importNote(_ sender: Any?) {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.rtf]
        openPanel.allowsMultipleSelection = true
        openPanel.message = "Select notes to import"

        guard openPanel.runModal() == .OK else { return }

        for url in openPanel.urls {
            guard let notesDir = NoteManager.shared.notesDirectory else { continue }
            let destURL = notesDir.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.copyItem(at: url, to: destURL)
        }

        try? NoteManager.shared.reloadNotes()
    }

    @IBAction func exportSelectedNote(_ sender: Any?) {
        guard let note = noteListViewController?.selectedNote else { return }

        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = note.fileName
        savePanel.allowedContentTypes = [.rtf]
        savePanel.canSelectHiddenExtension = true

        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try FileManager.default.copyItem(at: note.fileURL, to: url)
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }

    @IBAction func exportAllNotesToZip(_ sender: Any?) {
        guard NoteManager.shared.notesDirectory != nil else {
            let alert = NSAlert()
            alert.messageText = "No Notes Folder"
            alert.informativeText = "Please select a notes folder first."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        let notes = NoteManager.shared.notes
        guard !notes.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No Notes"
            alert.informativeText = "There are no notes to export."
            alert.alertStyle = .informational
            alert.runModal()
            return
        }

        let savePanel = NSSavePanel()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        savePanel.nameFieldStringValue = "nvSIL-export-\(dateString).zip"
        savePanel.allowedContentTypes = [UTType.zip]
        savePanel.canSelectHiddenExtension = true

        guard savePanel.runModal() == .OK, let zipURL = savePanel.url else { return }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            for note in notes {
                let destURL = tempDir.appendingPathComponent(note.fileURL.lastPathComponent)
                try FileManager.default.copyItem(at: note.fileURL, to: destURL)
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", tempDir.path, zipURL.path]

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let alert = NSAlert()
                alert.messageText = "Export Complete"
                alert.informativeText = "Successfully exported \(notes.count) notes to ZIP archive."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: "Show in Finder")
                if alert.runModal() == .alertSecondButtonReturn {
                    NSWorkspace.shared.activateFileViewerSelecting([zipURL])
                }
            } else {
                throw NSError(domain: "nvSIL", code: Int(process.terminationStatus), userInfo: [
                    NSLocalizedDescriptionKey: "Failed to create ZIP archive"
                ])
            }

            try? FileManager.default.removeItem(at: tempDir)

        } catch {
            try? FileManager.default.removeItem(at: tempDir)

            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    @IBAction func showSelectedNoteInFinder(_ sender: Any?) {
        guard let note = noteListViewController?.selectedNote else { return }
        NSWorkspace.shared.activateFileViewerSelecting([note.fileURL])
    }

    @IBAction func openWithDefaultEditor(_ sender: Any?) {
        guard let note = noteListViewController?.selectedNote else { return }
        NSWorkspace.shared.open(note.fileURL)
    }

    @IBAction func openWithTextEdit(_ sender: Any?) {
        guard let note = noteListViewController?.selectedNote else { return }
        if let textEditURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            NSWorkspace.shared.open([note.fileURL], withApplicationAt: textEditURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    @IBAction func openWithOther(_ sender: Any?) {
        guard let note = noteListViewController?.selectedNote else { return }

        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.directoryURL = URL(fileURLWithPath: "/Applications")
        openPanel.allowedContentTypes = [.application]
        openPanel.message = "Choose an application to open the note with"

        if openPanel.runModal() == .OK, let appURL = openPanel.url {
            NSWorkspace.shared.open([note.fileURL], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    @IBAction func printSelectedNote(_ sender: Any?) {
        guard let note = noteListViewController?.selectedNote else { return }

        let fullContent: NSAttributedString
        if let bodyAttrString = note.content.rtfAttributedString() {
            let titleAttr = NSMutableAttributedString(string: note.title + "\n\n", attributes: [
                .font: NSFont.boldSystemFont(ofSize: 14)
            ])
            titleAttr.append(bodyAttrString)
            fullContent = titleAttr
        } else {
            fullContent = NSAttributedString(string: note.title + "\n\n" + note.content, attributes: [
                .font: NSFont.systemFont(ofSize: 12)
            ])
        }

        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        printInfo.leftMargin = 72
        printInfo.rightMargin = 72
        printInfo.topMargin = 72
        printInfo.bottomMargin = 72

        let pageWidth = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        let pageHeight = printInfo.paperSize.height - printInfo.topMargin - printInfo.bottomMargin

        let textStorage = NSTextStorage(attributedString: fullContent)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(containerSize: NSSize(width: pageWidth, height: .greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let printView = NSTextView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        printView.layoutManager?.replaceTextStorage(textStorage)

        let printTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: 10000))
        printTextView.isEditable = false
        printTextView.isSelectable = false
        printTextView.textStorage?.setAttributedString(fullContent)
        printTextView.textContainer?.containerSize = NSSize(width: pageWidth, height: .greatestFiniteMagnitude)
        printTextView.textContainer?.widthTracksTextView = true
        printTextView.sizeToFit()

        printTextView.layoutManager?.ensureLayout(for: printTextView.textContainer!)

        let printOperation = NSPrintOperation(view: printTextView, printInfo: printInfo)
        printOperation.showsPrintPanel = true
        printOperation.showsProgressPanel = true
        printOperation.runModal(for: view.window!, delegate: nil, didRun: nil, contextInfo: nil)
    }

    @IBAction func selectNextNote(_ sender: Any?) {
        noteListViewController?.selectNextNote()
    }

    @IBAction func selectPreviousNote(_ sender: Any?) {
        noteListViewController?.selectPreviousNote()
    }

    @IBAction func deselectNote(_ sender: Any?) {
        noteListViewController?.selectNote(nil)
        loadNotes()
        editorViewController?.clearEditor()
    }

    @IBAction func pasteAsNewNote(_ sender: Any?) {
        guard let pasteboard = NSPasteboard.general.string(forType: .string),
              !pasteboard.isEmpty else { return }

        // Use first line as title, or first 50 chars
        let lines = pasteboard.components(separatedBy: .newlines)
        let firstLine = lines.first ?? ""
        let title = firstLine.isEmpty ? String(pasteboard.prefix(50)) : String(firstLine.prefix(100))

        if let note = NoteManager.shared.createNote(withTitle: title, content: pasteboard) {
            noteListViewController?.selectNote(note)
        }
    }

    @IBAction func togglePinSelectedNote(_ sender: Any?) {
        guard let note = noteListViewController?.selectedNote else { return }
        NoteManager.shared.togglePinNote(note)
        loadNotes()
        noteListViewController?.selectNote(note)
    }

    @IBAction func indentText(_ sender: Any?) {
        editorViewController?.indentText(sender)
    }

    @IBAction func outdentText(_ sender: Any?) {
        editorViewController?.outdentText(sender)
    }
}

extension NSLayoutConstraint {
    func withPriority(_ priority: NSLayoutConstraint.Priority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}

extension MainViewController: NSSplitViewDelegate {
    func splitViewDidResizeSubviews(_ notification: Notification) {
        saveSplitViewPosition()
    }
}

// MARK: - TabContainerViewDelegate

extension MainViewController: TabContainerViewDelegate {
    func tabContainer(_ container: TabContainerView, didSelectFolder folder: Folder?) {
        selectedSubfolder = folder
        hideTodoView()
        loadNotes()
    }

    func tabContainer(_ container: TabContainerView, didNavigateIntoFolder folder: Folder) {
        selectedSubfolder = nil
        NoteManager.shared.setCurrentFolder(folder)
    }

    func tabContainer(_ container: TabContainerView, didRequestNewSubfolderIn parent: Folder?) {
        let alert = NSAlert()
        alert.messageText = "New Folder"
        alert.informativeText = "Enter a name for the new folder:"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.stringValue = "New Folder"
        alert.accessoryView = textField

        if alert.runModal() == .alertFirstButtonReturn {
            let folderName = textField.stringValue.trimmingCharacters(in: .whitespaces)
            if !folderName.isEmpty {
                do {
                    _ = try NoteManager.shared.createSubfolder(named: folderName, in: parent)
                    tabContainerView.displayedSubfolders = NoteManager.shared.currentSubfolders
                } catch {
                    let errorAlert = NSAlert(error: error)
                    errorAlert.runModal()
                }
            }
        }
    }

    func tabContainer(_ container: TabContainerView, didRequestRenameFolder folder: Folder) {
        let alert = NSAlert()
        alert.messageText = "Rename Folder"
        alert.informativeText = "Enter a new name for '\(folder.name)':"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.stringValue = folder.name
        alert.accessoryView = textField

        if alert.runModal() == .alertFirstButtonReturn {
            let newName = textField.stringValue.trimmingCharacters(in: .whitespaces)
            if !newName.isEmpty && newName != folder.name {
                do {
                    try NoteManager.shared.renameFolder(folder, to: newName)
                    tabContainerView.displayedSubfolders = NoteManager.shared.currentSubfolders
                } catch {
                    let errorAlert = NSAlert(error: error)
                    errorAlert.runModal()
                }
            }
        }
    }

    func tabContainer(_ container: TabContainerView, didRequestDeleteFolder folder: Folder) {
        let alert = NSAlert()
        alert.messageText = "Delete Folder"
        alert.informativeText = "Are you sure you want to delete '\(folder.name)'? All notes inside will also be deleted."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            do {
                try NoteManager.shared.deleteFolder(folder)
                tabContainerView.displayedSubfolders = NoteManager.shared.currentSubfolders
            } catch {
                let errorAlert = NSAlert(error: error)
                errorAlert.runModal()
            }
        }
    }

    func tabContainer(_ container: TabContainerView, didReceiveDroppedNoteID noteID: String, onFolder folder: Folder) {
        guard let noteUUID = UUID(uuidString: noteID),
              let note = NoteManager.shared.notes.first(where: { $0.id == noteUUID }) else {
            return
        }

        // Don't move if note is already in target folder
        if note.parentFolderURL == folder.url {
            return
        }

        do {
            try NoteManager.shared.moveNote(note, to: folder)
            // Force reload notes from NoteManager to reflect the move
            try? NoteManager.shared.reloadNotes()
            loadNotes()
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    func tabContainerDidSelectTodoTab(_ container: TabContainerView) {
        if isTodoViewVisible {
            hideTodoView()
        } else {
            showTodoView()
        }
    }

    func tabContainer(_ container: TabContainerView, didReorderFolder folder: Folder, toIndex index: Int) {
        // Update the folder order in the parent folder or root
        if let currentFolder = NoteManager.shared.currentFolder {
            // Reorder subfolders to match the displayed order
            currentFolder.subfolders = container.displayedSubfolders
        }

        // Persist the tab order
        saveTabOrder()
    }

    private func saveTabOrder() {
        guard let currentFolder = NoteManager.shared.currentFolder else { return }

        // Store the order as folder URLs relative to the notes directory
        let orderedPaths = currentFolder.subfolders.map { $0.url.path }
        let key = "tabOrder:\(currentFolder.url.path)"
        UserDefaults.standard.set(orderedPaths, forKey: key)
    }

    private func restoreTabOrder() {
        guard let currentFolder = NoteManager.shared.currentFolder else { return }

        let key = "tabOrder:\(currentFolder.url.path)"
        guard let orderedPaths = UserDefaults.standard.stringArray(forKey: key) else { return }

        // Sort subfolders based on saved order
        var sorted: [Folder] = []
        for path in orderedPaths {
            if let folder = currentFolder.subfolders.first(where: { $0.url.path == path }) {
                sorted.append(folder)
            }
        }

        // Append any new folders not in saved order
        for folder in currentFolder.subfolders {
            if !sorted.contains(where: { $0.id == folder.id }) {
                sorted.append(folder)
            }
        }

        currentFolder.subfolders = sorted
        tabContainerView.displayedSubfolders = sorted
    }

    private func showTodoView() {
        isTodoViewVisible = true

        if todoListViewController == nil {
            todoListViewController = TodoListViewController()
            todoListViewController?.delegate = self
        }

        // Hide note list, show todo list
        noteListViewController.view.isHidden = true

        addChild(todoListViewController!)
        noteListContainer.addSubview(todoListViewController!.view)
        todoListViewController!.view.frame = noteListContainer.bounds
        todoListViewController!.view.autoresizingMask = [.width, .height]

        // Load todos from currently displayed notes
        let notes: [Note]
        if let subfolder = selectedSubfolder {
            notes = NoteManager.shared.notes.filter { $0.parentFolderURL == subfolder.url }
        } else if let currentFolder = NoteManager.shared.currentFolder {
            notes = NoteManager.shared.notes.filter { $0.parentFolderURL == currentFolder.url }
        } else {
            notes = NoteManager.shared.notes
        }
        todoListViewController?.loadTodos(from: notes)
    }

    private func hideTodoView() {
        guard isTodoViewVisible else { return }
        isTodoViewVisible = false

        todoListViewController?.view.removeFromSuperview()
        todoListViewController?.removeFromParent()

        noteListViewController.view.isHidden = false
        tabContainerView.deselectTodo()
    }
}

// MARK: - TodoListViewControllerDelegate

extension MainViewController: TodoListViewControllerDelegate {
    func todoListDidSelectTodo(_ todo: TodoItem) {
        // Navigate to the source note
        hideTodoView()
        noteListViewController.selectNote(todo.sourceNote)
        displayNote(todo.sourceNote)

        // Update search field with note title
        isUpdatingSearchFieldProgrammatically = true
        searchField.stringValue = todo.sourceNote.title
        isUpdatingSearchFieldProgrammatically = false
    }

    func todoListDidClose() {
        hideTodoView()
    }
}

