import SwiftUI

struct LevelerOverlay: View {
    let rotation: Double // Radians
    let isLevel: Bool
    
    var body: some View {
        ZStack {
            // Central fixed reference (Crosshair)
            Path { path in
                // Left tick
                path.move(to: CGPoint(x: -40, y: 0))
                path.addLine(to: CGPoint(x: -10, y: 0))
                // Right tick
                path.move(to: CGPoint(x: 10, y: 0))
                path.addLine(to: CGPoint(x: 40, y: 0))
            }
            .stroke(Theme.borderSubtle.opacity(0.8), lineWidth: 1)
            .frame(width: 80, height: 1)
            
            // Rotating "Horizon" line
            Rectangle()
                .fill(isLevel ? Theme.accentWarning : Theme.textPrimary)
                .frame(width: 140, height: isLevel ? 1.5 : 0.5)
                .shadow(color: .black.opacity(0.5), radius: 2)
                .rotationEffect(Angle(radians: rotation))
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isLevel)
                .animation(.linear(duration: 0.1), value: rotation)
            
            // Level indicator (Center Dot)
            if isLevel {
                Circle()
                    .fill(Theme.accentWarning)
                    .frame(width: 4, height: 4)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
    }
}
