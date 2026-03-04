import Foundation
import CoreVideo
import Combine
import Vision
import CoreImage

// Represents the output of a VLM or advanced semantic analysis model
struct SemanticFrameAnalysis: Equatable, Sendable {
    let sceneDescription: String // e.g., "A woman standing in front of a sunset."
    let lightingQuality: LightingQuality
    let compositionScore: Double // 0.0 to 1.0
    let creativeSuggestion: String? // e.g., "Try a lower angle for a heroic look."
    let clutterDetected: Bool
    
    // New: 3D / Spatial Guidance (The "Director's Cut")
    let spatialGuidance: SpatialGuidance?
    
    static let empty = SemanticFrameAnalysis(
        sceneDescription: "Analyzing scene...",
        lightingQuality: .unknown,
        compositionScore: 0.0,
        creativeSuggestion: nil,
        clutterDetected: false,
        spatialGuidance: nil
    )
}

struct SpatialGuidance: Equatable, Sendable {
    let action: String // e.g., "Move Left", "Tilt Up"
    let confidence: Double
    let targetObject: String? // e.g., "The Campanile", "Sunset"
}

enum LightingQuality: String, Sendable {
    case unknown = "Unknown"
    case poor = "Too Dark"
    case harsh = "Harsh Shadows"
    case good = "Good"
    case goldenHour = "Golden Hour"
    case studio = "Studio Quality"
    case tooBright = "Overexposed"
}

