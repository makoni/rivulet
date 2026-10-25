// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/urlcleaner (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The tracking parameters the reference removes from a URL. A parameter name is compared
/// lower-cased, and the two prefixes are checked before the table, as the reference does.
enum TrackingParameters {
    private static let trackingParams: Set<String> = [
        // Facebook Click Identifiers
        "fbclid", "_openstat", "fb_action_ids", "fb_action_types", "fb_ref", "fb_source",
        "fb_comment_id",

        // Humble Bundles
        "hmb_campaign", "hmb_medium", "hmb_source",

        // Likely Google as well
        "itm_campaign", "itm_medium", "itm_source",

        // Google Click Identifiers
        "gclid", "dclid", "gbraid", "wbraid", "gclsrc",

        // Google Analytics
        "campaign_id", "campaign_medium", "campaign_name", "campaign_source", "campaign_term",
        "campaign_content",

        // Google
        "srsltid",

        // Yandex Click Identifiers
        "yclid", "ysclid",

        // Twitter Click Identifier
        "twclid",

        // Microsoft Click Identifier
        "msclkid",

        // Mailchimp Click Identifiers
        "mc_cid", "mc_eid", "mc_tc",

        // Wicked Reports click tracking
        "wickedid",

        // Hubspot Click Identifiers
        "hsa_cam", "_hsenc", "__hssc", "__hstc", "__hsfp", "_hsmi", "hsctatracking",

        // Olytics
        "rb_clickid", "oly_anon_id", "oly_enc_id",

        // Vero Click Identifier
        "vero_id", "vero_conv",

        // Marketo email tracking
        "mkt_tok",

        // Adobe email tracking
        "sc_cid",

        // Beehiiv
        "_bhlid",

        // Branch.io
        "_branch_match_id", "_branch_referrer",

        // Readwise
        "__readwiseLocation",
    ]

    /// Outbound tracking parameters append the website's URL to outbound links, so `ref` is removed
    /// only when one of its values is the feed or the site host.
    private static let trackingParamsOutbound: Set<String> = ["ref"]

    private static let trackingParamsPrefixes: [String] = ["utm_", "mtm_"]

    /// The reference answers for three parsed URLs — the base URL, the feed URL and the URL being
    /// cleaned. A URL that did not parse is the nil this call rejects.
    static func remove(base: ParsedURL?, feed: ParsedURL?, input: ParsedURL?) throws -> String {
        guard let base, let feed, let input else { throw TrackingParametersError.missingURL }

        if input.rawQuery.isEmpty { return input.description }

        let query = input.query()
        var cleaned = query
        var foundTrackers = false
        let feedHost = feed.hostName
        let siteHost = base.hostName

        for key in query.values.keys.sorted() {
            let lowerKey = key.lowercased()

            if isTrackingParam(lowerKey) {
                cleaned.values.removeValue(forKey: key)
                foundTrackers = true
                continue
            }

            if trackingParamsOutbound.contains(lowerKey) {
                for value in query.values[key] ?? [] {
                    if value == feedHost || value == siteHost {
                        cleaned.values.removeValue(forKey: key)
                        foundTrackers = true
                        break
                    }
                }
            }
        }

        // Without a tracker the URL is returned as it was read, so its pairs keep their order.
        if !foundTrackers { return input.description }

        var rewritten = input
        rewritten.rawQuery = cleaned.encode()

        // Go trims a trailing "?" from the rebuilt string. It can only be there when the value was
        // read with a forced empty query, which the reference answers before this point, so the
        // trim is the reference's line kept as it is.
        let rebuilt = rewritten.description
        return rebuilt.hasSuffix("?") ? String(rebuilt.dropLast()) : rebuilt
    }

    private static func isTrackingParam(_ parameter: String) -> Bool {
        for prefix in trackingParamsPrefixes where parameter.hasPrefix(prefix) { return true }
        return trackingParams.contains(parameter)
    }
}
