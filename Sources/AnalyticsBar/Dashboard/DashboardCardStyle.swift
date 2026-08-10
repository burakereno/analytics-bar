import SwiftUI

struct DashboardCardStyle: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let borderOpacity = contrast == .increased ? 0.24 : 0.08
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.28))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                Color.white.opacity(borderOpacity),
                                lineWidth: 1
                            )
                    }
            }
    }
}

extension View {
    func dashboardCard() -> some View { modifier(DashboardCardStyle()) }
}
