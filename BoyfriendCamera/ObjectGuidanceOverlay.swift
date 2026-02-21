import SwiftUI
import Vision

struct ObjectGuidanceOverlay: View {
    let observations: [VNRecognizedObjectObservation]
    let frameSize: CGSize
    
    // Target configuration (could be dynamic later)
    let targetLabel: String = "person"
    
    var body: some View {
        ZStack {
            ForEach(observations, id: \.uuid) { observation in
                if observation.labels.first?.identifier == targetLabel {
                    // Draw Guidance System for the primary target
                    TargetHighlightView(
                        observation: observation,
                        frameSize: frameSize
                    )
                } else {
                    // Draw subtle boxes for other objects (context)
                    BoundingBoxView(
                        observation: observation,
                        color: .gray.opacity(0.3),
                        frameSize: frameSize
                    )
                }
            }
            
            // Central Reticle (Reference Point)
            Circle()
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                .frame(width: 20, height: 20)
            
            // Dynamic Arrow if target is off-center
            if let target = observations.first(where: { $0.labels.first?.identifier == targetLabel }) {
                DirectionalArrowView(
                    targetBox: target.boundingBox,
                    frameSize: frameSize
                )
            }
        }
    }
}

struct TargetHighlightView: View {
    let observation: VNRecognizedObjectObservation
    let frameSize: CGSize
    
    var body: some View {
        let rect = VNImageRectForNormalizedRect(observation.boundingBox, Int(frameSize.width), Int(frameSize.height))
        
        // Invert Y because Vision is bottom-left origin, SwiftUI is top-left
        let swiftUIRect = CGRect(
            x: rect.origin.x,
            y: frameSize.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        
        ZStack(alignment: .topLeading) {
            // Corner Bracket Style Box
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.yellow, lineWidth: 2)
                .frame(width: swiftUIRect.width, height: swiftUIRect.height)
            
            // Label
            Text(observation.labels.first?.identifier.uppercased() ?? "OBJECT")
                .font(.caption2.bold())
                .padding(4)
                .background(Color.yellow)
                .foregroundColor(.black)
                .cornerRadius(4)
                .offset(x: 0, y: -24)
        }
        .position(x: swiftUIRect.midX, y: swiftUIRect.midY)
    }
}

struct BoundingBoxView: View {
    let observation: VNRecognizedObjectObservation
    let color: Color
    let frameSize: CGSize
    
    var body: some View {
        let rect = VNImageRectForNormalizedRect(observation.boundingBox, Int(frameSize.width), Int(frameSize.height))
        let swiftUIRect = CGRect(
            x: rect.origin.x,
            y: frameSize.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        
        Rectangle()
            .stroke(color, lineWidth: 1)
            .frame(width: swiftUIRect.width, height: swiftUIRect.height)
            .position(x: swiftUIRect.midX, y: swiftUIRect.midY)
    }
}

struct DirectionalArrowView: View {
    let targetBox: CGRect // Normalized
    let frameSize: CGSize
    
    var body: some View {
        // Calculate center of screen vs center of target
        let screenCenter = CGPoint(x: 0.5, y: 0.5)
        let targetCenter = CGPoint(x: targetBox.midX, y: targetBox.midY)
        
        // Vector from Screen Center -> Target Center
        let dx = targetCenter.x - screenCenter.x
        let dy = targetCenter.y - screenCenter.y
        
        // If the target is sufficiently far from center, draw arrow
        let distance = sqrt(dx*dx + dy*dy)
        
        Group {
            if distance > 0.15 {
                let angle = atan2(dy, dx)
                
                // Position arrow at screen center, rotate to point to target
                Image(systemName: "arrow.right")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 30)
                    .foregroundColor(.yellow.opacity(0.8))
                    // Vision Y is inverted (Up is +), SwiftUI Y is down (+).
                    // atan2(dy, dx) gives angle where +Y is Up.
                    // SwiftUI rotation is clockwise. We need -angle.
                    .rotationEffect(Angle(radians: -angle))
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .position(x: frameSize.width / 2, y: frameSize.height / 2)
            }
        }
    }
}
