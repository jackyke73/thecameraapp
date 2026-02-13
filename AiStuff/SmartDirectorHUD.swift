import SwiftUI

struct SmartDirectorHUD: View {
    @ObservedObject var cameraManager: CameraManager
    /// A compact, single-line HUD intended for the top menu bar.
    var compact: Bool = false
    /// When true, the HUD will accept hit-testing (e.g., for drag gestures).
    var isInteractive: Bool = false

    var body: some View {
        Group {
            if compact {
                // Top Bar Compact Mode
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                        Text(cameraManager.isPersonDetected ? "YES" : "NO")
                            .font(.caption2.bold())
                    }
                    
                    if cameraManager.peopleCount > 0 {
                        Text("\(cameraManager.peopleCount)")
                            .font(.caption2.monospacedDigit())
                            .padding(4)
                            .background(Circle().fill(.white.opacity(0.2)))
                    }
                    
                    // Mini Score Indicator
                    if cameraManager.semanticAnalysis.compositionScore > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                            Text(String(format: "%.0f", cameraManager.semanticAnalysis.compositionScore * 100))
                                .font(.caption2.monospacedDigit())
                        }
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
            } else {
                // Full Floating HUD Mode
                if cameraManager.semanticAnalysis == .empty && !cameraManager.isPersonDetected {
                    // Minimal fallback if no data
                    VStack(alignment: .leading) {
                        Text("Waiting for scene...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                } else {
                    SemanticGuidanceView(analysis: cameraManager.semanticAnalysis)
                }
            }
        }
        .allowsHitTesting(isInteractive)
        .animation(.spring(), value: cameraManager.semanticAnalysis.compositionScore)
    }
}
