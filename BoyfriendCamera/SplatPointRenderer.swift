import SwiftUI
import MetalKit

/// A high-performance, point-cloud based Splat Previewer.
/// This acts as a fallback/accelerator when the full Gaussian Splat renderer is overkill or unavailable.
struct SplatPointRenderer: View {
    let splatData: [SIMD3<Float>] // The raw points
    
    @State private var rotationX: Float = 0
    @State private var rotationY: Float = 0
    @State private var lastDrag: CGPoint = .zero
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let scale: Float = Float(min(size.width, size.height)) * 0.8
                    
                    // Simple projection & rotation
                    let cosX = cos(rotationX)
                    let sinX = sin(rotationX)
                    let cosY = cos(rotationY)
                    let sinY = sin(rotationY)
                    
                    for point in splatData {
                        // Rotation Y
                        var px = point.x * cosY - point.z * sinY
                        var pz = point.x * sinY + point.z * cosY
                        
                        // Rotation X
                        let py = point.y * cosX - pz * sinX
                        pz = point.y * sinX + pz * cosX
                        
                        // Perspective projection
                        let perspective = 2.0 / (pz + 3.0)
                        if pz > -2.5 { // Clipping
                            let screenX = center.x + CGFloat(px * perspective * scale)
                            let screenY = center.y + CGFloat(py * perspective * scale)
                            
                            let rect = CGRect(x: screenX, y: screenY, width: 1.5, height: 1.5)
                            context.fill(Path(ellipseIn: rect), with: .color(.yellow.opacity(Double(perspective) * 0.5)))
                        }
                    }
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let dx = Float(value.location.x - (lastDrag.x == 0 ? value.location.x : lastDrag.x)) * 0.01
                            let dy = Float(value.location.y - (lastDrag.y == 0 ? value.location.y : lastDrag.y)) * 0.01
                            rotationY += dx
                            rotationX += dy
                            lastDrag = value.location
                        }
                        .onEnded { _ in
                            lastDrag = .zero
                        }
                )
                
                // Overlay info
                VStack {
                    Spacer()
                    HStack {
                        VStack(alignment: .leading) {
                            Text("GAUSSIAN POINT CLOUD")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                            Text("\(splatData.count) Primitives")
                                .font(.system(size: 8, design: .monospaced))
                        }
                        .foregroundColor(.white.opacity(0.6))
                        .padding()
                        Spacer()
                    }
                }
            }
        }
    }
}
