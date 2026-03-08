import SwiftUI
import MetalKit

/// A high-performance, point-cloud based Splat Previewer.
/// This acts as a fallback/accelerator when the full Gaussian Splat renderer is overkill or unavailable.
struct SplatPointRenderer: View {
    let splatData: [SIMD3<Float>] // The raw points
    
    @State private var rotationX: Float = 0
    @State private var rotationY: Float = 0
    @State private var lastDrag: CGPoint = .zero
    @State private var zoom: Float = 1.0
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let baseScale = Float(min(size.width, size.height)) * 0.8
                    let scale = baseScale * zoom
                    
                    // Simple projection & rotation
                    let cosX = cos(rotationX)
                    let sinX = sin(rotationX)
                    let cosY = cos(rotationY)
                    let sinY = sin(rotationY)
                    
                    // Depth sorting for basic transparency/occlusion
                    let sortedPoints = splatData.map { point -> (SIMD3<Float>, Float) in
                        // Rotation Y
                        let px = point.x * cosY - point.z * sinY
                        let pz1 = point.x * sinY + point.z * cosY
                        
                        // Rotation X
                        let py = point.y * cosX - pz1 * sinX
                        let pz = point.y * sinX + pz1 * cosX
                        return (SIMD3<Float>(px, py, pz), pz)
                    }.sorted { $0.1 > $1.1 }
                    
                    for (p, pz) in sortedPoints {
                        // Perspective projection
                        let perspective = 2.0 / (pz + 3.0)
                        if pz > -2.5 { // Clipping
                            let screenX = center.x + CGFloat(p.x * perspective * scale)
                            let screenY = center.y + CGFloat(p.y * perspective * scale)
                            
                            let size = CGFloat(2.0 * perspective)
                            let rect = CGRect(x: screenX - size/2, y: screenY - size/2, width: size, height: size)
                            
                            // Color mapping based on Y (height) for visual interest
                            let hue = Double(p.y + 0.5)
                            context.fill(Path(ellipseIn: rect), with: .color(Color(hue: hue, saturation: 0.6, brightness: 1.0).opacity(Double(perspective) * 0.7)))
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
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            zoom = Float(value)
                        }
                )
                
                // Overlay info
                VStack {
                    Spacer()
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("GAUSSIAN POINT CLOUD")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.yellow)
                            Text("\(splatData.count) Primitives")
                                .font(.system(size: 8, design: .monospaced))
                            Text("RENDER MODE: DEPTH-SORTED VOXEL-PROXY")
                                .font(.system(size: 8, design: .monospaced))
                        }
                        .foregroundColor(.white.opacity(0.6))
                        .padding(20)
                        .background(.black.opacity(0.4))
                        .cornerRadius(10)
                        Spacer()
                    }
                    .padding(.bottom, 30)
                }
            }
        }
    }
}
