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
    
    static let empty = SemanticFrameAnalysis(
        sceneDescription: "Analyzing scene...",
        lightingQuality: .unknown,
        compositionScore: 0.0,
        creativeSuggestion: nil,
        clutterDetected: false
    )
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
actor SemanticDirectorEngine {
    
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
        
        if let result = visionResult {
            if result.faceCount == 0 {
                description = "Landscape / Object"
                suggestion = "Find a subject!"
                score = 0.3
            } else if result.faceCount == 1 {
                description = "Portrait"
                if let face = result.mainFaceBounds {
                    let faceArea = face.width * face.height
                    // Face coordinates are normalized (0.0 to 1.0)
                    
                    if faceArea < 0.05 {
                        suggestion = "Move closer!"
                        score = 0.4
                    } else if faceArea > 0.6 {
                        suggestion = "Back up a bit!"
                        score = 0.4
                    } else {
                        // Check centering (Rule of Thirds-ish)
                        let centerX = face.midX
                        let centerY = face.midY
                        
                        // Vision coordinates: (0,0) is Bottom-Left.
                        // Power Points X: 0.33, 0.66
                        // Power Points Y: 0.33, 0.66
                        
                        let powerPoints = [
                            CGPoint(x: 0.333, y: 0.333),
                            CGPoint(x: 0.666, y: 0.333),
                            CGPoint(x: 0.333, y: 0.666),
                            CGPoint(x: 0.666, y: 0.666)
                        ]
                        
                        // Find distance to closest power point
                        let faceCenter = CGPoint(x: centerX, y: centerY)
                        let closestDist = powerPoints.map { p in
                            sqrt(pow(p.x - faceCenter.x, 2) + pow(p.y - faceCenter.y, 2))
                        }.min() ?? 1.0
                        
                        // Distance threshold (in normalized coords)
                        // 0.05 is roughly 5% of screen width
                        if closestDist < 0.08 {
                            suggestion = "Perfect! Hold it."
                            score = 0.95
                        } else if closestDist < 0.15 {
                            suggestion = "Almost there..."
                            score = 0.8
                        } else {
                            // Determine direction
                            if centerX < 0.33 {
                                suggestion = "Pan Right ->"
                            } else if centerX > 0.66 {
                                suggestion = "<- Pan Left"
                            } else {
                                // Center X is okay, maybe check Y?
                                if centerY < 0.33 {
                                    suggestion = "Tilt Up"
                                } else if centerY > 0.66 {
                                    suggestion = "Tilt Down"
                                } else {
                                    suggestion = "Align with Grid"
                                }
                            }
                            score = 0.6
                        }
                    }
                }
            } else {
                description = "Group Shot (\(result.faceCount))"
                suggestion = "Squeeze in closer!"
                score = 0.7
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

        return SemanticFrameAnalysis(
            sceneDescription: description,
            lightingQuality: finalLighting,
            compositionScore: score,
            creativeSuggestion: suggestion,
            clutterDetected: false // TODO: Use segmentation mask ratio
        )
    }
}
