import AVFoundation
import Combine
import SwiftUI

enum VoiceDirectorState {
    case idle
    case speaking
    case cooldown
}

class VoiceDirectorEngine: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = VoiceDirectorEngine()
    
    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpokenInstruction: String?
    private var lastSpokenTime: Date = .distantPast
    private var state: VoiceDirectorState = .idle
    
    // Configuration
    var isEnabled: Bool = true
    private let minInterval: TimeInterval = 2.5 // Minimum time between instructions
    private let repetitionInterval: TimeInterval = 5.0 // Time before repeating the same instruction
    
    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }
    
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: [.mixWithOthers])
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
        utterance.rate = 0.55
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        // Select a good voice (English)
        if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }
        
        synthesizer.speak(utterance)
        
        lastSpokenInstruction = text
        lastSpokenTime = now
        state = .speaking
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        state = .cooldown
        // Small buffer after speaking before next one
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if self.state == .cooldown {
                self.state = .idle
            }
        }
    }
}
