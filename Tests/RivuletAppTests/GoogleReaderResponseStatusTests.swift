import NIOCore
import Testing
import Vapor
@testable import RivuletApp

/// The response builder's status mapping for `internal/http/response/json.go` at `c4d54f87`.
///
/// What these pins can fail on: the status each builder writes, which a patch that wrote every
/// error as 400 fails on; the JSON error document body, which a patch that wrote text instead fails
/// on; and the three headers the builder writes on every response, which a status-specific write
/// that set only its content type fails on. The handler status mapping for the reachable 400 and
/// 500 shapes is also pinned over a socket by `GoogleReaderHandlerTests`; this pin reads the helper
/// that the handler uses, including the 404 shape, which no request can reach because the auth read
/// found the row it returns.
@Suite struct GoogleReaderResponseStatusTests {
    @Test func theErrorStatusMappingWritesTheJSONErrorDocumentForEachStatus() throws {
        #expect(GoogleReaderResponse.badRequest("bad").status == .badRequest,
            "the handler answer for a read error")
        #expect(bodyText(GoogleReaderResponse.badRequest("bad")) == "{\"error_message\":\"bad\"}",
            "the same document the unauthorized login shape writes")

        #expect(GoogleReaderResponse.serverError("bad").status == .internalServerError,
            "the handler answer for the stream and tag read errors")
        #expect(bodyText(GoogleReaderResponse.serverError("bad")) == "{\"error_message\":\"bad\"}",
            "the same document, not the text shape")

        #expect(GoogleReaderResponse.notFound().status == .notFound,
            "the handler answer for a resource the storage read does not find")
        #expect(bodyText(GoogleReaderResponse.notFound()) == "{\"error_message\":\"resource not found\"}",
            "the reference's wording")
    }

    @Test func theErrorStatusMappingKeepsTheBuilderHeadersOnEveryShape() throws {
        for response in [GoogleReaderResponse.badRequest("x"), GoogleReaderResponse.serverError("x"),
            GoogleReaderResponse.notFound()] {
            #expect(response.headers.first(name: "X-Content-Type-Options") == "nosniff")
            #expect(response.headers.first(name: "X-Frame-Options") == "DENY")
            #expect(response.headers.first(name: "Referrer-Policy") == "no-referrer")
            #expect(response.headers.first(name: "Content-Type") == "application/json",
                "the JSON error shape keeps the same content type as the success shape")
        }
    }

    private func bodyText(_ response: Response) -> String {
        let buffer = response.body.buffer
        return buffer.map { String(decoding: $0.readableBytesView, as: UTF8.self) } ?? ""
    }
}
