@testable import EnchiridionKit
import Foundation
import Testing

@Suite struct ClientTests {
    // MARK: Headers and timeouts

    @Test func getHeaders() async throws {
        let transport = StubTransport(StubResponse(json: Fixture.infoOff))
        let info = try await EnchiridionClient.test(transport).info()
        #expect(info == Info(name: "enchiridion", auth: []))
        let request = try #require(await transport.last())
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://enchiridion.example.test/info")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "X-Enchiridion-Client") == "ios/0.1 app")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
        #expect(request.value(forHTTPHeaderField: "Origin") == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.httpBody == nil)
        #expect(request.timeoutInterval == 30)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test func shareRole() async throws {
        let transport = StubTransport(StubResponse(json: Fixture.meLocal))
        let client = EnchiridionClient.test(transport, role: .share)
        #expect(client.configuration.timeout == .seconds(10))
        _ = try await client.me()
        let request = try #require(await transport.last())
        #expect(request.url?.path == "/me")
        #expect(request.value(forHTTPHeaderField: "X-Enchiridion-Client") == "ios/0.1 share")
        #expect(request.timeoutInterval == 10)
    }

    @Test func explicitTimeoutAndServerPath() async throws {
        let transport = StubTransport(StubResponse(json: Fixture.infoOn))
        let client = EnchiridionClient(
            .init(server: URL(string: "http://localhost:4321/")!, role: .app, appVersion: "2.0", timeout: .milliseconds(1_500)),
            transport: transport
        )
        _ = try await client.info()
        let request = try #require(await transport.last())
        #expect(request.url?.absoluteString == "http://localhost:4321/info")
        #expect(request.timeoutInterval == 1.5)
        #expect(request.value(forHTTPHeaderField: "X-Enchiridion-Client") == "ios/2.0 app")
    }

    // MARK: Records

    @Test func list() async throws {
        let transport = StubTransport(StubResponse(json: "[\(Fixture.listRow),\(Fixture.highlightRow)]"))
        let rows = try await EnchiridionClient.test(transport).list(.index)
        #expect(rows.map(\.id) == [812, 901])
        let request = try #require(await transport.last())
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/records")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        let body = try request.jsonObject()
        #expect(body["limit"] as? Int == 100_000)
        #expect((body["filters"] as? [String: Any])?["hideUntitledChildren"] as? Bool == true)
        let order = try #require(body["orderBy"] as? [[String: String]])
        #expect(order == [["field": "recordCreatedAt", "direction": "desc"], ["field": "slug", "direction": "asc"]])
    }

    @Test func search() async throws {
        let transport = StubTransport(StubResponse(json: "[\(Fixture.searchRow)]"))
        let rows = try await EnchiridionClient.test(transport).search("  c++ & café  ")
        #expect(rows.first?.score != nil)
        let request = try #require(await transport.last())
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/search/hybrid")
        // `+` and `&` are escaped so Express reads them as themselves; the query is trimmed.
        #expect(request.url?.query(percentEncoded: true) == "q=c%2B%2B%20%26%20caf%C3%A9&limit=100")
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
        #expect(items?.first { $0.name == "q" }?.value == "c++ & café")
    }

