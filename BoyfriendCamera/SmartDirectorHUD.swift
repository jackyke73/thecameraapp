import SwiftUI

struct SmartDirectorHUD: View {
    @ObservedObject var cameraManager: CameraManager
    var compact: Bool = false
    var isInteractive: Bool = false
    
    var body: some View {
        if compact {
            // Compact Mode (for Top Bar)
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(.yellow)
                Text(cameraManager.semanticAnalysis.lightingQuality.rawValue)
                    .font(.caption.bold())
                    .foregroundColor(.white)
                
                // Score indicator
                Circle()
                    .trim(from: 0, to: cameraManager.semanticAnalysis.compositionScore)
                    .stroke(Color.green, lineWidth: 2)
                    .frame(width: 14, height: 14)
                    .rotationEffect(.degrees(-90))
                    .background(Circle().stroke(Color.white.opacity(0.2), lineWidth: 2))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
        } else {
            // Expanded Mode (Floating HUD)
            VStack(alignment: .leading, spacing: 12) {
                // Header: Scene & Score
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI DIRECTOR")
                            .font(.caption2.bold())
                            .foregroundColor(.gray)
                        Text(cameraManager.semanticAnalysis.sceneDescription)
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    Spacer()
                    
                    // Score Ring
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: cameraManager.semanticAnalysis.compositionScore)
                            .stroke(
                                LinearGradient(colors: [.red, .yellow, .green], startPoint: .top, endPoint: .bottom),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        
                        Text("\(Int(cameraManager.semanticAnalysis.compositionScore * 100))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 32, height: 32)
                }
                
                Divider().background(Color.white.opacity(0.2))
                
                // Lighting
                HStack {
                    Image(systemName: lightingIcon)
                        .foregroundColor(lightingColor)
                    Text(cameraManager.semanticAnalysis.lightingQuality.rawValue)
                        .font(.footnote.bold())
                        .foregroundColor(lightingColor)
                    Spacer()
                }
                
                // Cinematic Motion (New)
                if let score = cameraManager.cinematicScore {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: score.isStable ? "video.fill" : "video.slash.fill")
                                .font(.caption2)
                                .foregroundColor(score.isStable ? .green : .orange)
                            
                            Text(score.feedback.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(score.isStable ? .green : .orange)
                            
                            Spacer()
                            
                            Text("\(Int(score.value * 100))%")
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.white.opacity(0.6))
                        }
                        
                        // Stability Bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(height: 4)
                                
                                Capsule()
                                    .fill(score.isStable ? Color.green : Color.orange)
                                    .frame(width: geo.size.width * score.stability, height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(8)
                }
                
                // Spatial Guidance (New)
                if let guidance = cameraManager.semanticAnalysis.spatialGuidance {
                    HStack(spacing: 12) {
                        Image(systemName: arrowIcon(for: guidance.action))
                            .font(.title2)
                            .foregroundColor(.cyan)
                            .frame(width: 30)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(guidance.action.uppercased())
                                .font(.system(size: 12, weight: .black))
                                .foregroundColor(.cyan)
                            if let target = guidance.targetObject {
                                Text("Target: \(target)")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.cyan.opacity(0.15))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
                    )
                }
                
                // Creative Suggestion
                if let suggestion = cameraManager.semanticAnalysis.creativeSuggestion {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                            .padding(.top, 2)
                        Text(suggestion)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding(12)
            .frame(width: 220)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
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
        case .good, .studio: return .green
        case .goldenHour: return .orange
        case .poor: return .red
        case .harsh, .tooBright: return .yellow
        default: return .gray
        }
    }
}
