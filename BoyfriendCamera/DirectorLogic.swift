import Foundation
import CoreGraphics
import SwiftUI

enum DirectorInstructionPriority: Int, Comparable {
    case low = 0
    case medium = 1
    case high = 2
    case critical = 3
    
    static func < (lhs: DirectorInstructionPriority, rhs: DirectorInstructionPriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

struct DirectorInstruction: Equatable {
    let text: String
    let icon: String
    let color: Color
    let priority: DirectorInstructionPriority
    let haptic: DirectorHapticType // New haptic field
    
    static let none = DirectorInstruction(text: "", icon: "", color: .clear, priority: .low, haptic: .none)
}

struct DirectorLogic {
    
    // Configurable thresholds
    static let rollThreshold: Double = 0.05 // ~3 degrees
    static let alignmentThreshold: CGFloat = 0.05 // normalized distance
    static let pitchThreshold: Double = 0.15 // ~8-9 degrees tilt
    
    static func determineInstruction(
        isPersonDetected: Bool,
        peopleCount: Int,
        nosePoint: CGPoint?,
        faceBounds: CGRect?,
        targetPoint: CGPoint,
        deviceRoll: Double,
        devicePitch: Double, 
        isLevel: Bool,
        expressions: [String],
        lighting: LightingQuality = .good, 
        yoloCommand: String? = nil,
        depthGrid: [[Float]]? = nil // VLM2 Memory-Augmented Parameter
    ) -> DirectorInstruction {
        
        // 0. Sovereign AI Override (Highest Priority if meaningful)
        if let command = yoloCommand, !command.isEmpty, command != "Searching for Subject..." {
             return DirectorInstruction(text: command, icon: "eye.fill", color: .purple, priority: .critical, haptic: .correction)
        }
        
        // 1. Critical: Level the phone (Roll)
        if !isLevel {
            if deviceRoll > rollThreshold {
                return DirectorInstruction(text: "Tilt Left", icon: "rotate.left.fill", color: .red, priority: .critical, haptic: .correction)
            } else if deviceRoll < -rollThreshold {
                return DirectorInstruction(text: "Tilt Right", icon: "rotate.right.fill", color: .red, priority: .critical, haptic: .correction)
            }
        }
        
        // 2. Composition: Subject Presence
        if !isPersonDetected {
            return DirectorInstruction(text: "Find your Subject", icon: "person.fill.viewfinder", color: .yellow, priority: .high, haptic: .none)
        }
        
        // 2b. Lighting Check
        if lighting == .poor {
             return DirectorInstruction(text: "Too Dark - Find Light", icon: "sun.max.trianglebadge.exclamationmark", color: .yellow, priority: .high, haptic: .warning)
        } else if lighting == .tooBright {
             return DirectorInstruction(text: "Too Bright - Reduce Exposure", icon: "sun.min.fill", color: .yellow, priority: .high, haptic: .warning)
        }
        
        // 3. Perspective: Pitch Correction (Angle of Attack)
        if abs(devicePitch) > pitchThreshold {
             if devicePitch > pitchThreshold {
                 return DirectorInstruction(text: "Angle Forward", icon: "arrow.turn.right.down", color: .orange, priority: .high, haptic: .correction)
             } else {
                 return DirectorInstruction(text: "Angle Upward", icon: "arrow.turn.right.up", color: .orange, priority: .high, haptic: .correction)
             }
        }
        
        // 4. VLM² Contextual Depth Reasoning
        // Using the 3x3 depth grid from the VLM Memory Engine (DepthAnythingV2)
        if let grid = depthGrid {
            let centerDepth = grid[1][1]
            let topLeftDepth = grid[0][0]
            let topRightDepth = grid[0][2]
            
            // Logic: If center (subject) is too close to background (similar depth),
            // recommend moving for better bokeh/depth separation.
            let backgroundDepth = (topLeftDepth + topRightDepth) / 2.0
            if abs(centerDepth - backgroundDepth) < 0.1 && centerDepth < 0.8 {
                return DirectorInstruction(text: "Move for Depth Separation", icon: "camera.aperture", color: .blue, priority: .medium, haptic: .warning)
            }
        }
        
        // 5. Distance: Check Face Size
        if let face = faceBounds {
            let faceWidth = face.width
            if faceWidth < 0.15 {
                return DirectorInstruction(text: "Move Closer", icon: "arrow.up.left.and.arrow.down.right", color: .orange, priority: .medium, haptic: .correction)
            } else if faceWidth > 0.6 {
                return DirectorInstruction(text: "Back Up", icon: "arrow.down.right.and.arrow.up.left", color: .orange, priority: .medium, haptic: .correction)
            }
        }
        
        // 6. Framing: Center the subject (using nose point)
        if let nose = nosePoint {
            let mirroredNoseX = 1.0 - nose.x
            let dx = mirroredNoseX - targetPoint.x
            let dy = nose.y - targetPoint.y 
            let dist = sqrt(dx*dx + dy*dy)
            
            if dist > alignmentThreshold {
                if abs(dx) > abs(dy) {
                    if dx > 0 {
                        return DirectorInstruction(text: "Pan Right", icon: "arrow.right", color: .orange, priority: .medium, haptic: .correction)
                    } else {
                        return DirectorInstruction(text: "Pan Left", icon: "arrow.left", color: .orange, priority: .medium, haptic: .correction)
                    }
                } else {
                    if dy > 0 {
                         return DirectorInstruction(text: "Tilt Down", icon: "arrow.down", color: .orange, priority: .medium, haptic: .correction)
                    } else {
                         return DirectorInstruction(text: "Tilt Up", icon: "arrow.up", color: .orange, priority: .medium, haptic: .correction)
                    }
                }
            }
        }
        
        // 7. Expression / Vibe
        if let firstExpr = expressions.first {
            if firstExpr == "Neutral" || firstExpr == "Sad" || firstExpr == "Angry" {
                 return DirectorInstruction(text: "Make her laugh!", icon: "face.smiling", color: .blue, priority: .low, haptic: .warning)
            }
        }
        
        // 8. Success
        return DirectorInstruction(text: "Perfect! Shoot!", icon: "camera.shutter.button.fill", color: .green, priority: .high, haptic: .success)
    }
}
