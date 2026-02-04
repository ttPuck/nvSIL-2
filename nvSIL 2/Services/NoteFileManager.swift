
import Cocoa

class NoteFileManager {
    private let fileManager = FileManager.default
    private let supportedExtensions = ["rtf"]

    func readNote(from url: URL) throws -> Note {
        do {
            let rawContent = try String(contentsOf: url, encoding: .utf8)
            let title = url.deletingPathExtension().lastPathComponent
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let tags = readTags(from: url)
            let isPinned = readPinnedState(from: url)

            return Note(
                title: title,
                content: rawContent,
                fileURL: url,
                dateCreated: attributes[.creationDate] as? Date ?? Date(),
                dateModified: attributes[.modificationDate] as? Date ?? Date(),
                tags: tags,
                isPinned: isPinned
            )
        } catch {
            throw NoteError.fileReadFailed(url, error)
        }
    }

    func readPinnedState(from url: URL) -> Bool {
        guard let data = try? url.extendedAttribute(forName: "nvSIL.pinned"),
              let pinnedString = String(data: data, encoding: .utf8) else {
            return false
        }
        return pinnedString == "1"
    }

    func writeNote(_ note: Note) throws {
        do {
            // Save pin state before writing (atomic write may lose xattrs)
            let wasPinned = note.isPinned

            if let data = note.content.data(using: .utf8) {
                try data.write(to: note.fileURL, options: .atomic)
            } else {
                throw NoteError.fileWriteFailed(note.fileURL, NSError(domain: "NoteFileManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert content to data"]))
            }
            let now = Date()
            note.dateModified = now
            try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: note.fileURL.path)
            try writeTags(note.tags, to: note.fileURL)

