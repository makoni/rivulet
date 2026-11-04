// Ported from Miniflux internal/googlereader/handler.go's checkAndSimplifyTags (Apache-2.0);
// adapted for Swift/SQLite.

import Foundation

/// The tags `edit-tag` builds from the values it reads.
///
/// The add loop runs before the remove loop, which is what the two guards see. Inside the add loop
/// the guard asks for a key that loop never writes, so it can never be true and both values of the
/// pair are read, the last one winning; `GoogleReaderTagsTests` pins what that guard leaves behind.
/// The wordings are the ones the 500 answer writes, and the guard that an empty add and an empty
/// remove answer the reference's own wording is the handler's rule, not this function's.
public enum GoogleReaderTags {
    /// What this read reports for a pair of values that cannot both be written, and for a value
    /// that is not one of the tag types.
    public enum ReadError: Error, CustomStringConvertible, Sendable {
        case readAndKeptUnreadSimultaneously
        case starredSimultaneously
        case unsupportedTagType(GoogleReaderStreamType)

        public var description: String {
            switch self {
            case .readAndKeptUnreadSimultaneously:
                return "googlereader: kept-unread and read should not be supplied simultaneously"
            case .starredSimultaneously:
                return "googlereader: starred should not be supplied for add and remove simultaneously"
            case .unsupportedTagType(let type):
                return "googlereader: unsupported tag type: \(type.rawValue)"
            }
        }
    }

    /// `checkAndSimplifyTags`.
    ///
    /// - Throws: `ReadError`. - Returns: the values written, which is nothing for `broadcast` and
    /// `like`: those branches log and continue.
    public static func simplify(adds: [GoogleReaderStream], removes: [GoogleReaderStream]) throws
        -> [GoogleReaderStreamType: Bool] {
        var tags: [GoogleReaderStreamType: Bool] = [:]

        for stream in adds {
            switch stream.type {
            case .read:
                guard tags[.keptUnread] == nil else { throw ReadError.readAndKeptUnreadSimultaneously }
                tags[.read] = true
            case .keptUnread:
                guard tags[.read] == nil else { throw ReadError.readAndKeptUnreadSimultaneously }
                tags[.read] = false
            case .starred: tags[.starred] = true
            case .broadcast, .like: break
            default: throw ReadError.unsupportedTagType(stream.type)
            }
        }

        for stream in removes {
            switch stream.type {
            case .read:
                guard tags[.read] == nil else { throw ReadError.readAndKeptUnreadSimultaneously }
                tags[.read] = false
            case .keptUnread:
                guard tags[.read] == nil else { throw ReadError.readAndKeptUnreadSimultaneously }
                tags[.read] = true
            case .starred:
                guard tags[.starred] == nil else { throw ReadError.starredSimultaneously }
                tags[.starred] = false
            case .broadcast, .like: break
            default: throw ReadError.unsupportedTagType(stream.type)
            }
        }

        return tags
    }
}
