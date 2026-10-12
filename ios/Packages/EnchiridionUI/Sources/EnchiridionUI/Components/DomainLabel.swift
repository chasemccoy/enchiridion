import SwiftUI

/// "at example.com": where a record's URL points, its host with a leading `www.` stripped (`Record.domain`), in
/// `textMuted`. The prefix and the domain never break apart. The web draws the site's favicon before the domain,
/// from Google's favicon service; the app doesn't, so no record's domain leaves the tailnet.
public struct DomainLabel: View {
    let domain: String
    let prefix: String?
    let font: Font

    public init(_ domain: String, prefix: String? = "at", font: Font = Typography.byline) {
        self.domain = domain
        self.prefix = prefix
        self.font = font
    }

    /// The label's words, joined by a no-break space, for setting inline in a longer `Text`.
    public static func string(_ domain: String, prefix: String? = "at") -> String {
        guard let prefix, !prefix.isEmpty else { return domain }
        return "\(prefix)\u{00A0}\(domain)"
    }

    public var body: some View {
        Text(verbatim: Self.string(domain, prefix: prefix))
            .font(font)
            .foregroundStyle(Palette.textMuted)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

#if DEBUG
#Preview("Domain label") {
    VStack(alignment: .leading, spacing: Space.cardGap) {
        DomainLabel("example.com")
        DomainLabel("robinsloan.com", prefix: nil, font: Typography.detailByline)
    }
    .padding(Space.margin)
    .previewRoot()
}
#endif
