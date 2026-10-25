// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/urlcleaner (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// Why the cleaner cannot answer: the reference returns an error when any of the three parsed URLs
/// is absent. The reader decides what to keep in that case, so the failure is reported rather than
/// answered with an empty string.
enum TrackingParametersError: Error, Equatable {
    case missingURL
}
