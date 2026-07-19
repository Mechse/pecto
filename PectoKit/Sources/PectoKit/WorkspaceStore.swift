import Foundation

/// One entry in the flat task list. `path` is the filename (the workspace has
/// no folders). Parse failures still list the file, carrying `error` instead.
public struct TaskSummary: Equatable, Sendable, Identifiable {
    public let path: String
    public let name: String?
    public let description: String?
    public let placeholders: [String]
    public let error: String?

    public var id: String { path }

    public init(path: String, name: String? = nil, description: String? = nil, placeholders: [String] = [], error: String? = nil) {
        self.path = path
        self.name = name
        self.description = description
        self.placeholders = placeholders
        self.error = error
    }
}

/// File operations on a flat workspace folder of `.md` tasks.
/// Dotfiles and directories are ignored; the slug rule (no `/`) keeps it flat.
public struct WorkspaceStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    // MARK: - Listing

    public func listTasks() throws -> [TaskSummary] {
        let fileManager = FileManager.default
        let entries = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        )
        let taskFiles = entries
            .filter { url in
                let name = url.lastPathComponent
                guard name.hasSuffix(".md"), !name.hasPrefix(".") else { return false }
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile == true
            }
            .map(\.lastPathComponent)
            .sorted { $0.localizedCompare($1) == .orderedAscending }

        return taskFiles.map { path in
            do {
                let task = try parseTask(try readFile(path))
                return TaskSummary(
                    path: path,
                    name: task.frontmatter.name,
                    description: task.frontmatter.description,
                    placeholders: extractPlaceholders(task.instructions)
                )
            } catch let error as TaskParseError {
                return TaskSummary(path: path, error: error.message)
            } catch {
                return TaskSummary(path: path, error: "This file could not be read.")
            }
        }
    }

    // MARK: - Files

    public func readFile(_ path: String) throws -> String {
        let url = try resolve(path)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            throw TaskParseError("This file no longer exists.")
        }
        return content
    }

    public func writeFile(_ path: String, content: String) throws {
        guard path.hasSuffix(".md") else {
            throw TaskParseError("Only .md task files can be saved.")
        }
        let url = try resolve(path)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    public func loadTask(_ path: String) throws -> ParsedTask {
        try parseTask(try readFile(path))
    }

    // MARK: - Task lifecycle

    /// Creates `<path>` from the template and returns its content.
    @discardableResult
    public func createTask(_ path: String) throws -> String {
        guard path.hasSuffix(".md") else {
            throw TaskParseError("Task files end in .md.")
        }
        try assertSlug(String(path.dropLast(3)), what: "Task file names")
        let url = try resolve(path)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw TaskParseError("Something with that name already exists.")
        }
        let content = newTaskTemplate(name: String(path.dropLast(3)))
        try content.write(to: url, atomically: true, encoding: .utf8)
        return content
    }

    public func deleteTask(_ path: String) throws {
        guard path.hasSuffix(".md") else {
            throw TaskParseError("Only .md task files can be deleted.")
        }
        let url = try resolve(path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw TaskParseError("This file no longer exists.")
        }
        try FileManager.default.removeItem(at: url)
    }

    public func renameTask(from: String, to: String) throws {
        let fromURL = try resolve(from)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fromURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw TaskParseError("This file no longer exists.")
        }
        guard to.hasSuffix(".md") else {
            throw TaskParseError("Task files end in .md.")
        }
        try assertSlug(String(to.dropLast(3)), what: "Task file names")
        let toURL = try resolve(to)
        guard !FileManager.default.fileExists(atPath: toURL.path) else {
            throw TaskParseError("Something with that name already exists.")
        }
        try FileManager.default.moveItem(at: fromURL, to: toURL)
    }

    // MARK: - Internals

    private func resolve(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path).standardizedFileURL
        guard url.path == root.path || url.path.hasPrefix(root.path + "/") else {
            throw TaskParseError("That file is outside the workspace.")
        }
        return url
    }

    private func assertSlug(_ value: String, what: String) throws {
        guard isTaskSlug(value) else {
            throw TaskParseError("\(what) use lowercase letters, numbers and dashes (e.g. enrich-new-signups).")
        }
    }
}
