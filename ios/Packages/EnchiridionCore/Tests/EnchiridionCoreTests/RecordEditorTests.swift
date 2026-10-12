import EnchiridionKit
import Foundation
import Synchronization
import Testing
@testable import EnchiridionCore

struct RecordSlugTests {
    @Test func fromTheTitleElseTheURL() {
        #expect(RecordSlug.base(title: "Hello, World!", url: "https://example.com/x") == "hello-world")
        #expect(RecordSlug.base(title: "🌱🌱", url: "https://www.example.com/posts/Tiny_Internets?x=1#top")
            == "example-com-posts-tiny-internets")
        #expect(RecordSlug.base(title: nil, url: "https://example.com/") == "example-com")
        #expect(RecordSlug.base(title: "🌱", url: nil) == "")
        #expect(RecordSlug.base(title: nil, url: "not a url") == "")
    }

    @Test func aBareHostIsReadAsAWebAddress() {
        // The editor's URL field prompts "example.com", and links open bare hosts as https.
        #expect(RecordSlug.base(title: nil, url: "example.com/article") == "example-com-article")
        #expect(RecordSlug.base(title: "🌱", url: " www.example.com/posts/Tiny_Internets ")
            == "example-com-posts-tiny-internets")
        #expect(RecordSlug.fromURL("example.com") == "example-com")
        #expect(RecordSlug.fromURL("localhost:4321/x") == "localhost-x")
        #expect(RecordSlug.fromURL("mailto:chase@example.com") == "", "a scheme that names no host")
        #expect(WebAddress.url("example.com/article")?.absoluteString == "https://example.com/article")
        #expect(WebAddress.url("http://example.com")?.absoluteString == "http://example.com")
        #expect(WebAddress.url("mailto:chase@example.com") == nil)
        #expect(WebAddress.url("not a url") == nil)
    }

    @Test func urlSlugsAreCutAtAWord() {
        let path = (1 ... 30).map { "word\($0)" }.joined(separator: "/")
        let slug = RecordSlug.fromURL("https://example.com/\(path)")
        #expect(slug.count <= RecordSlug.urlSlugLimit)
        #expect(slug.hasPrefix("example-com-word1-word2"))
        #expect(!slug.hasSuffix("-"))
        #expect(slug.split(separator: "-").allSatisfy { $0 == "example" || $0 == "com" || $0.hasPrefix("word") })
        #expect(RecordSlug.truncated("abcdefghij", to: 4) == "abcd", "no hyphen to cut at")
    }

    @Test func candidates() {
        let candidates = RecordSlug.candidates(for: "tiny")
        #expect(candidates.count == RecordSlug.maxProbes)
        #expect(candidates.prefix(3) == ["tiny", "tiny-2", "tiny-3"])
        #expect(candidates.last == "tiny-20")
    }
}

struct RecordDraftTests {
    @Test func whatCountsAsSomethingToSave() {
        #expect(!RecordDraft().hasContent)
        #expect(!RecordDraft(title: "  ", notes: "only notes").hasContent)
        #expect(RecordDraft(title: "A title").hasContent)
        #expect(RecordDraft(url: "https://example.com").hasContent)
        #expect(RecordDraft(summary: "A summary").hasContent)
        #expect(RecordDraft(content: "Some content").hasContent)
    }

    @Test func blankFieldsAreSentAsNull() throws {
        let input = RecordDraft(title: "  Tiny internets ", url: " ", summary: "\n", content: "Line one\nLine two\n")
            .input(slug: "tiny-internets")
        #expect(input == RecordInput(slug: "tiny-internets", type: .artifact, title: "Tiny internets", url: nil,
                                     summary: nil, content: "Line one\nLine two\n", notes: nil, source: .manual))
    }
}

