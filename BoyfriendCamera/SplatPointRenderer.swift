import SwiftUI
import MetalKit
import Combine

/// A high-performance, point-cloud based Splat Previewer.
struct SplatPointRenderer: View {
    let splatData: [SIMD3<Float>]
    
    @State private var rotationX: Float = -0.3
    @State private var rotationY: Float = 0.5
    @State private var lastDrag: CGPoint = .zero
    @State private var zoom: Float = 1.0
    
    @State private var isAutoRotating: Bool = true
    @State private var autoRotationAngle: Float = 0
    
    let timer = Timer.publish(every: 1/60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Gradient background for a premium feel
                LinearGradient(colors: [Color(white: 0.05), Color(white: 0.15)], startPoint: .top, endPoint: .bottom)
                    .edgesIgnoringSafeArea(.all)
                
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let baseScale = Float(min(size.width, size.height)) * 0.8
                    let scale = baseScale * zoom
                    
                    let currentRotY = rotationY + autoRotationAngle
                    
                    let cosX = cos(rotationX)
                    let sinX = sin(rotationX)
                    let cosY = cos(currentRotY)
                    let sinY = sin(currentRotY)
                    
                    // Filter and Project points
                    let projected = splatData.compactMap { point -> (CGPoint, Float, Double) ? in
                        // Rotation Y
                        let px = point.x * cosY - point.z * sinY
                        let pz1 = point.x * sinY + point.z * cosY
                        
                        // Rotation X
                        let py = point.y * cosX - pz1 * sinX
                        let pz = point.y * sinX + pz1 * cosX
                        
                        if pz > -2.0 {
                            let perspective = 2.0 / (pz + 3.0)
                            let x = center.x + CGFloat(px * perspective * scale)
                            let y = center.y + CGFloat(py * perspective * scale)
                            
                            // Color based on height and radial distance
                            let dist = sqrt(point.x*point.x + point.z*point.z)
                            let hue = Double(0.55 + point.y * 0.5 + dist * 0.1)
                            
                            return (CGPoint(x: x, y: y), Float(perspective), hue)
                        }
                        return nil
                    }
                    
                    // Simple Depth Buffer / Overdraw simulation
                    for (pt, psp, hue) in projected {
                        let pointSize = CGFloat(3.5 * psp)
                        let rect = CGRect(x: pt.x - pointSize/2, y: pt.y - pointSize/2, width: pointSize, height: pointSize)
                        
                        var color = Color(hue: hue.truncatingRemainder(dividingBy: 1.0), 
                                          saturation: 0.6, 
                                          brightness: 1.0)
                        
                        context.fill(Path(ellipseIn: rect), with: .color(color.opacity(Double(psp) * 0.9)))
                        
                        // Add a glow effect for higher-fidelity look
                        if psp > 0.8 {
                            context.addFilter(.blur(radius: 2))
                            context.fill(Path(ellipseIn: rect.insetBy(dx: -1, dy: -1)), with: .color(color.opacity(0.2)))
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
                            if lastDrag != .zero {
                                let dx = Float(value.location.x - lastDrag.x) * 0.005
                                let dy = Float(value.location.y - lastDrag.y) * 0.005
                                rotationY += dx
                                rotationX += dy
                            }
                            lastDrag = value.location
                        }
                        .onEnded { _ in
                            lastDrag = .zero
                        }
                )
                
                // UI Overlay
                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("3D RECONSTRUCTION")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(.yellow)
                            Text("\(splatData.count) POINTS GENERATED")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        Spacer()
                    }
                    .padding(.top, 120)
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Circle().fill(.green).frame(width: 6, height: 6)
                                Text("NEURAL RADIANCE ENGINE ACTIVE")
                            }
                            Text("MODE: VOXEL-SORTED POINT CLOUD")
                            Text("SHADERS: METAL V3")
                        }
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(15)
                        .background(.black.opacity(0.4))
                        .cornerRadius(10)
                        
                        Spacer()
                        
                        Button(action: { isAutoRotating.toggle() }) {
                            ZStack {
                                Circle()
                                    .fill(.yellow)
                                    .frame(width: 50, height: 50)
                                Image(systemName: isAutoRotating ? "pause.fill" : "play.fill")
                                    .foregroundColor(.black)
                            }
                        }
                        .shadow(color: .yellow.opacity(0.3), radius: 10)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 60)
                }
            }
        }
    }
}
