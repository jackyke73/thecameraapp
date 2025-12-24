import SwiftUI

struct AIDebugHUD: View {
    @ObservedObject var cameraManager: CameraManager
    /// A compact, single-line HUD intended for the top menu bar.
    var compact: Bool = false
    /// When true, the HUD will accept hit-testing (e.g., for drag gestures).
    var isInteractive: Bool = false

    // Expression pop-out bubble state (menu-bar HUD only).
    @State private var lastExprKey: String = ""
    @State private var bubbleTexts: [String] = []
    @State private var showBubble: Bool = false
    @State private var exprDebounceWork: DispatchWorkItem?

    var body: some View {
        Group {
            if compact {
                HStack(spacing: 10) {
                    Text(cameraManager.isPersonDetected ? "Person: Yes" : "Person: No")
                        .font(.caption)

                    Text("Count: \(cameraManager.peopleCount)")
                        .font(.caption)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Person:")
                        Text(cameraManager.isPersonDetected ? "Yes" : "No")
                            .fontWeight(.bold)
                    }
                    .font(.caption)

                    HStack {
                        Text("Count:")
                        Text("\(cameraManager.peopleCount)")
                            .fontWeight(.bold)
                    }
                    .font(.caption)

                    if !cameraManager.expressions.isEmpty {
                        Text("Expr: " + cameraManager.expressions.joined(separator: ", "))
                            .font(.caption)
                    }
                }
            }
        }
        .foregroundColor(.white)
        .padding(10)
        // ✅ Liquid Glass
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 4)
        // ✅ Default behavior: do not block taps / sheets.
        .allowsHitTesting(isInteractive)
        // Expression pop-out effect anchored to the menu-bar HUD.
        .overlay(alignment: .bottom) {
            if compact && showBubble && !bubbleTexts.isEmpty {
                VStack(spacing: 6) {
                    ForEach(bubbleTexts, id: \.self) { t in
                        _ExprBubble(text: t)
                    }
                }
                .offset(y: 18)
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .onChange(of: cameraManager.expressions) { _, newValue in
            guard compact else { return }

            // Cancel any pending update to slow down rapid expression churn.
            exprDebounceWork?.cancel()

            // Reset when expressions disappear.
            if newValue.isEmpty {
                lastExprKey = ""
                withAnimation(.easeOut(duration: 0.18)) {
                    showBubble = false
                }
                bubbleTexts = []
                return
            }

            let incomingKey = newValue.joined(separator: "|")
            guard incomingKey != lastExprKey else { return }

            let work = DispatchWorkItem {
                // Use the latest value at fire time.
                let current = cameraManager.expressions
                guard !current.isEmpty else { return }

                let key = current.joined(separator: "|")
                guard key != lastExprKey else { return }

                let texts = Array(current.prefix(3)).filter { !$0.isEmpty }
                guard !texts.isEmpty else { return }

                // Fade away the old bubble(s) before showing the new expression(s).
                if showBubble {
                    withAnimation(.easeOut(duration: 0.18)) {
                        showBubble = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        bubbleTexts = texts
                        lastExprKey = key
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.80)) {
                            showBubble = true
                        }
                    }
                } else {
                    bubbleTexts = texts
                    lastExprKey = key
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.80)) {
                        showBubble = true
                    }
                }
            }

            exprDebounceWork = work
            // Debounce to slow down the update frequency.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: work)
        }
    }
}

private struct _ExprBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundColor(.white)
            .background(
                .ultraThinMaterial,
                in: Capsule(style: .continuous)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.22), radius: 8, x: 0, y: 4)
    }
}
