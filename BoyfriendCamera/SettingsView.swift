import SwiftUI

struct SettingsView: View {
    @ObservedObject var cameraManager: CameraManager
    
    // Bindings to ContentView state
    @Binding var isVoiceEnabled: Bool
    @Binding var isHapticEnabled: Bool
    @Binding var showDirectorMode: Bool
    @Binding var isGridEnabled: Bool
    @Binding var isLevelerEnabled: Bool
    @Binding var isTimerEnabled: Bool
    @Binding var isLandmarkLockEnabled: Bool
    @Binding var showFloatingAIHUD: Bool
    @Binding var currentAspectRatio: AspectRatio
    
    // Dismiss action
    var dismiss: () -> Void
    
    // Internal state for new settings
    @AppStorage("voxelDebugViz") private var isVoxelDebugEnabled = false
    @AppStorage("splatExportFormat") private var splatExportFormat = "PLY" // "PLY" or "SPZ"
    
    var body: some View {
        ZStack {
            // Dark obsidian background
            Color(hex: "050505").ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Settings")
                        .font(.system(size: 20, weight: .semibold, design: .default))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(8)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                }
                .padding()
                .background(Color.black.opacity(0.5))
                
                ScrollView {
                    VStack(spacing: 24) {
                        
                        // NEW PREVIEW HUD SECTION
                        if cameraManager.isAIFeaturesEnabled {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("HUD PREVIEW")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.gray)
                                    .tracking(1)
                                
                                DirectorHUD(cameraManager: cameraManager)
                                    .scaleEffect(0.9)
                                    .frame(maxWidth: .infinity)
                            }
                        }

                        // Section: Director Mode
                        SettingsSection(title: "Director Mode") {
                            SettingsToggle(
                                icon: "waveform.circle",
                                title: "Voice Guidance",
                                subtitle: "AI speaks framing instructions",
                                isOn: $isVoiceEnabled
                            )
                            
                            SettingsToggle(
                                icon: "waveform.path.ecg",
                                title: "Haptic Feedback",
                                subtitle: "Vibrate on alignment",
                                isOn: $isHapticEnabled
                            )
                            
                            SettingsToggle(
                                icon: "sparkles",
                                title: "AI Features",
                                subtitle: "Enable semantic analysis",
                                isOn: $cameraManager.isAIFeaturesEnabled
                            )
                            
                            SettingsToggle(
                                icon: "rectangle.and.hand.point.up.left",
                                title: "Floating HUD",
                                subtitle: "Show director stats overlay",
                                isOn: $showFloatingAIHUD
                            )
                        }
                        
                        // Section: Camera Tools
                        SettingsSection(title: "Camera Tools") {
                            SettingsToggle(icon: "grid", title: "Grid", isOn: $isGridEnabled)
                            SettingsToggle(icon: "gyroscope", title: "Leveler", isOn: $isLevelerEnabled)
                            SettingsToggle(icon: "timer", title: "3s Timer", isOn: $isTimerEnabled)
                            SettingsToggle(icon: "scope", title: "Landmark Lock", isOn: $isLandmarkLockEnabled)
                            SettingsToggle(icon: "camera.shutter.button.fill", title: "Smart Shutter", isOn: $cameraManager.isSmartShutterEnabled)
                        }
                        
                        // Section: Aspect Ratio
                        SettingsSection(title: "Aspect Ratio") {
                            HStack(spacing: 12) {
                                ForEach(AspectRatio.allCases, id: \.self) { ratio in
                                    Button {
                                        withAnimation { currentAspectRatio = ratio }
                                    } label: {
                                        Text(ratio.rawValue)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(currentAspectRatio == ratio ? .black : .white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(currentAspectRatio == ratio ? Color.white : Color.white.opacity(0.1))
                                            )
                                    }
                                }
                            }
                        }
                        
                        // Section: 3D Splatting
                        SettingsSection(title: "3D Splatting") {
                            Button {
                                showDirectorMode = true
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "cube.transparent")
                                    Text("Enter Splat Capture Mode")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(10)
                            }
                            
                            SettingsToggle(
                                icon: "cube.fill",
                                title: "Voxel Debug Viz",
                                subtitle: "Visualize sparse point cloud",
                                isOn: $isVoxelDebugEnabled
                            )
                            
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Export Format")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.gray)
                                
                                Picker("Export Format", selection: $splatExportFormat) {
                                    Text("PLY (Standard)").tag("PLY")
                                    Text("SPZ (Compressed)").tag("SPZ")
                                }
                                .pickerStyle(.segmented)
                                .colorScheme(.dark)
                            }
                            .padding(.top, 4)
                        }
                        
                        // Section: Reset
                        Button {
                            cameraManager.resetSettings()
                        } label: {
                            Text("Reset All Settings")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(12)
                        }
                        .padding(.top, 20)
                        
                        // Footer
                        Text("BoyfriendCamera v1.0")
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.5))
                            .padding(.bottom, 40)
                    }
                    .padding()
                }
            }
        }
    }
}

// MARK: - Subcomponents

struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.gray)
                .tracking(1)
            
            VStack(spacing: 1) {
                content
            }
            .background(Color.white.opacity(0.03))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
        }
    }
}

struct SettingsToggle: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    
    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .frame(width: 24)
                    .foregroundColor(isOn ? .white : .gray)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: .white))
        .padding()
        .background(Color.black.opacity(0.2))
    }
}
