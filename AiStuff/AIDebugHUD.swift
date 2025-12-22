import SwiftUI

struct AIDebugHUD: View {
    @ObservedObject var cameraManager: CameraManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(cameraManager.isAIFeaturesEnabled ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

                Text("AI \(cameraManager.isAIFeaturesEnabled ? "ON" : "OFF")")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }

            Text("Detected: \(cameraManager.isPersonDetected ? "YES" : "NO")")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))

            Text("People: \(cameraManager.peopleCount)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))

            if cameraManager.expressions.isEmpty {
                Text("Expr: —")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Expr:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))

                    ForEach(Array(cameraManager.expressions.prefix(3).enumerated()), id: \.offset) { idx, expr in
                        Text("#\(idx + 1): \(expr)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                    }

                    if cameraManager.expressions.count > 3 {
                        Text("…+\(cameraManager.expressions.count - 3)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.75))
                    }
                }
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}
