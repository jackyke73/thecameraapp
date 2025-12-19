import Foundation
import CoreLocation

// This struct defines the "Orders" the app gives the human
struct DirectorAdvice {
    let message: String
    let icon: String // SF Symbol name
    let isUrgent: Bool
    let lightingScore: Int // 0 to 100
}

class PhotoDirector {
    
    // The Master Function: Takes all sensor data -> Returns specific advice
    static func evaluate(
        sunPosition: SunPosition,
        deviceHeading: CLHeading?,
        isPersonDetected: Bool
    ) -> DirectorAdvice {
        
        // 1. If we don't know where we are facing, we can't help.
        guard let heading = deviceHeading else {
            return DirectorAdvice(message: "Calibrating Compass...", icon: "location.circle", isUrgent: false, lightingScore: 0)
        }
        
        // 2. Calculate the "Relative Sun Angle"
        // This math tells us: Is the sun BEHIND the camera (Good) or IN FRONT (Bad)?
        // We want the sun to be roughly 180 degrees opposite to where we are looking.
        
        let lookDirection = heading.trueHeading // Where camera is pointing (0-360)
        let sunDirection = sunPosition.azimuth // Where sun is (0-360)
        
        // Calculate the difference (Absolute delta)
        var diff = abs(lookDirection - sunDirection)
        if diff > 180 { diff = 360 - diff } // Handle the wrap-around (e.g. 350 vs 10 degrees)
        
        // 3. Evaluate Lighting Quality (The "Score")
        
        // SCENARIO A: Shooting into the sun (Silhouette Risk)
        // If the sun is within 45 degrees of where we are looking...
        if diff < 45 {
            return DirectorAdvice(
                message: "STOP! Backlit. Turn around.",
                icon: "exclamationmark.triangle.fill",
                isUrgent: true,
                lightingScore: 20
            )
        }
        
        // SCENARIO B: Harsh Noon Light (Raccoon Eyes Risk)
        // If the sun is higher than 60 degrees in the sky...
        if sunPosition.elevation > 60 {
            return DirectorAdvice(
                message: "Sun too high. Find shade.",
                icon: "cloud.sun.fill",
                isUrgent: true,
                lightingScore: 40
            )
        }
        
        // SCENARIO C: Golden Hour (Perfect)
        if sunPosition.isGoldenHour {
            return DirectorAdvice(
                message: "GOLDEN HOUR! Shoot now!",
                icon: "sparkles",
                isUrgent: false,
                lightingScore: 100
            )
        }
        
        // SCENARIO D: Side Lighting (Dramatic)
        if diff >= 45 && diff < 135 {
            return DirectorAdvice(
                message: "Side lighting. Good for drama.",
                icon: "sun.max",
                isUrgent: false,
                lightingScore: 80
            )
        }
        
        // SCENARIO E: Front Lighting (Safe, Boring)
        // This is when the sun is directly behind the photographer (diff > 135)
        return DirectorAdvice(
            message: "Great lighting. Take the shot.",
            icon: "camera.fill",
            isUrgent: false,
            lightingScore: 90
        )
    }
}
