import Foundation

/// A fetch response: status, headers, the bytes actually read, and the URL the response came
/// from after redirects.
///
/// Ported from Miniflux `internal/reader/fetcher/response_handler.go` (Apache-2.0); adapted for
/// Swift. The reference measures the body through `Content-Length`; Rivulet has the bytes it read,
/// so an empty body is decided from the body itself. Everything else here is the same decision.
public struct FetchResponse: Sendable, Equatable {
    /// HTTP status.
    public let status: Int

    /// Response headers, in the form the client delivered them.
    ///
    /// A name that appears twice keeps only the last value, because a dictionary cannot hold both; the
    /// reference keeps a list per name. Nothing in stage 2 reads a repeated header — `Set-Cookie` is the
    /// usual case — so the single value is recorded here rather than modelled.
    public let headers: [String: String]

    /// Body bytes, capped by the fetcher; empty for a conditional hit.
    public let body: Data

    /// URL the response belongs to, which is the last one after redirects.
    public let effectiveURL: URL

    /// Creates a response.
    public init(
        status: Int,
        headers: [String: String] = [:],
        body: Data = Data(),
        effectiveURL: URL
    ) {
        self.status = status
        self.headers = headers
        self.body = body
        self.effectiveURL = effectiveURL
    }

    /// Header lookup is case-insensitive, as HTTP field names are.
    public func header(_ name: String) -> String? {
        let wanted = name.lowercased()
        for (key, value) in headers where key.lowercased() == wanted {
            return value
        }
        return nil
    }

    /// `Content-Type` value, empty when the header is absent.
    public var contentType: String { header("Content-Type") ?? "" }

    /// A conditional hit: no body, no error, nothing to re-parse.
    public var isConditionalHit: Bool { status == 304 }

    /// A response that asks for no cache at all — the reference treats `Expires: 0` as a signal
    /// to ignore the caching headers.
    private var cachesForbidden: Bool { header("Expires") == "0" }

    /// Validators stored for the next conditional request; empty when caching is forbidden.
    public var etag: String { cachesForbidden ? "" : (header("ETag") ?? "") }

    /// Validators stored for the next conditional request; empty when caching is forbidden.
    public var lastModified: String { cachesForbidden ? "" : (header("Last-Modified") ?? "") }

    /// The reference reports only 429 as rate limited.
    public var isRateLimited: Bool { status == 429 }

    /// Whether the response carries content that is new for this feed.
    ///
    /// RFC 9110 §8.8.1 gives `ETag` precedence over `Last-Modified`, so a changed
    /// `Last-Modified` alone is not a change when an `ETag` is present and matches.
    public func isModified(against stored: FeedFetchState) -> Bool {
        if isConditionalHit {
            return false
        }
        let responseEtag = etag
        if !responseEtag.isEmpty {
            return responseEtag != stored.etag
        }
        let responseLastModified = lastModified
        if !responseLastModified.isEmpty {
            return responseLastModified != stored.lastModified
        }
        return true
    }

    /// Time until the cached response expires, in whole minutes, as upstream
    /// (`time.Until(t).Truncate(minute) + minute`): the minute the value falls in, plus one. A
    /// value inside the current minute yields a minute even when it is already past; a past value
    /// that truncates to exactly the previous minute yields nothing, because the truncation and the
    /// added minute cancel; one further past yields a negative delay, which upstream returns too —
    /// its handler takes `refreshDelay = max(feed TTL, max-age, expires)` and `ScheduleNextCheck`
    /// then clamps that with `max(interval, refreshDelay)`, so a negative value cannot shorten the
    /// schedule. An unparsable value yields nothing. The division truncates toward zero, which is
    /// what Go's `Truncate` does, so a negative value behaves the same here as upstream.
    public func expires(now: Int) -> Duration {
        guard let value = header("Expires"), let date = HTTPDate.parse(value) else {
            return .zero
        }
        let seconds = date - now
        return .seconds(seconds / 60 * 60 + 60)
    }

    /// `Cache-Control: max-age`, in seconds; the first matching directive wins, as upstream.
    public var cacheControlMaxAge: Duration {
        guard let value = header("Cache-Control") else {
            return .zero
        }
        for directive in value.split(separator: ",") {
            let trimmed = directive.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("max-age=") else {
                continue
            }
            if let seconds = Int(trimmed.dropFirst("max-age=".count)) {
                return .seconds(seconds)
            }
        }
        return .zero
    }

    /// `Retry-After`, as seconds or as an HTTP-date relative to `now`. A date in the past is not
    /// clamped, which is what upstream does.
    public func retryAfter(now: Int) -> Duration {
        guard let value = header("Retry-After") else {
            return .zero
        }
        if let seconds = Int(value) {
            return .seconds(seconds)
        }
        if let date = HTTPDate.parse(value) {
            return .seconds(date - now)
        }
        return .zero
    }

    /// A Cloudflare bot challenge, recognised from the headers only so the check stays cheap.
    public var isCloudflareChallenge: Bool {
        status == 403
            && header("Cf-Mitigated")?.lowercased() == "challenge"
            && contentType.lowercased().hasPrefix("text/html")
    }

    /// The fetch failure this response represents, or nil when it can be processed.
    public func error() -> FetchError? {
        if isCloudflareChallenge {
            return .cloudflareChallenge(status)
        }
        if status >= 400 {
            return .status(status)
        }
        if !isConditionalHit && body.isEmpty {
            return .emptyBody
        }
        return nil
    }
}
