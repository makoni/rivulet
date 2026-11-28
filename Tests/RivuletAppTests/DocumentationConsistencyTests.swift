import ConsoleKit
import Foundation
import Testing
@testable import RivuletApp

/// The user-facing documents against the code they describe: every `rivulet` command they show is a
/// registered command, every flag they pass is one that command declares, every environment
/// variable they set is one the configuration reads, and every public declaration in the sources
/// carries a documentation comment.
@Suite struct DocumentationConsistencyTests {
    /// The repository root, three levels above this file (`Tests/RivuletAppTests/<file>`).
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The documents an operator follows: the README, the deployment and backup guides, the DocC
    /// catalog, and the deployment examples.
    private static func userDocuments() throws -> [(path: String, text: String)] {
        let fixed = ["README.md", "docs/deploy.md", "docs/backup-restore.md", ".env.example",
                     "deploy/compose.yml", "deploy/rivulet.service"]
        let catalog = try files(under: "Sources/RivuletCore/RivuletCore.docc") {
            $0.hasSuffix(".tutorial") || $0.hasSuffix(".md")
        }
        return try (fixed + catalog).map { ($0, try text($0)) }
    }

    @Test func everyCommandTheDocumentsShowIsRegistered() throws {
        let registered = Set(Self.commands().keys)
        let shown = try Self.userDocuments().flatMap { Self.invocations(in: $0.text) }
        #expect(shown.count > 20, "the scan found almost no `rivulet` invocations: \(shown.count)")
        var unknown: [String] = []
        for document in try Self.userDocuments() {
            for invocation in Self.invocations(in: document.text) where !registered.contains(invocation.command) {
                unknown.append("\(document.path): rivulet \(invocation.command)")
            }
        }
        #expect(unknown.isEmpty, "commands the documents show but the CLI does not register: \(unknown)")
    }

    @Test func everyFlagTheDocumentsPassIsDeclaredByItsCommand() throws {
        let commands = Self.commands()
        var unknown: [String] = []
        for document in try Self.userDocuments() {
            for invocation in Self.invocations(in: document.text) {
                guard let command = commands[invocation.command] else { continue }
                let declared = Self.declaredNames(of: command)
                    .union(invocation.command == "serve" ? Self.servePassThrough : [])
                for flag in invocation.flags where !declared.contains(flag) && flag != "help" {
                    unknown.append("\(document.path): rivulet \(invocation.command) --\(flag)")
                }
            }
        }
        #expect(unknown.isEmpty, "flags the documents pass that the command does not declare: \(unknown)")
    }

    @Test func everyVariableTheDocumentsSetIsReadByTheConfiguration() throws {
        let read = try Self.configurationNames()
        #expect(read.contains("DATABASE_URL"), "the configuration scan found no names: \(read)")
        var unknown: [String] = []
        for document in try Self.userDocuments() {
            for name in Self.matches(#"(?m)(?:^|[\s`])([A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+)="#, in: document.text)
            where !read.contains(name) {
                unknown.append("\(document.path): \(name)")
            }
        }
        #expect(unknown.isEmpty, "variables the documents set that the configuration does not read: \(unknown)")
    }

    @Test func theReadmeConfigurationTableIsEveryVariableTheConfigurationReads() throws {
        let read = try Self.configurationNames()
        let table = Set(Self.matches(#"(?m)^\| `([A-Z][A-Z0-9_]+)` \|"#, in: try Self.text("README.md")))
        let extra = table.subtracting(read).sorted(), missing = read.subtracting(table).sorted()
        #expect(table == read, "README lists \(extra) the configuration does not read, and misses \(missing)")
    }

    @Test func everyPublicDeclarationHasADocumentationComment() throws {
        let modifiers = "((final|static|class|mutating|nonisolated|override|convenience|required"
            + "|indirect|lazy|dynamic)\\s+)*"
        let kinds = "(struct|enum|class|actor|protocol|func|typealias|var|let|init|subscript)"
        let attributes = "(@[A-Za-z]+(\\([^)]*\\))?\\s+)*"
        let declaration = try Regex("^\\s*\(attributes)(public|open)\\s+\(modifiers)\(kinds)\\b")
        var missing: [String] = []
        for path in try Self.files(under: "Sources", where: { $0.hasSuffix(".swift") }) {
            let lines = try Self.text(path).split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() where line.contains(declaration) {
                var above = index - 1
                while above >= 0, lines[above].trimmingCharacters(in: .whitespaces).hasPrefix("@") { above -= 1 }
                if above < 0 || !lines[above].trimmingCharacters(in: .whitespaces).hasPrefix("///") {
                    missing.append("\(path):\(index + 1)")
                }
            }
        }
        #expect(missing.isEmpty, "public declarations without a documentation comment: \(missing)")
    }

    // MARK: - Reads

    /// The flags `serve` hands to Vapor's own serve command rather than declaring them itself
    /// (see `Serve.swift`).
    private static let servePassThrough: Set<String> = ["hostname", "port", "bind", "unix-socket"]

    private static func commands() -> [String: any AnyAsyncCommand] {
        RivuletCLI.makeCommandGroup(environment: [:]).commands
    }

    /// The option and flag names a command's signature declares, read from its property wrappers.
    private static func declaredNames(of command: any AnyAsyncCommand) -> Set<String> {
        guard let command = command as? any AsyncCommand else { return [] }
        return signatureNames(command)
    }

    private static func signatureNames<C: AsyncCommand>(_: C) -> Set<String> {
        var names: Set<String> = []
        for child in Mirror(reflecting: C.Signature()).children {
            let value = Mirror(reflecting: child.value)
            let type = String(describing: value.subjectType)
            guard type.hasPrefix("Option<") || type == "Flag" else { continue }
            if let name = value.children.first(where: { $0.label == "name" })?.value as? String {
                names.insert(name)
            }
        }
        return names
    }

    /// Each `rivulet <command>` the text shows, with the `--flags` that follow it on the same line. In
    /// a table row (the README's command table) every flag the row names belongs to its command.
    private static func invocations(in text: String) -> [(command: String, flags: [String])] {
        text.split(separator: "\n").flatMap { line -> [(command: String, flags: [String])] in
            let parts = line.split(separator: "rivulet ", omittingEmptySubsequences: false).dropFirst()
            let isTableRow = line.hasPrefix("|")
            return parts.compactMap { part in
                guard let command = matches(#"^([a-z][a-z-]*[a-z])\b"#, in: String(part)).first else { return nil }
                let rest = isTableRow ? String(part) : String(part.prefix { $0 != "`" && $0 != "|" })
                return (command, matches(#"(?:^|[\s`])--([a-z][a-z-]*)"#, in: rest))
            }
        }
    }

    /// The variable names the configuration sources read: `environment["NAME"]` and `variable: "NAME"`.
    private static func configurationNames() throws -> Set<String> {
        var names: Set<String> = []
        for path in try files(under: "Sources/RivuletCore/Config", where: { $0.hasSuffix(".swift") }) {
            let source = try text(path)
            names.formUnion(matches(#"environment\["([A-Z0-9_]+)"\]"#, in: source))
            names.formUnion(matches(#"variable: "([A-Z0-9_]+)""#, in: source))
        }
        return names
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    private static func text(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private static func files(under directory: String, where keep: (String) -> Bool) throws -> [String] {
        let base = root.appendingPathComponent(directory)
        guard let walker = FileManager.default.enumerator(atPath: base.path) else { return [] }
        return walker.compactMap { $0 as? String }.filter(keep).sorted().map { "\(directory)/\($0)" }
    }
}
