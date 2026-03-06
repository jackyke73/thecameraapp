import SwiftUI
import MetalKit
// import MetalSplatter
// import SplatIO
// import SampleBoxRenderer // For math utilities if needed, or I'll inline them

struct SplatView: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        
        if let defaultDevice = MTLCreateSystemDefaultDevice() {
            mtkView.device = defaultDevice
        }
        
        mtkView.colorPixelFormat = .bgra8Unorm_srgb
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.sampleCount = 1
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        
        /*
        let renderer = SplatViewRenderer(mtkView)
        context.coordinator.renderer = renderer
        mtkView.delegate = renderer
        
        Task {
            do {
                try await renderer?.load(url: url)
            } catch {
                print("Error loading splat: \(error)")
            }
        }
        */
        
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        // Handle updates if URL changes, though usually splats are static for a view instance
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        // var renderer: SplatViewRenderer?
    }
}

/*
class SplatViewRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var splatRenderer: SplatRenderer?
    
    // Camera state
    var rotation: Float = 0
    
    init?(_ mtkView: MTKView) {
        guard let device = mtkView.device,
              let commandQueue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = commandQueue
        super.init()
    }
    
    func load(url: URL) async throws {
        // Initialize renderer
        let renderer = try SplatRenderer(
            device: device,
            colorFormat: .bgra8Unorm_srgb,
            depthFormat: .depth32Float,
            sampleCount: 1,
            maxViewCount: 1,
            maxSimultaneousRenders: 1
        )
        
        // Load PLY
        let reader = try AutodetectSceneReader(url)
        let points = try await reader.readAll()
        let chunk = try SplatChunk(device: device, from: points)
        await renderer.addChunk(chunk)
        
        self.splatRenderer = renderer
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle resize if needed
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let splatRenderer = splatRenderer else { return }
        
        // Simple rotation for demo
        rotation += 0.01
        
        let projectionMatrix = matrix_perspective_right_hand(
            fovyRadians: Float(60.0 * .pi / 180.0),
            aspectRatio: Float(view.drawableSize.width / view.drawableSize.height),
            nearZ: 0.1,
            farZ: 100.0
        )
        
        let viewMatrix = matrix_look_at_right_hand(
            eye: SIMD3<Float>(0, 0, 5), // Camera back 5 units
            target: SIMD3<Float>(0, 0, 0),
            up: SIMD3<Float>(0, 1, 0)
        )
        
        // Model rotation
        let modelMatrix = matrix4x4_rotation(radians: rotation, axis: SIMD3<Float>(0, 1, 0))
        
        let viewport = MTLViewport(
            originX: 0, originY: 0,
            width: Double(view.drawableSize.width),
            height: Double(view.drawableSize.height),
            znear: 0, zfar: 1
        )
        
        let viewportDescriptor = SplatRenderer.ViewportDescriptor(
            viewport: viewport,
            projectionMatrix: projectionMatrix,
            viewMatrix: viewMatrix * modelMatrix, // Apply model rotation to view for simplicity
            screenSize: SIMD2(x: Int(view.drawableSize.width), y: Int(view.drawableSize.height))
        )
        
        do {
            try splatRenderer.render(
                viewports: [viewportDescriptor],
                colorTexture: view.multisampleColorTexture ?? drawable.texture,
                colorStoreAction: view.multisampleColorTexture == nil ? .store : .multisampleResolve,
                depthTexture: view.depthStencilTexture,
                rasterizationRateMap: nil,
                renderTargetArrayLength: 0,
                to: commandBuffer
            )
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
        } catch {
            print("Render error: \(error)")
        }
    }
}

// MARK: - Matrix Helpers
// Basic matrix math needed for 3D rendering

func matrix_perspective_right_hand(fovyRadians fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
    let ys = 1 / tanf(fovy * 0.5)
    let xs = ys / aspectRatio
    let zs = farZ / (nearZ - farZ)
    return matrix_float4x4.init(columns: (
        vector_float4(xs,  0, 0,   0),
        vector_float4( 0, ys, 0,   0),
        vector_float4( 0,  0, zs, -1),
        vector_float4( 0,  0, zs * nearZ, 0)
    ))
}

func matrix_look_at_right_hand(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> matrix_float4x4 {
    let z = normalize(eye - target)
    let x = normalize(cross(up, z))
    let y = cross(z, x)
    return matrix_float4x4.init(columns: (
        vector_float4(x.x, y.x, z.x, 0),
        vector_float4(x.y, y.y, z.y, 0),
        vector_float4(x.z, y.z, z.z, 0),
        vector_float4(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
    ))
}

func matrix4x4_rotation(radians: Float, axis: SIMD3<Float>) -> matrix_float4x4 {
    let unitAxis = normalize(axis)
    let ct = cosf(radians)
    let st = sinf(radians)
    let ci = 1 - ct
    let x = unitAxis.x, y = unitAxis.y, z = unitAxis.z
    return matrix_float4x4.init(columns: (
        vector_float4(ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
        vector_float4(x * y * ci - z * st, ct + y * y * ci, z * y * ci + x * st, 0),
        vector_float4(x * z * ci + y * st, y * z * ci - x * st, ct + z * z * ci, 0),
        vector_float4(0, 0, 0, 1)
    ))
}
*/
