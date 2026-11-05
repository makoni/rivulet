// Ported from Miniflux internal/googlereader/handler.go (Apache-2.0); adapted for Swift/SQLite.

import Foundation
import RivuletCore
import Vapor

/// The three POST write handlers of this path.
///
/// Split from `GoogleReaderHandlers` to keep each file within the size budget. These handlers read
/// the rules that file already uses — the form read, the stream read and the integer read — and add
/// the choices that are their own: which status a read error becomes, the order the guards run in,
/// which storage read each branch writes through, and that none of them applies the output check.
extension GoogleReaderHandlers {
    /// `renameTagHandler`. The two read failures name the parameter the read was given, which is
    /// this handler's own wording rather than the error the stream read gave, and `markAllAsRead`
    /// writes the error it gave instead — which is what the pins show for both.
    func renameTag(form: GoogleReaderForm, userID: Int) async throws -> Response {
        let source: GoogleReaderStream
        do {
            source = try GoogleReaderStream.parse(streamID: form.value(named: "s"), userID: userID)
        } catch {
            return GoogleReaderResponse.badRequest(Self.invalidData(named: "s"))
        }

        let destination: GoogleReaderStream
        do {
            destination = try GoogleReaderStream.parse(streamID: form.value(named: "dest"), userID: userID)
        } catch {
            return GoogleReaderResponse.badRequest(Self.invalidData(named: "dest"))
        }

        guard source.type == .label, destination.type == .label else {
            return GoogleReaderResponse.badRequest(Self.renameLabelsMessage)
        }
        guard !destination.id.isEmpty else {
            return GoogleReaderResponse.badRequest(Self.emptyDestinationMessage)
        }

        do {
            return try await storage.withConnection { connection in
                let categories = CategoryRepository(connection)
                guard let category = try await categories.byTitle(userID: userID, title: source.id),
                    let categoryID = category.id else {
                    return GoogleReaderResponse.notFound()
                }

                let duplicate = try await categories.anotherTitleExists(userID: userID,
                    categoryID: categoryID, title: destination.id)
                if let rule = CategoryValidation.validate(title: destination.id,
                    titleIsDuplicate: duplicate) {
                    // The port names the rule rather than the locale string, so the message is the
                    // rule name; the reference writes what its key translates to, which is recorded
                    // in `docs/reference-notes.md`.
                    return GoogleReaderResponse.badRequest(rule.rawValue)
                }

                try await categories.setTitle(userID: userID, categoryID: categoryID, title: destination.id)
                return GoogleReaderResponse.text("OK")
            }
        } catch {
            return GoogleReaderResponse.serverError(String(describing: error))
        }
    }

    /// `disableTagHandler`. `s` is the whole merged list here, which is the difference from the
    /// other handlers that read one value with the same name, and the guard runs per value — in the
    /// order the list was read — before any title is collected.
    func disableTag(form: GoogleReaderForm, userID: Int) async throws -> Response {
        let streams: [GoogleReaderStream]
        do {
            streams = try Self.streams(form.values(named: "s"), userID: userID)
        } catch {
            return GoogleReaderResponse.badRequest(Self.invalidData(named: "s"))
        }

        for stream in streams {
            guard stream.type == .label else {
                return GoogleReaderResponse.badRequest(Self.disableLabelsMessage)
            }
        }
        let titles = streams.map(\.id)

        do {
            try await storage.withTransaction { connection in
                try await CategoryRepository(connection).removeAndReplaceNamed(userID: userID, titles: titles)
            }
        } catch {
            return GoogleReaderResponse.serverError(String(describing: error))
        }

        return GoogleReaderResponse.text("OK")
    }

    /// `markAllAsReadHandler`. The reference's switch has three cases, so a stream type it does not
    /// handle falls through and answers `OK` writing nothing; this port states the same answer with
    /// an explicit no-op default. The integer read the feed branch makes is this handler's 400,
    /// where the same read answers 500 for `stream/items/ids`.
    func markAllAsRead(form: GoogleReaderForm, userID: Int) async throws -> Response {
        let stream: GoogleReaderStream
        do {
            stream = try GoogleReaderStream.parse(streamID: form.value(named: "s"), userID: userID)
        } catch {
            return GoogleReaderResponse.badRequest(String(describing: error))
        }

        let before: Int
        do {
            before = try GoogleReaderTimestamp.before(value: form.value(named: "ts"),
                now: Int(Date.now.timeIntervalSince1970))
        } catch {
            return GoogleReaderResponse.badRequest(String(describing: error))
        }

        do {
            return try await storage.withConnection { connection in
                let entries = EntryRepository(connection)
                let categories = CategoryRepository(connection)
                switch stream.type {
                case .feed:
                    let feedID = try Self.parseFeedID(stream.id)
                    try await entries.markFeedAsRead(userID: userID, feedID: feedID, before: before)
                case .label:
                    guard let category = try await categories.byTitle(userID: userID, title: stream.id),
                        let categoryID = category.id else {
                        return GoogleReaderResponse.notFound()
                    }
                    try await entries.markCategoryAsRead(userID: userID, categoryID: categoryID,
                        before: before)
                case .readingList:
                    try await entries.markAllAsRead(userID: userID, before: before)
                default:
                    break
                }
                return GoogleReaderResponse.text("OK")
            }
        } catch let parseError as GoParseInt.ParseError {
            return GoogleReaderResponse.badRequest(String(describing: parseError))
        } catch {
            return GoogleReaderResponse.serverError(String(describing: error))
        }
    }

    // MARK: - Handler rules

    /// `fmt.Errorf("googlereader: invalid data in %s", name)`: what this handler answers when the
    /// stream read reports, which names the parameter rather than the error the read gave.
    private static func invalidData(named name: String) -> String {
        "googlereader: invalid data in \(name)"
    }

    /// The two wordings that name different things: this handler's guard and `disableTagHandler`'s.
    private static let renameLabelsMessage = "googlereader: only labels supported"
    private static let disableLabelsMessage = "googlereader: only labels are supported"
    private static let emptyDestinationMessage = "googlereader: empty destination name"
}
