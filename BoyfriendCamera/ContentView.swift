import SwiftUI

struct ContentView: View {
    @StateObject var manager = CameraManager()

    var body: some View {
        ZStack {
            // 1. The Camera Feed
            CameraPreview(cameraManager: manager)
                .ignoresSafeArea()

            // 2. The "Heads Up Display" (HUD)
            VStack {
                // Status Indicator at the top
                HStack {
                    Circle()
                        .fill(manager.isPersonDetected ? Color.green : Color.red)
                        .frame(width: 20, height: 20)
                    
                    Text(manager.isPersonDetected ? "PERSON DETECTED" : "NO PERSON")
                        .font(.headline)
                        .foregroundColor(manager.isPersonDetected ? .green : .red)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(10)
                    
                    Spacer()
                }
                .padding(.top, 50) // Push down from the notch
                .padding(.leading, 20)

                Spacer()
                
                // Instructions at bottom
                Text("Point camera at a human")
                    .foregroundColor(.white)
                    .padding(.bottom, 30)
            }
        }
    }
}

#Preview {
    ContentView()
}
