import SwiftUI

struct OnboardingView: View {
    var continueAction: () -> Void

    @State private var step = 0
    private let pages = OnboardingPage.all

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemBackground), Color.accentColor.opacity(0.10)],
                startPoint: .top,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $step) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        pageView(page)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Button(step == pages.count - 1 ? "Set up LazyFlow" : "Continue") {
                    if step == pages.count - 1 {
                        continueAction()
                    } else {
                        withAnimation(.smooth) { step += 1 }
                    }
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
            }
        }
    }

    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: 30) {
            Spacer(minLength: 50)

            ZStack {
                Circle()
                    .fill(page.tint.opacity(0.12))
                    .frame(width: 152, height: 152)
                Image(systemName: page.symbol)
                    .font(.system(size: 56, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(page.tint)
            }
            .symbolEffect(.breathe, options: .repeating)

            VStack(spacing: 12) {
                Text(page.title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(page.body)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }
}

private struct OnboardingPage {
    let symbol: String
    let title: String
    let body: String
    let tint: Color

    static let all = [
        OnboardingPage(
            symbol: "waveform",
            title: "Speak. It types.",
            body: "Dictate naturally in any app from a focused voice keyboard.",
            tint: .blue
        ),
        OnboardingPage(
            symbol: "keyboard",
            title: "Keep your keyboard",
            body: "Switch to LazyFlow when you want to speak, then use Apple’s keyboard whenever you want to type.",
            tint: .purple
        ),
        OnboardingPage(
            symbol: "lock.shield",
            title: "Private by design",
            body: "Transcription and tone cleanup run on your iPhone. There is no account or API key.",
            tint: .mint
        )
    ]
}

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}
