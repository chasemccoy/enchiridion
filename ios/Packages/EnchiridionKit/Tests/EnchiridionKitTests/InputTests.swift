@testable import EnchiridionKit
import Foundation
import Testing

private func json(_ value: some Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

@Suite struct InputTests {
    @Test func createEncodesNullsAndOmitsID() throws {
        let input = RecordInput(slug: "tiny-internets", title: "Tiny internets", url: "https://example.com/a")
        #expect(try json(input) == #"{"content":null,"isCurated":false,"notes":null,"slug":"tiny-internets","source":null,"summary":null,"title":"Tiny internets","type":"artifact","url":"https://example.com/a"}"#)
    }

    @Test func updateCarriesIDAndClearsEmptiedFields() throws {
        var input = RecordInput(try JSONDecoder().decode(Record.self, from: Data(Fixture.record.utf8)))
        #expect(input.id == 812)
        #expect(input.slug == "tiny-internets")
        #expect(input.isCurated)
        #expect(input.notes == "A note")
        input.notes = nil
        input.type = .concept
        #expect(try json(input) == #"{"content":"Body","id":812,"isCurated":true,"notes":null,"slug":"tiny-internets","source":"manual","summary":"Page meta description","title":"Tiny internets","type":"concept","url":"https://example.com/tiny-internets"}"#)
    }

    @Test func anUpdateSendsOnlyTheFieldsItChanges() throws {
        let stored = RecordInput(try JSONDecoder().decode(Record.self, from: Data(Fixture.record.utf8)))
        var edited = stored
        edited.title = "Small internets"
        edited.notes = nil
        let changed = edited.fieldsDiffering(from: stored)
        #expect(changed == [.title, .notes])
        // The notes cleared go as null; every untouched column, stale or not, stays off the wire.
        #expect(try json(edited.only(changed))
            == #"{"id":812,"notes":null,"slug":"tiny-internets","title":"Small internets"}"#)
        #expect(try json(edited.only([])) == #"{"id":812,"slug":"tiny-internets"}"#)
        #expect(stored.fieldsDiffering(from: stored).isEmpty)
        #expect(Set(RecordInput.Field.allCases.map(\.rawValue))
            == ["type", "title", "url", "isCurated", "summary", "content", "notes", "source"])
    }

    @Test func inputFromListRow() throws {
        let row = try JSONDecoder().decode(ListRecord.self, from: Data(Fixture.highlightRow.utf8))
        let input = RecordInput(row)
        #expect(input == RecordInput(id: 901, slug: "01gmm8fjrxc8g1k5sh80rkxdp2", type: .artifact, title: nil, url: nil,
                                     isCurated: true, summary: nil, content: "A highlighted passage.", notes: "my note",
                                     source: .readwise))
    }

    @Test func linkInputOmitsNils() throws {
        #expect(try json(LinkInput(sourceId: 812, targetId: 4, predicate: .hasFormat))
            == #"{"predicate":"has_format","sourceId":812,"targetId":4}"#)
        #expect(try json(LinkInput(id: 9, sourceId: 1, targetId: 2, predicate: .creatorOf, notes: "n"))
            == #"{"id":9,"notes":"n","predicate":"creator_of","sourceId":1,"targetId":2}"#)
    }

    @Test func indexQueryMatchesTheWeb() throws {
        #expect(try json(ListQuery.index) == #"{"filters":{"hideUntitledChildren":true},"limit":100000,"orderBy":[{"direction":"desc","field":"recordCreatedAt"},{"direction":"asc","field":"slug"}]}"#)
    }

    @Test func emptyQueryTakesServerDefaults() throws {
        #expect(try json(ListQuery()) == #"{"filters":{}}"#)
        let query = ListQuery(filters: .init(type: .concept, isCurated: false, text: "tiny"), limit: 20, offset: 40)
        #expect(try json(query) == #"{"filters":{"isCurated":false,"text":"tiny","type":"concept"},"limit":20,"offset":40}"#)
    }
}
