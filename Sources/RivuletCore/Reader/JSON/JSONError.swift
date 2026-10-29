// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Rivulet's own reader over the bytes; the failures are the ones `encoding/json`
// reports, in its own words. `JSONScanner` names the source the rules are traced against.

/// Failures of the JSON reader.
///
/// Each failure names the position the parse state is in, in the words Go uses, so a pin
/// can compare it against what the reference reports for the same byte. `unexpectedEnd`
/// is what the path `Decode` takes reports for input that ends: `io.EOF` when nothing
/// was read and `io.ErrUnexpectedEOF` when a value is still open, which `checkValid`
/// reports as one message, so the two are one case here, as `docs/parity.md` records.
enum JSONError: Error, Equatable, Sendable {
    /// The input ended with a value still open, or had no value at all.
    case unexpectedEnd

    /// A byte the position the machine is in cannot accept.
    case unexpectedCharacter(character: UInt8, context: String)

    /// A value nested deeper than the depth `pushParseState` limits to, which is 10000.
    case maxDepthExceeded

    /// `UnmarshalTypeError`: the value the machine read is not the type the field it is assigned
    /// to is. This is the field read's failure rather than the machine's, so it names the
    /// value word Go uses for the literal and the type Go names for the target. The byte offset
    /// the reference keeps is not modelled, because nothing in the port reads the message.
    case unmarshalTypeError(value: String, target: String)
}
