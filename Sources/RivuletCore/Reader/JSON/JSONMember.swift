// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Rivulet's own reader over the bytes; the shape is what the reference's decoder produces for the
// value it reads. `JSONScanner` names the source the rules are traced against.

import Foundation

/// One member of an object: the key as the machine decoded it, and the value it is assigned.
///
/// A key that appears twice is two members, in the order the document wrote them, which is what the
/// tree keeps; the reference's map keeps one, and the value it keeps is the last assignment, so the
/// field read that walks these members takes the last one.
struct JSONMember: Equatable, Sendable {
    let key: String
    let value: JSONValue
}
