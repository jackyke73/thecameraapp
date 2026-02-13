import SwiftUI

struct SemanticGuidanceView: View {
    let analysis: SemanticFrameAnalysis
    
    @State private var animatePulse: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: AI Status
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.yellow)
                    .scaleEffect(animatePulse ? 1.1 : 1.0)
                    .animation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: animatePulse)
                
                Text("AI DIRECTOR")
                    .font(.caption2)
                    .fontWeight(.heavy)
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer()
                
                Text(String(format: "SCORE: %.0f", analysis.compositionScore * 100))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(scoreColor(analysis.compositionScore))
            }
            
            // Progress Bar for Score
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 4)
                    
                    Rectangle()
                        .fill(scoreColor(analysis.compositionScore))
                        .frame(width: geo.size.width * analysis.compositionScore, height: 4)
                        .animation(.spring(), value: analysis.compositionScore)
                }
            }
            .frame(height: 4)
            .cornerRadius(2)
            
            // Context & Suggestion
            if let suggestion = analysis.creativeSuggestion {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.top, 2)
                    
                    Text(suggestion)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            
            // Lighting Badge
            HStack {
                Text(analysis.lightingQuality.rawValue.uppercased())
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(lightingColor(analysis.lightingQuality).opacity(0.2))
                    .foregroundColor(lightingColor(analysis.lightingQuality))
                    .cornerRadius(4)
                
                if analysis.clutterDetected {
                    Text("CLUTTER")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.2))
                        .foregroundColor(.red)
                        .cornerRadius(4)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .onAppear {
            animatePulse = true
        }
    }
    
    private func scoreColor(_ score: Double) -> Color {
        if score > 0.8 { return .green }
        if score > 0.5 { return .yellow }
        return .red
    }
    
    private func lightingColor(_ quality: LightingQuality) -> Color {
        switch quality {
        case .goldenHour: return .orange
        case .good, .studio: return .green
        case .poor, .harsh: return .red
        case .unknown: return .gray
        }
    }
}

struct SemanticGuidanceView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            SemanticGuidanceView(analysis: SemanticFrameAnalysis(
                sceneDescription: "Test scene",
                lightingQuality: .goldenHour,
                compositionScore: 0.85,
                creativeSuggestion: "Tilt slightly up to capture the sky.",
                clutterDetected: false
            ))
            .padding()
        }
    }
}
