// Ported from Miniflux internal/googlereader/stream.go (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// A stream the Google Reader contract names: the type and the part of the value that is left after
/// the prefix is removed.
///
/// Upstream reads this in `getStream`. The two forms of each prefix are an OR in its `switch`, so
/// the generic form (`user/-/…`) matches on its own whatever user the read is for, and the value
/// that matches no prefix is the fallback error. `GoogleReaderStreamTests` pins the branches, the
/// seven suffixes, the empty value, and the wording the 500 answer writes.
public struct GoogleReaderStream: Sendable, Equatable {
    public let type: GoogleReaderStreamType
    public let id: String

    /// What the reference reports for a value that is not one of the forms it reads, which is the
    /// wording the 500 answer writes. The first names the part left after the prefix, the second
    /// the whole value.
    public enum ReadError: Error, CustomStringConvertible, Sendable {
        case unknownStreamWithID(String)
        case unknownStreamType(String)

        public var description: String {
            switch self {
            case .unknownStreamWithID(let id): return "googlereader: unknown stream with id: \(id)"
            case .unknownStreamType(let value): return "googlereader: unknown stream type: \(value)"
            }
        }
    }

    private static let feedPrefix = "feed/"
    private static let streamPrefix = "user/-/state/com.google/"
    private static let labelPrefix = "user/-/label/"

    private static let readSuffix = "read"
    private static let starredSuffix = "starred"
    private static let readingListSuffix = "reading-list"
    private static let keptUnreadSuffix = "kept-unread"
    private static let broadcastSuffix = "broadcast"
    private static let broadcastFriendsSuffix = "broadcast-friends"
    private static let likeSuffix = "like"

    /// `getStream`.
    ///
    /// - Throws: `ReadError`, with the reference's wording.
    public static func parse(streamID: String, userID: Int) throws -> GoogleReaderStream {
        if streamID.hasPrefix(feedPrefix) {
            return GoogleReaderStream(type: .feed, id: String(streamID.dropFirst(feedPrefix.count)))
        }

        if streamID.hasPrefix(userStreamPrefix(userID)) || streamID.hasPrefix(streamPrefix) {
            let suffix = streamID.hasPrefix(userStreamPrefix(userID))
                ? String(streamID.dropFirst(userStreamPrefix(userID).count))
                : String(streamID.dropFirst(streamPrefix.count))
            guard let type = suffixTypes[suffix] else {
                throw ReadError.unknownStreamWithID(suffix)
            }
            return GoogleReaderStream(type: type, id: "")
        }

        if streamID.hasPrefix(userLabelPrefix(userID)) || streamID.hasPrefix(labelPrefix) {
            let label = streamID.hasPrefix(userLabelPrefix(userID))
                ? String(streamID.dropFirst(userLabelPrefix(userID).count))
                : String(streamID.dropFirst(labelPrefix.count))
            return GoogleReaderStream(type: .label, id: label)
        }

        if streamID.isEmpty { return GoogleReaderStream(type: .noStream, id: "") }
        throw ReadError.unknownStreamType(streamID)
    }

    /// The seven suffixes, in the order the reference's `switch` reads them.
    private static let suffixTypes: [String: GoogleReaderStreamType] = [
        readSuffix: .read,
        starredSuffix: .starred,
        readingListSuffix: .readingList,
        keptUnreadSuffix: .keptUnread,
        broadcastSuffix: .broadcast,
        broadcastFriendsSuffix: .broadcastFriends,
        likeSuffix: .like,
    ]

    private static func userStreamPrefix(_ userID: Int) -> String { "user/\(userID)/state/com.google/" }

    private static func userLabelPrefix(_ userID: Int) -> String { "user/\(userID)/label/" }
}
