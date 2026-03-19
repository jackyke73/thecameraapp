import SwiftUI

/**
 * ⚡️ SmartDirectorHUD_v3.1 (2026-03-18)
 *
 * Integrated with the VLM² Memory Engine. 
 * Features a high-end "Memory Monitor" and enhanced spatial reasoning.
 */

struct SmartDirectorHUD: View {
    @ObservedObject var cameraManager: CameraManager
    var compact: Bool = false
    var isInteractive: Bool = false
    
    var body: some View {
        if compact {
            // Compact Mode (for Top Bar)
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(Theme.accentWarning)
                Text("VLM²")
                    .font(.caption.monospaced().bold())
                    .foregroundColor(Theme.textPrimary)
                
                // Score indicator
                Circle()
                    .trim(from: 0, to: cameraManager.semanticAnalysis.compositionScore)
                    .stroke(Theme.accentSuccess, lineWidth: 1.5)
                    .frame(width: 14, height: 14)
                    .rotationEffect(.degrees(-90))
                    .background(Circle().stroke(Theme.borderSubtle, lineWidth: 1.5))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassPanel()
        } else {
            // Expanded Mode (Floating HUD)
            VStack(alignment: .leading, spacing: 12) {
                // Header: Scene & Score
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("VLM² DIRECTOR")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(1)
                                .foregroundColor(Theme.accentInfo)
                            
                            // Memory Pulse
                            Circle()
                                .fill(Theme.accentInfo)
                                .frame(width: 4, height: 4)
                                .opacity(0.8)
                        }
                        
                        Text(cameraManager.semanticAnalysis.sceneDescription)
                            .font(.caption.bold())
                            .foregroundColor(Theme.textPrimary)
                            .lineLimit(1)
                    }
                    Spacer()
                    
                    // Score Ring
                    ZStack {
                        Circle()
                            .stroke(Theme.borderSubtle, lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: cameraManager.semanticAnalysis.compositionScore)
                            .stroke(
                                LinearGradient(colors: [Theme.accentDestructive, Theme.accentWarning, Theme.accentSuccess], startPoint: .top, endPoint: .bottom),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        
                        Text("\(Int(cameraManager.semanticAnalysis.compositionScore * 100))")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(Theme.textPrimary)
                    }
                    .frame(width: 32, height: 32)
                }
                
                Divider().background(Theme.borderSubtle)
                
                // VLM Memory Stats (New)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("EPISODIC_MEMORY")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(Theme.textSecondary)
                        HStack(spacing: 4) {
                            Capsule().fill(Theme.accentInfo).frame(width: 20, height: 4)
                            Capsule().fill(Theme.accentInfo).frame(width: 20, height: 4)
                            Capsule().fill(Theme.accentInfo.opacity(0.3)).frame(width: 20, height: 4)
                            Capsule().fill(Theme.accentInfo.opacity(0.3)).frame(width: 20, height: 4)
                        }
                    }
                    Spacer()
                    Text("128 TOKENS")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.bottom, 4)
                
                // Lighting
                HStack {
                    Image(systemName: lightingIcon)
                        .foregroundColor(lightingColor)
                        .font(.caption)
                    Text(cameraManager.semanticAnalysis.lightingQuality.rawValue)
                        .font(.footnote.monospaced().bold())
                        .foregroundColor(lightingColor)
                    Spacer()
                }
                
                // Cinematic Motion
                if let score = cameraManager.cinematicScore {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: score.isStable ? "video.fill" : "video.slash.fill")
                                .font(.caption2)
                                .foregroundColor(score.isStable ? Theme.accentSuccess : Theme.accentWarning)
                            
                            Text(score.feedback.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(score.isStable ? Theme.accentSuccess : Theme.accentWarning)
                            
                            Spacer()
                            
                            Text("\(Int(score.value * 100))%")
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(Theme.textSecondary)
                        }
                        
                        // Stability Bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Theme.borderSubtle)
                                    .frame(height: 3)
                                
                                Capsule()
                                    .fill(score.isStable ? Theme.accentSuccess : Theme.accentWarning)
                                    .frame(width: geo.size.width * score.stability, height: 3)
                            }
                        }
                        .frame(height: 3)
                    }
                    .padding(10)
                    .background(Theme.bgTertiary.opacity(0.6))
                    .cornerRadius(8)
                }
                
                // Spatial Guidance
                if let guidance = cameraManager.semanticAnalysis.spatialGuidance {
                    HStack(spacing: 12) {
                        Image(systemName: arrowIcon(for: guidance.action))
                            .font(.title3)
                            .foregroundColor(Theme.accentInfo)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(guidance.action.uppercased())
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(Theme.accentInfo)
                            if let target = guidance.targetObject {
                                Text("Target: \(target)")
                                    .font(.caption2)
                                    .foregroundColor(Theme.textSecondary)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accentInfo.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Theme.accentInfo.opacity(0.25), lineWidth: 0.5)
                    )
                }
                
                // Creative Suggestion
                if let suggestion = cameraManager.semanticAnalysis.creativeSuggestion {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(Theme.accentWarning)
                            .font(.caption)
                            .padding(.top, 2)
                        Text(suggestion)
                            .font(.caption)
                            .foregroundColor(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .background(Theme.accentWarning.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Theme.accentWarning.opacity(0.2), lineWidth: 0.5)
                    )
                }
            }
            .padding(16)
            .frame(width: 240)
            .glassPanel()
        }
    }
    
    private func arrowIcon(for action: String) -> String {
        switch action {
        case "Move Forward": return "arrow.up"
        case "Move Back": return "arrow.down"
        case "Pan Right": return "arrow.right"
        case "Pan Left": return "arrow.left"
        case "Tilt Up": return "arrow.up.circle"
        case "Tilt Down": return "arrow.down.circle"
        case "Hold": return "checkmark.circle.fill"
        case "Step Back": return "arrow.down.to.line"
        case "Move for Depth Separation": return "camera.aperture"
        default: return "scope"
        }
    }
    
    private var lightingIcon: String {
        switch cameraManager.semanticAnalysis.lightingQuality {
        case .good, .studio, .goldenHour: return "sun.max.fill"
        case .poor: return "moon.fill"
        case .harsh, .tooBright: return "sun.haze.fill"
        default: return "camera.metering.unknown"
        }
    }
    
    private var lightingColor: Color {
        switch cameraManager.semanticAnalysis.lightingQuality {
        case .good, .studio: return Theme.accentSuccess
        case .goldenHour: return Theme.accentWarning
        case .poor: return Theme.accentDestructive
        case .harsh, .tooBright: return Theme.accentWarning
        default: return Theme.textSecondary
        }
    }
}