    @Test func blankSearchAsksNothing() async throws {
        let transport = StubTransport(StubResponse(status: 400, json: #"{"error":"Missing query parameter \"q\""}"#))
        #expect(try await EnchiridionClient.test(transport).search(" \n ").isEmpty)
        #expect(await transport.recorded().isEmpty)
    }

    @Test func recordByID() async throws {
        let transport = StubTransport(StubResponse(json: Fixture.detail))
        let detail = try await EnchiridionClient.test(transport).record(id: 812)
        #expect(detail.title == "Tiny internets")
        let request = try #require(await transport.last())
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/record/812")
    }

    @Test func similarRecords() async throws {
        let body = #"[{"record":{"id":646,"slug":"spencer-chang","type":"entity","title":"Spencer Chang","url":"https://spencer.place","isCurated":true,"summary":null,"content":null,"notes":null,"source":"manual","recordCreatedAt":"2025-07-29 22:28:42","recordUpdatedAt":"2025-11-16 23:37:17","contentCreatedAt":null,"contentUpdatedAt":null},"score":0.499,"reasons":["50% similar by content"]}]"#
        let transport = StubTransport(StubResponse(json: body))
        let similar = try await EnchiridionClient.test(transport).similar(id: 1, limit: 5)
        #expect(similar.map(\.id) == [646])
        #expect(similar.first?.record.type == .entity)
        #expect(similar.first?.reasons == ["50% similar by content"])
        let request = try #require(await transport.last())
        #expect(request.url?.path == "/record/1/similar")
        #expect(request.url?.query == "limit=5")
    }

    @Test func missingRecordByID() async {
        let transport = StubTransport(.text("Record with id 99999999 not found", status: 404))
        await #expect(throws: EnchiridionError.notFound) {
            try await EnchiridionClient.test(transport).record(id: 99_999_999)
        }
    }

    @Test func recordBySlug() async throws {
        let transport = StubTransport { request in
            request.url?.path == "/record/slug/tiny-internets"
                ? StubResponse(json: Fixture.bySlug)
                : .text("Record with slug x not found", status: 404)
        }
        let client = EnchiridionClient.test(transport)
        #expect(try await client.record(slug: "tiny-internets")?.id == 812)
        #expect(try await client.record(slug: "tiny-internets-2") == nil)
    }

    @Test func slugIsOnePathSegment() async throws {
        let transport = StubTransport(.text("not found", status: 404))
        _ = try await EnchiridionClient.test(transport).record(slug: "a/b?c#d e")
        let request = try #require(await transport.last())
        #expect(request.url?.path(percentEncoded: true) == "/record/slug/a%2Fb%3Fc%23d%20e")
        #expect(request.url?.query == nil)
    }

    @Test func recordBySlugStillThrowsOtherErrors() async {
        let transport = StubTransport(StubResponse(status: 502))
        await #expect(throws: EnchiridionError.restarting) {
            try await EnchiridionClient.test(transport).record(slug: "x")
        }
    }

    @Test func links() async throws {
        let transport = StubTransport(StubResponse(json: Fixture.linksBundle))
        let bundle = try await EnchiridionClient.test(transport).links(id: 812)
        #expect(bundle.outgoingLinks.count == 1)
        #expect(await transport.last()?.url?.path == "/record/812/links")
    }

