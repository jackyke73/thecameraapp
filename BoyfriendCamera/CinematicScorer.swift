import Foundation
import CoreMotion
import SwiftUI

/// Analyzes device motion to determine if the camera movement is "cinematic".
/// Cinematic movement is characterized by smooth, intentional pans/tilts (low jitter)
/// and moderate velocity (not too fast, not dead still).
struct CinematicScore {
    let value: Double // 0.0 to 1.0 (1.0 is perfect cinematic movement)
    let stability: Double // 0.0 to 1.0 (1.0 is perfectly stable/smooth)
    let velocityScore: Double // 0.0 to 1.0 (1.0 is ideal speed)
    let feedback: String // User-facing feedback
    let isStable: Bool
}

class CinematicScorer {
    
    // Config
    private let idealRotationRate: Double = 0.15 // rad/s (approx 8-9 deg/s) - slow pan
    private let maxRotationRate: Double = 1.2 // rad/s - too fast
    private let jitterThreshold: Double = 0.05 // High frequency noise threshold
    
    // State
    private var rotationHistory: [Double] = []
    private let historySize = 10 // approx 1 second at 10Hz
    
    // Smoothing
    private var smoothedVelocity: Double = 0.0
    private var smoothedJitter: Double = 0.0
    
    func update(motion: CMDeviceMotion) -> CinematicScore {
        // 1. Calculate magnitude of rotation rate (angular velocity)
        // x, y, z are in rad/s
        let r = motion.rotationRate
        let magnitude = sqrt(r.x*r.x + r.y*r.y + r.z*r.z)
        
        // 2. Update smoothed velocity (EWMA)
        // Alpha of 0.2 means we trust new data 20%, old data 80% (smoothing)
        smoothedVelocity = (0.2 * magnitude) + (0.8 * smoothedVelocity)
        
        // 3. Calculate Jitter (High frequency noise)
        // Jitter is the deviation of the current instantaneous rate from the smoothed rate
        let instantaneousJitter = abs(magnitude - smoothedVelocity)
        smoothedJitter = (0.1 * instantaneousJitter) + (0.9 * smoothedJitter)
        
        // 4. Score Calculation
        
        // A. Velocity Score: Bell curve around idealRotationRate
        // If velocity is 0, score is okay (static shot), but moving slightly is "cinematic".
        // Actually, for "Cinematic", steady is good, slow pan is good. Fast is bad.
        
        let velocityPenalty: Double
        if smoothedVelocity > maxRotationRate {
            velocityPenalty = 1.0
        } else {
            // Quadratic penalty for speed
            velocityPenalty = pow(smoothedVelocity / maxRotationRate, 2)
        }
        let velocityScore = 1.0 - velocityPenalty
        
        // B. Stability Score: Penalize jitter
        // Jitter > 0.1 is bad.
        let stabilityRaw = 1.0 - (smoothedJitter / 0.1) // 0.1 rad/s deviation is high
        let stabilityScore = max(0.0, min(1.0, stabilityRaw))
        
        // Combined Score
        // Weighted average: Stability is king (70%), Velocity is flavor (30%)
        let totalScore = (stabilityScore * 0.7) + (velocityScore * 0.3)
        
        // Feedback
        var feedback = ""
        if stabilityScore < 0.6 {
            feedback = "Stabilize Hand"
        } else if velocityScore < 0.4 {
            feedback = "Slow Down"
        } else if smoothedVelocity > 0.05 {
            feedback = "Cinematic Pan"
        } else {
            feedback = "Steady"
        }
        
        return CinematicScore(
            value: totalScore,
            stability: stabilityScore,
            velocityScore: velocityScore,
            feedback: feedback,
            isStable: stabilityScore > 0.8
        )
    }
    
    func reset() {
        smoothedVelocity = 0.0
        smoothedJitter = 0.0
        rotationHistory.removeAll()
    }
}
