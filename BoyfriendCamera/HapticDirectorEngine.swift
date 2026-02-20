import UIKit
import CoreHaptics

enum DirectorHapticType {
    case none
    case success      // Double tap (Heavy)
    case warning      // Single heavy thud
    case correction   // Light rapid ticks (Geiger counter style)
    case critical     // Heavy rapid pulsing
}

class HapticDirectorEngine {
    static let shared = HapticDirectorEngine()
    
    private let feedbackGenerator = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpactGenerator = UIImpactFeedbackGenerator(style: .heavy)
    
    // State to prevent spamming
    private var lastHapticTime: Date = .distantPast
    private var lastType: DirectorHapticType = .none
    
    // Minimum interval between haptics for continuous modes
    private let correctionInterval: TimeInterval = 0.15 
    private let criticalInterval: TimeInterval = 0.3
    
    private init() {
        feedbackGenerator.prepare()
        selectionGenerator.prepare()
        impactGenerator.prepare()
    }
    
    func play(_ type: DirectorHapticType) {
        let now = Date()
        
        switch type {
        case .none:
            break
            
        case .success:
            // Only play success if we haven't just played it (debounce 2s)
            // or if the previous state wasn't success.
            if lastType != .success || now.timeIntervalSince(lastHapticTime) > 2.0 {
                feedbackGenerator.notificationOccurred(.success)
                lastHapticTime = now
            }
            
        case .warning:
            if now.timeIntervalSince(lastHapticTime) > 1.0 {
                feedbackGenerator.notificationOccurred(.warning)
                lastHapticTime = now
            }
            
        case .correction:
            // Geiger counter effect
            if now.timeIntervalSince(lastHapticTime) > correctionInterval {
                selectionGenerator.selectionChanged()
                lastHapticTime = now
            }
            
        case .critical:
            if now.timeIntervalSince(lastHapticTime) > criticalInterval {
                heavyImpactGenerator.impactOccurred()
                lastHapticTime = now
            }
        }
        
        lastType = type
    }
}
