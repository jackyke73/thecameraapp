import Foundation
import CoreVideo

// The standard output format for any Director Engine (Heuristic, VLM, or Hybrid).
// This ensures that the UI layer doesn't need to know *which* brain is running the show.
protocol DirectorEngineProtocol: Actor {
    
    // Primary inference method.
    // Takes a raw pixel buffer and returns a structured semantic analysis.
    // Must be thread-safe and ideally non-blocking (async).
    func analyze(pixelBuffer: CVPixelBuffer) async throws -> SemanticFrameAnalysis
    
    // Optional: Reset state (e.g. for temporal smoothing or VLM context window)
    func resetState() async
}
