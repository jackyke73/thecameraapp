import Foundation
import CoreGraphics
import SwiftUI

/// Defines the color scheme for our "Director's HUD"
struct DirectorTheme {
    static let primary = Color.white
    static let secondary = Color.gray
    static let accent = Color.yellow
    static let background = Color.black.opacity(0.8)
    static let warning = Color.orange
    static let success = Color.green
    static let critical = Color.red
    
    static let fontMain = Font.system(.caption, design: .monospaced).bold()
    static let fontHuge = Font.system(size: 32, weight: .bold, design: .monospaced)
}

struct DirectorMetric: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let color: Color
}

/// A highly functional, high-end "Director's HUD" for real-time camera stats.
struct DirectorHUD: View {
    @ObservedObject var cameraManager: CameraManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Camera Status & Frame Stats
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DIRECTOR_ENGINE_v2.1")
                        .font(DirectorTheme.fontMain)
                        .foregroundColor(DirectorTheme.accent)
                    
                    HStack(spacing: 8) {
                        StatusIndicator(isActive: cameraManager.isAIFeaturesEnabled, label: "AI")
                        StatusIndicator(isActive: cameraManager.isLevel, label: "LVL")
                        StatusIndicator(isActive: cameraManager.isPersonDetected, label: "SUBJ")
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("FPS: 30") // Constant for now, or could measure
                        .font(DirectorTheme.fontMain)
                        .foregroundColor(DirectorTheme.secondary)
                    
                    Text("LUX: \(Int(cameraManager.semanticAnalysis.compositionScore * 100))%") // Mock lux
                        .font(DirectorTheme.fontMain)
                        .foregroundColor(DirectorTheme.secondary)
                }
            }
            
            Divider().background(Color.white.opacity(0.2))
            
            // Middle: Major Metrics
            HStack(spacing: 20) {
                MetricView(label: "ROLL", value: String(format: "%.1f°", cameraManager.deviceRoll * 180 / .pi), color: cameraManager.isLevel ? DirectorTheme.success : DirectorTheme.primary)
                MetricView(label: "PITCH", value: String(format: "%.1f°", cameraManager.devicePitch * 90), color: DirectorTheme.primary)
                MetricView(label: "LIGHT", value: cameraManager.semanticAnalysis.lightingQuality.rawValue.uppercased(), color: lightingColor)
            }
            
            // Bottom: Composition Score & Analysis
            VStack(alignment: .leading, spacing: 4) {
                Text("COMPOSITION_SCORE")
                    .font(DirectorTheme.fontMain)
                    .foregroundColor(DirectorTheme.secondary)
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 4)
                        
                        Rectangle()
                            .fill(scoreColor)
                            .frame(width: geo.size.width * CGFloat(cameraManager.semanticAnalysis.compositionScore), height: 4)
                    }
                }
                .frame(height: 4)
                
                Text(cameraManager.semanticAnalysis.sceneDescription.uppercased())
                    .font(DirectorTheme.fontMain)
                    .foregroundColor(DirectorTheme.primary)
                    .padding(.top, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DirectorTheme.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .frame(width: 300)
    }
    
    private var lightingColor: Color {
        switch cameraManager.semanticAnalysis.lightingQuality {
        case .good, .goldenHour, .studio: return DirectorTheme.success
        case .poor, .tooBright: return DirectorTheme.critical
        case .harsh: return DirectorTheme.warning
        default: return DirectorTheme.primary
        }
    }
    
    private var scoreColor: Color {
        let score = cameraManager.semanticAnalysis.compositionScore
        if score > 0.8 { return DirectorTheme.success }
        if score > 0.5 { return DirectorTheme.warning }
        return DirectorTheme.critical
    }
}

struct StatusIndicator: View {
    let isActive: Bool
    let label: String
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isActive ? DirectorTheme.success : DirectorTheme.secondary)
                .frame(width: 4, height: 4)
            Text(label)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(isActive ? DirectorTheme.primary : DirectorTheme.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.white.opacity(0.05))
        .cornerRadius(4)
    }
}

struct MetricView: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(DirectorTheme.secondary)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
    }
}
