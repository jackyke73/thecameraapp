import SwiftUI

struct ArcZoomDial: View {
    @Binding var currentZoom: CGFloat
    let minZoom: CGFloat
    let maxZoom: CGFloat
    let presets: [CGFloat]
    
    // Configuration
    private let arcAngle: Double = 140 // Visual span of the arc
    private let radius: CGFloat = 300 // Curvature radius
    
    // Gesture State
    @State private var initialZoomState: CGFloat? = nil
    
    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height + radius - 60)
            
            ZStack {
                // 1. TICKS
                let ticks = generateTicks()
                ForEach(ticks.indices, id: \.self) { index in
                    let tick = ticks[index]
                    TickMark(
                        tick: tick,
                        center: center,
                        radius: radius,
                        arcAngle: arcAngle,
                        currentZoom: currentZoom
                    )
                }
                
                // 2. INDICATOR (Static Yellow Triangle)
                IndicatorTriangle()
                    .fill(Color.yellow)
                    .frame(width: 14, height: 9)
                    .position(x: geo.size.width / 2, y: 10)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            }
            .drawingGroup()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDrag(value: value, center: center)
                    }
                    .onEnded { _ in
                        initialZoomState = nil // Reset state
                    }
            )
            // Mask to keep edges clean
            .mask(
                DialMask(center: center, radius: radius, width: 200)
            )
        }
        .frame(height: 100)
        .background(
            // Fade-out Gradient
            LinearGradient(
                colors: [Color.black.opacity(0.8), Color.black.opacity(0.0)],
                startPoint: .bottom,
                endPoint: .top
            )
            .mask(ArcShape(radius: radius, width: 150))
            .offset(y: 30)
        )
    }
    
    // MARK: - LOGIC (The Fix)
    
    private func handleDrag(value: DragGesture.Value, center: CGPoint) {
        // 1. Lock initial state when drag starts
        if initialZoomState == nil {
            initialZoomState = currentZoom
        }
        
        guard let startZoom = initialZoomState else { return }
        
        // 2. Calculate Angular Change
        // We compare the angle of the *current* finger position vs the *start* finger position
        let startAngle = angleFromPoint(value.startLocation, center: center)
        let currentAngle = angleFromPoint(value.location, center: center)
        let deltaAngle = currentAngle - startAngle
        
        // 3. Apply Delta to Zoom
        // Logic: "Pulling Tape".
        // Dragging LEFT (Negative Delta) should bring Right-side numbers (Higher Zoom) to center.
        // So: New Angle = Original Zoom Angle - Delta
        let originalDialAngle = zoomToAngle(startZoom)
        let newDialAngle = originalDialAngle - deltaAngle
        
        // 4. Convert back to Zoom Factor
        let newZoom = angleToZoom(newDialAngle)
        
        // 5. Clamp
        self.currentZoom = max(minZoom, min(maxZoom, newZoom))
    }
    
    private func angleFromPoint(_ point: CGPoint, center: CGPoint) -> Double {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let radians = atan2(dy, dx)
        let degrees = radians * 180 / .pi
        return degrees + 90 // Normalize so "Up" is 0
    }
    
    // --- Mapping Logic ---
    
    // Convert Zoom Factor -> Visual Angle (for drawing ticks)
    private func zoomToAngle(_ zoom: CGFloat) -> Double {
        // Logarithmic scale: distance between 1x and 2x is same as 2x and 4x
        let minLog = log2(minZoom)
        let maxLog = log2(maxZoom)
        let logZoom = log2(zoom)
        
        // Normalize 0.0 to 1.0
        let percent = (logZoom - minLog) / (maxLog - minLog)
        
        // Map to angle range (-70 to +70 degrees)
        return -arcAngle/2 + (percent * arcAngle)
    }
    
    // Convert Visual Angle -> Zoom Factor (for gesture calculation)
    private func angleToZoom(_ angle: Double) -> CGFloat {
        let percent = (angle + arcAngle/2) / arcAngle
        
        let minLog = log2(minZoom)
        let maxLog = log2(maxZoom)
        let logZoom = minLog + (percent * (maxLog - minLog))
        
        return pow(2, logZoom)
    }
    
    private func generateTicks() -> [TickInfo] {
        var ticks: [TickInfo] = []
        // Major Ticks (The Buttons)
        for preset in presets {
            ticks.append(TickInfo(zoom: preset, isMajor: true))
        }
        // Minor Ticks
        var v = minZoom
        while v < maxZoom {
            let nextV = v * 2
            // Add 4 ticks between powers of 2
            let step = (log2(nextV) - log2(v)) / 5
            for i in 1...4 {
                let zoomVal = pow(2, log2(v) + step * Double(i))
                if zoomVal < maxZoom {
                    ticks.append(TickInfo(zoom: zoomVal, isMajor: false))
                }
            }
            v = nextV
        }
        return ticks.sorted { $0.zoom < $1.zoom }
    }
}

