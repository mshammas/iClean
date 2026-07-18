import SwiftUI

/// A consistent screen scaffold used across iClean.
///
/// Layout: scrollable content area on top (so large Dynamic Type never clips), with an
/// optional pinned footer holding the primary action(s) so the main button is always
/// reachable without hunting. Generous padding throughout.
struct ICScreen<Content: View, Footer: View>: View {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    init(@ViewBuilder content: @escaping () -> Content,
         @ViewBuilder footer: @escaping () -> Footer) {
        self.content = content
        self.footer = footer
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    content()
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer()
                .padding(24)
                .background(.bar)
        }
        .background(ICColor.background)
    }
}

extension ICScreen where Footer == EmptyView {
    init(@ViewBuilder content: @escaping () -> Content) {
        self.init(content: content, footer: { EmptyView() })
    }
}
