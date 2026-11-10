import Foundation
import Testing

///The calling sets the replay suite reads as data, and the two record files beside them. Both
///halves read the same copy: the pins read it through the bundle, `Tools/clients/replay.py` reads
///the same files from disk. That is why the sets live inside this target — a pin that reads the
///recorded order and the check half that reads the same order cannot disagree by restating it
///twice. The pins read the records for what they expect, so a pin is not a restatement of the
///matrix: the field names are the ones the check half reads, and the pairing of a call with the pin
///that reads it is `CallingSets/replayed.txt`, which the check half reads as data. What the pins
///cannot show is named in `docs/testing.md` under the matrix.
enum CallingSets {
    ///One client's calling set, as the record file writes it. Only the fields the pins read are
    ///modelled; a field the pins do not read is read by the check half.
    struct CallingSet: Codable {
        struct Source: Codable {
            let kind: String
            let project: String
            let file: String
            let commit: String?
            let readOn: String

            enum CodingKeys: String, CodingKey {
                case kind, project, file, commit
                case readOn = "read_on"
            }
        }

        struct Half: Codable {
            let api: String
            let prefix: String
            let callsRead: String
            let answeredHere: String

            enum CodingKeys: String, CodingKey {
                case api, prefix
                case callsRead = "calls_read"
                case answeredHere = "answered_here"
            }
        }

        struct Call: Codable {
            let key: String
            let method: String
            let auth: String
            let names: [String]
            let path: String?
            let dispatch: String?
            let pageSize: String?
            let idForm: String?

            enum CodingKeys: String, CodingKey {
                case key, method, auth, names, path, dispatch
                case pageSize = "page_size"
                case idForm = "id_form"
            }
        }

        struct Shape: Codable {
            let loginFirst: Bool
            let tokenBeforeToken: Bool
            let actsOnHeader: String?

            enum CodingKeys: String, CodingKey {
                case loginFirst = "login_first"
                case tokenBeforeToken = "token_before_T"
                case actsOnHeader = "acts_on_header"
            }
        }

        let client: String
        let api: String
        let source: Source
        let halves: [Half]
        let sequenceKind: String
        let declaredOrder: [String]
        let sourceOrder: [String]
        let calls: [Call]
        let notReached: [String]
        let shape: Shape

        enum CodingKeys: String, CodingKey {
            case client, api, source, halves, calls
            case sequenceKind = "sequence_kind"
            case declaredOrder = "declared_order"
            case sourceOrder = "source_order"
            case notReached = "not_reached"
            case shape = "runtime_shape"
        }

        ///The name the two record files key their lines with: the file stem, which is the client
        ///name in the lower form the records use.
        var stem: String {
            client.lowercased().replacingOccurrences(of: " ", with: "-")
        }

        ///The call the set records for this key, or nothing when the set records no call for it.
        func call(_ key: String) -> Call? { calls.first { $0.key == key } }
    }

    ///Every set, in the order the file names sort in, which is the order the record lines group by.
    static func all() throws -> [CallingSet] {
        try names().map { name in
            let set = try JSONDecoder().decode(CallingSet.self,
                from: Data(contentsOf: url(name)))
            return set
        }
    }

    static func set(_ client: String) throws -> CallingSet {
        try #require(all().first { $0.client == client }, "no calling set for \(client)")
    }

    ///The replay list as the record writes it: the key and the pin or the reason the check half
    ///names.
    static func replayed() throws -> [String: String] {
        try records("replayed.txt")
    }

    ///The manifest as the record writes it: the key and the class the check half reads it against.
    static func manifest() throws -> [String: String] {
        try records("manifest.txt")
    }

    private static func records(_ name: String) throws -> [String: String] {
        let text = String(decoding: try Data(contentsOf: url(name)), as: UTF8.self)
        return text.split(separator: "\n").map(String.init).filter {
            !$0.isEmpty && !$0.hasPrefix("#")
        }.reduce(into: [String: String]()) { found, line in
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            // A record line is one record: the key and the part the check half reads it against. A
            // line with fewer parts is not a record, so it reads as nothing rather than as an index
            // that cannot be answered.
            guard parts.count >= 2 else { return }
            found[parts[0]] = parts[1]
        }
    }

    private static func names() -> [String] {
        let directory = Bundle.module.resourceURL?.appendingPathComponent("CallingSets")
        let files = try? FileManager.default.contentsOfDirectory(atPath: directory?.path ?? "")
        return (files ?? []).filter { $0.hasSuffix(".json") }.sorted()
    }

    private static func url(_ name: String) -> URL {
        guard let url = Bundle.module.resourceURL?.appendingPathComponent(
            "CallingSets/\(name)") else {
            preconditionFailure("calling set not found: \(name)")
        }
        return url
    }
}
