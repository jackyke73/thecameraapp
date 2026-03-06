import SwiftUI

struct SettingsOverlay: View {
    @Binding var isPresented: Bool
    @ObservedObject var cameraManager: CameraManager
    
    // Bindings to ContentView state
    @Binding var isGridEnabled: Bool
    @Binding var isLevelerEnabled: Bool
    @Binding var isTimerEnabled: Bool
    @Binding var isHapticEnabled: Bool
    @Binding var isVoiceEnabled: Bool
    @Binding var isLandmarkLockEnabled: Bool
    @Binding var showDirectorMode: Bool
    @Binding var showFloatingAIHUD: Bool
    @Binding var currentAspectRatio: AspectRatio
    
    // Internal state for sliders
    @State private var exposureValue: Float = 0.0
    
    var body: some View {
        ZStack {
            // Dim background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { withAnimation { isPresented = false } }
            
            VStack(spacing: 0) {
                Spacer()
                
                VStack(spacing: 20) {
                    // Header
                    HStack {
                        Text("SETTINGS")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(Theme.textSecondary)
                        Spacer()
                        Button {
                            withAnimation { isPresented = false }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Theme.textPrimary)
                                .padding(8)
                                .background(Theme.bgTertiary)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)
                    
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 24) {
                            
                            // Section: Tools
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader("ASSISTIVE TOOLS")
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 12) {
                                    ToggleChip(title: "Grid", icon: "grid", isOn: $isGridEnabled)
                                    ToggleChip(title: "Level", icon: "gyroscope", isOn: $isLevelerEnabled)
                                    ToggleChip(title: "Haptic", icon: "waveform.path.ecg", isOn: $isHapticEnabled)
                                    ToggleChip(title: "Voice", icon: "waveform.circle", isOn: $isVoiceEnabled)
                                    ToggleChip(title: "HUD", icon: "rectangle.and.hand.point.up.left", isOn: $showFloatingAIHUD)
                                    ToggleChip(title: "Lock", icon: "scope", isOn: $isLandmarkLockEnabled)
                                }
                            }
                            
                            // Section: Camera
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader("CAMERA")
                                HStack {
                                    Text("Aspect Ratio")
                                        .font(.caption)
                                        .foregroundColor(Theme.textPrimary)
                                    Spacer()
                                    Picker("Aspect Ratio", selection: $currentAspectRatio) {
                                        ForEach(AspectRatio.allCases, id: \.self) { ratio in
                                            Text(ratio.rawValue).tag(ratio)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(width: 180)
                                }
                                
                                HStack {
                                    Text("Timer (3s)")
                                        .font(.caption)
                                        .foregroundColor(Theme.textPrimary)
                                    Spacer()
                                    Toggle("", isOn: $isTimerEnabled)
                                        .labelsHidden()
                                        .tint(Theme.accentWarning)
                                }
                                
                                HStack {
                                    Text("Smart Shutter")
                                        .font(.caption)
                                        .foregroundColor(Theme.textPrimary)
                                    Spacer()
                                    Toggle("", isOn: $cameraManager.isSmartShutterEnabled)
                                        .labelsHidden()
                                        .tint(Theme.accentSuccess)
                                }
                            }
                            
                            // Section: Manual
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader("MANUAL CONTROL")
                                
                                ControlSlider(icon: "sun.max.fill", value: $exposureValue, range: -2...2) {
                                    cameraManager.setExposure(ev: exposureValue)
                                }
                            }
                            
                            // Section: Advanced
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader("ADVANCED")
                                Button {
                                    showDirectorMode = true
                                    isPresented = false
                                } label: {
                                    HStack {
                                        Image(systemName: "cube.transparent")
                                        Text("Enter 3D Splat Mode")
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                    }
                                    .font(.caption.bold())
                                    .foregroundColor(Theme.textPrimary)
                                    .padding()
                                    .background(Theme.bgTertiary)
                                    .cornerRadius(8)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 40)
                    }
                }
                .background(Theme.bgSecondary.ignoresSafeArea())
                .cornerRadius(24, corners: [.topLeft, .topRight])
                .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: -5)
            }
        }
        .zIndex(100)
    }
}

// MARK: - Components

struct SectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(Theme.textTertiary)
            .padding(.leading, 4)
    }
}

struct ToggleChip: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    
    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3)) { isOn.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.caption2.bold())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundColor(isOn ? Theme.bgPrimary : Theme.textPrimary)
            .background(isOn ? Theme.accent : Theme.bgTertiary)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isOn ? Theme.accent : Theme.borderSubtle, lineWidth: 1)
            )
        }
    }
}

struct ControlSlider: View {
    let icon: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let onChange: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(Theme.textSecondary)
                .font(.caption)
                .frame(width: 20)
            
            Slider(value: $value, in: range, onEditingChanged: { editing in
                if !editing { onChange() }
            })
            .tint(Theme.accent)
            
            Text(String(format: "%.1f", value))
                .font(.caption.monospacedDigit())
                .foregroundColor(Theme.textPrimary)
                .frame(width: 30)
        }
        .padding(12)
        .background(Theme.bgTertiary)
        .cornerRadius(12)
    }
}

// FlowLayout removed

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
