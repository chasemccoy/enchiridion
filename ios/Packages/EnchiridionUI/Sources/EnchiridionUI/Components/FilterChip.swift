import EnchiridionKit
import SwiftUI

/// A filter toggle in the list's filter bar (All, Artifact, Concept, Entity, Needs curation): soft `primary` when
/// selected, a neutral ghost otherwise (`ChipButtonStyle`). VoiceOver reads the selection as a trait.
public struct FilterChip: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    /// A record type's chip: its name and its symbol.
    public init(type: RecordType, isSelected: Bool, action: @escaping () -> Void) {
        self.init(type.displayName, systemImage: type.symbolName, isSelected: isSelected, action: action)
    }

    public var body: some View {
        Button(action: action) {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(verbatim: title)
            }
        }
        .buttonStyle(.chip(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#if DEBUG
#Preview("Filter chips") {
    @Previewable @State var type: RecordType?
    @Previewable @State var needsCuration = true
    ScrollView(.horizontal) {
        HStack(spacing: Space.chipGap) {
            FilterChip("All", isSelected: type == nil) { type = nil }
            ForEach(RecordType.known, id: \.self) { candidate in
                FilterChip(type: candidate, isSelected: type == candidate) { type = candidate }
            }
            FilterChip("Needs curation", systemImage: Symbol.needsCuration, isSelected: needsCuration) {
                needsCuration.toggle()
            }
        }
        .padding(Space.margin)
    }
    .previewRoot()
}
#endif
