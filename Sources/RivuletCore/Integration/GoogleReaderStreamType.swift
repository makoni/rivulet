// Ported from Miniflux internal/googlereader/stream.go's stream types (Apache-2.0); adapted for
// Swift/SQLite.

/// The stream type, named as the reference names it in its log line.
public enum GoogleReaderStreamType: String, CaseIterable, Sendable {
    case noStream = "NoStream"
    case read = "ReadStream"
    case starred = "StarredStream"
    case readingList = "ReadingListStream"
    case keptUnread = "KeptUnreadStream"
    case broadcast = "BroadcastStream"
    case broadcastFriends = "BroadcastFriendsStream"
    case label = "LabelStream"
    case feed = "FeedStream"
    case like = "LikeStream"
}
