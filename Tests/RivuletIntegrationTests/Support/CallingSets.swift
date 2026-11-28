import Foundation
import Testing

///The recorded client calling sets the replay suite reads. `replayed.txt` beside them lists, for
///reference, the test that replays each recorded call or why it is not replayed; `docs/clients.md`
///describes the clients.
enum CallingSets {
    ///One client's calling set, as the record file writes it. Only the fields the pins read are
    ///modelled.
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
