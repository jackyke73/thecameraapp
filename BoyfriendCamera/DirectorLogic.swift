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
    
    static let none = DirectorInstruction(text: "", icon: "", color: .clear, priority: .low)
}

struct DirectorLogic {
    
    // Configurable thresholds
    static let rollThreshold: Double = 0.05 // ~3 degrees
    static let alignmentThreshold: CGFloat = 0.05 // normalized distance
    
    static func determineInstruction(
        isPersonDetected: Bool,
        peopleCount: Int,
        nosePoint: CGPoint?,
        targetPoint: CGPoint,
        deviceRoll: Double,
        isLevel: Bool,
        expressions: [String]
    ) -> DirectorInstruction {
        
        // 1. Critical: Level the phone (unless we are intentionally doing a dutch angle, but for BF camera, level is usually king)
        // We use the 'isLevel' boolean from CameraManager which already has hysteresis/smoothing, 
        // but we can also double check the raw roll if we want strictly "Level it" vs "Perfect".
        if !isLevel {
            // Check direction of tilt to give specific advice
            if deviceRoll > rollThreshold {
                return DirectorInstruction(text: "Tilt Left", icon: "rotate.left.fill", color: .red, priority: .critical)
            } else if deviceRoll < -rollThreshold {
                return DirectorInstruction(text: "Tilt Right", icon: "rotate.right.fill", color: .red, priority: .critical)
            }
        }
        
        // 2. Composition: Subject Presence
        if !isPersonDetected {
            return DirectorInstruction(text: "Find your Subject", icon: "person.fill.viewfinder", color: .yellow, priority: .high)
        }
        
        // 3. Framing: Center the subject (using nose point)
        if let nose = nosePoint {
            let dx = nose.x - targetPoint.x
            let dy = nose.y - targetPoint.y // Remember Y might be inverted depending on view, but magnitude is safe
            let dist = sqrt(dx*dx + dy*dy)
            
            if dist > alignmentThreshold {
                // Determine direction
                // Assuming nosePoint and targetPoint are in the same 0..1 coordinate space (Preview space)
                // If nose.x > target.x, nose is to the right, so we need to move camera Right (to bring subject Left? No, pan Right to bring subject Left in frame)
                // Actually, if subject is to the Right of center, we need to Turn Right to center them.
                
                if abs(dx) > abs(dy) {
                    // Horizontal correction
                    if dx > 0 {
                        return DirectorInstruction(text: "Pan Right", icon: "arrow.right", color: .orange, priority: .medium)
                    } else {
                        return DirectorInstruction(text: "Pan Left", icon: "arrow.left", color: .orange, priority: .medium)
                    }
                } else {
                    // Vertical correction
                    if dy > 0 {
                         return DirectorInstruction(text: "Tilt Down", icon: "arrow.down", color: .orange, priority: .medium)
                    } else {
                         return DirectorInstruction(text: "Tilt Up", icon: "arrow.up", color: .orange, priority: .medium)
                    }
                }
            }
        }
        
        // 4. Expression / Vibe
        if let firstExpr = expressions.first {
            if firstExpr == "Neutral" || firstExpr == "Sad" || firstExpr == "Angry" {
                 return DirectorInstruction(text: "Make her laugh!", icon: "face.smiling", color: .blue, priority: .low)
            }
        }
        
        // 5. Success
        return DirectorInstruction(text: "Perfect! Shoot!", icon: "camera.shutter.button.fill", color: .green, priority: .high)
    }
}