            // Restore pin state after atomic write (which may have lost xattrs)
            if wasPinned {
                try writePinnedState(true, to: note.fileURL)
            }
        } catch {
            throw NoteError.fileWriteFailed(note.fileURL, error)
        }
    }

    func writePinnedState(_ isPinned: Bool, to url: URL) throws {
        let pinData = isPinned ? "1" : "0"
        guard let data = pinData.data(using: .utf8) else { return }
        try url.setExtendedAttribute(data: data, forName: "nvSIL.pinned")
    }

    func createNoteFile(in directory: URL, title: String, content: String) throws -> Note {
        let filename = sanitizeFilename(title) + ".rtf"
        var fileURL = directory.appendingPathComponent(filename)

        var counter = 1
        while fileManager.fileExists(atPath: fileURL.path) {
            if counter > 1000 { throw NoteError.tooManyDuplicates }
            let timestamp = DateFormatter.filenameSafe.string(from: Date())
            let uniqueFilename = "\(sanitizeFilename(title))-\(timestamp).rtf"
            fileURL = directory.appendingPathComponent(uniqueFilename)
            counter += 1
        }

        let attributedString = NSAttributedString(string: content)
        if let rtfData = try? attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) {
            try rtfData.write(to: fileURL, options: .atomic)
        } else {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        return try readNote(from: fileURL)
    }

    func deleteNoteFile(at url: URL) throws {
        do {
            var trashedURL: NSURL?
            try fileManager.trashItem(at: url, resultingItemURL: &trashedURL)
        } catch {
            throw NoteError.fileDeleteFailed(url, error)
        }
    }

    func renameNoteFile(_ note: Note, to newTitle: String) throws -> URL {
        let directory = note.fileURL.deletingLastPathComponent()
        let fileExtension = note.fileURL.pathExtension
        let newFilename = sanitizeFilename(newTitle) + "." + fileExtension
        var newURL = directory.appendingPathComponent(newFilename)

        if fileManager.fileExists(atPath: newURL.path) && newURL != note.fileURL {
            let timestamp = DateFormatter.filenameSafe.string(from: Date())
            let uniqueFilename = "\(sanitizeFilename(newTitle))-\(timestamp).\(fileExtension)"
            newURL = directory.appendingPathComponent(uniqueFilename)
        }

        // Read extended attributes BEFORE file operations (they may be lost during move/write)
        let tags = readTags(from: note.fileURL)
        let wasPinned = readPinnedState(from: note.fileURL)

        if newURL != note.fileURL {
            try fileManager.moveItem(at: note.fileURL, to: newURL)
        }

        let isRTF = fileExtension.lowercased() == "rtf"

        if isRTF {
            let bodyAttributedString = getBodyAttributedString(from: note.content)
            let titleAttributedString = NSMutableAttributedString(string: newTitle + "\n\n")
            titleAttributedString.append(bodyAttributedString)

            if let rtfData = try? titleAttributedString.data(
                from: NSRange(location: 0, length: titleAttributedString.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            ) {
                try rtfData.write(to: newURL, options: .atomic)
            }
        } else {
            let bodyContent = getBodyPlainText(from: note.content)
            let fullContent = newTitle + "\n\n" + bodyContent
            try fullContent.write(to: newURL, atomically: true, encoding: .utf8)
        }

        // Restore extended attributes after atomic write
        try writeTags(tags, to: newURL)
        if wasPinned {
            try writePinnedState(true, to: newURL)
        }

        return newURL
    }

    private func getBodyAttributedString(from content: String) -> NSAttributedString {
        return content.rtfAttributedString() ?? NSAttributedString(string: content)
    }

    private func getBodyPlainText(from content: String) -> String {
        return content.plainText()
    }

    func sanitizeFilename(_ title: String) -> String {
        let invalidCharacters: Set<Character> = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]
        var sanitized = title.map { invalidCharacters.contains($0) ? "-" : String($0) }.joined()
        sanitized = String(sanitized.prefix(255))
        return sanitized.isEmpty ? "untitled" : sanitized
    }

    func loadNotes(from directory: URL, includeSubfolders: Bool = false) throws -> [Note] {
        guard fileManager.fileExists(atPath: directory.path) else {
            throw NoteError.directoryNotAccessible(directory)
        }

        var notes: [Note] = []

        if includeSubfolders {
            // Recursive enumeration
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                throw NoteError.directoryNotAccessible(directory)
            }

            while let fileURL = enumerator.nextObject() as? URL {
                var isDirectory: ObjCBool = false
                fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory)

                if !isDirectory.boolValue && supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                    if var note = try? readNote(from: fileURL) {
                        note.parentFolderURL = fileURL.deletingLastPathComponent()
                        notes.append(note)
                    }
                }
            }
        } else {
            // Current folder only
            do {
                let fileURLs = try fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                )

                let noteFiles = fileURLs.filter { supportedExtensions.contains($0.pathExtension.lowercased()) }

                for fileURL in noteFiles {
                    if var note = try? readNote(from: fileURL) {
                        note.parentFolderURL = directory
                        notes.append(note)
                    }
                }
            } catch {
                throw NoteError.directoryNotAccessible(directory)
            }
        }

        return notes.sorted { $0.dateModified > $1.dateModified }
    }

    // MARK: - Folder Operations

    func discoverFolderHierarchy(from directory: URL, parent: Folder? = nil) throws -> Folder {
        let folder = Folder(name: directory.lastPathComponent, url: directory, parent: parent)

        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for item in contents {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory) && isDirectory.boolValue {
                let subfolder = try discoverFolderHierarchy(from: item, parent: folder)
                folder.subfolders.append(subfolder)
            }
        }

        folder.sortSubfolders()
        return folder
    }

    func createFolder(named name: String, in directory: URL) throws -> URL {
        let sanitizedName = sanitizeFilename(name)
        let folderURL = directory.appendingPathComponent(sanitizedName)

        if fileManager.fileExists(atPath: folderURL.path) {
            throw NSError(domain: "NoteFileManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "A folder with this name already exists"
            ])
        }

        // Note: Don't use isWritableFile() - it doesn't work with security-scoped bookmarks
        do {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: false, attributes: nil)
            return folderURL
        } catch let error as NSError {
            // Provide helpful error message for permission issues
            if error.code == NSFileWriteNoPermissionError || error.code == 513 {
                throw NSError(domain: "NoteFileManager", code: error.code, userInfo: [
                    NSLocalizedDescriptionKey: "Permission denied. Try using 'File > Change Notes Folder' to re-select your notes folder."
                ])
            }
            throw NSError(domain: "NoteFileManager", code: error.code, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create folder '\(sanitizedName)': \(error.localizedDescription)"
            ])
        }
    }

    func renameFolder(at url: URL, to newName: String) throws -> URL {
        let sanitizedName = sanitizeFilename(newName)
        let newURL = url.deletingLastPathComponent().appendingPathComponent(sanitizedName)

        if url == newURL {
            return url
        }

        if fileManager.fileExists(atPath: newURL.path) {
            throw NSError(domain: "NoteFileManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "A folder with this name already exists"
            ])
        }

        try fileManager.moveItem(at: url, to: newURL)
        return newURL
    }

    func deleteFolder(at url: URL) throws {
        var trashedURL: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &trashedURL)
    }

    func moveNote(_ note: Note, to destinationFolder: URL) throws -> URL {
        let fileName = note.fileURL.lastPathComponent
        var destinationURL = destinationFolder.appendingPathComponent(fileName)

        // Handle duplicate filenames
        if fileManager.fileExists(atPath: destinationURL.path) && destinationURL != note.fileURL {
            let baseName = note.fileURL.deletingPathExtension().lastPathComponent
            let ext = note.fileURL.pathExtension
            let timestamp = DateFormatter.filenameSafe.string(from: Date())
            destinationURL = destinationFolder.appendingPathComponent("\(baseName)-\(timestamp).\(ext)")
        }

        // Read extended attributes before move (they might be lost)
        let tags = readTags(from: note.fileURL)
        let isPinned = readPinnedState(from: note.fileURL)

        // Move the file
        try fileManager.moveItem(at: note.fileURL, to: destinationURL)

        // Restore extended attributes
        try writeTags(tags, to: destinationURL)
        if isPinned {
            try writePinnedState(true, to: destinationURL)
        }

        return destinationURL
    }

    func readTags(from url: URL) -> Set<String> {
        guard let data = try? url.extendedAttribute(forName: "nvSIL.tags"),
              let tagsString = String(data: data, encoding: .utf8) else {
            return []
        }
        return Set(tagsString.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty })
    }

    func writeTags(_ tags: Set<String>, to url: URL) throws {
        let tagsString = tags.sorted().joined(separator: ",")
        guard let data = tagsString.data(using: .utf8) else { return }
        try url.setExtendedAttribute(data: data, forName: "nvSIL.tags")
    }
}

// MARK: - URL Extended Attributes

extension URL {
    func extendedAttribute(forName name: String) throws -> Data {
        try self.withUnsafeFileSystemRepresentation { fileSystemPath -> Data in
            let length = getxattr(fileSystemPath, name, nil, 0, 0, 0)
            guard length >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            var data = Data(count: length)
            let result = data.withUnsafeMutableBytes { [count = data.count] in
                getxattr(fileSystemPath, name, $0.baseAddress, count, 0, 0)
            }
            guard result >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            return data
        }
    }

    func setExtendedAttribute(data: Data, forName name: String) throws {
        try self.withUnsafeFileSystemRepresentation { fileSystemPath in
            let result = data.withUnsafeBytes {
                setxattr(fileSystemPath, name, $0.baseAddress, data.count, 0, 0)
            }
            guard result >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        }
    }
}
