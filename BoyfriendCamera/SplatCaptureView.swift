import SwiftUI
import RealityKit
import ARKit

struct SplatCaptureView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var engine = SplatCaptureEngine()
    @State private var arView: ARView?
    
    var body: some View {
        ZStack {
            // AR Camera Feed
            ARViewContainer(engine: engine, arViewBinding: $arView)
                .edgesIgnoringSafeArea(.all)
            
            // UI Overlay
            VStack {
                // Top Bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                    .padding(.trailing, 8)
                    
                    Text("Director Mode")
                        .font(.headline)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                    Spacer()
                    Text(engine.instructions)
                        .font(.headline)
                        .foregroundColor(.yellow)
                        .padding(8)
                        .background(.black.opacity(0.6))
                        .cornerRadius(8)
                }
                .padding(.top, 50)
                .padding(.horizontal)
                
                Spacer()
                
                // Debug Visualization (Uncertain Voxels)
                // In a real app, this would be 3D entities in RealityKit.
                // For MVP, we list them or show a count.
                if !engine.uncertainVoxels.isEmpty {
                    VStack {
                        Text("High Uncertainty Zones: \(engine.uncertainVoxels.count)")
                            .font(.caption)
                            .foregroundColor(.red)
                        // Simple compass/arrow guidance
                        if let guide = engine.guidanceVector {
                            Image(systemName: "arrow.up")
                                .rotationEffect(Angle(radians: Double(atan2(guide.x, -guide.y))))
                                .font(.largeTitle)
                                .foregroundColor(.yellow)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)
                    .padding(.bottom, 20)
                }
                
                // Capture Button
                Button(action: {
                    if engine.state == .idle {
                        // Assume center is 1m in front of camera
                        if let currentFrame = arView?.session.currentFrame {
                            let transform = currentFrame.camera.transform
                            var translation = matrix_identity_float4x4
                            translation.columns.3.z = -1.0 // 1 meter forward
                            let center = (transform * translation).columns.3
                            engine.startCapture(at: simd_make_float3(center))
                        }
                    }
                }) {
                    ZStack {
                        Circle()
                            .stroke(.white, lineWidth: 4)
                            .frame(width: 80, height: 80)
                        
                        Circle()
                            .fill(engine.state == .capturing ? .red : .white)
                            .frame(width: 70, height: 70)
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var engine: SplatCaptureEngine
    @Binding var arViewBinding: ARView?
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        // Configure AR Session
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        arView.session.run(config)
        
        // Set delegate
        arView.session.delegate = context.coordinator
        
        // Pass view back
        DispatchQueue.main.async {
            self.arViewBinding = arView
        }
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(engine: engine)
    }
    
    class Coordinator: NSObject, ARSessionDelegate {
        var engine: SplatCaptureEngine
        
        init(engine: SplatCaptureEngine) {
            self.engine = engine
        }
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            engine.update(with: frame)
        }
    }
}
