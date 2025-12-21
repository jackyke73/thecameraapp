import SwiftUI

@main
struct BoyfriendCameraApp: App {
    // Tracks if we are showing the splash screen
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    SplashScreen(showSplash: $showSplash)
                        .transition(.opacity) // Fade out
                        .zIndex(1) // Sit on top
                } else {
                    ContentView()
                        .transition(.opacity) // Fade in
                        .zIndex(0)
                }
            }
            // This animation controls the speed of the cross-fade between views
            .animation(.easeInOut(duration: 0.5), value: showSplash)
        }
    }
}