// Service to run semantic inference (VLM / MobileVLM mock + Vision Analysis)
actor SemanticDirectorEngine: DirectorEngineProtocol {
    
    // Simulate inference time
    private let inferenceDuration: TimeInterval = 0.1 // Fast Vision loop (100ms)
    
    // Vision Service
    private let visionService: VisionAnalysisService
    
    init() {
        print("SemanticDirectorEngine: Initializing Vision resources...")
        self.visionService = VisionAnalysisService()
    }
    
    // State for temporal smoothing to prevent flicker
    private var lastLightingQuality: LightingQuality = .unknown
    private var lightingStabilityCount: Int = 0
    private let stabilityThreshold: Int = 2 // Require 2 consecutive frames for a change
    
    // State for "Director Persona" (Mock VLM Context)
    private var frameCounter: Int = 0
    private var lastGuidanceChangeTime: TimeInterval = 0
    
    // Conformance to DirectorEngineProtocol
    func resetState() {
        lastLightingQuality = .unknown
        lightingStabilityCount = 0
        frameCounter = 0
        lastGuidanceChangeTime = 0
    }

    func analyze(pixelBuffer: CVPixelBuffer) async throws -> SemanticFrameAnalysis {
        // Run Vision analysis
        let visionResult = visionService.analyze(pixelBuffer: pixelBuffer)
        
        // --- 1. Lighting Analysis (Heuristic from Luma) ---
        var detectedLighting: LightingQuality = .unknown
        if let result = visionResult {
            let b = result.brightness
            if b < 0.25 {
                detectedLighting = .poor
            } else if b > 0.85 {
                detectedLighting = .tooBright
            } else if b > 0.6 && b < 0.8 {
                detectedLighting = .good // "Studio" range roughly
            } else {
                detectedLighting = .good
            }
        }

        // --- 2. Composition Logic (The "Director") ---
        var suggestion: String? = nil
        var score: Double = 0.5
        var description = "Scene"
        var spatialAction: SpatialGuidance? = nil
        
        if let result = visionResult {
            // Priority 1: Face Logic
            if result.faceCount == 0 {
                description = "Landscape / Object"
                suggestion = "Find a subject!"
                score = 0.3
                
                // Simulating VLM "Interest"
                if result.subjectIsolationScore > 0.3 {
                   description = "Object Detected"
                   suggestion = "Center the object."
                   score = 0.6
                }
            } else if result.faceCount >= 1 {
                // We have a subject. Let's see if we have body pose data too.
                var poseFeedback: String? = nil
                var poseType = "Portrait"
                
                if let pose = result.bodyPose {
                     // Check for Full Body
                     let joints = try? pose.recognizedPoints(.all)
                     if let leftAnkle = joints?[.leftAnkle], let rightAnkle = joints?[.rightAnkle], leftAnkle.confidence > 0.5 || rightAnkle.confidence > 0.5 {
                         poseType = "Full Body"
                     } else if let leftHip = joints?[.leftHip], let rightHip = joints?[.rightHip], leftHip.confidence > 0.5 {
                         poseType = "Waist Up"
                     }
                     
                     // Check Posture (Shoulder Tilt)
                     if let leftShoulder = joints?[.leftShoulder], let rightShoulder = joints?[.rightShoulder],
                        leftShoulder.confidence > 0.6 && rightShoulder.confidence > 0.6 {
                         
                         let tilt = leftShoulder.location.y - rightShoulder.location.y
                         if abs(tilt) > 0.05 { // 5% height difference
                             poseFeedback = "Level your shoulders!"
                         }
                     }
                }
                
                description = poseType
                
                if let face = result.mainFaceBounds {
                    let faceArea = face.width * face.height
                    
                    if faceArea < 0.05 && poseType == "Portrait" {
                        suggestion = "Move closer!"
                        score = 0.4
                        spatialAction = SpatialGuidance(action: "Move Forward", confidence: 0.8, targetObject: "Subject")
                    } else if faceArea > 0.6 {
                        suggestion = "Back up a bit!"
                        score = 0.4
                        spatialAction = SpatialGuidance(action: "Move Back", confidence: 0.8, targetObject: "Subject")
                    } else {
                        // Check centering (Rule of Thirds-ish)
                        let centerX = face.midX
                        let centerY = face.midY
                        
                        let powerPoints = [
                            CGPoint(x: 0.333, y: 0.333),
                            CGPoint(x: 0.666, y: 0.333),
                            CGPoint(x: 0.333, y: 0.666),
                            CGPoint(x: 0.666, y: 0.666)
                        ]
                        
                        let faceCenter = CGPoint(x: centerX, y: centerY)
                        let closestDist = powerPoints.map { p in
                            sqrt(pow(p.x - faceCenter.x, 2) + pow(p.y - faceCenter.y, 2))
                        }.min() ?? 1.0
                        
                        if closestDist < 0.08 {
                            suggestion = poseFeedback ?? "Perfect! Hold it."
                            score = 0.95
                            spatialAction = SpatialGuidance(action: "Hold", confidence: 1.0, targetObject: "Composition")
                        } else if closestDist < 0.15 {
                            suggestion = poseFeedback ?? "Almost there..."
                            score = 0.8
                        } else {
                            // Determine direction
                            if centerX < 0.33 {
                                suggestion = "Pan Right ->"
                                spatialAction = SpatialGuidance(action: "Pan Right", confidence: 0.7, targetObject: "Rule of Thirds")
                            } else if centerX > 0.66 {
                                suggestion = "<- Pan Left"
                                spatialAction = SpatialGuidance(action: "Pan Left", confidence: 0.7, targetObject: "Rule of Thirds")
                            } else {
                                if centerY < 0.33 {
                                    suggestion = "Tilt Up"
                                    spatialAction = SpatialGuidance(action: "Tilt Up", confidence: 0.7, targetObject: "Eye Level")
                                } else if centerY > 0.66 {
                                    suggestion = "Tilt Down"
                                    spatialAction = SpatialGuidance(action: "Tilt Down", confidence: 0.7, targetObject: "Eye Level")
                                } else {
                                    suggestion = poseFeedback ?? "Align with Grid"
                                }
                            }
                            score = 0.6
                        }
                    }
                }
                
                // Override with group text if multiple faces
                if result.faceCount > 1 {
                    description = "Group Shot (\(result.faceCount))"
                    if score < 0.5 {
                         suggestion = "Squeeze in closer!"
                    }
                }
            }
        }
        
        // Temporal Smoothing for Lighting
        let finalLighting: LightingQuality
        if detectedLighting == lastLightingQuality {
            lightingStabilityCount += 1
            finalLighting = detectedLighting
        } else {
            if lightingStabilityCount >= stabilityThreshold {
                lastLightingQuality = detectedLighting
                lightingStabilityCount = 0
                finalLighting = detectedLighting
            } else {
                lightingStabilityCount += 1
                finalLighting = lastLightingQuality
            }
        }
        
        // Creative Overrides
        let now = Date().timeIntervalSince1970
        if now - lastGuidanceChangeTime > 5.0 && score > 0.7 {
             if Double.random(in: 0...1) > 0.8 {
                 suggestion = [
                    "Try a lower angle for a heroic look.",
                    "Look for leading lines in the background.",
                    "Capture the negative space on the left.",
                    "Great light! Try a silhouette?"
                 ].randomElement()
             }
        }

        return SemanticFrameAnalysis(
            sceneDescription: description,
            lightingQuality: finalLighting,
            compositionScore: score,
            creativeSuggestion: suggestion,
            clutterDetected: false,
            spatialGuidance: spatialAction
        )
    }
}