    @Test func linksForAMissingRecord() async {
        // The server answers a missing id with 200, application/json and an empty body.
        let transport = StubTransport(StubResponse(json: ""))
        await #expect(throws: EnchiridionError.notFound) {
            try await EnchiridionClient.test(transport).links(id: 4_040)
        }
    }

    @Test func save() async throws {
        let transport = StubTransport(StubResponse(json: Fixture.record))
        let input = RecordInput(slug: "tiny-internets", title: "Tiny internets", url: "https://example.com/tiny-internets",
                                source: .manual)
        let record = try await EnchiridionClient.test(transport).save(input)
        #expect(record.id == 812)
        let request = try #require(await transport.last())
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/record")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try request.jsonObject()
        #expect(body["id"] == nil)
        #expect(body["slug"] as? String == "tiny-internets")
        #expect(body["url"] as? String == "https://example.com/tiny-internets")
        #expect(body["summary"] is NSNull)
        #expect(body["notes"] is NSNull)
        #expect(body["isCurated"] as? Bool == false)
        #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("https://example.com"))
    }

    @Test func duplicateSlugIsAPermanentServerError() async {
        let transport = StubTransport(StubResponse(status: 500, json: #"{"message":"Failed query: insert into \"records\" (\"id\", \"slug\") values (null, ?)\nparams: tiny-internets"}"#))
        do {
            _ = try await EnchiridionClient.test(transport).save(RecordInput(slug: "tiny-internets"))
            Issue.record("expected a throw")
        } catch let error as EnchiridionError {
            guard case .server(500, let message) = error else {
                Issue.record("expected .server, got \(error)")
                return
            }
            #expect(message.hasPrefix("Failed query: insert into"))
            #expect(!error.isTransient)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func setCurated() async throws {
        let transport = StubTransport(StubResponse(json: Fixture.record))
        _ = try await EnchiridionClient.test(transport).setCurated(id: 812, slug: "tiny-internets", true)
        let request = try #require(await transport.last())
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/record")
        #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            == #"{"id":812,"isCurated":true,"slug":"tiny-internets"}"#)
    }

    @Test func deleteRecordAndMedia() async throws {
        let transport = StubTransport { request in
            request.url?.path == "/record/812" ? StubResponse(json: "[\(Fixture.record)]") : StubResponse(json: "[]")
        }
        let client = EnchiridionClient.test(transport)
        let media = try await client.deleteMedia(recordID: 812)
        let deleted = try await client.delete(id: 812)
        #expect(media.isEmpty)
        #expect(deleted.map(\.id) == [812])
        let requests = await transport.recorded()
        #expect(requests.map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" }
            == ["DELETE /media/record/812", "DELETE /record/812"])
        #expect(requests.allSatisfy { $0.httpBody == nil && $0.value(forHTTPHeaderField: "Content-Type") == nil })
    }

    // MARK: Links

    @Test func putAndDeleteLink() async throws {
        let transport = StubTransport { request in
            request.httpMethod == "PUT" ? StubResponse(json: Fixture.link) : StubResponse(json: "[\(Fixture.link)]")
        }
        let client = EnchiridionClient.test(transport)
        let link = try await client.putLink(LinkInput(sourceId: 812, targetId: 4, predicate: .hasFormat))
        #expect(link.id == 1_400)
        let deleted = try await client.deleteLink(id: 1_400)
        #expect(deleted.map(\.id) == [1_400])
        let requests = await transport.recorded()
        #expect(requests[0].httpMethod == "PUT")
        #expect(requests[0].url?.path == "/link")
        #expect(String(decoding: requests[0].httpBody ?? Data(), as: UTF8.self)
            == #"{"predicate":"has_format","sourceId":812,"targetId":4}"#)
        #expect(requests[1].httpMethod == "DELETE")
        #expect(requests[1].url?.path == "/link/1400")
    }

    // MARK: Failures

    @Test func transportErrorsAreMapped() async {
        await #expect(throws: EnchiridionError.tailscaleOff) {
            try await EnchiridionClient.test(StubTransport(failing: .cannotFindHost)).info()
        }
        await #expect(throws: EnchiridionError.offline) {
            try await EnchiridionClient.test(StubTransport(failing: .notConnectedToInternet)).list(.index)
        }
        await #expect(throws: CancellationError.self) {
            try await EnchiridionClient.test(StubTransport(failing: .cancelled)).me()
        }
    }

    @Test func unauthorizedCarriesTheDevice() async {
        let transport = StubTransport(StubResponse(status: 401, headers: ["WWW-Authenticate": #"Tailscale realm="enchiridion""#],
                                                   json: Fixture.unauthorizedKnown))
        await #expect(throws: EnchiridionError.unauthorized(device: Device(id: "nXYZ123CNTRL", name: "vern"))) {
            try await EnchiridionClient.test(transport).list(.index)
        }
    }

    @Test func undecodableSuccessIsADecodingError() async {
        let transport = StubTransport(StubResponse(json: #"{"rows":[]}"#))
        do {
            _ = try await EnchiridionClient.test(transport).list(.index)
            Issue.record("expected a throw")
        } catch let error as EnchiridionError {
            guard case .decoding(let detail) = error else {
                Issue.record("expected .decoding, got \(error)")
                return
            }
            #expect(detail.hasPrefix("Array<ListRecord>"))
        } catch {
            Issue.record("unexpected \(error)")
        }
    }
}

@Suite struct MediaCacheTests {
    /// `AsyncImage` loads record images through `URLCache.shared`: after launch it keeps them in memory, never on disk.
    @Test func mediaStaysInMemory() {
        URLCache.keepMediaInMemory()
        #expect(URLCache.shared.diskCapacity == 0)
        #expect(URLCache.shared.memoryCapacity == URLCache.mediaMemoryCapacity)
        #expect(URLSession.enchiridion.configuration.urlCache == nil, "the API's own session caches nothing at all")
    }
}
