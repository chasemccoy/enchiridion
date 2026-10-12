@testable import EnchiridionKit
import struct EnchiridionKit.Predicate   // Foundation has a `Predicate` too; this one wins in type positions
import Foundation
import Testing

@Suite struct PredicateTests {
    @Test func vocabulary() {
        #expect(Predicate.vocabulary.count == 20)
        #expect(Set(Predicate.known).count == 20)
        #expect(Predicate.vocabulary.filter(\.canonical).count == 11)
    }

    @Test(arguments: Predicate.vocabulary)
    func inversesPair(definition: Predicate.Definition) throws {
        let inverse = try #require(definition.inverse.definition)
        #expect(inverse.inverse == definition.slug)
        #expect(inverse.type == definition.type)
        #expect(inverse.role == definition.role)
        // Exactly one direction of a pair is stored; a self-inverse predicate is canonical.
        if inverse.slug == definition.slug {
            #expect(definition.canonical)
        } else {
            #expect(inverse.canonical != definition.canonical)
        }
    }

    @Test func displayNames() {
        #expect(Predicate.createdBy.displayName(.outgoing) == "created by")
        #expect(Predicate.createdBy.displayName(.incoming) == "creator of")
        #expect(Predicate.containedBy.displayName(.incoming) == "contains")
        #expect(Predicate.taggedWith.displayName(.incoming) == "tag of")
        #expect(Predicate.relatedTo.displayName(.incoming) == "related to")
        #expect(Predicate.hasFormat.name == "has format")
    }

    @Test func unknownSlug() throws {
        let odd: Predicate = "inspired_by"
        #expect(!odd.isKnown)
        #expect(odd.definition == nil)
        #expect(odd.name == "inspired by")
        #expect(odd.displayName(.incoming) == "inspired by")
        #expect(odd.type == nil)
        #expect(!odd.isCanonical)
        let decoded = try JSONDecoder().decode([Predicate].self, from: Data(#"["inspired_by","via"]"#.utf8))
        #expect(decoded == [odd, .via])
        #expect(String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self) == #"["inspired_by","via"]"#)
    }

    @Test func byType() {
        #expect(Predicate.ofType(.containment) == [.containedBy, .contains, .quotes, .quotedIn])
        #expect(Predicate.ofType(.description) == [.hasFormat, .formatOf, .taggedWith, .tagOf])
        #expect(Predicate.ofType(.identity) == [.sameAs])
        #expect(Predicate.createdBy.definition?.role == "creator")
        #expect(Predicate.createdBy.isCanonical)
        #expect(!Predicate.creatorOf.isCanonical)
    }

    @Test func recordTypesAndSources() throws {
        #expect(RecordType.known.map(\.displayName) == ["Artifact", "Concept", "Entity"])
        #expect(RecordSource.readwise.displayName == "Readwise")
        let types = try JSONDecoder().decode([RecordType].self, from: Data(#"["entity","place"]"#.utf8))
        #expect(types == [.entity, "place"])
        #expect(types.map(\.isKnown) == [true, false])
    }
}
