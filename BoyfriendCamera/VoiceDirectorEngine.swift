import AVFoundation
import Combine
import SwiftUI

enum VoiceDirectorState {
    case idle
    case speaking
    case cooldown
}

// DirectorInstructionPriority is defined in DirectorLogic.swift

@MainActor
class VoiceDirectorEngine: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = VoiceDirectorEngine()
    
    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpokenInstruction: String?
    private var lastSpokenTime: Date = .distantPast
    private var state: VoiceDirectorState = .idle
    
    // Config
    var isEnabled: Bool = false
    private let minInterval: TimeInterval = 3.5 // Don't nag too much
    private let repetitionInterval: TimeInterval = 8.0 // Don't repeat same thing quickly
    
    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }
    
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: [.mixWithOthers, .duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("VoiceDirectorEngine: Failed to set audio session category: \(error)")
        }
    }
    
    func speak(_ text: String, priority: DirectorInstructionPriority = .medium) {
        guard isEnabled, !text.isEmpty else { return }
        
        // Don't interrupt high priority with low priority
        if state == .speaking && priority < .high { return }
        
        let now = Date()
        
        // Check for repetition
        if text == lastSpokenInstruction {
            if now.timeIntervalSince(lastSpokenTime) < repetitionInterval { return }
        } else {
            // New instruction, check minimum interval
            if now.timeIntervalSince(lastSpokenTime) < minInterval && priority < .critical { return }
        }
        
        // Stop previous if critical
        if priority == .critical && state == .speaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.53 // Slightly slower for clarity
        utterance.pitchMultiplier = 1.05 // Slightly higher/enthusiastic
        utterance.volume = 1.0
        
        // Select a good voice (English)
        // Prefer "Samantha" (classic Siri-ish) or a high quality neural voice if available
        let voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.voice = voice
        
        synthesizer.speak(utterance)
        
        lastSpokenInstruction = text
        lastSpokenTime = now
        state = .speaking
    }
    
    // MARK: - Logic Bridge
    
    func processAnalysis(_ analysis: SemanticFrameAnalysis) {
        // Priority 1: Spatial Guidance (Critical)
        if let guidance = analysis.spatialGuidance {
            // "Move Back!", "Tilt Up!"
            // Only speak if confidence is high
            if guidance.confidence > 0.8 {
                let phrase = naturalizeAction(guidance.action)
                speak(phrase, priority: .high)
                return
            }
        }
        
        // Priority 2: Lighting (Warning)
        if analysis.lightingQuality == .poor {
            speak("It's too dark. Can we find better light?", priority: .medium)
            return
        } else if analysis.lightingQuality == .harsh {
            speak("Watch out for harsh shadows.", priority: .low)
            return
        }
        
        // Priority 3: Composition Score (Encouragement)
        if analysis.compositionScore > 0.85 {
            // Don't spam compliments, but say it occasionally
            if Double.random(in: 0...1) > 0.7 {
                let compliments = ["Perfect.", "Hold that.", "Beautiful shot.", "That's the one."]
                speak(compliments.randomElement()!, priority: .high) // High priority to "lock in" the moment
            }
            return
        }
        
        // Priority 4: Creative Suggestion (Low)
        if let suggestion = analysis.creativeSuggestion {
            // Only speak if it's actionable
            if !suggestion.contains("Scene") && !suggestion.contains("Object") {
                speak(suggestion, priority: .low)
            }
        }
    }
    
    private func naturalizeAction(_ action: String) -> String {
        switch action {
        case "Move Forward": return "Step closer."
        case "Move Back": return "Back up a little."
        case "Pan Right": return "Pan right."
        case "Pan Left": return "Pan left."
        case "Tilt Up": return "Tilt up."
        case "Tilt Down": return "Tilt down."
        case "Hold": return "Hold it right there."
        default: return action
        }
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.state = .cooldown
            // Small buffer after speaking before next one
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            if self.state == .cooldown {
                self.state = .idle
            }
        }
    }
}
