import SwiftUI

struct GuidanceOverlay: View {
    let nosePoint: CGPoint?      // normalized 0..1
    let targetPoint: CGPoint     // normalized 0..1
    let isAligned: Bool
    
    // Internal state for animations
    @State private var pulseScale: CGFloat = 1.0
    @State private var reticleOpacity: Double = 0.0
    
    // Haptics
    private let haptic = UINotificationFeedbackGenerator()

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            // Convert normalized target to screen coords
            let target = CGPoint(x: targetPoint.x * w, y: targetPoint.y * h)
            
            // --- 1. TARGET RETICLE (The "Goal") ---
            ZStack {
                // Outer ring (static-ish)
                Circle()
                    .strokeBorder(
                        isAligned ? Color.green : Color.white.opacity(0.5),
                        style: StrokeStyle(lineWidth: 2, dash: [4, 4])
                    )
                    .frame(width: 60, height: 60)
                
                // Inner pulsing core (only when aligned)
                if isAligned {
                    Circle()
                        .fill(Color.green.opacity(0.3))
                        .frame(width: 50, height: 50)
                        .scaleEffect(pulseScale)
                        .onAppear {
                            withAnimation(Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                                pulseScale = 1.2
                            }
                        }
                }
                
                // Crosshair markers
                Path { p in
                    let s: CGFloat = 10
                    // Top
                    p.move(to: CGPoint(x: 30, y: 30 - s)); p.addLine(to: CGPoint(x: 30, y: 30 - 20))
                    // Bottom
                    p.move(to: CGPoint(x: 30, y: 30 + s)); p.addLine(to: CGPoint(x: 30, y: 30 + 20))
                    // Left
                    p.move(to: CGPoint(x: 30 - s, y: 30)); p.addLine(to: CGPoint(x: 30 - 20, y: 30))
                    // Right
                    p.move(to: CGPoint(x: 30 + s, y: 30)); p.addLine(to: CGPoint(x: 30 + 20, y: 30))
                }
                .stroke(isAligned ? Color.green : Color.white, lineWidth: 1.5)
                .frame(width: 60, height: 60)
            }
            .position(target)
            .shadow(color: isAligned ? .green.opacity(0.5) : .black.opacity(0.2), radius: 8)


            // --- 2. SUBJECT TRACKER (The "Nose") ---
            if let nose = nosePoint {
                let n = CGPoint(x: nose.x * w, y: nose.y * h)

                // Dynamic Line (Rubber band effect)
                Path { p in
                    p.move(to: n)
                    p.addLine(to: target)
                }
                .stroke(
                    LinearGradient(
                        colors: [isAligned ? .green : .yellow, isAligned ? .green.opacity(0.5) : .white.opacity(0.1)],
                        startPoint: .init(x: 0, y: 0),
                        endPoint: .init(x: 1, y: 1) // Approximation, Gradient along line is tricky in SwiftUI Path, but this works for global
                    ),
                    style: StrokeStyle(lineWidth: isAligned ? 1 : 2, lineCap: .round, dash: isAligned ? [] : [4, 6])
                )
                
                // Subject "Lock" Box
                ZStack {
                    // Corner brackets for the subject
                    Corners(length: 10)
                        .stroke(isAligned ? Color.green : Color.yellow, lineWidth: 2)
                        .frame(width: 40, height: 40)
                    
                    // Center dot
                    Circle()
                        .fill(isAligned ? Color.green : Color.yellow)
                        .frame(width: 6, height: 6)
                }
                .position(n)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: n)
            }
            
            // --- 3. STATUS TEXT ---
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    if isAligned {
                        Text("SUBJECT LOCKED")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green)
                            .cornerRadius(4)
                    } else if nosePoint != nil {
                        Text("ALIGN SUBJECT")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.yellow)
                            .cornerRadius(4)
                    }
                    Spacer()
                }
                .padding(.bottom, 80) // Above the shutter button area
            }
        }
        .allowsHitTesting(false)
        .onChange(of: isAligned) { _, aligned in
            if aligned {
                haptic.notificationOccurred(.success)
            }
        }
    }
}

// Helper shape for corners
struct Corners: Shape {
    var length: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Top Left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))

        // Top Right
        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))

        // Bottom Left
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.maxY))

        // Bottom Right
        path.move(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - length))

        return path
    }
}