@MainActor
struct RecordEditorModelTests {
    /// A server holding records by slug: lookups answer from it, creates add to it.
    private func server(taken: Set<String>, onSave: @escaping @Sendable (StubRequest) throws -> StubResponse = { _ in
        .json(Fixture.record(900, slug: "unused"))
    }) -> StubTransport {
        StubTransport { request in
            if request.method == "GET", request.path.hasPrefix("/record/slug/") {
                let slug = String(request.path.dropFirst("/record/slug/".count))
                return taken.contains(slug) ? .json(Fixture.record(1, slug: slug)) : .notFound
            }
            return try onSave(request)
        }
    }

    @Test func aNewRecordGetsTheFirstFreeSlug() async throws {
        let created = Fixture.record(42, slug: "hello-world-3", title: "Hello, World!")
        let transport = server(taken: ["hello-world", "hello-world-2"], onSave: { _ in .json(created) })
        let log = ChangeLog()
        let editor = RecordEditorModel(environment: .test(transport), onChange: log.handler)
        editor.draft.title = "Hello, World!"
        editor.draft.notes = "Read again"

        #expect(await editor.save() == created)
        #expect(editor.state == .saved(created))
        #expect(log.changes == [.created(created)])
        #expect(await transport.routes == ["GET /record/slug/hello-world", "GET /record/slug/hello-world-2",
                                           "GET /record/slug/hello-world-3", "PUT /record"])
        let body = try #require(await transport.requests.last).json()
        #expect(body["id"] == nil, "a create sends no id")
        #expect(body["slug"] as? String == "hello-world-3")
        #expect(body["type"] as? String == "artifact")
        #expect(body["source"] as? String == "manual")
        #expect(body["notes"] as? String == "Read again")
        #expect(body["url"] is NSNull)
        #expect(body["isCurated"] as? Bool == false)
    }

    @Test func twentyTakenSlugsFallBack() async throws {
        let taken = Set(RecordSlug.candidates(for: "tiny"))
        let transport = server(taken: taken)
        let editor = RecordEditorModel(environment: .test(transport, fallbackSlug: "note-0000beef"))
        editor.draft.title = "Tiny"
        await editor.save()
        #expect(await transport.routes.count == RecordSlug.maxProbes + 1)
        #expect(try #require(await transport.requests.last).json()["slug"] as? String == "note-0000beef")
    }

    @Test func nothingToMakeASlugFromStartsWithAFallback() async throws {
        let transport = server(taken: [])
        let editor = RecordEditorModel(environment: .test(transport, fallbackSlug: "note-1a2b3c4d"))
        editor.draft.content = "A thought without a title."
        await editor.save()
        #expect(await transport.routes == ["GET /record/slug/note-1a2b3c4d", "PUT /record"])
    }

    @Test func anEditResendsItsOwnSlugAndOnlyWhatChanged() async throws {
        var original = Fixture.record(5, slug: "tiny-internets", title: "Tiny internets", url: "https://example.com")
        original.summary = "Old summary"
        original.source = .readwise
        let record = original
        let transport = server(taken: [], onSave: { _ in .json(record) })
        let log = ChangeLog()
        let editor = RecordEditorModel(draft: RecordDraft(record), environment: .test(transport),
                                       onChange: log.handler)
        #expect(!editor.isNew)
        #expect(!editor.hasChanges)
        editor.draft.title = "Small internets"
        editor.draft.summary = ""
        #expect(editor.hasChanges)

        await editor.save()
        #expect(await transport.routes == ["PUT /record"], "no slug probing for an edit")
        let body = try #require(await transport.requests.last).json()
        #expect(Set(body.keys) == ["id", "slug", "title", "summary"], "nothing untouched is written back")
        #expect(body["id"] as? Int == 5)
        #expect(body["slug"] as? String == "tiny-internets", "the title changed; the slug didn't")
        #expect(body["title"] as? String == "Small internets")
        #expect(body["summary"] is NSNull, "an emptied field clears")
        #expect(log.changes == [.updated(record)])
    }

    @Test func anEditFromAStaleRowLeavesWhatItDidNotTouch() async throws {
        // The row was loaded before an agent added notes and curated the record; the edit fixes a typo in the title.
        let stale = Fixture.row(812, title: "Tiny internt")
        let transport = server(taken: [], onSave: { _ in .json(Fixture.record(812, title: "Tiny internet")) })
        let editor = RecordEditorModel(draft: RecordDraft(stale), environment: .test(transport))
        editor.draft.title = "Tiny internet"
        await editor.save()
        let body = try #require(await transport.requests.last).json()
        #expect(Set(body.keys) == ["id", "slug", "title"])
    }

    @Test func anEditWithNothingChangedOnlyReadsTheRecordBack() async {
        let fresh = Fixture.record(5, title: "Changed elsewhere")
        let transport = StubTransport { request in
            request.route == "GET /record/5" ? .json(RecordDetail(record: fresh)) : .notFound
        }
        let log = ChangeLog()
        let editor = RecordEditorModel(draft: RecordDraft(Fixture.record(5)), environment: .test(transport),
                                       onChange: log.handler)
        #expect(await editor.save() == fresh)
        #expect(await transport.routes == ["GET /record/5"], "no write")
        #expect(log.changes == [.updated(fresh)])
    }

    @Test func anEditOfARecordDeletedElsewhereSaysSoAndDropsIt() async {
        let transport = StubTransport { _ in
            .raw(#"{"error":{"code":"not_found","message":"Record 5 doesn't exist (anymore)"},"message":"x"}"#,
                 status: 404)
        }
        let log = ChangeLog()
        let editor = RecordEditorModel(draft: RecordDraft(Fixture.record(5)), environment: .test(transport),
                                       onChange: log.handler)
        editor.draft.notes = "Too late"
        #expect(await editor.save() == nil)
        #expect(editor.state == .failed(.notFound))
        #expect(editor.draft.notes == "Too late")
        #expect(log.changes.isEmpty, "not yet: that would close the detail presenting the editor, error and text with it")
        editor.close()
        #expect(log.changes == [.deleted(id: 5)])
        editor.close()
        #expect(log.changes == [.deleted(id: 5)], "once")
    }

    @Test func editsMadeAfterALostCreateGoToTheRecordThatLanded() async throws {
        let server = FakeRecordServer()
        let transport = StubTransport { try server.handle($0) }
        let log = ChangeLog()
        let editor = RecordEditorModel(environment: .test(transport), onChange: log.handler)
        editor.draft.title = "Tiny"
        server.loseNextAnswer()
        await editor.save()
        #expect(editor.state == .failed(.unreachable), "landed, but neither the answer nor the check got back")
        #expect(editor.mayHaveSaved, "\"Couldn't confirm the save\"")

        // Retitled before saving again: the same record takes the new title; no second record.
        editor.draft.title = "Small"
        server.recover()
        let saved = try #require(await editor.save())
        #expect(server.records.count == 1)
        #expect(saved.id == 42)
        #expect(saved.slug == "tiny", "the slug the create used stays")
        #expect(saved.title == "Small")
        let update = try #require(server.puts.last)
        #expect(Set(update.keys) == ["id", "slug", "title"])
        #expect(log.changes == [.created(saved)])
    }

    @Test func aURLChangedAfterALostCreateUpdatesTheRecordToo() async throws {
        let server = FakeRecordServer()
        let transport = StubTransport { try server.handle($0) }
        let editor = RecordEditorModel(environment: .test(transport))
        editor.draft.title = "Tiny"
        editor.draft.url = "example.com/tiny"
        server.loseNextAnswer()
        await editor.save()
        #expect(editor.state == .failed(.unreachable))

        editor.draft.url = "https://example.com/tiny"
        editor.draft.notes = "Read again"
        server.recover()
        let saved = try #require(await editor.save())
        #expect(server.records.count == 1)
        #expect(saved.url == "https://example.com/tiny")
        #expect(saved.notes == "Read again")
    }

    @Test func anUpdateThatFailsAfterALostCreateIsSentAgainNotCreated() async throws {
        let server = FakeRecordServer()
        let transport = StubTransport { try server.handle($0) }
        let editor = RecordEditorModel(environment: .test(transport))
        editor.draft.title = "Tiny"
        server.loseNextAnswer()
        await editor.save()
        editor.draft.notes = "One"
        server.recover()
        server.loseNextAnswer() // the update lands, its answer doesn't
        await editor.save()
        #expect(editor.state == .failed(.unreachable))

        editor.draft.notes = "Two"
        server.recover()
        let saved = try #require(await editor.save())
        #expect(server.records.count == 1)
        #expect(saved.notes == "Two")
        #expect(server.puts.filter { $0["id"] == nil }.count == 1, "one create, then updates")
    }

    @Test func aRetryAfterALostCreateKeepsWhatChangedElsewhere() async throws {
        let server = FakeRecordServer()
        let transport = StubTransport { try server.handle($0) }
        let editor = RecordEditorModel(environment: .test(transport))
        editor.draft.title = "Tiny"
        server.loseNextAnswer()
        await editor.save()
        #expect(editor.state == .failed(.unreachable))

        // Meanwhile an agent curates the record and writes a summary.
        server.edit(42) {
            $0.isCurated = true
            $0.summary = "Written by an agent"
        }
        server.recover()
        let saved = try #require(await editor.save())
        #expect(server.puts.count == 1, "nothing edited here since the create, so nothing is written")
        #expect(saved.isCurated)
        #expect(saved.summary == "Written by an agent")
    }

    @Test func anEditAfterALostCreateSendsOnlyItself() async throws {
        let server = FakeRecordServer()
        let transport = StubTransport { try server.handle($0) }
        let editor = RecordEditorModel(environment: .test(transport))
        editor.draft.title = "Tiny"
        server.loseNextAnswer()
        await editor.save()

        server.edit(42) {
            $0.isCurated = true
            $0.summary = "Written by an agent"
        }
        editor.draft.notes = "Phone note"
        server.recover()
        let saved = try #require(await editor.save())
        let update = try #require(server.puts.last)
        #expect(Set(update.keys) == ["id", "slug", "notes"])
        #expect(saved.notes == "Phone note")
        #expect(server.records.first?.isCurated == true)
        #expect(server.records.first?.summary == "Written by an agent")
    }

    @Test func aFieldPutBackAfterAnUpdateThatMayHaveLandedIsSentAgain() async throws {
        let server = FakeRecordServer()
        let transport = StubTransport { try server.handle($0) }
        let editor = RecordEditorModel(environment: .test(transport))
        editor.draft.title = "Tiny"
        server.loseNextAnswer()
        await editor.save()
        editor.draft.notes = "One"
        server.recover()
        server.loseNextAnswer() // the update lands, its answer doesn't
        await editor.save()
        #expect(editor.state == .failed(.unreachable))

        // Back to what the create sent: still different from what the lost update stored.
        editor.draft.notes = ""
        server.recover()
        let saved = try #require(await editor.save())
        let update = try #require(server.puts.last)
        #expect(Set(update.keys) == ["id", "slug", "notes"])
        #expect(update["notes"] is NSNull)
        #expect(saved.notes == nil)
        #expect(server.records.first?.notes == nil)
    }

    /// Record 42, "Tiny", on `server`, and an editor open on it (over `transport`, else straight to the server).
    private func editingTiny(on server: FakeRecordServer, transport: (any HTTPTransport)? = nil,
                             clock: any Clock<Duration> = ContinuousClock(),
                             timings: Timings = .immediate) -> (RecordEditorModel, ChangeLog) {
        let tiny = Fixture.record(42, slug: "tiny", title: "Tiny")
        server.seed(tiny)
        let log = ChangeLog()
        let environment = AppEnvironment.test(transport ?? StubTransport { try server.handle($0) }, clock: clock,
                                              timings: timings)
        return (RecordEditorModel(draft: RecordDraft(tiny), environment: environment, onChange: log.handler), log)
    }

    @Test func aFieldPutBackAfterALostEditIsSentAgain() async throws {
        let server = FakeRecordServer()
        let (editor, log) = editingTiny(on: server)
        editor.draft.title = "Small"
        server.loseNextAnswer() // the update lands; neither its answer nor the check after it gets back
        #expect(await editor.save() == nil)
        #expect(editor.state == .failed(.unreachable))
        #expect(editor.mayHaveSaved, "the update may have landed")
        #expect(server.records.first?.title == "Small")
        #expect(log.changes.isEmpty)

        // Back to how the editor opened: nothing left in the draft, but the server may hold "Small".
        editor.draft.title = "Tiny"
        #expect(!editor.hasChanges)
        #expect(editor.hasUnsettledEdit, "Save stays on, and closing asks first")
        server.recover()
        let saved = try #require(await editor.save())
        let update = try #require(server.puts.last)
        #expect(Set(update.keys) == ["id", "slug", "title"])
        #expect(update["title"] as? String == "Tiny")
        #expect(saved.title == "Tiny")
        #expect(server.records.first?.title == "Tiny")
        #expect(!editor.hasUnsettledEdit)
        #expect(log.changes == [.updated(saved)])
    }

    @Test func anEditAfterALostOneCarriesItsFieldsToo() async throws {
        let server = FakeRecordServer()
        let (editor, _) = editingTiny(on: server)
        editor.draft.title = "Small"
        server.loseNextAnswer()
        await editor.save()
        editor.draft.title = "Tiny"
        editor.draft.notes = "Read again"
        server.recover()
        let saved = try #require(await editor.save())
        #expect(Set(try #require(server.puts.last).keys) == ["id", "slug", "title", "notes"])
        #expect(saved.title == "Tiny")
        #expect(saved.notes == "Read again")
    }

    @Test func aLostEditThatLandedIsASave() async throws {
        let server = FakeRecordServer()
        let (editor, log) = editingTiny(on: server)
        editor.draft.title = "Small"
        server.loseNextAnswer(lookupsToo: false)
        let saved = try #require(await editor.save())
        #expect(saved.title == "Small")
        #expect(editor.state == .saved(saved))
        #expect(!editor.hasUnsettledEdit)
        #expect(log.changes == [.updated(saved)])
        #expect(server.puts.count == 1)
    }

    @Test func aLostEditTheRecordDoesNotHoldIsNotASave() async {
        let tiny = Fixture.record(42, slug: "tiny", title: "Tiny")
        let transport = StubTransport { request in
            switch request.route {
            case "PUT /record": throw URLError(.timedOut) // it never arrived
            case "GET /record/42": .json(RecordDetail(record: tiny))
            default: .notFound
            }
        }
        let editor = RecordEditorModel(draft: RecordDraft(tiny), environment: .test(transport))
        editor.draft.title = "Small"
        #expect(await editor.save() == nil)
        #expect(editor.state == .failed(.unreachable))
        #expect(editor.hasUnsettledEdit)
        #expect(await transport.routes == ["PUT /record", "GET /record/42"])
    }

    @Test func discardingAfterALostEditShowsWhatTheServerHolds() async throws {
        let server = FakeRecordServer()
        let (editor, log) = editingTiny(on: server)
        editor.draft.title = "Small"
        server.loseNextAnswer()
        await editor.save()
        server.recover()
        // Cancel, then Discard: the rows and the detail take the record as stored, not the "Tiny" they had.
        await editor.close()?.value
        let stored = try #require(server.records.first)
        #expect(stored.title == "Small")
        #expect(log.changes == [.updated(stored)])
        #expect(editor.close() == nil, "once")
    }

    @Test func aStalledEditGivesUpAtTheDeadlineAndIsSentAgain() async throws {
        let clock = TestClock()
        let server = FakeRecordServer()
        // The update reaches the server, and its answer stalls.
        let transport = HoldingTransport(StubTransport { try server.handle($0) }) { $0.route == "PUT /record" }
        let (editor, log) = editingTiny(on: server, transport: transport, clock: clock, timings: .standard)
        editor.draft.title = "Small"
        let saving = Task { await editor.save() }
        await transport.waitUntilHeld()
        await clock.waitForSleepers(1)
        #expect(editor.state == .saving)
        clock.advance(by: Timings.standard.editorDeadline)
        #expect(await saving.value == nil)
        #expect(editor.state == .failed(.unreachable))
        #expect(editor.canSave, "Save, Cancel and swiping away are back")
        #expect(editor.hasUnsettledEdit, "the stalled update reached the server")
        #expect(server.records.first?.title == "Small")
        #expect(log.changes.isEmpty)

        await transport.hold { _ in false }
        editor.draft.title = "Tiny"
        let saved = try #require(await editor.save())
        #expect(saved.title == "Tiny", "the put-back title went, though the draft no longer differs")
        #expect(server.records.first?.title == "Tiny")
    }

    @Test func aStalledCreateGivesUpAtTheDeadlineAndRetryFindsWhatLanded() async throws {
        let clock = TestClock()
        let server = FakeRecordServer()
        // The create reaches the server, and its answer stalls.
        let transport = HoldingTransport(StubTransport { try server.handle($0) }) { $0.route == "PUT /record" }
        let editor = RecordEditorModel(environment: .test(transport, clock: clock, timings: .standard))
        editor.draft.title = "Tiny"
        let saving = Task { await editor.save() }
        await transport.waitUntilHeld()
        await clock.waitForSleepers(1)
        clock.advance(by: Timings.standard.editorDeadline)
        #expect(await saving.value == nil)
        #expect(editor.state == .failed(.unreachable))

        let saved = try #require(await editor.save())
        #expect(saved.id == 42)
        #expect(server.records.count == 1, "the retry found the record the stalled save made")
        #expect(await transport.stub.routes.filter { $0 == "PUT /record" }.count == 1)
    }

    @Test func discardingAfterALostCreateShowsTheRecordThatLanded() async throws {
        let server = FakeRecordServer()
        let transport = StubTransport { try server.handle($0) }
        let log = ChangeLog()
        let editor = RecordEditorModel(environment: .test(transport), onChange: log.handler)
        editor.draft.title = "Tiny"
        server.loseNextAnswer()
        #expect(await editor.save() == nil)
        #expect(log.changes.isEmpty)

        // Cancel, then Discard: the record is on the server, so the list gets it now, not at the next reload.
        server.recover()
        await editor.close()?.value
        let stored = try #require(server.records.first)
        #expect(log.changes == [.created(stored)])
        #expect(editor.close() == nil, "once")
        #expect(server.records.count == 1)
    }

    @Test func discardingAfterACreateThatNeverLandedReportsNothing() async {
        // The PUT never arrived, and the check after it timed out too.
        let lookups = Mutex(0)
        let transport = StubTransport { request in
            switch request.route {
            case "GET /record/slug/tiny":
                let lookup = lookups.withLock { count in
                    count += 1
                    return count
                }
                if lookup == 2 { throw URLError(.timedOut) }
                return .notFound
            case "PUT /record":
                throw URLError(.timedOut)
            default:
                return .notFound
            }
        }
        let log = ChangeLog()
        let editor = RecordEditorModel(environment: .test(transport), onChange: log.handler)
        editor.draft.title = "Tiny"
        await editor.save()
        #expect(editor.mayHaveSaved)
        await editor.close()?.value
        #expect(log.changes.isEmpty)
        #expect(await transport.routes.last == "GET /record/slug/tiny", "looked it up as it closed")
    }

    @Test func discardingAfterAnEditToALandedCreateFailedReportsTheRecordAsStored() async throws {
        let server = FakeRecordServer()
        let transport = StubTransport { try server.handle($0) }
        let log = ChangeLog()
        let editor = RecordEditorModel(environment: .test(transport), onChange: log.handler)
        editor.draft.title = "Tiny"
        server.loseNextAnswer()
        await editor.save()
        editor.draft.notes = "One"
        server.recover()
        server.loseNextAnswer() // the create is found; the update to it lands, its answer doesn't
        await editor.save()
        #expect(editor.mayHaveSaved)

        server.recover()
        await editor.close()?.value
        let stored = try #require(server.records.first)
        #expect(stored.notes == "One")
        #expect(log.changes == [.created(stored)], "read back, with the update that landed")
    }

    @Test func closingAfterASavedCreateReportsNothingMore() async throws {
        let server = FakeRecordServer()
        let transport = StubTransport { try server.handle($0) }
        let log = ChangeLog()
        let editor = RecordEditorModel(environment: .test(transport), onChange: log.handler)
        editor.draft.title = "Tiny"
        let saved = try #require(await editor.save())
        #expect(editor.close() == nil)
        #expect(log.changes == [.created(saved)])
    }

    @Test func nothingToSaveSendsNothing() async {
        let transport = server(taken: [])
        let editor = RecordEditorModel(environment: .test(transport))
        editor.draft.notes = "Just a note"
        #expect(!editor.canSave)
        #expect(editor.validationMessage == "Add a title, URL, summary or content to save.")
        #expect(await editor.save() == nil)
        #expect(await transport.routes.isEmpty)
        #expect(editor.state == .editing)
    }

    @Test func aRejectedSaveFailsWithoutALookup() async {
        let transport = server(taken: [], onSave: { _ in
            .raw(#"{"message":"Failed query: insert into \"records\""}"#, status: 500)
        })
        let editor = RecordEditorModel(environment: .test(transport))
        editor.draft.title = "Tiny"
        await editor.save()
        #expect(editor.state == .failed(.server(status: 500, message: #"Failed query: insert into "records""#)))
        #expect(!editor.mayHaveSaved, "refused: \"Couldn't save the record\"")
        #expect(await transport.routes == ["GET /record/slug/tiny", "PUT /record"])
        #expect(editor.canSave, "Save works again for a retry")
    }

    @Test func aRetryAfterRetitlingTakesTheNewTitle() async throws {
        let attempts = Mutex(0)
        let transport = server(taken: [], onSave: { _ in
            let attempt = attempts.withLock { count in
                count += 1
                return count
            }
            if attempt == 1 { throw URLError(.cannotConnectToHost) }
            return .json(Fixture.record(42, slug: "small"))
        })
        let editor = RecordEditorModel(environment: .test(transport))
        editor.draft.title = "Tiny"
        await editor.save()
        #expect(editor.state == .failed(.unreachable))

        editor.draft.title = "Small"
        await editor.save()
        #expect(editor.state.savedRecord?.slug == "small")
        #expect(await transport.routes == [
            "GET /record/slug/tiny", "PUT /record", "GET /record/slug/tiny",
            "GET /record/slug/tiny", "GET /record/slug/small", "PUT /record",
        ])
        #expect(try #require(await transport.requests.last).json()["slug"] as? String == "small")
    }

    @Test func aCreateWhoseAnswerWasLostIsFound() async {
        let stored = Mutex<Record?>(nil)
        let transport = StubTransport { request in
            switch request.route {
            case "GET /record/slug/tiny":
                return stored.withLock { $0 }.map { .json($0) } ?? .notFound
            case "PUT /record":
                stored.withLock { $0 = Fixture.record(42, slug: "tiny", title: "Tiny", url: "https://example.com") }
                throw URLError(.timedOut)
            default:
                return .notFound
            }
        }
        let editor = RecordEditorModel(environment: .test(transport))
        editor.draft.title = "Tiny"
        editor.draft.url = "https://example.com"
        await editor.save()
        #expect(editor.state.savedRecord?.id == 42)
        #expect(await transport.routes == ["GET /record/slug/tiny", "PUT /record", "GET /record/slug/tiny"])
    }
}
