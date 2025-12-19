import SwiftUI

struct DirectorHUD: View {
    let advice: DirectorAdvice
    
    var body: some View {
        VStack {
            // The "Score" Bar
            HStack {
                Text("LIGHTING SCORE")
                    .font(.caption)
                    .bold()
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text("\(advice.lightingScore)/100")
                    .font(.caption)
                    .bold()
                    .foregroundColor(scoreColor)
            }
            
            // The Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle() // Background
                        .frame(width: geo.size.width, height: 6)
                        .opacity(0.3)
                        .foregroundColor(.gray)
                    
                    Rectangle() // Fill
                        .frame(width: geo.size.width * (Double(advice.lightingScore) / 100.0), height: 6)
                        .foregroundColor(scoreColor)
                }
                .cornerRadius(3)
            }
            .frame(height: 6)
            
            // The Advice Message
            HStack(spacing: 15) {
                Image(systemName: advice.icon)
                    .font(.title)
                    .foregroundColor(advice.isUrgent ? .red : .white)
                
                Text(advice.message)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Spacer()
            }
            .padding(.top, 10)
        }
        .padding()
        .background(.ultraThinMaterial) // Glass effect
        .cornerRadius(15)
        .padding(.horizontal)
        // If it's urgent, add a red border glow
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(advice.isUrgent ? Color.red : Color.clear, lineWidth: 2)
        )
    }
    
    // Helper to pick colors
    var scoreColor: Color {
        if advice.lightingScore < 40 { return .red }
        if advice.lightingScore < 70 { return .yellow }
        return .green
    }
}

#Preview {
    // Test data for the preview
    DirectorHUD(advice: DirectorAdvice(message: "Turn Around", icon: "arrow.uturn.right", isUrgent: true, lightingScore: 30))
        .background(Color.black)
}
