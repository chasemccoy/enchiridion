import EnchiridionKit
import Foundation
import Synchronization
import Testing
@testable import EnchiridionCore

struct ShareInputTests {
    private let page = URL(string: "https://example.com/sqlite")!

    @Test func safariResultsComeFirst() {
        let input = ShareInput.from(
            javaScript: ["url": "https://example.com/sqlite", "title": " Why SQLite is so great ", "selection": "",
                         "description": " A database in a file. "],
            url: URL(string: "https://other.example/"), text: "ignored"
        )
        #expect(input == ShareInput(url: page, title: "Why SQLite is so great", summary: "A database in a file."))
    }

    @Test func javaScriptWithoutAWebPageIsIgnored() {
        let input = ShareInput.from(javaScript: ["url": "about:blank", "title": "Blank"], url: page, text: nil)
        #expect(input == ShareInput(url: page))
    }

    @Test func aURLItemThenText() {
        #expect(ShareInput.from(javaScript: nil, url: page, text: nil) == ShareInput(url: page))
        #expect(ShareInput.from(javaScript: [:], url: page, text: "A page title")
            == ShareInput(url: page, title: "A page title"))
        #expect(ShareInput.from(javaScript: nil, url: page, text: "line one\nline two")
            == ShareInput(url: page, selection: "line one\nline two"))
        #expect(ShareInput.from(javaScript: nil, url: page, text: page.absoluteString) == ShareInput(url: page))
    }

    @Test func textOnly() {
        #expect(ShareInput.from(javaScript: nil, url: nil, text: "  Remember the milk  ")
            == ShareInput(text: "Remember the milk"))
        #expect(ShareInput.from(javaScript: nil, url: nil, text: "https://example.com/sqlite") == ShareInput(url: page),
                "plain text that is just a link is shared as the link")
        #expect(ShareInput.from(javaScript: nil, url: URL(string: "mailto:chase@example.com"), text: nil)
            == ShareInput(text: "mailto:chase@example.com"))
        #expect(ShareInput.from(javaScript: nil, url: nil, text: "   ") == nil)
        #expect(ShareInput.from(javaScript: nil, url: nil, text: nil) == nil)
    }
}

struct ShareDraftTests {
    @Test func fromAPage() {
        let draft = ShareDraft(ShareInput(url: URL(string: "https://example.com/a")!, title: "Tiny\n  internets\n",
                                          selection: "Quoted", summary: "About tiny internets"))
        #expect(draft == ShareDraft(title: "Tiny internets", url: "https://example.com/a",
                                    summary: "About tiny internets", selection: "Quoted"))
        #expect(draft.slugBase == "tiny-internets")
    }

    @Test func sharedTextIsTheContent() {
        let draft = ShareDraft(ShareInput(text: "Remember the milk"))
        #expect(draft.selection == "Remember the milk")
        #expect(draft.url == nil)
        #expect(draft.slugBase == "", "a fallback slug, like the live untitled notes")
    }

    @Test func theCreateBody() {
        var draft = ShareDraft(title: "Tiny internets", url: "https://example.com/a", summary: "About it",
                               selection: "Quoted")
        draft.note = "  Worth a reread  "
        #expect(draft.input(slug: "tiny-internets") == RecordInput(
            slug: "tiny-internets", type: .artifact, title: "Tiny internets", url: "https://example.com/a",
            summary: "About it", content: "Quoted", notes: "Worth a reread", source: .manual
        ))
    }
}

@MainActor
struct ShareComposeModelTests {
    private nonisolated static let page = URL(string: "https://www.example.com/tiny")!
    private nonisolated static let input = ShareInput(url: page, title: "Tiny internets", selection: "A quote",
                                          summary: "About tiny internets")
    /// The record the share's create stores.
    private nonisolated static let saved: Record = {
        var record = Fixture.record(42, slug: "tiny-internets", title: "Tiny internets",
                                    url: "https://www.example.com/tiny")
        record.summary = "About tiny internets"
        record.content = "A quote"
        return record
    }()

    /// A server where the create lands (stored under its slug) and then answers `put`'s way.
    private func server(put: @escaping @Sendable () throws -> StubResponse,
                        lookups: @escaping @Sendable (Record?) throws -> StubResponse = { stored in
                            stored.map { .json($0) } ?? .notFound
                        }) -> StubTransport {
        let stored = Mutex<Record?>(nil)
        let transport = StubTransport { request in
            switch request.route {
            case "GET /record/slug/tiny-internets":
                return try lookups(stored.withLock { $0 })
            case "PUT /record":
                stored.withLock { $0 = Self.saved }
                return try put()
            default:
                return .notFound
            }
        }
        return transport
    }

