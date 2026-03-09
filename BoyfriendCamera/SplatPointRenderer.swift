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
    
    // Auto-rotation state
    @State private var isAutoRotating: Bool = true
    @State private var autoRotationAngle: Float = 0
    
    let timer = Timer.publish(every: 1/60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let baseScale = Float(min(size.width, size.height)) * 0.8
                    let scale = baseScale * zoom
                    
                    let currentRotY = rotationY + autoRotationAngle
                    
                    // Simple projection & rotation
                    let cosX = cos(rotationX)
                    let sinX = sin(rotationX)
                    let cosY = cos(currentRotY)
                    let sinY = sin(currentRotY)
                    
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
                            
                            let pointSize = CGFloat(2.5 * perspective)
                            let rect = CGRect(x: screenX - pointSize/2, y: screenY - pointSize/2, width: pointSize, height: pointSize)
                            
                            // Visual interest: Color by distance from center and height
                            let dist = sqrt(p.x*p.x + p.z*p.z)
                            let hue = Double(0.5 + p.y + dist * 0.2)
                            
                            context.fill(Path(ellipseIn: rect), with: .color(Color(hue: hue.truncatingRemainder(dividingBy: 1.0), saturation: 0.7, brightness: 1.0).opacity(Double(perspective) * 0.8)))
                        }
                    }
                }
                .onReceive(timer) { _ in
                    if isAutoRotating {
                        autoRotationAngle += 0.005
                    }
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isAutoRotating = false
                            let dx = Float(value.location.x - (lastDrag.x == 0 ? value.location.x : lastDrag.x)) * 0.01
                            let dy = Float(value.location.y - (lastDrag.y == 0 ? value.location.y : lastDrag.y)) * 0.01
                            rotationY += dx
                            rotationX += dy
                            lastDrag = value.location
                        }
                        .onEnded { _ in
                            lastDrag = .zero
                            // Optional: resume auto-rotate after delay
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            zoom = Float(value)
                        }
                )
                
                // Tech Overlay (The "Wow" Factor)
                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("STREAMING PRIMITIVES")
                                .font(.system(size: 8, weight: .black))
                                .foregroundColor(.yellow)
                            Text("BUFFER: \(splatData.count) POINTS")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.white)
                        }
                        .padding(8)
                        .background(.black.opacity(0.6))
                        .cornerRadius(4)
                        Spacer()
                    }
                    .padding(.top, 120)
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    // Bottom Controls
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("GAUSSIAN POINT CLOUD")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.yellow)
                            Text("RENDER MODE: DEPTH-SORTED VOXEL-PROXY")
                                .font(.system(size: 8, design: .monospaced))
                            Text("SHADERS: METAL COMPUTE [EMULATED]")
                                .font(.system(size: 8, design: .monospaced))
                        }
                        .foregroundColor(.white.opacity(0.6))
                        .padding(20)
                        .background(.black.opacity(0.4))
                        .cornerRadius(10)
                        
                        Spacer()
                        
                        Button(action: { isAutoRotating.toggle() }) {
                            Image(systemName: isAutoRotating ? "pause.fill" : "play.fill")
                                .foregroundColor(.black)
                                .padding(12)
                                .background(Color.yellow)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 50)
                }
            }
        }
    }
}
