import SwiftUI

struct LevelerOverlay: View {
    let rotation: Double // Radians
    let isLevel: Bool
    
    var body: some View {
        ZStack {
            // Central fixed reference (Short lines)
            HStack(spacing: 60) {
                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 20, height: 1)
                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 20, height: 1)
            }
            
            // Rotating "Horizon" line
            Rectangle()
                .fill(isLevel ? Color.yellow : Color.white)
                .frame(width: 200, height: isLevel ? 2 : 1)
                .shadow(color: .black.opacity(0.5), radius: 2)
                .rotationEffect(Angle(radians: rotation))
                .animation(.linear(duration: 0.1), value: rotation)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isLevel)
        }
        .allowsHitTesting(false)
    }
}
