import Foundation
import ARKit
import SwiftUI
import Combine

/// The SplatCaptureEngine manages the "Orbital Sweep" UX.
class SplatCaptureEngine: ObservableObject {
    
    enum CaptureState {
        case idle
        case centering // User is aligning the object
        case capturing // Active sweep
        case processing // Local training in progress
        case complete
    }
    
    @Published var state: CaptureState = .idle
    @Published var coverage: Float = 0.0
    @Published var instructions: String = "Find your object"
    @Published var uncertainVoxels: [SIMD3<Float>] = []
    @Published var guidanceVector: SIMD3<Float>? = nil
    @Published var capturedFrameCount: Int = 0
    @Published var showCoachingPrompt: Bool = false
    @Published var coachingMessage: String = ""
    @Published var capturedSplatPoints: [SIMD3<Float>] = []

    private var capturedKeyframes: [ARFrame] = []
    private var centerPoint: simd_float3?
    private let requiredKeyframes = 40
    
    private var capturedBuckets: Set<Int> = []
    private let horizontalBuckets = 36
    private let verticalBuckets = 12
    
    private let agentic3DEngine = Agentic3DEngine()
    
    private var lastGuidanceTime: Date = Date()
    private var stagnationCount: Int = 0
    private var previousCoverage: Float = 0.0
    
    func startCapture(at center: simd_float3) {
        self.centerPoint = center
        self.state = .capturing
        self.capturedKeyframes = []
        self.capturedBuckets = []
        self.capturedSplatPoints = []
        self.coverage = 0.0
        self.capturedFrameCount = 0
        self.instructions = "Slowly orbit the object"
        
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
        
        checkCaptureStagnation(currentCoverage: coverage)

        if distance < 0.3 {
            self.instructions = "Too Close - Move Back"
            return
        } else if distance > 3.0 {
            self.instructions = "Too Far - Get Closer"
            return
        }

        let azimuth = atan2(direction.z, direction.x)
        let polar = acos(direction.y / distance)
        
        let aziBucket = Int(((azimuth + .pi) / (2 * .pi)) * Float(horizontalBuckets)) % horizontalBuckets
        let polBucket = Int((polar / .pi) * Float(verticalBuckets)) % verticalBuckets
        let bucketKey = (aziBucket << 8) | polBucket
        
        // Logic change: even if bucket is visited, we still want to stream points for the visualizer
        // but only "record" the keyframe if it's new for coverage
        
        // Extract feature points for point-cloud preview
        if let points = frame.rawFeaturePoints?.points {
            let localPoints = points.map { $0 - center }
            DispatchQueue.main.async {
                self.capturedSplatPoints.append(contentsOf: localPoints)
                // Performance: cap the preview points
                if self.capturedSplatPoints.count > 12000 {
                    self.capturedSplatPoints.removeFirst(localPoints.count)
                }
            }
        }

        if !capturedBuckets.contains(bucketKey) || capturedKeyframes.count < requiredKeyframes {
            if !capturedBuckets.contains(bucketKey) {
                capturedBuckets.insert(bucketKey)
                
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }
            
            capturedKeyframes.append(frame)
            self.capturedFrameCount = capturedKeyframes.count
            
            coverage = min(Float(capturedBuckets.count) / Float(requiredKeyframes), 1.0)
            
            Task {
                let newSplats = frame.rawFeaturePoints?.points ?? []
                if let vector = await agentic3DEngine.updateUncertaintyMap(currentCameraPosition: cameraPos, newSplats: newSplats) {
                    await MainActor.run {
                        self.guidanceVector = vector
                        updateInstructions(guidance: vector, cameraPos: cameraPos, target: center)
                    }
                }
                
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
        if currentCoverage <= previousCoverage {
            stagnationCount += 1
        } else {
            stagnationCount = 0
            previousCoverage = currentCoverage
            if showCoachingPrompt {
                DispatchQueue.main.async { self.showCoachingPrompt = false }
            }
        }
        
        if stagnationCount > 180 { 
            triggerCoaching(message: "Change your height or orbit faster")
            stagnationCount = 0
        }
    }
    
    private func triggerCoaching(message: String) {
        DispatchQueue.main.async {
            self.coachingMessage = message
            self.showCoachingPrompt = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                if self.coachingMessage == message {
                    self.showCoachingPrompt = false
                }
            }
        }
        
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
    
    private func updateInstructions(guidance: SIMD3<Float>, cameraPos: SIMD3<Float>, target: SIMD3<Float>) {
        let viewDir = simd_normalize(target - cameraPos)
        
        if abs(guidance.y) > 0.7 {
            self.instructions = guidance.y > 0 ? "Rise Up" : "Lower Camera"
        } else {
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
        self.instructions = "Generating Splats..."
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // Higher autonomy: we could trigger a real cloud build here in the future
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.state = .complete
            self.instructions = "3D Asset Ready"
        }
    }
}
