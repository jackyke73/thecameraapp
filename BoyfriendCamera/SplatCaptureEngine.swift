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
    @Published var uncertainVoxels: [SIMD3<Float>] = [] // For visualization
    @Published var guidanceVector: SIMD3<Float>? = nil // Direction to move
    @Published var capturedFrameCount: Int = 0
    @Published var showCoachingPrompt: Bool = false
    @Published var coachingMessage: String = ""

    private var capturedKeyframes: [ARFrame] = []
    private var centerPoint: simd_float3?
    private let requiredKeyframes = 40
    
    // Octree for spatial diversity check (prevent redundant frame capture)
    private var capturedBuckets: Set<Int> = []
    private let horizontalBuckets = 36 // 10 degrees per bucket
    private let verticalBuckets = 12   // 15 degrees per bucket
    
    // Dependencies
    private let agentic3DEngine = Agentic3DEngine()
    
    // Coaching State
    private var lastGuidanceTime: Date = Date()
    private var stagnationCount: Int = 0
    private var previousCoverage: Float = 0.0
    
    func startCapture(at center: simd_float3) {
        self.centerPoint = center
        self.state = .capturing
        self.capturedKeyframes = []
        self.capturedBuckets = []
        self.coverage = 0.0
        self.capturedFrameCount = 0
        self.instructions = "Slowly orbit the object"
        
        // Haptic feedback for start
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    func update(with frame: ARFrame) {
        guard state == .capturing, let center = centerPoint else { return }
        
        let cameraTransform = frame.camera.transform
        let cameraPos = simd_make_float3(cameraTransform.columns.3)
        
        processFrameForCoverage(frame, cameraPos: cameraPos, center: center)
    }
    
    private func processFrameForCoverage(_ frame: ARFrame, cameraPos: simd_float3, center: simd_float3) {
        let direction = cameraPos - center
        let distance = simd_length(direction)
        
        // Stagnation / Drift Check
        checkCaptureStagnation(currentCoverage: coverage)

        // Distance check: Stay within a reasonable capture range (0.3m to 3.0m)
        if distance < 0.3 {
            self.instructions = "Too Close - Move Back"
            return
        } else if distance > 3.0 {
            self.instructions = "Too Far - Get Closer"
            return
        }

        // Calculate angular position on the capture sphere
        let azimuth = atan2(direction.z, direction.x) // -PI to PI
        let polar = acos(direction.y / distance)    // 0 to PI
        
        // Discretize into buckets for diversity tracking
        let aziBucket = Int(((azimuth + .pi) / (2 * .pi)) * Float(horizontalBuckets)) % horizontalBuckets
        let polBucket = Int((polar / .pi) * Float(verticalBuckets)) % verticalBuckets
        let bucketKey = (aziBucket << 8) | polBucket
        
        // If this is a new angle or we need more frames generally
        if !capturedBuckets.contains(bucketKey) || capturedKeyframes.count < requiredKeyframes {
            if !capturedBuckets.contains(bucketKey) {
                capturedBuckets.insert(bucketKey)
                
                // Haptic feedback for discovery of new angle
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }
            
            capturedKeyframes.append(frame)
            self.capturedFrameCount = capturedKeyframes.count
            
            // Coverage is based on discovered angles vs target diversity
            // Max potential unique buckets is horizontalBuckets * verticalBuckets
            // But we only need ~40 for a good splat.
            coverage = min(Float(capturedBuckets.count) / Float(requiredKeyframes), 1.0)
            
            // AG-Splatting Integration (Visualization & Active Guidance)
            Task {
                // Use sparse feature points as proxies for splat density
                let newSplats = frame.rawFeaturePoints?.points ?? []
                
                // Update Engine & Get Next Best View Vector
                if let vector = await agentic3DEngine.updateUncertaintyMap(currentCameraPosition: cameraPos, newSplats: newSplats) {
                    await MainActor.run {
                        self.guidanceVector = vector
                        
                        // Smart instruction logic based on guidance vector vs camera look direction
                        updateInstructions(guidance: vector, cameraPos: cameraPos, target: center)
                    }
                }
                
                // Update Debug Visualization
                let voxels = await agentic3DEngine.getHighUncertaintyVoxels()
                await MainActor.run {
                    self.uncertainVoxels = voxels
                }
            }
            
            if coverage >= 1.0 && capturedKeyframes.count >= requiredKeyframes {
                finalizeCapture()
            }
        }
    }
    
    private func checkCaptureStagnation(currentCoverage: Float) {
        let now = Date()
        
        // If coverage hasn't increased in 3 seconds of active scanning
        if currentCoverage <= previousCoverage {
            stagnationCount += 1
        } else {
            stagnationCount = 0
            previousCoverage = currentCoverage
            if showCoachingPrompt {
                DispatchQueue.main.async { self.showCoachingPrompt = false }
            }
        }
        
        // Trigger coaching if stuck or time-based nudge
        if stagnationCount > 180 { // Approx 3 seconds at 60fps
            triggerCoaching(message: "Change your height or orbit faster")
            stagnationCount = 0
        }
    }
    
    private func triggerCoaching(message: String) {
        DispatchQueue.main.async {
            self.coachingMessage = message
            self.showCoachingPrompt = true
            
            // Auto-hide after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                if self.coachingMessage == message {
                    self.showCoachingPrompt = false
                }
            }
        }
        
        // Haptic nudge
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
    
    private func updateInstructions(guidance: SIMD3<Float>, cameraPos: SIMD3<Float>, target: SIMD3<Float>) {
        // Guidance vector is in world space. 
        // We want to translate this into camera-relative instructions.
        
        // Vector from camera to object
        let viewDir = simd_normalize(target - cameraPos)
        
        // Project guidance onto horizontal/vertical axes relative to camera
        // (Simplified logic for now)
        if abs(guidance.y) > 0.7 {
            self.instructions = guidance.y > 0 ? "Rise Up" : "Lower Camera"
        } else {
            // Check cross product for left/right orbit
            let cross = simd_cross(viewDir, guidance)
            if cross.y > 0.3 {
                self.instructions = "Orbit Right"
            } else if cross.y < -0.3 {
                self.instructions = "Orbit Left"
            } else {
                self.instructions = "Orbit Slowly"
            }
        }
    }
    
    private func finalizeCapture() {
        self.state = .processing
        self.instructions = "Finalizing 3D Reconstruction..."
        
        // Haptic notification for completion
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // Simulated local reconstruction time
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            self.state = .complete
            self.instructions = "3D Asset Ready"
        }
    }
}
