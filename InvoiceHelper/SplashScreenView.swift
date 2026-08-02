import SwiftUI

/// Branded loading UI during `AppStore.bootstrap()` with a short entrance animation.
struct SplashScreenView: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.13, green: 0.59, blue: 0.95).opacity(0.22),
                    Color(.systemGroupedBackground),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Image("SplashLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260, maxHeight: 140)
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                    .scaleEffect(animate ? 1 : 0.88)
                    .opacity(animate ? 1 : 0.35)

                ProgressView()
                    .scaleEffect(1.1)
                    .tint(Color(red: 0.13, green: 0.59, blue: 0.95))
            }
            .padding(32)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                animate = true
            }
        }
    }
}
