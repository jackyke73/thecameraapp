import Foundation
import ARKit
import SwiftUI
import Combine

/// The SplatCaptureEngine manages the "Orbital Sweep" UX.
/// It uses ARKit to track the camera position and ensure the user captures enough 
/// viewpoints for a successful 3D Gaussian Splat training session on-device.
class SplatCaptureEngine: ObservableObject {
    
    enum CaptureState {
        case idle
        case centering // User is aligning the object
        case capturing // Active sweep
        case processing // Local training in progress
        case complete
    }
    
    @Published var state: CaptureState = .idle
    @Published var coverage: Float = 0.0 // 0.0 to 1.0 (percent of the sphere covered)
    @Published var instructions: String = "Find your object"
    
    private var capturedKeyframes: [ARFrame] = []
    private var centerPoint: simd_float3?
    private let requiredKeyframes = 40
    
    func startCapture(at center: simd_float3) {
        self.centerPoint = center
        self.state = .capturing
        self.capturedKeyframes = []
        self.coverage = 0.0
        self.instructions = "Slowly orbit the object"
    }
    
    func update(with frame: ARFrame) {
        guard state == .capturing, let center = centerPoint else { return }
        
        let cameraTransform = frame.camera.transform
        let cameraPos = simd_make_float3(cameraTransform.columns.3)
        
        // Logic: Calculate angle around the center point
        // Check if we have a keyframe at this angle. If not, save one.
        // Update coverage based on angle diversity.
        
        processFrameForCoverage(frame, cameraPos: cameraPos, center: center)
    }
    
    private func processFrameForCoverage(_ frame: ARFrame, cameraPos: simd_float3, center: simd_float3) {
        // Simplified heuristic for this prototype:
        // Measure the angle around the Y-axis relative to the center.
        let direction = cameraPos - center
        let angle = atan2(direction.z, direction.x)
        
        // If this angle is 'new' enough, store the frame for the trainer
        // (In a real app, we'd store the image buffer + pose)
        
        // Update mock coverage for UI development
        if capturedKeyframes.count < requiredKeyframes {
            capturedKeyframes.append(frame)
            coverage = Float(capturedKeyframes.count) / Float(requiredKeyframes)
            
            if coverage >= 1.0 {
                finalizeCapture()
            }
        }
    }
    
    private func finalizeCapture() {
        self.state = .processing
        self.instructions = "Training 3D Memory (Local)..."
        
        // Mock the 90s training time for the MVP UI
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.state = .complete
            self.instructions = "3D Memory Ready"
        }
    }
}
