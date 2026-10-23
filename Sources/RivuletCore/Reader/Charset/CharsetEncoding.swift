// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/encoding/encoding.go (Apache-2.0); adapted for
// Swift/SQLite. The label table is transcribed from golang.org/x/text encoding/htmlindex.

import Foundation
import CoreFoundation

/// One of the encodings of the WHATWG Encoding Standard, named by its canonical name.
///
/// Case names mirror the `htmlEncoding` constants of `golang.org/x/text/encoding/htmlindex`,
/// which is what the reference resolves labels against. The label table below is transcribed
/// from that package (v0.40.0, BSD-3-Clause); the labels themselves are published by the
/// WHATWG Encoding Standard.
enum CharsetEncoding: String, CaseIterable {
    case utf8 = "utf-8"
    case ibm866 = "ibm866"
    case iso8859_2 = "iso-8859-2"
    case iso8859_3 = "iso-8859-3"
    case iso8859_4 = "iso-8859-4"
    case iso8859_5 = "iso-8859-5"
    case iso8859_6 = "iso-8859-6"
    case iso8859_7 = "iso-8859-7"
    case iso8859_8 = "iso-8859-8"
    case iso8859_8I = "iso-8859-8-i"
    case iso8859_10 = "iso-8859-10"
    case iso8859_13 = "iso-8859-13"
    case iso8859_14 = "iso-8859-14"
    case iso8859_15 = "iso-8859-15"
    case iso8859_16 = "iso-8859-16"
    case koi8r = "koi8-r"
    case koi8u = "koi8-u"
    case macintosh = "macintosh"
    case windows874 = "windows-874"
    case windows1250 = "windows-1250"
    case windows1251 = "windows-1251"
    case windows1252 = "windows-1252"
    case windows1253 = "windows-1253"
    case windows1254 = "windows-1254"
    case windows1255 = "windows-1255"
    case windows1256 = "windows-1256"
    case windows1257 = "windows-1257"
    case windows1258 = "windows-1258"
    case macintoshCyrillic = "x-mac-cyrillic"
    case gbk = "gbk"
    case gb18030 = "gb18030"
    case big5 = "big5"
    case eucjp = "euc-jp"
    case iso2022jp = "iso-2022-jp"
    case shiftJIS = "shift_jis"
    case euckr = "euc-kr"
    case replacement = "replacement"
    case utf16be = "utf-16be"
    case utf16le = "utf-16le"
    case xUserDefined = "x-user-defined"

    /// Resolves a WHATWG label, case-insensitively and ignoring surrounding whitespace.
    static func named(_ label: String) -> CharsetEncoding? {
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return labelTable[normalized]
    }

