import SwiftUI
import RealityKit
import ARKit
import Combine

struct SplatCaptureView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var engine = SplatCaptureEngine()
    @State private var arView: VoxelARView?
    @State private var showingReview = false

    var body: some View {
        ZStack {
            // AR Camera Feed
            ARViewContainer(engine: engine, arViewBinding: $arView)
                .edgesIgnoringSafeArea(.all)
            
            // Modern HUD Overlay
            VStack {
                // Top Bar
                HStack(alignment: .top) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("SPLATMARKET")
                            .font(.system(size: 10, weight: .black))
                            .tracking(2)
                            .foregroundColor(.yellow)
                        
                        HStack(spacing: 4) {
                            Circle()
                                .fill(engine.state == .capturing ? .red : .gray)
                                .frame(width: 6, height: 6)
                            Text("\(engine.totalPointsInWorld) PTS")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        
                        Text(engine.instructions.uppercased())
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(engine.instructions.contains("Too") ? .red : .yellow)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.8))
                            .cornerRadius(4)
                    }
                }
                .padding(.top, 60)
                .padding(.horizontal)
                
                Spacer()
                
                // Vibe Score Meter (Right Side)
                if engine.state == .capturing {
                    HStack {
                        Spacer()
                        VibeMeter(score: engine.currentVibeScore)
                            .frame(width: 40, height: 200)
                            .padding(.trailing, 20)
                    }
                }
                
                // Guidance Indicator (Active AG-Splatting)
                if engine.state == .capturing, let guide = engine.guidanceVector {
                    CaptureGuidanceRing(vector: guide, coverage: engine.coverage)
                        .frame(width: 200, height: 200)
                        .padding(.bottom, 40)
                        .overlay(
                            VStack {
                                if engine.showCoachingPrompt {
                                    Text(engine.coachingMessage.uppercased())
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.yellow)
                                        .cornerRadius(4)
                                        .transition(.opacity.combined(with: .offset(y: 10)))
                                        .animation(.easeInOut, value: engine.showCoachingPrompt)
                                }
                            }
                            .offset(y: 60)
                        )
                }
                
                // Progress & Controls
                VStack(spacing: 20) {
                    if engine.state == .capturing || engine.state == .processing {
                        VStack(spacing: 8) {
                            HStack {
                                Text("MODEL COVERAGE")
                                    .font(.system(size: 10, weight: .bold))
                                Spacer()
                                Text("\(Int(engine.coverage * 100))%")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                            }
                            .foregroundColor(.white)
                            
                            ProgressView(value: engine.coverage)
                                .progressViewStyle(LinearProgressViewStyle(tint: .yellow))
                                .scaleEffect(x: 1, y: 2, anchor: .center)
                        }
                        .padding(.horizontal, 40)
                    }
                    
                    if engine.state == .complete {
                        Button(action: { 
                            showingReview = true 
                        }) {
                            Text("POST TO FEED")
                                .font(.system(size: 14, weight: .black))
                                .foregroundColor(.black)
                                .padding(.horizontal, 30)
                                .padding(.vertical, 15)
                                .background(Color.yellow)
                                .cornerRadius(30)
                                .shadow(color: .yellow.opacity(0.3), radius: 10)
                        }
                        .transition(.scale.combined(with: .opacity))
                    } else if engine.state == .processing {
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .stroke(Color.white.opacity(0.1), lineWidth: 4)
                                    .frame(width: 60, height: 60)
                                Circle()
                                    .trim(from: 0, to: CGFloat(engine.neuralOptimizationProgress))
                                    .stroke(Color.yellow, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                    .frame(width: 60, height: 60)
                                    .rotationEffect(.degrees(-90))
                                
                                Text("\(Int(engine.neuralOptimizationProgress * 100))%")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                            
                            Text("TRAINING GAUSSIANS")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    } else {
                        // Capture Button
                        Button(action: {
                            if engine.state == .idle {
                                startCaptureSequence()
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .stroke(.white, lineWidth: 3)
                                    .frame(width: 84, height: 84)
                                
                                Circle()
                                    .fill(engine.state == .capturing ? .red : .white)
                                    .frame(width: 72, height: 72)
                                    .scaleEffect(engine.state == .capturing ? 0.8 : 1.0)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: engine.state)
                            }
                        }
                        .disabled(engine.state == .processing)
                    }
                }
                .padding(.bottom, 50)
            }
        }
        .fullScreenCover(isPresented: $showingReview) {
            ZStack {
                SplatPointRenderer(splatData: engine.capturedSplatPoints)
                
                VStack {
                    HStack {
                        Button(action: { showingReview = false }) {
                            Image(systemName: "chevron.left")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        Spacer()
                        Text("SPLATMARKET PREVIEW")
                            .font(.system(size: 12, weight: .black))
                            .foregroundColor(.white)
                        Spacer()
                        Button(action: { /* Share action */ }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.top, 60)
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    Text("SWIPE TO ROTATE • PINCH TO ZOOM")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.bottom, 40)
                }
            }
            .edgesIgnoringSafeArea(.all)
        }
        .onChange(of: engine.uncertainVoxels) { newVoxels in
            arView?.updateVoxelVisualization(voxels: newVoxels)
        }
    }
    
    private func startCaptureSequence() {
        if let currentFrame = arView?.session.currentFrame {
            let transform = currentFrame.camera.transform
            var translation = matrix_identity_float4x4
            translation.columns.3.z = -1.0 // 1m forward
            let center = (transform * translation).columns.3
            engine.startCapture(at: simd_make_float3(center.x, center.y, center.z))
        }
    }
}