// MARK: - SUBVIEWS

struct TickInfo {
    let zoom: CGFloat
    let isMajor: Bool
}

struct TickMark: View {
    let tick: TickInfo
    let center: CGPoint
    let radius: CGFloat
    let arcAngle: Double
    let currentZoom: CGFloat
    
    var body: some View {
        // 1. Where should this tick be drawn?
        let angle = zoomToAngle(tick.zoom)
        
        // 2. Where is it relative to the "Center" of the screen now?
        let currentAngle = zoomToAngle(currentZoom)
        let delta = angle - currentAngle
        
        // Only draw if visible
        let isVisible = abs(delta) < (arcAngle/2 + 5)
        
        if isVisible {
            ZStack {
                // Tick Line
                Rectangle()
                    .fill(tick.isMajor ? Color.white : Color.white.opacity(0.4))
                    .frame(width: tick.isMajor ? 2 : 1, height: tick.isMajor ? 14 : 7)
                    .offset(y: -radius) // Move to rim
                
                // Labels (Only Major)
                if tick.isMajor {
                    VStack(spacing: 2) {
                        Text(formatLabel(tick.zoom))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(abs(delta) < 4 ? .yellow : .white)
                            .shadow(color: .black.opacity(0.3), radius: 1)
                        
                        // Only show focal length if near center
                        Text(focalLength(for: tick.zoom))
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.yellow)
                            .opacity(abs(delta) < 4 ? 1 : 0)
                    }
                    .rotationEffect(.degrees(-delta)) // Keep text upright relative to screen
                    .offset(y: -radius - 25) // Move text above ticks
                }
            }
            .rotationEffect(.degrees(delta)) // Rotate to position on arc
            .position(x: center.x, y: center.y)
        }
    }
    
    // Duplicate math helper for the View
    private func zoomToAngle(_ zoom: CGFloat) -> Double {
        let minLog = log2(0.5) // Hardcoded UI bounds for consistency
        let maxLog = log2(15.0)
        let logZoom = log2(zoom)
        let percent = (logZoom - minLog) / (maxLog - minLog)
        return -70 + (percent * 140) // -70 to +70 degrees
    }
    
    private func formatLabel(_ val: CGFloat) -> String {
        return val == 0.5 ? ".5" : String(format: "%.0f", val)
    }
    
    private func focalLength(for val: CGFloat) -> String {
        switch val {
        case 0.5: return "13mm"
        case 1.0: return "24mm"
        case 2.0: return "48mm"
        case 4.0: return "120mm"
        default: return ""
        }
    }
}

// Shapes
struct IndicatorTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct DialMask: Shape {
    let center: CGPoint
    let radius: CGFloat
    let width: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: center, radius: radius + 60, startAngle: .degrees(-160), endAngle: .degrees(-20), clockwise: false)
        path.addLine(to: center)
        path.closeSubpath()
        return path
    }
}

struct ArcShape: Shape {
    let radius: CGFloat
    let width: CGFloat
    
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.maxY + radius - 60)
        var path = Path()
        path.addArc(center: center, radius: radius + width/2, startAngle: .degrees(-160), endAngle: .degrees(-20), clockwise: false)
        path.addArc(center: center, radius: radius - width/2, startAngle: .degrees(-20), endAngle: .degrees(-160), clockwise: true)
        path.closeSubpath()
        return path
    }
}
