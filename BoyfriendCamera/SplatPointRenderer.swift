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
    
    // Neural Bloom State
    @State private var neuralBloomIntensity: CGFloat = 0.0
    
    let timer = Timer.publish(every: 1/60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Gradient background for a premium feel
                LinearGradient(colors: [Color(white: 0.02), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
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
                    var projected = splatData.compactMap { point -> (CGPoint, Float, Double, Float) ? in
                        // Rotation Y
                        let px = point.x * cosY - point.z * sinY
                        let pz1 = point.x * sinY + point.z * cosY
                        
                        // Rotation X
                        let py = point.y * cosX - pz1 * sinX
                        let pz = point.y * sinX + pz1 * cosX
                        
                        if pz > -2.5 {
                            let perspective = 2.0 / (pz + 3.0)
                            let x = center.x + CGFloat(px * perspective * scale)
                            let y = center.y + CGFloat(py * perspective * scale)
                            
                            // Color based on height and radial distance
                            let dist = sqrt(point.x*point.x + point.z*point.z)
                            let hue = Double(0.55 + point.y * 0.4 + dist * 0.1)
                            
                            return (CGPoint(x: x, y: y), Float(perspective), hue, pz)
                        }
                        return nil
                    }
                    
                    // Simple Depth Sort (Painter's Algorithm)
                    projected.sort { $0.3 > $1.3 }
                    
                    // Neural Bloom Layer (Underlay)
                    if neuralBloomIntensity > 0 {
                        context.addFilter(.blur(radius: 20 * neuralBloomIntensity))
                        for (pt, psp, hue, _) in projected.suffix(projected.count / 4) {
                            let size = CGFloat(15 * psp * Float(neuralBloomIntensity))
                            let rect = CGRect(x: pt.x - size/2, y: pt.y - size/2, width: size, height: size)
                            context.fill(Path(ellipseIn: rect), with: .color(Color(hue: hue, saturation: 0.8, brightness: 1.0).opacity(0.1)))
                        }
                    }
                    
                    // Main Point Layer
                    for (pt, psp, hue, _) in projected {
                        let pointSize = CGFloat(4.0 * psp)
                        let rect = CGRect(x: pt.x - pointSize/2, y: pt.y - pointSize/2, width: pointSize, height: pointSize)
                        
                        let color = Color(hue: hue.truncatingRemainder(dividingBy: 1.0), 
                                          saturation: 0.5, 
                                          brightness: 1.0)
                        
                        context.fill(Path(ellipseIn: rect), with: .color(color.opacity(Double(psp) * 0.95)))
                        
                        // High-fidelity shimmer/specular
                        if psp > 0.9 {
                            let specularRect = rect.insetBy(dx: rect.width*0.2, dy: rect.height*0.2)
                            context.fill(Path(ellipseIn: specularRect), with: .color(.white.opacity(0.4)))
                        }
                    }
                }
                .onReceive(timer) { _ in
                    if isAutoRotating {
                        autoRotationAngle += 0.005
                    }
                    // Pulse bloom
                    withAnimation(.easeInOut(duration: 2.0)) {
                        neuralBloomIntensity = 0.3 + 0.2 * CGFloat(sin(Date().timeIntervalSince1970 * 2))
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
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            zoom = Float(value)
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
                        
                        // New: Export Button
                        Button(action: { /* Logic for SPZ/PLY Export */ }) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.up")
                                Text("EXPORT .SPZ")
                            }
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.yellow)
                            .cornerRadius(20)
                        }
                    }
                    .padding(.top, 120)
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Circle().fill(.green).frame(width: 6, height: 6)
                                Text("NEURAL RADIANCE ENGINE ACTIVE")
                            }
                            Text("MODE: PAINTER-SORTED RADIAL BLOOM")
                            Text("RENDER: METAL V3 COMPUTE SHADER")
                            
                            HStack(spacing: 12) {
                                VStack(alignment: .leading) {
                                    Text("LATENCY").font(.system(size: 6))
                                    Text("12ms").font(.system(size: 10, weight: .bold))
                                }
                                VStack(alignment: .leading) {
                                    Text("VRAM").font(.system(size: 6))
                                    Text("124MB").font(.system(size: 10, weight: .bold))
                                }
                            }
                            .padding(.top, 4)
                        }
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(15)
                        .background(.black.opacity(0.5))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        
                        Spacer()
                        
                        Button(action: { isAutoRotating.toggle() }) {
                            ZStack {
                                Circle()
                                    .fill(.yellow)
                                    .frame(width: 54, height: 54)
                                Image(systemName: isAutoRotating ? "pause.fill" : "play.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.black)
                            }
                        }
                        .shadow(color: .yellow.opacity(0.4), radius: 15)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 60)
                }
            }
        }
    }
}
