import SwiftUI

struct GuidanceOverlay: View {
    let nosePoint: CGPoint?          // normalized 0...1
    let targetPoint: CGPoint         // normalized 0...1
    let isActive: Bool

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            // convert normalized -> pixel
            let target = CGPoint(x: targetPoint.x * size.width,
                                 y: targetPoint.y * size.height)

            let nose = nosePoint.map { p in
                CGPoint(x: p.x * size.width,
                        y: p.y * size.height)
            }

            ZStack {
                if isActive, let nose = nose {
                    // dashed line from nose -> target
                    Path { path in
                        path.move(to: nose)
                        path.addLine(to: target)
                    }
                    .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 6]))
                    .foregroundColor(.white.opacity(0.9))

                    // nose dot (light)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .position(nose)
                        .shadow(radius: 6)

                    // target ring
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.9), lineWidth: 2)
                            .frame(width: 40, height: 40)
                        Circle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 6, height: 6)
                    }
                    .position(target)
                    .shadow(radius: 6)
                }
            }
            .animation(.easeOut(duration: 0.15), value: nosePoint?.x ?? 0)
            .animation(.easeOut(duration: 0.15), value: nosePoint?.y ?? 0)
        }
        .allowsHitTesting(false) // ✅ do not block taps/gestures
    }
}