    /// How the decoder for this encoding is built, or `nil` when the platform cannot provide
    /// a converter for a legacy encoding.
    var decoderStrategy: CharsetDecoderStrategy? {
        switch self {
        case .utf8: return .utf8
        case .ibm866: return String.Encoding.iana("ibm866").map(CharsetDecoderStrategy.singleByte)
        case .iso8859_2: return String.Encoding.iana("iso-8859-2").map(CharsetDecoderStrategy.singleByte)
        case .iso8859_3: return String.Encoding.iana("iso-8859-3").map(CharsetDecoderStrategy.singleByte)
        case .iso8859_4: return String.Encoding.iana("iso-8859-4").map(CharsetDecoderStrategy.singleByte)
        case .iso8859_5: return String.Encoding.iana("iso-8859-5").map(CharsetDecoderStrategy.singleByte)
        case .iso8859_6: return String.Encoding.iana("iso-8859-6").map(CharsetDecoderStrategy.singleByte)
        case .iso8859_7: return String.Encoding.iana("iso-8859-7").map(CharsetDecoderStrategy.singleByte)
        case .iso8859_8: return String.Encoding.iana("iso-8859-8").map(CharsetDecoderStrategy.singleByte)
        case .iso8859_8I: return String.Encoding.iana("iso-8859-8-i").map(CharsetDecoderStrategy.singleByte)
        case .iso8859_10: return String.Encoding.iana("iso-8859-10").map(CharsetDecoderStrategy.singleByte)
        case .iso8859_13: return String.Encoding.iana("iso-8859-13").map(CharsetDecoderStrategy.singleByte)
        case .iso8859_14: return String.Encoding.iana("iso-8859-14").map(CharsetDecoderStrategy.singleByte)
        case .iso8859_15: return String.Encoding.iana("iso-8859-15").map(CharsetDecoderStrategy.singleByte)
        case .iso8859_16: return String.Encoding.iana("iso-8859-16").map(CharsetDecoderStrategy.singleByte)
        case .koi8r: return String.Encoding.iana("koi8-r").map(CharsetDecoderStrategy.singleByte)
        case .koi8u: return String.Encoding.iana("koi8-u").map(CharsetDecoderStrategy.singleByte)
        case .macintosh: return String.Encoding.iana("macintosh").map(CharsetDecoderStrategy.singleByte)
        case .windows874: return String.Encoding.iana("windows-874").map(CharsetDecoderStrategy.singleByte)
        case .windows1250: return String.Encoding.iana("windows-1250").map(CharsetDecoderStrategy.singleByte)
        case .windows1251: return String.Encoding.iana("windows-1251").map(CharsetDecoderStrategy.singleByte)
        case .windows1252: return String.Encoding.iana("windows-1252").map(CharsetDecoderStrategy.singleByte)
        case .windows1253: return String.Encoding.iana("windows-1253").map(CharsetDecoderStrategy.singleByte)
        case .windows1254: return String.Encoding.iana("windows-1254").map(CharsetDecoderStrategy.singleByte)
        case .windows1255: return String.Encoding.iana("windows-1255").map(CharsetDecoderStrategy.singleByte)
        case .windows1256: return String.Encoding.iana("windows-1256").map(CharsetDecoderStrategy.singleByte)
        case .windows1257: return String.Encoding.iana("windows-1257").map(CharsetDecoderStrategy.singleByte)
        case .windows1258: return String.Encoding.iana("windows-1258").map(CharsetDecoderStrategy.singleByte)
        case .macintoshCyrillic: return String.Encoding.iana("x-mac-cyrillic").map(CharsetDecoderStrategy.singleByte)
        case .gbk: return String.Encoding.iana("gbk").map(CharsetDecoderStrategy.multiByte)
        case .gb18030: return String.Encoding.iana("gb18030").map(CharsetDecoderStrategy.multiByte)
        case .big5: return String.Encoding.iana("big5").map(CharsetDecoderStrategy.multiByte)
        case .eucjp: return String.Encoding.iana("euc-jp").map(CharsetDecoderStrategy.multiByte)
        case .iso2022jp: return String.Encoding.iana("iso-2022-jp").map(CharsetDecoderStrategy.multiByte)
        case .shiftJIS: return String.Encoding.iana("shift_jis").map(CharsetDecoderStrategy.multiByte)
        case .euckr: return String.Encoding.iana("euc-kr").map(CharsetDecoderStrategy.multiByte)
        case .replacement: return .replacement
        case .utf16be: return .utf16BigEndian
        case .utf16le: return .utf16LittleEndian
        case .xUserDefined: return .userDefined
        }
    }

