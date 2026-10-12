import Foundation

/// Response bodies in the server's shapes. The list row and detail are the constructed examples from the API map
/// (`queries/records.ts`), not live data.
enum Fixture {
    static let listRow = #"""
    {"id":812,"slug":"tiny-internets","title":"Tiny internets","url":"https://www.example.com/tiny-internets","type":"artifact",
     "content":null,"summary":"Page meta description","recordCreatedAt":"2026-10-11 22:27:12","recordUpdatedAt":"2026-10-11 22:27:12",
     "contentCreatedAt":null,"notes":null,"isCurated":false,"source":"manual",
     "media":[],
     "outgoingLinks":[{"predicate":"has_format","target":{"id":4,"title":"Article","slug":"article"}},
                      {"predicate":"created_by","target":{"id":120,"title":"Jane Doe","slug":"jane-doe"}},
                      {"predicate":"tagged_with","target":{"id":77,"title":"web","slug":"web"}}],
     "incomingLinks":[{"predicate":"related_to"},{"predicate":"contained_by"},{"predicate":"contained_by"},{"predicate":"quotes"}]}
    """#

    /// A Readwise highlight: untitled, source readwise, ULID slug, an image, a containment parent.
    static let highlightRow = #"""
    {"id":901,"slug":"01gmm8fjrxc8g1k5sh80rkxdp2","title":null,"url":null,"type":"artifact",
     "content":"A highlighted passage.","summary":null,"recordCreatedAt":"2025-01-02 03:04:05","recordUpdatedAt":"2025-01-02 03:04:05",
     "contentCreatedAt":"2024-12-31 23:59:59","notes":"my note","isCurated":true,"source":"readwise",
     "media":[{"id":51,"recordId":901,"url":"/uploads/images/3f1ce9.jpg","altText":null,"type":"image","contentTypeString":"image/jpeg",
       "fileSize":183422,"width":1200,"height":800,"recordCreatedAt":"2026-10-11 22:27:13","recordUpdatedAt":"2026-10-11 22:27:13"}],
     "outgoingLinks":[{"predicate":"contained_by","target":{"id":300,"title":"A Book","slug":"a-book"}}],
     "incomingLinks":[]}
    """#

    /// A hybrid search row: a ListRow plus `score`, with values this build doesn't know.
    static let searchRow = #"""
    {"id":5,"slug":"future","title":"From the future","url":"not a url","type":"hypothesis",
     "content":null,"summary":null,"recordCreatedAt":"2026-01-01 00:00:00","recordUpdatedAt":"2026-01-02 00:00:00",
     "contentCreatedAt":null,"notes":null,"isCurated":false,"source":null,
     "media":[],"outgoingLinks":[{"predicate":"inspired_by","target":{"id":6,"title":null,"slug":"x"}}],
     "incomingLinks":[{"predicate":"inspired_by"}],"score":0.032266458495966696}
    """#

    static let detail = #"""
    {"id":812,"slug":"tiny-internets","type":"artifact","title":"Tiny internets","url":"https://example.com/tiny-internets",
     "isCurated":false,"summary":"Page meta description","content":null,"notes":null,"source":"manual",
     "recordCreatedAt":"2026-10-11 22:27:12","recordUpdatedAt":"2026-10-11 22:30:01","contentCreatedAt":null,"contentUpdatedAt":null,
     "outgoingLinks":[{"predicate":"has_format","target":{"id":4,"slug":"article","type":"concept","title":"Article","url":null,"isCurated":true,
       "summary":null,"content":null,"notes":null,"source":"manual","recordCreatedAt":"2025-06-28 18:54:06","recordUpdatedAt":"2025-07-28 20:30:39",
       "contentCreatedAt":null,"contentUpdatedAt":null}},
       {"predicate":"created_by","target":{"id":120,"slug":"jane-doe","type":"entity","title":"Jane Doe","url":null,"isCurated":false,
       "summary":null,"content":null,"notes":null,"source":null,"recordCreatedAt":"2025-06-28 18:54:06","recordUpdatedAt":"2025-06-28 18:54:06",
       "contentCreatedAt":null,"contentUpdatedAt":null}}],
     "media":[{"id":51,"recordId":812,"url":"/uploads/images/3f1ce9.jpg","altText":null,"type":"image","contentTypeString":"image/jpeg",
       "fileSize":183422,"width":1200,"height":800,"recordCreatedAt":"2026-10-11 22:27:13","recordUpdatedAt":"2026-10-11 22:27:13"}],
     "archives":[{"id":3,"recordId":812,"url":"https://example.com/tiny-internets","path":"example.com/2026-10-11","status":"ok","title":"Tiny internets",
       "error":null,"archivedAt":"2026-10-11 22:31:00","recordCreatedAt":"2026-10-11 22:30:40","recordUpdatedAt":"2026-10-11 22:31:00"}]}
    """#

    /// RecordSelect, as `PUT /record` returns it.
    static let record = #"""
    {"id":812,"slug":"tiny-internets","type":"artifact","title":"Tiny internets","url":"https://example.com/tiny-internets",
     "isCurated":true,"summary":"Page meta description","content":"Body","notes":"A note","source":"manual",
     "recordCreatedAt":"2026-10-11 22:27:12","recordUpdatedAt":"2026-10-11 22:30:01","contentCreatedAt":"2026-03-14 16:12:00","contentUpdatedAt":null}
    """#

    /// `GET /record/slug/:slug`: RecordSelect plus media and archives, no outgoing links.
    static let bySlug = #"""
    {"id":812,"slug":"tiny-internets","type":"artifact","title":"Tiny internets","url":"https://example.com/tiny-internets",
     "isCurated":false,"summary":null,"content":null,"notes":null,"source":"manual",
     "recordCreatedAt":"2026-10-11 22:27:12","recordUpdatedAt":"2026-10-11 22:30:01","contentCreatedAt":null,"contentUpdatedAt":null,
     "media":[],"archives":[]}
    """#

    static let link = #"""
    {"id":1400,"sourceId":812,"targetId":4,"predicate":"has_format","notes":null,
     "recordCreatedAt":"2026-10-11 22:27:12","recordUpdatedAt":"2026-10-11 22:27:12"}
    """#

    static let linksBundle = #"""
    {"id":812,
     "outgoingLinks":[{"id":1400,"sourceId":812,"targetId":4,"predicate":"has_format","notes":null,
       "recordCreatedAt":"2026-10-11 22:27:12","recordUpdatedAt":"2026-10-11 22:27:12","target":{"title":"Article","slug":"article"}}],
     "incomingLinks":[{"id":1401,"sourceId":901,"targetId":812,"predicate":"contained_by","notes":"from the book",
       "recordCreatedAt":"2026-10-11 22:28:00","recordUpdatedAt":"2026-10-11 22:28:00",
       "source":{"title":null,"slug":"01gmm8fjrxc8g1k5sh80rkxdp2","content":"A highlighted passage."}}]}
    """#

    static let infoOn = #"{"name":"enchiridion","auth":["tailscale"]}"#
    static let infoOff = #"{"name":"enchiridion","auth":[]}"#
    static let meTailscale = #"{"scheme":"tailscale","device":{"id":"nXYZ123CNTRL","name":"vern"},"user":"chase@github"}"#
    static let meLocal = #"{"scheme":"local","device":null,"user":null}"#

    static let unauthorizedKnown = #"""
    {"error":{"code":"unauthorized","message":"This device isn't on Enchiridion's list yet."},
     "message":"This device isn't on Enchiridion's list yet.","device":{"id":"nXYZ123CNTRL","name":"vern"}}
    """#
    static let unauthorizedUnknown = #"""
    {"error":{"code":"unauthorized","message":"Enchiridion couldn't tell which device this is. Is Tailscale on?"},
     "message":"Enchiridion couldn't tell which device this is. Is Tailscale on?","device":null}
    """#
    /// A zod failure through `errorHandler`: 500 with the issues pretty-printed into `message`.
    static let zodError = #"""
    {"message":"[\n  {\n    \"expected\": \"number\",\n    \"code\": \"invalid_type\",\n    \"path\": [\n      \"limit\"\n    ],\n    \"message\": \"Invalid input: expected number, received string\"\n  }\n]"}
    """#
}
