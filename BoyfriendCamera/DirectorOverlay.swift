import SwiftUI

struct DirectorOverlay: View {
    let instruction: DirectorInstruction
    
    @State private var animatedText: String = ""
    @State private var showIcon: Bool = false
    
    var body: some View {
        if instruction.text.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 12) {
                if !instruction.icon.isEmpty {
                    Image(systemName: instruction.icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(instruction.color)
                        .transition(.scale.combined(with: .opacity))
                }
                
                Text(instruction.text)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                Capsule()
                    .stroke(instruction.color.opacity(0.6), lineWidth: 2)
            )
            .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: instruction)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

struct DirectorOverlay_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            VStack(spacing: 20) {
                DirectorOverlay(instruction: DirectorInstruction(text: "Tilt Left", icon: "rotate.left.fill", color: .red, priority: .critical))
                DirectorOverlay(instruction: DirectorInstruction(text: "Perfect! Shoot!", icon: "star.fill", color: .green, priority: .high))
                DirectorOverlay(instruction: DirectorInstruction(text: "Make her laugh!", icon: "face.smiling", color: .blue, priority: .medium))
            }
        }
    }
}