    /// WHATWG label (lowercase) to encoding, exactly the table of the reference.
    static let labelTable: [String: CharsetEncoding] = [
        // utf-8
        "unicode-1-1-utf-8": .utf8, "unicode11utf8": .utf8, "unicode20utf8": .utf8, "utf-8": .utf8, "utf8": .utf8, "x-unicode20utf8": .utf8,
        // ibm866
        "866": .ibm866, "cp866": .ibm866, "csibm866": .ibm866, "ibm866": .ibm866,
        // iso-8859-2
        "csisolatin2": .iso8859_2, "iso-8859-2": .iso8859_2, "iso-ir-101": .iso8859_2, "iso8859-2": .iso8859_2, "iso88592": .iso8859_2, "iso_8859-2": .iso8859_2, "iso_8859-2:1987": .iso8859_2, "l2": .iso8859_2, "latin2": .iso8859_2,
        // iso-8859-3
        "csisolatin3": .iso8859_3, "iso-8859-3": .iso8859_3, "iso-ir-109": .iso8859_3, "iso8859-3": .iso8859_3, "iso88593": .iso8859_3, "iso_8859-3": .iso8859_3, "iso_8859-3:1988": .iso8859_3, "l3": .iso8859_3, "latin3": .iso8859_3,
        // iso-8859-4
        "csisolatin4": .iso8859_4, "iso-8859-4": .iso8859_4, "iso-ir-110": .iso8859_4, "iso8859-4": .iso8859_4, "iso88594": .iso8859_4, "iso_8859-4": .iso8859_4, "iso_8859-4:1988": .iso8859_4, "l4": .iso8859_4, "latin4": .iso8859_4,
        // iso-8859-5
        "csisolatincyrillic": .iso8859_5, "cyrillic": .iso8859_5, "iso-8859-5": .iso8859_5, "iso-ir-144": .iso8859_5, "iso8859-5": .iso8859_5, "iso88595": .iso8859_5, "iso_8859-5": .iso8859_5, "iso_8859-5:1988": .iso8859_5,
        // iso-8859-6
        "arabic": .iso8859_6, "asmo-708": .iso8859_6, "csiso88596e": .iso8859_6, "csiso88596i": .iso8859_6, "csisolatinarabic": .iso8859_6, "ecma-114": .iso8859_6, "iso-8859-6": .iso8859_6, "iso-8859-6-e": .iso8859_6, "iso-8859-6-i": .iso8859_6, "iso-ir-127": .iso8859_6, "iso8859-6": .iso8859_6, "iso88596": .iso8859_6, "iso_8859-6": .iso8859_6, "iso_8859-6:1987": .iso8859_6,
        // iso-8859-7
        "csisolatingreek": .iso8859_7, "ecma-118": .iso8859_7, "elot_928": .iso8859_7, "greek": .iso8859_7, "greek8": .iso8859_7, "iso-8859-7": .iso8859_7, "iso-ir-126": .iso8859_7, "iso8859-7": .iso8859_7, "iso88597": .iso8859_7, "iso_8859-7": .iso8859_7, "iso_8859-7:1987": .iso8859_7, "sun_eu_greek": .iso8859_7,
        // iso-8859-8
        "csiso88598e": .iso8859_8, "csisolatinhebrew": .iso8859_8, "hebrew": .iso8859_8, "iso-8859-8": .iso8859_8, "iso-8859-8-e": .iso8859_8, "iso-ir-138": .iso8859_8, "iso8859-8": .iso8859_8, "iso88598": .iso8859_8, "iso_8859-8": .iso8859_8, "iso_8859-8:1988": .iso8859_8, "visual": .iso8859_8,
        // iso-8859-8-i
        "csiso88598i": .iso8859_8I, "iso-8859-8-i": .iso8859_8I, "logical": .iso8859_8I,
        // iso-8859-10
        "csisolatin6": .iso8859_10, "iso-8859-10": .iso8859_10, "iso-ir-157": .iso8859_10, "iso8859-10": .iso8859_10, "iso885910": .iso8859_10, "l6": .iso8859_10, "latin6": .iso8859_10,
        // iso-8859-13
        "iso-8859-13": .iso8859_13, "iso8859-13": .iso8859_13, "iso885913": .iso8859_13,
        // iso-8859-14
        "iso-8859-14": .iso8859_14, "iso8859-14": .iso8859_14, "iso885914": .iso8859_14,
        // iso-8859-15
        "csisolatin9": .iso8859_15, "iso-8859-15": .iso8859_15, "iso8859-15": .iso8859_15, "iso885915": .iso8859_15, "iso_8859-15": .iso8859_15, "l9": .iso8859_15,
        // iso-8859-16
        "iso-8859-16": .iso8859_16,
        // koi8-r
        "cskoi8r": .koi8r, "koi": .koi8r, "koi8": .koi8r, "koi8-r": .koi8r, "koi8_r": .koi8r,
        // koi8-u
        "koi8-ru": .koi8u, "koi8-u": .koi8u,
        // macintosh
        "csmacintosh": .macintosh, "mac": .macintosh, "macintosh": .macintosh, "x-mac-roman": .macintosh,
        // windows-874
        "dos-874": .windows874, "iso-8859-11": .windows874, "iso8859-11": .windows874, "iso885911": .windows874, "tis-620": .windows874, "windows-874": .windows874,
        // windows-1250
        "cp1250": .windows1250, "windows-1250": .windows1250, "x-cp1250": .windows1250,
        // windows-1251
        "cp1251": .windows1251, "windows-1251": .windows1251, "x-cp1251": .windows1251,
        // windows-1252
        "ansi_x3.4-1968": .windows1252, "ascii": .windows1252, "cp1252": .windows1252, "cp819": .windows1252, "csisolatin1": .windows1252, "ibm819": .windows1252, "iso-8859-1": .windows1252, "iso-ir-100": .windows1252, "iso8859-1": .windows1252, "iso88591": .windows1252, "iso_8859-1": .windows1252, "iso_8859-1:1987": .windows1252, "l1": .windows1252, "latin1": .windows1252, "us-ascii": .windows1252, "windows-1252": .windows1252, "x-cp1252": .windows1252,
        // windows-1253
        "cp1253": .windows1253, "windows-1253": .windows1253, "x-cp1253": .windows1253,
        // windows-1254
        "cp1254": .windows1254, "csisolatin5": .windows1254, "iso-8859-9": .windows1254, "iso-ir-148": .windows1254, "iso8859-9": .windows1254, "iso88599": .windows1254, "iso_8859-9": .windows1254, "iso_8859-9:1989": .windows1254, "l5": .windows1254, "latin5": .windows1254, "windows-1254": .windows1254, "x-cp1254": .windows1254,
        // windows-1255
        "cp1255": .windows1255, "windows-1255": .windows1255, "x-cp1255": .windows1255,
        // windows-1256
        "cp1256": .windows1256, "windows-1256": .windows1256, "x-cp1256": .windows1256,
        // windows-1257
        "cp1257": .windows1257, "windows-1257": .windows1257, "x-cp1257": .windows1257,
        // windows-1258
        "cp1258": .windows1258, "windows-1258": .windows1258, "x-cp1258": .windows1258,
        // x-mac-cyrillic
        "x-mac-cyrillic": .macintoshCyrillic, "x-mac-ukrainian": .macintoshCyrillic,
        // gbk
        "chinese": .gbk, "csgb2312": .gbk, "csiso58gb231280": .gbk, "gb2312": .gbk, "gb_2312": .gbk, "gb_2312-80": .gbk, "gbk": .gbk, "iso-ir-58": .gbk, "x-gbk": .gbk,
        // gb18030
        "gb18030": .gb18030,
        // big5
        "big5": .big5, "big5-hkscs": .big5, "cn-big5": .big5, "csbig5": .big5, "x-x-big5": .big5,
        // euc-jp
        "cseucpkdfmtjapanese": .eucjp, "euc-jp": .eucjp, "x-euc-jp": .eucjp,
        // iso-2022-jp
        "csiso2022jp": .iso2022jp, "iso-2022-jp": .iso2022jp,
        // shift_jis
        "csshiftjis": .shiftJIS, "ms932": .shiftJIS, "ms_kanji": .shiftJIS, "shift-jis": .shiftJIS, "shift_jis": .shiftJIS, "sjis": .shiftJIS, "windows-31j": .shiftJIS, "x-sjis": .shiftJIS,
        // euc-kr
        "cseuckr": .euckr, "csksc56011987": .euckr, "euc-kr": .euckr, "iso-ir-149": .euckr, "korean": .euckr, "ks_c_5601-1987": .euckr, "ks_c_5601-1989": .euckr, "ksc5601": .euckr, "ksc_5601": .euckr, "windows-949": .euckr,
        // replacement
        "csiso2022kr": .replacement, "hz-gb-2312": .replacement, "iso-2022-cn": .replacement, "iso-2022-cn-ext": .replacement, "iso-2022-kr": .replacement, "replacement": .replacement,
        // utf-16be
        "unicodefffe": .utf16be, "utf-16be": .utf16be,
        // utf-16le
        "csunicode": .utf16le, "iso-10646-ucs-2": .utf16le, "ucs-2": .utf16le, "unicode": .utf16le, "unicodefeff": .utf16le, "utf-16": .utf16le, "utf-16le": .utf16le,
        // x-user-defined
        "x-user-defined": .xUserDefined,
    ]
}

/// The platform-independent description of how a ``CharsetEncoding`` is decoded.
enum CharsetDecoderStrategy {
    /// UTF-8: valid bytes pass through, and every maximal subpart of an ill-formed subsequence
    /// becomes U+FFFD, like the reference's decoder.
    case utf8
    /// A single-byte encoding decoded byte by byte; undefined bytes become U+FFFD.
    case singleByte(String.Encoding)
    /// A multi-byte encoding decoded through the platform converter, with a tolerance layer.
    case multiByte(String.Encoding)
    case utf16LittleEndian
    case utf16BigEndian
    case userDefined
    case replacement
}

extension String.Encoding {
    /// Resolves an IANA charset name to a platform encoding.
    ///
    /// CoreFoundation owns the IANA name registry, so this is the same lookup the reference
    /// relies on for its canonical names; `nil` means the name is unknown to the platform.
    static func iana(_ name: String) -> String.Encoding? {
        guard let cfName = CFStringCreateWithCString(kCFAllocatorDefault, name, CFStringBuiltInEncodings.UTF8.rawValue) else {
            return nil
        }
        let encoding = CFStringConvertIANACharSetNameToEncoding(cfName)
        guard encoding != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
    }
}
