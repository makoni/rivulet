// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/urlcleaner (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// Stub for the red run.
enum TrackingParametersError: Error, Equatable {
    case missingURL
}
