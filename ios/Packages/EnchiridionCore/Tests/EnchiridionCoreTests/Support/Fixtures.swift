import EnchiridionKit
import struct EnchiridionKit.Predicate
import Foundation

/// Rows and records shaped like the live data.
enum Fixture {
    static func row(_ id: Int, title: String? = nil, type: RecordType = .artifact, curated: Bool = false,
                    created: DBTimestamp = "2026-09-14 15:00:00", url: String? = nil,
                    media: [Media] = []) -> ListRecord {
        ListRecord(id: id, slug: "record-\(id)", title: title ?? "Record \(id)", url: url, type: type,
                   recordCreatedAt: created, isCurated: curated, source: .manual, media: media)
    }

    static func record(_ id: Int, slug: String? = nil, title: String? = nil, url: String? = nil,
                       curated: Bool = false, created: DBTimestamp = "2026-09-14 15:00:00") -> Record {
        Record(id: id, slug: slug ?? "record-\(id)", title: title ?? "Record \(id)", url: url, isCurated: curated,
               source: .manual, recordCreatedAt: created)
    }

    static func media(_ id: Int, recordID: Int) -> Media {
        Media(id: id, recordId: recordID, url: "/uploads/images/\(id).jpg", type: "image",
              contentTypeString: "image/jpeg", recordCreatedAt: "2026-09-14 15:00:01")
    }

    static func link(_ id: Int, from source: Int, to target: Int, _ predicate: Predicate) -> Link {
        Link(id: id, sourceId: source, targetId: target, predicate: predicate, recordCreatedAt: "2026-09-14 15:00:02")
    }
}
