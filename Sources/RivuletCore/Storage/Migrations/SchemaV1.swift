// Ported from Miniflux internal/database/migrations.go (Apache-2.0); adapted for Swift/SQLite.
import FluentKit

/// Initial Rivulet schema: tables, indexes, the FTS5 index over entries and its
/// synchronization triggers.
///
/// Shapes follow `docs/architecture.md` and the reference (`internal/database/migrations.go`):
/// entry statuses are `unread`/`read` only, timestamps are Unix seconds, entry identity is
/// `(feed_id, hash)`, feeds cascade from their category. sqlite-nio prepares one statement
/// per call, so each DDL statement runs separately.
public struct SchemaV1: AsyncMigration {
    /// Creates the migration.
    public init() {}

    /// Creates the tables, indexes, FTS5 table and its triggers.
    public func prepare(on database: any Database) async throws {
        for statement in Self.statements {
            try await RawSQL.run(statement, on: database)
        }
    }

    /// Drops everything created by ``prepare(on:)``.
    public func revert(on database: any Database) async throws {
        for statement in Self.revertStatements {
            try await RawSQL.run(statement, on: database)
        }
    }

    // MARK: - Statements

    static let statements: [String] = [
        """
        CREATE TABLE users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL UNIQUE,
            password_hash TEXT NOT NULL,
            is_admin INTEGER NOT NULL DEFAULT 0,
            google_reader_username TEXT,
            google_reader_password_hash TEXT,
            fever_username TEXT,
            fever_token TEXT UNIQUE,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        )
        """,
        """
        CREATE TABLE categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
            title TEXT NOT NULL,
            position INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            UNIQUE (user_id, title)
        )
        """,
        """
        CREATE TABLE icons (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            hash TEXT NOT NULL UNIQUE,
            mime_type TEXT NOT NULL,
            content BLOB NOT NULL,
            external_id TEXT NOT NULL UNIQUE,
            created_at INTEGER NOT NULL
        )
        """,
        """
        CREATE TABLE feeds (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
            category_id INTEGER NOT NULL REFERENCES categories (id) ON DELETE CASCADE,
            url TEXT NOT NULL,
            site_url TEXT NOT NULL DEFAULT '',
            title TEXT NOT NULL DEFAULT '',
            description TEXT NOT NULL DEFAULT '',
            icon_id INTEGER REFERENCES icons (id) ON DELETE SET NULL,
            etag TEXT NOT NULL DEFAULT '',
            last_modified TEXT NOT NULL DEFAULT '',
            next_check_at INTEGER,
            check_interval INTEGER NOT NULL DEFAULT 60,
            parsing_error_count INTEGER NOT NULL DEFAULT 0,
            parsing_error_message TEXT NOT NULL DEFAULT '',
            user_agent TEXT NOT NULL DEFAULT '',
            disabled INTEGER NOT NULL DEFAULT 0,
            fetched_at INTEGER,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            UNIQUE (user_id, url)
        )
        """,
        """
        CREATE TABLE entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
            feed_id INTEGER NOT NULL REFERENCES feeds (id) ON DELETE CASCADE,
            hash TEXT NOT NULL,
            title TEXT NOT NULL DEFAULT '',
            url TEXT NOT NULL DEFAULT '',
            author TEXT NOT NULL DEFAULT '',
            content TEXT NOT NULL DEFAULT '',
            content_text TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL DEFAULT 'unread' CHECK (status IN ('unread', 'read')),
            starred INTEGER NOT NULL DEFAULT 0,
            published_at INTEGER NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            UNIQUE (feed_id, hash)
        )
        """,
        """
        CREATE TABLE entry_tombstones (
            feed_id INTEGER NOT NULL REFERENCES feeds (id) ON DELETE CASCADE,
            hash TEXT NOT NULL CHECK (hash <> ''),
            deleted_at INTEGER NOT NULL,
            PRIMARY KEY (feed_id, hash)
        )
        """,
        """
        CREATE TABLE enclosures (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entry_id INTEGER NOT NULL REFERENCES entries (id) ON DELETE CASCADE,
            url TEXT NOT NULL,
            mime_type TEXT NOT NULL DEFAULT '',
            size INTEGER NOT NULL DEFAULT 0
        )
        """,
        "CREATE INDEX entries_feed_status_idx ON entries (feed_id, status)",
        "CREATE INDEX entries_user_status_published_idx ON entries (user_id, status, published_at)",
        "CREATE INDEX entries_user_status_created_idx ON entries (user_id, status, created_at)",
        "CREATE INDEX entries_user_id_status_starred_idx ON entries (user_id, status, starred)",
        "CREATE INDEX feeds_user_category_idx ON feeds (user_id, category_id)",
        "CREATE INDEX feeds_next_check_at_idx ON feeds (next_check_at)",
        "CREATE INDEX enclosures_entry_id_idx ON enclosures (entry_id)",
        "CREATE INDEX entry_tombstones_deleted_at_idx ON entry_tombstones (deleted_at)",
        """
        CREATE VIRTUAL TABLE entries_fts USING fts5 (
            title,
            content_text,
            content = 'entries',
            content_rowid = 'id',
            tokenize = 'unicode61 remove_diacritics 2'
        )
        """,
        """
        CREATE TRIGGER entries_fts_ai AFTER INSERT ON entries BEGIN
            INSERT INTO entries_fts (rowid, title, content_text)
            VALUES (new.id, new.title, new.content_text);
        END
        """,
        """
        CREATE TRIGGER entries_fts_ad AFTER DELETE ON entries BEGIN
            INSERT INTO entries_fts (entries_fts, rowid, title, content_text)
            VALUES ('delete', old.id, old.title, old.content_text);
        END
        """,
        """
        CREATE TRIGGER entries_fts_au AFTER UPDATE OF title, content_text ON entries BEGIN
            INSERT INTO entries_fts (entries_fts, rowid, title, content_text)
            VALUES ('delete', old.id, old.title, old.content_text);
            INSERT INTO entries_fts (rowid, title, content_text)
            VALUES (new.id, new.title, new.content_text);
        END
        """,
    ]

    static let revertStatements: [String] = [
        "DROP TRIGGER entries_fts_ai",
        "DROP TRIGGER entries_fts_ad",
        "DROP TRIGGER entries_fts_au",
        "DROP TABLE entries_fts",
        "DROP TABLE enclosures",
        "DROP TABLE entries",
        "DROP TABLE entry_tombstones",
        "DROP TABLE feeds",
        "DROP TABLE icons",
        "DROP TABLE categories",
        "DROP TABLE users",
    ]
}
