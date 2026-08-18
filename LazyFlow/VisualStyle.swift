import SwiftUI

extension View {
    /// Native Liquid Glass on macOS 26+, with a restrained material fallback.
    @ViewBuilder
    func lazyFlowGlass<S: Shape>(
        in shape: S,
        interactive: Bool = false
    ) -> some View {
        if #available(macOS 26.0, *) {
            if interactive {
                glassEffect(.regular.interactive(), in: shape)
            } else {
                glassEffect(.regular, in: shape)
            }
        } else {
            background(.regularMaterial, in: shape)
                .overlay {
                    shape.stroke(.white.opacity(0.1), lineWidth: 0.5)
                }
        }
    }

    @ViewBuilder
    func lazyFlowGlassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else if prominent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }
}