    @Test func savesTheShareAsAnArtifact() async throws {
        let transport = server(put: { .json(Self.saved) })
        let model = ShareComposeModel(input: Self.input, environment: .test(transport))
        #expect(model.domain == "example.com")
        model.draft.note = "Worth a reread"

        await model.save()
        #expect(model.state == .saved(Self.saved))
        #expect(!model.canSave, "saved once")
        let put = try #require(await transport.requests.last)
        #expect(put.headers["X-Enchiridion-Client"] == "ios/0.1 share")
        let body = put.json()
        #expect(body["type"] as? String == "artifact")
        #expect(body["source"] as? String == "manual")
        #expect(body["title"] as? String == "Tiny internets")
        #expect(body["slug"] as? String == "tiny-internets")
        #expect(body["url"] as? String == "https://www.example.com/tiny")
        #expect(body["summary"] as? String == "About tiny internets")
        #expect(body["content"] as? String == "A quote")
        #expect(body["notes"] as? String == "Worth a reread")
    }

    @Test func aTimeoutThatLandedIsASave() async {
        let transport = server(put: { throw URLError(.timedOut) })
        let model = ShareComposeModel(input: Self.input, environment: .test(transport))
        await model.save()
        #expect(model.state == .saved(Self.saved))
        #expect(await transport.routes == ["GET /record/slug/tiny-internets", "PUT /record",
                                           "GET /record/slug/tiny-internets"])
    }

    @Test func aTimeoutThatDidNotLandFailsAndRetryReusesTheSlug() async {
        let attempts = Mutex(0)
        let transport = StubTransport { request in
            switch request.route {
            case "GET /record/slug/tiny-internets":
                return .notFound
            case "PUT /record":
                let attempt = attempts.withLock { count in
                    count += 1
                    return count
                }
                if attempt == 1 { throw URLError(.networkConnectionLost) }
                return .json(Self.saved)
            default:
                return .notFound
            }
        }
        let model = ShareComposeModel(input: Self.input, environment: .test(transport))
        await model.save()
        #expect(model.state == .failed(.unreachable))
        #expect(!model.mayHaveSaved, "the check got through and found the slug free: \"Not saved\"")
        #expect(model.canSave, "Retry")

        await model.save()
        #expect(model.state == .saved(Self.saved))
        #expect(await transport.routes == [
            "GET /record/slug/tiny-internets", "PUT /record", "GET /record/slug/tiny-internets",
            "GET /record/slug/tiny-internets", "PUT /record",
        ], "the retry checks its slug once and saves under it, not under tiny-internets-2")
    }

    @Test func aRetryFindsWhatTheLastAttemptCouldNotConfirm() async {
        // The probe gets through, then the network drops: the create lands unanswered and the check times out too.
        let lookups = Mutex(0)
        let transport = server(put: { throw URLError(.timedOut) }, lookups: { _ in
            let lookup = lookups.withLock { count in
                count += 1
                return count
            }
            if lookup == 1 { return .notFound }
            throw URLError(.timedOut)
        })
        let model = ShareComposeModel(input: Self.input, environment: .test(transport))
        await model.save()
        #expect(model.state == .failed(.unreachable))
        #expect(model.mayHaveSaved, "landed, for all the card knows: not \"Not saved\", or Cancel and a new share saves twice")

        await transport.respond { request in
            request.route == "GET /record/slug/tiny-internets" ? .json(Self.saved) : .notFound
        }
        await model.save()
        #expect(model.state == .saved(Self.saved))
        #expect(!model.mayHaveSaved)
        #expect(await transport.routes.filter { $0 == "PUT /record" }.count == 1, "never saved twice")
        #expect(await transport.routes.last == "GET /record/slug/tiny-internets")
    }

    @Test func someoneElsesRecordUnderTheSlugIsNotOurs() async {
        let other = Fixture.record(7, slug: "tiny-internets", title: "Tiny internets", url: "https://other.example")
        let found = Mutex(false)
        let transport = StubTransport { request in
            switch request.route {
            case "GET /record/slug/tiny-internets":
                return found.withLock { $0 } ? .json(other) : .notFound
            case "PUT /record":
                found.withLock { $0 = true }
                throw URLError(.timedOut)
            default:
                return .notFound
            }
        }
        let model = ShareComposeModel(input: Self.input, environment: .test(transport))
        await model.save()
        #expect(model.state == .failed(.unreachable))
        #expect(!model.mayHaveSaved, "ours can't be under a slug someone else holds")
    }

    @Test func aRefusalIsNotCheckedForALostSuccess() async {
        let transport = StubTransport { request in
            switch request.route {
            case "GET /record/slug/tiny-internets": .notFound
            default: .raw(#"{"error":{"code":"unauthorized","message":"x"},"message":"x","device":null}"#, status: 401)
            }
        }
        let model = ShareComposeModel(input: Self.input, environment: .test(transport))
        await model.save()
        #expect(model.state == .failed(.unauthorized(device: nil)))
        #expect(!model.mayHaveSaved, "refused: nothing was saved")
        #expect(await transport.routes == ["GET /record/slug/tiny-internets", "PUT /record"])
    }

    @Test func aRefusedRetryAfterAnUnconfirmedOneSaysNotSaved() async {
        // Lost, unchecked; then the retry's check finds the slug free and the server refuses the create.
        let lookups = Mutex(0)
        let transport = StubTransport { request in
            switch request.route {
            case "GET /record/slug/tiny-internets":
                let lookup = lookups.withLock { count in
                    count += 1
                    return count
                }
                if lookup == 2 { throw URLError(.timedOut) }
                return .notFound
            case "PUT /record":
                if lookups.withLock({ $0 }) < 3 { throw URLError(.timedOut) }
                return .raw(#"{"message":"Failed query: insert into \"records\""}"#, status: 500)
            default:
                return .notFound
            }
        }
        let model = ShareComposeModel(input: Self.input, environment: .test(transport))
        await model.save()
        #expect(model.mayHaveSaved)
        await model.save()
        #expect(model.state == .failed(.server(status: 500, message: #"Failed query: insert into "records""#)))
        #expect(!model.mayHaveSaved)
    }

    @Test func aNoteAddedBeforeRetryReachesTheRecordThatLanded() async throws {
        let server = FakeRecordServer()
        let transport = StubTransport { try server.handle($0) }
        let model = ShareComposeModel(input: Self.input, environment: .test(transport))
        server.loseNextAnswer()
        await model.save()
        #expect(model.state == .failed(.unreachable))

        model.draft.note = "Worth a reread"
        server.recover()
        await model.save()
        let saved = try #require(model.state.savedRecord)
        #expect(saved.notes == "Worth a reread", "not dropped behind \"Saved to Enchiridion\"")
        #expect(server.records.count == 1)
        #expect(server.records.first?.notes == "Worth a reread")
    }

    @Test func aRetryWithNoEditsLeavesWhatTheWebChangedSince() async throws {
        let server = FakeRecordServer()
        let transport = StubTransport { try server.handle($0) }
        let model = ShareComposeModel(input: Self.input, environment: .test(transport))
        model.draft.note = "Phone note"
        server.loseNextAnswer()
        await model.save()
        #expect(model.state == .failed(.unreachable))

        // Curated on the web, and a note of its own, while the card says it couldn't confirm the save.
        server.edit(42) {
            $0.isCurated = true
            $0.notes = "Web note"
        }
        server.recover()
        await model.save()
        #expect(model.state.savedRecord?.id == 42)
        #expect(server.puts.count == 1, "no write: the card's draft is what the create sent")
        #expect(server.records.first?.isCurated == true)
        #expect(server.records.first?.notes == "Web note")
    }

    @Test func aTitleAddedToATextShareBeforeRetryMakesNoSecondRecord() async throws {
        let server = FakeRecordServer()
        let transport = StubTransport { try server.handle($0) }
        let model = ShareComposeModel(input: ShareInput(text: "Remember the milk"),
                                      environment: .test(transport, fallbackSlug: "note-0000beef"))
        server.loseNextAnswer()
        await model.save()
        #expect(model.state == .failed(.unreachable))

        model.draft.title = "Milk"
        server.recover()
        await model.save()
        #expect(model.state.savedRecord?.title == "Milk")
        #expect(server.records.map(\.slug) == ["note-0000beef"])
        #expect(server.records.first?.title == "Milk")
    }

    @Test func aStalledSaveGivesUpAtTheDeadlineAndRetryFindsWhatLanded() async throws {
        let clock = TestClock()
        let server = FakeRecordServer()
        // The create reaches the server, and its answer stalls.
        let transport = HoldingTransport(StubTransport { try server.handle($0) }) { $0.route == "PUT /record" }
        let model = ShareComposeModel(input: Self.input,
                                      environment: .test(transport, clock: clock, timings: .standard))
        let saving = Task { await model.save() }
        await transport.waitUntilHeld()
        await clock.waitForSleepers(1)
        #expect(model.state == .saving)
        clock.advance(by: Timings.standard.shareDeadline)
        await saving.value
        #expect(model.state == .failed(.unreachable))
        #expect(model.mayHaveSaved, "the stalled create reached the server: \"Couldn't confirm it saved\"")
        #expect(model.canSave, "Retry, and Cancel is back")

        let retrying = Task { await model.save() }
        await retrying.value
        #expect(model.state.savedRecord?.id == 42)
        #expect(server.records.count == 1, "the retry found the record the stalled save made")
        #expect(await transport.stub.routes.filter { $0 == "PUT /record" }.count == 1)
    }

    @Test func aTextShareGetsAFallbackSlug() async throws {
        let transport = StubTransport { request in
            request.method == "PUT" ? .json(Fixture.record(43, slug: "note-0000beef")) : .notFound
        }
        let model = ShareComposeModel(input: ShareInput(text: "Remember the milk"),
                                      environment: .test(transport, fallbackSlug: "note-0000beef"))
        #expect(model.domain == nil)
        await model.save()
        #expect(model.state.savedRecord?.slug == "note-0000beef")
        let body = try #require(await transport.requests.last).json()
        #expect(body["content"] as? String == "Remember the milk")
        #expect(body["title"] is NSNull)
        #expect(body["url"] is NSNull)
    }
}