struct VibeMeter: View {
    let score: Float
    
    var body: some View {
        VStack(spacing: 8) {
            Text("VIBE")
                .font(.system(size: 8, weight: .black))
                .foregroundColor(.yellow)
            
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 6)
                
                Capsule()
                    .fill(LinearGradient(colors: [.yellow, .orange, .red], startPoint: .top, endPoint: .bottom))
                    .frame(width: 6, height: 200 * CGFloat(score))
            }
            
            Text("\(Int(score * 100))")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
    }
}

struct CaptureGuidanceRing: View {
    let vector: SIMD3<Float>
    let coverage: Float
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.2), lineWidth: 2)
            
            Circle()
                .trim(from: 0, to: CGFloat(coverage))
                .stroke(Color.yellow, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            
            // Directional Arrow
            Image(systemName: "chevron.up")
                .font(.system(size: 30, weight: .black))
                .foregroundColor(.yellow)
                .offset(y: -80)
                .rotationEffect(Angle(radians: Double(atan2(vector.x, -vector.z))))
            
            Text("SCAN ZONE")
                .font(.system(size: 8, weight: .black))
                .foregroundColor(.white.opacity(0.4))
        }
    }
}

// AR Implementation
class VoxelARView: ARView {
    private var voxelAnchor: AnchorEntity?
    
    func setup() {
        let anchor = AnchorEntity(world: .zero)
        scene.anchors.append(anchor)
        self.voxelAnchor = anchor
    }

    func updateVoxelVisualization(voxels: [SIMD3<Float>]) {
        guard let anchor = voxelAnchor else { return }
        anchor.children.removeAll()
        
        let mesh = MeshResource.generateBox(size: 0.04)
        let material = SimpleMaterial(color: .red.withAlphaComponent(0.4), isMetallic: false)
        
        for position in voxels.prefix(50) { // Limit for performance
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.position = position
            anchor.addChild(entity)
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var engine: SplatCaptureEngine
    @Binding var arViewBinding: VoxelARView?
    
    func makeUIView(context: Context) -> VoxelARView {
        let arView = VoxelARView(frame: .zero)
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        arView.session.run(config)
        arView.setup()
        arView.session.delegate = context.coordinator
        DispatchQueue.main.async { self.arViewBinding = arView }
        return arView
    }
    
    func updateUIView(_ uiView: VoxelARView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(engine: engine) }
    
    class Coordinator: NSObject, ARSessionDelegate {
        var engine: SplatCaptureEngine
        init(engine: SplatCaptureEngine) { self.engine = engine }
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            engine.update(with: frame)
        }
    }
}
