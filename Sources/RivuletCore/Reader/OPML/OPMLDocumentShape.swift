// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/opml/opml.go (the document shape) and
// `serializer.go` (`convertSubscriptionsToOPML`, `groupSubscriptionsByFeed`) (Apache-2.0);
// adapted for Swift/SQLite.

/// The document the write builds, as the reference model holds it before the encoder runs.
///
/// The document build rule sets the version, the namespace and the head title from its constants
/// and the date from the time it is given; the groups come from the grouping rule, which keeps the
/// order the records arrived in inside a category, and from the sort rule, which orders the
/// categories as bytes.
struct OPMLDocumentShape: Equatable, Sendable {
    var version: String
    var namespace: String
    var headerTitle: String
    var dateCreated: String
    var ownerName: String = ""
    var groups: [OPMLGroup]

    init(version: String, namespace: String, headerTitle: String, dateCreated: String,
        groups: [OPMLGroup]) {
        self.version = version
        self.namespace = namespace
        self.headerTitle = headerTitle
        self.dateCreated = dateCreated
        self.groups = groups
    }
}

/// One category of the grouping rule.
struct OPMLGroup: Equatable, Sendable {
    var name: String
    var subscriptions: [OPMLSubscription]
}
