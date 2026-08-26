import SwiftUI

/// A horizontal row of films under a heading.
///
/// The shape every television library uses, because a remote moves in one direction at
/// a time and a grid forces the viewer to think about which direction that is.
struct TVShelf<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 60)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 36) {
                    content
                }
                // Room for the focused card to grow into without clipping.
                .padding(.horizontal, 60)
                .padding(.vertical, 22)
            }
        }
    }
}
