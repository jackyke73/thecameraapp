import SwiftUI

struct SplashScreen: View {
    @Binding var showSplash: Bool
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 20) {
                // 1. Logo Icon
                Image(systemName: "camera.macro") // Professional lens icon
                    .font(.system(size: 80))
                    .foregroundStyle(
                        .linearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .scaleEffect(isAnimating ? 1.0 : 0.5)
                    .opacity(isAnimating ? 1 : 0)
                
                // 2. Text
                VStack(spacing: 8) {
                    Text("The Camera App")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("beta")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.yellow)
                        .clipShape(Capsule())
                }
                .offset(y: isAnimating ? 0 : 20)
                .opacity(isAnimating ? 1 : 0)
            }
        }
        .onAppear {
            // 1. Trigger Animation immediately
            withAnimation(.easeOut(duration: 1.0)) {
                isAnimating = true
            }
            
            // 2. Dismiss after 2.5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                // Use a Binding to tell the parent (App) to switch views
                // The actual transition animation is handled in the App struct
                showSplash = false
            }
        }
    }
}
