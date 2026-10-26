// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/sanitizer (`srcset.go`) (Apache-2.0); adapted for
// Swift/SQLite.

import Foundation

/// One candidate of a srcset attribute: the URL and the descriptor the parser keeps.
struct ImageCandidate {
    var imageURL: String
    var descriptor: String

    /// The candidate as the reference writes it back into the attribute, which is what
    /// `imageCandidates.String()` joins with `", "`.
    var description: String {
        descriptor.isEmpty ? imageURL : imageURL + " " + descriptor
    }
}
