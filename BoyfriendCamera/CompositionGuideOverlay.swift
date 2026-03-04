import SwiftUI
import Vision

// A smart overlay that guides the user to align the subject with the Rule of Thirds.
struct CompositionGuideOverlay: View {
    // Face Bounds in Normalized Coordinates (0-1), relative to the image buffer
    // Vision: Origin Bottom-Left.
    let mainFaceBounds: CGRect?
    let compositionScore: Double
    
    @State private var gridColor: Color = .white.opacity(0.3)
    
    // Impact generator for haptics
    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    
    // Nearest power point (calculated during body evaluation)
    @State private var nearestPowerPoint: CGPoint? = nil

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 1. The Rule of Thirds Grid
                GridPath()
                    .stroke(gridColor, lineWidth: 1)
                    .animation(.easeInOut, value: gridColor)
                
                // 2. Active Guidance (if face detected)
                if let face = mainFaceBounds {
                    let screenW = geometry.size.width
                    let screenH = geometry.size.height
                    
                    // Convert Vision rect (0,0 Bottom-Left) to SwiftUI rect (0,0 Top-Left)
                    // Vision: x, y, w, h are 0.0-1.0
                    // SwiftUI Y = (1.0 - visionY - visionHeight) * screenHeight
                    
                    let faceW = face.width * screenW
                    let faceH = face.height * screenH
                    let faceX = face.minX * screenW
                    let faceY = (1.0 - face.minY - face.height) * screenH
                    
                    let faceCenter = CGPoint(x: faceX + faceW/2, y: faceY + faceH/2)
                    
                    // Draw Face Box (Debug/Feedback - subtle)
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1) // Reduced opacity to reduce clutter
                        .frame(width: faceW, height: faceH)
                        .position(x: faceCenter.x, y: faceCenter.y)
                    
                    // 3. Find Nearest Power Point (Intersection of Thirds)
                    let thirdW = screenW / 3.0
                    let thirdH = screenH / 3.0
                    
                    let points = [
                        CGPoint(x: thirdW, y: thirdH),       // Top-Left
                        CGPoint(x: thirdW * 2, y: thirdH),   // Top-Right
                        CGPoint(x: thirdW, y: thirdH * 2),   // Bottom-Left
                        CGPoint(x: thirdW * 2, y: thirdH * 2)// Bottom-Right
                    ]
                    
                    // Find closest point to face center
                    if let closest = points.min(by: { dist($0, faceCenter) < dist($1, faceCenter) }) {
                        
                        let distance = dist(faceCenter, closest)
                        let threshold: CGFloat = 40.0 // Pixels tolerance
                        
                        // Dynamic Arrow Logic
                        // Only draw line if distance is significant but not huge (don't clutter if way off)
                        if distance > threshold && distance < 300 {
                             // Draw an arrow pointing FROM face TO power point
                             ArrowPath(start: faceCenter, end: closest)
                                .stroke(Color.yellow.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [4, 4]))
                                .shadow(color: .black.opacity(0.5), radius: 2)
                        }

                        if distance < threshold {
                            // Perfect Alignment!
                            Circle()
                                .fill(Color.green)
                                .frame(width: 12, height: 12)
                                .position(x: closest.x, y: closest.y)
                                .shadow(radius: 4)
                        } else {
                            // Target Indicator (Where to go) - Pulse animation could go here
                            Circle()
                                .strokeBorder(Color.yellow, lineWidth: 2)
                                .background(Circle().fill(Color.yellow.opacity(0.2)))
                                .frame(width: 24, height: 24)
                                .position(x: closest.x, y: closest.y)
                        }
                    }
                }
            }
        }
        .onChange(of: compositionScore) { newValue in
            if newValue > 0.8 {
                gridColor = .green.opacity(0.8)
            } else {
                gridColor = .white.opacity(0.3)
            }
        }
    }
    
    private func dist(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        return sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2))
    }
}

// Simple Arrow Shape
struct ArrowPath: Shape {
    var start: CGPoint
    var end: CGPoint
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        
        // Arrowhead
        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = 10
        let arrowAngle: CGFloat = .pi / 6 // 30 degrees
        
        let p1 = CGPoint(
            x: end.x - arrowLength * cos(angle - arrowAngle),
            y: end.y - arrowLength * sin(angle - arrowAngle)
        )
        let p2 = CGPoint(
            x: end.x - arrowLength * cos(angle + arrowAngle),
            y: end.y - arrowLength * sin(angle + arrowAngle)
        )
        
        path.move(to: end)
        path.addLine(to: p1)
        path.move(to: end)
        path.addLine(to: p2)
        
        return path
    }
}

struct GridPath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let thirdW = rect.width / 3.0
        let thirdH = rect.height / 3.0
        
        // Vertical lines
        path.move(to: CGPoint(x: thirdW, y: 0))
        path.addLine(to: CGPoint(x: thirdW, y: rect.height))
        
        path.move(to: CGPoint(x: thirdW * 2, y: 0))
        path.addLine(to: CGPoint(x: thirdW * 2, y: rect.height))
        
        // Horizontal lines
        path.move(to: CGPoint(x: 0, y: thirdH))
        path.addLine(to: CGPoint(x: rect.width, y: thirdH))
        
        path.move(to: CGPoint(x: 0, y: thirdH * 2))
        path.addLine(to: CGPoint(x: rect.width, y: thirdH * 2))
        
        return path
    }
}
