import SwiftUI
import CoreLocation
import AVFoundation

// --- 1. Enum ---
enum AspectRatio: String, CaseIterable {
    case fourThree = "4:3"
    case sixteenNine = "16:9"
    case square = "1:1"

    // Target Height / Width ratio
    var value: CGFloat {
        switch self {
        case .fourThree: return 4.0 / 3.0
        case .sixteenNine: return 16.0 / 9.0
        case .square: return 1.0
        }
    }
}

// --- 2. Main View ---
struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var locationManager = LocationManager()
    private let smoother = CompassSmoother()

    @State private var currentAdvice: DirectorAdvice?
    @State private var showMap = false
    @State private var showFlashAnimation = false
    @State private var isCapturing = false
    @State private var isZoomDialVisible = false

    // Default Aspect Ratio
    @State private var currentAspectRatio: AspectRatio = .fourThree

    // Gallery & Thumbnail States
    @State private var showPhotoReview = false
    @State private var thumbnailScale: CGFloat = 1.0

    // SETTINGS STATES
    @State private var showSettings = false
    @State private var exposureValue: Float = 0.0
    @State private var whiteBalanceValue: Float = 5500.0
    @State private var focusValue: Float = 0.5
    @State private var torchValue: Float = 0.0

    @State private var isGridEnabled = false
    @State private var isLevelerEnabled = true
    @State private var isTimerEnabled = false

    // ✅ Top bar measurements (for collision-avoidance + bounding)
    @State private var topBarGlobalFrame: CGRect = .zero
    @State private var topBarLeftWidth: CGFloat = 0
    @State private var topBarRightWidth: CGFloat = 0


    @State private var previewGlobalFrame: CGRect = .zero
    // ✅ Floating AI HUD (draggable, constrained to the camera preview)
    @State private var showFloatingAIHUD = false
    @State private var floatingHUDOffset: CGSize = .zero
    @State private var floatingHUDStartOffset: CGSize = .zero
    @State private var isDraggingFloatingHUD = false
    @State private var floatingHUDSize: CGSize = .zero

    // ✅ Landmark lock toggle
    @State private var isLandmarkLockEnabled = true

    // ✅ Throttle landmark guidance updates so UI stays responsive
    @State private var lastNavUpdateTime: Date = .distantPast
    private let navUpdateMinInterval: TimeInterval = 0.12

    @State private var targetLandmark = Landmark(
        name: "The Campanile",
        coordinate: CLLocationCoordinate2D(latitude: 37.8720, longitude: -122.2578)
    )

    var targetLandmarkBinding: Binding<MapLandmark> {
        Binding(
            get: { MapLandmark(name: targetLandmark.name, coordinate: targetLandmark.coordinate) },
            set: { new in targetLandmark = Landmark(name: new.name, coordinate: new.coordinate) }
        )
    }



    // ✅ Clamp floating HUD offset so it never leaves the visible camera preview.
    private func _clampFloatingHUDOffset(_ proposed: CGSize,
                                        previewSize: CGSize,
                                        hudSize: CGSize,
                                        padding: CGFloat,
                                        minYOffset: CGFloat = 0) -> CGSize {
        let maxX = max(0, previewSize.width - hudSize.width - 2 * padding)

        let rawMaxY = previewSize.height - hudSize.height - 2 * padding
        let maxY = max(minYOffset, max(0, rawMaxY))

        let x = min(max(0, proposed.width), maxX)
        let y = min(max(minYOffset, proposed.height), maxY)
        return CGSize(width: x, height: y)
    }
    
    // ✅ Computed Instruction for the Smart Director
    private var currentInstruction: DirectorInstruction {
        guard cameraManager.isAIFeaturesEnabled else { return .none }
        return DirectorLogic.determineInstruction(
            isPersonDetected: cameraManager.isPersonDetected,
            peopleCount: cameraManager.peopleCount,
            nosePoint: cameraManager.nosePoint,
            targetPoint: cameraManager.targetPoint,
            deviceRoll: cameraManager.deviceRoll,
            isLevel: cameraManager.isLevel,
            expressions: cameraManager.expressions
        )
    }

    // Zoom gesture start
    @State private var startZoomValue: CGFloat = 1.0

    var body: some View {
        GeometryReader { outerGeo in
            let topSafe = outerGeo.safeAreaInsets.top

            NavigationStack {
                ZStack {
                    Color.black.ignoresSafeArea()

                    // 1) CAMERA CONTAINER
                    GeometryReader { geo in
                        let width = geo.size.width

                        let sensorRatio: CGFloat = 4.0 / 3.0
                        let sensorHeight = width * sensorRatio
                        let targetHeight = width * currentAspectRatio.value

                        // Scaling Logic
                        let scaleFactor: CGFloat = currentAspectRatio.value > sensorRatio
                        ? (currentAspectRatio.value / sensorRatio)
                        : 1.0

                        ZStack(alignment: .topLeading) {
                            ZStack {
                                CameraPreview(cameraManager: cameraManager)
                                    .frame(width: width, height: sensorHeight)
                                    .scaleEffect(scaleFactor)

                                // ✅ AI nose guidance overlay (keeps dotted nose marker alive)
                                GuidanceOverlay(
                                    nosePoint: cameraManager.nosePoint,
                                    targetPoint: cameraManager.targetPoint,
                                    isAligned: cameraManager.isAligned
                                )

                                // ✅ Sun / light direction guidance (uses location + heading)
                                if cameraManager.isAIFeaturesEnabled {
                                    VStack {
                                        HStack {
                                            Spacer()
                                            SunGuidanceOverlay(
                                                location: locationManager.location,
                                                heading: locationManager.heading,
                                                isInterferenceHigh: locationManager.isInterferenceHigh
                                            )
                                        }
                                        Spacer()
                                    }
                                    .padding(.top, 10)
                                    .padding(.trailing, 10)
                                }

                                if isGridEnabled {
                                    GridOverlay()
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                        .frame(width: width, height: targetHeight)
                                }
                                
                                if isLevelerEnabled {
                                    LevelerOverlay(
                                        rotation: cameraManager.deviceRoll,
                                        isLevel: cameraManager.isLevel
                                    )
                                    .frame(width: width, height: targetHeight)
                                }
                            }

                            // ✅ Optional floating AI HUD inside the camera preview
                            if showFloatingAIHUD && cameraManager.isAIFeaturesEnabled {
                                let padding: CGFloat = 8
                                let previewSize = CGSize(width: width, height: targetHeight)

                                // Keep the floating HUD from overlapping the top menu bar.
                                // Compute how much of the preview's top area is covered by the menu bar (in preview-local coords).
                                let overlap = max(0, topBarGlobalFrame.maxY - previewGlobalFrame.minY)
                                let minYOffset = max(0, overlap + 6 - padding)

                                // Always render using a clamped offset (even if state was previously out-of-bounds)
                                let effectiveOffset = _clampFloatingHUDOffset(
                                    floatingHUDOffset,
                                    previewSize: previewSize,
                                    hudSize: floatingHUDSize,
                                    padding: padding,
                                    minYOffset: minYOffset
                                )

                                AIDebugHUD(cameraManager: cameraManager, compact: false, isInteractive: true)
                                    .background(
                                        GeometryReader { proxy in
                                            Color.clear
                                                .preference(key: _ViewSizePreferenceKey.self, value: proxy.size)
                                        }
                                    )
                                    .onPreferenceChange(_ViewSizePreferenceKey.self) { newSize in
                                        floatingHUDSize = newSize
                                        floatingHUDOffset = _clampFloatingHUDOffset(
                                            floatingHUDOffset,
                                            previewSize: previewSize,
                                            hudSize: newSize,
                                            padding: padding,
                                            minYOffset: minYOffset
                                        )
                                    }
                                    .onAppear {
                                        // Clamp on first appearance so it can't start outside the preview
                                        floatingHUDOffset = _clampFloatingHUDOffset(
                                            floatingHUDOffset,
                                            previewSize: previewSize,
                                            hudSize: floatingHUDSize,
                                            padding: padding,
                                            minYOffset: minYOffset
                                        )
                                    }
                                    .onChange(of: topBarGlobalFrame) { _, _ in
                                        // Re-clamp if the top bar layout changes (e.g., device rotation / layout updates)
                                        let overlap = max(0, topBarGlobalFrame.maxY - previewGlobalFrame.minY)
                                        let minYOffset = max(0, overlap + 6 - padding)
                                        floatingHUDOffset = _clampFloatingHUDOffset(
                                            floatingHUDOffset,
                                            previewSize: previewSize,
                                            hudSize: floatingHUDSize,
                                            padding: padding,
                                            minYOffset: minYOffset
                                        )
                                    }
                                    .onChange(of: currentAspectRatio) { _, _ in
                                        floatingHUDOffset = _clampFloatingHUDOffset(
                                            floatingHUDOffset,
                                            previewSize: previewSize,
                                            hudSize: floatingHUDSize,
                                            padding: padding,
                                            minYOffset: minYOffset
                                        )
                                    }
                                    .onChange(of: previewGlobalFrame) { _, _ in
                                        floatingHUDOffset = _clampFloatingHUDOffset(
                                            floatingHUDOffset,
                                            previewSize: previewSize,
                                            hudSize: floatingHUDSize,
                                            padding: padding,
                                            minYOffset: minYOffset
                                        )
                                    }
                                    .offset(x: padding + effectiveOffset.width, y: padding + effectiveOffset.height)
                                    .gesture(
                                        DragGesture()
                                            .onChanged { value in
                                                if !isDraggingFloatingHUD {
                                                    isDraggingFloatingHUD = true
                                                    floatingHUDOffset = _clampFloatingHUDOffset(
                                                        floatingHUDOffset,
                                                        previewSize: previewSize,
                                                        hudSize: floatingHUDSize,
                                                        padding: padding,
                                                        minYOffset: minYOffset
                                                    )
                                                    floatingHUDStartOffset = floatingHUDOffset
                                                }

                                                let proposedX = floatingHUDStartOffset.width + value.translation.width
                                                let proposedY = floatingHUDStartOffset.height + value.translation.height

                                                floatingHUDOffset = _clampFloatingHUDOffset(
                                                    CGSize(width: proposedX, height: proposedY),
                                                    previewSize: previewSize,
                                                    hudSize: floatingHUDSize,
                                                    padding: padding,
                                                    minYOffset: minYOffset
                                                )
                                            }
                                            .onEnded { _ in
                                                isDraggingFloatingHUD = false
                                                floatingHUDOffset = _clampFloatingHUDOffset(
                                                    floatingHUDOffset,
                                                    previewSize: previewSize,
                                                    hudSize: floatingHUDSize,
                                                    padding: padding,
                                                    minYOffset: minYOffset
                                                )
                                            }
                                    )
                                    .transition(.opacity)
                            }
                        }
                        .frame(width: width, height: targetHeight)
                        .clipped()
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(key: _PreviewGlobalFrameKey.self, value: proxy.frame(in: .global))
                            }
                        )
                        .gesture(
                            MagnificationGesture()
                                .onChanged { val in
                                    // Disable pinch zoom for front
                                    guard cameraManager.currentPosition == .back else { return }
                                    if startZoomValue == 1.0 { startZoomValue = cameraManager.currentZoomFactor }
                                    let newZoom = startZoomValue * val
                                    cameraManager.setZoomInstant(newZoom)
                                }
                                .onEnded { _ in
                                    startZoomValue = 1.0
                                }
                        )
                    }
                    .ignoresSafeArea()

                    // 3) LANDMARK OVERLAYS (only when lock enabled)
                    if isLandmarkLockEnabled, let advice = currentAdvice {
                        FloatingTargetView(angleDiff: advice.turnAngle, isLocked: abs(advice.turnAngle) < 3)
                            .zIndex(50)
                    }

                    // ✅ Smart Director Overlay
                    if cameraManager.isAIFeaturesEnabled {
                         VStack {
                             // Place it slightly below the top bar area (approx 100pt if frame not ready)
                             Spacer()
                                 .frame(height: max(100, topBarGlobalFrame.maxY + 10))
                             
                             DirectorOverlay(instruction: currentInstruction)
                             
                             Spacer()
                         }
                         .zIndex(60)
                         .allowsHitTesting(false)
                         .animation(.easeInOut, value: currentInstruction)
                    }

                    // 4) UI CONTROLS
                    VStack {
                        // --- TOP BAR ---
                        ZStack(alignment: .top) {
                            HStack(alignment: .top) {
                                // Left cluster
                                HStack(alignment: .top, spacing: 12) {
                                    // Map button (top-left)
                                    Button { showMap = true } label: {
                                        Image(systemName: "map.fill")
                                            .font(.headline)
                                            .foregroundColor(.white)
                                            .padding(10)
                                            .background(.ultraThinMaterial)
                                            .clipShape(Circle())
                                    }

                                    // GPS + AI ON/OFF (AI toggle right below GPS)
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(locationManager.permissionGranted ? Color.green : Color.red)
                                                .frame(width: 6, height: 6)
                                            Text(locationManager.permissionGranted ? "GPS" : "NO GPS")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                                .fixedSize(horizontal: true, vertical: false)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.black.opacity(0.4))
                                        .cornerRadius(12)

                                        Button {
                                            cameraManager.isAIFeaturesEnabled.toggle()
                                        } label: {
                                            HStack(spacing: 6) {
                                                Circle()
                                                    .fill(cameraManager.isAIFeaturesEnabled ? Color.green : Color.gray)
                                                    .frame(width: 6, height: 6)
                                                Text(cameraManager.isAIFeaturesEnabled ? "AI ON" : "AI OFF")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundColor(.white)
                                                    .lineLimit(1)
                                                    .fixedSize(horizontal: true, vertical: false)
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.black.opacity(0.4))
                                            .cornerRadius(12)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.top, 2)
                                }
                                .background(
                                    GeometryReader { proxy in
                                        Color.clear
                                            .preference(key: _TopBarLeftWidthKey.self, value: proxy.size.width)
                                    }
                                )

                                Spacer()

                                // Right cluster
                                HStack(alignment: .top, spacing: 12) {
                                    Button { withAnimation { showSettings.toggle() } } label: {
                                        Image(systemName: "slider.horizontal.3")
                                            .font(.headline)
                                            .foregroundColor(showSettings ? .yellow : .white)
                                            .padding(10)
                                            .background(.ultraThinMaterial)
                                            .clipShape(Circle())
                                    }
                                }
                                .background(
                                    GeometryReader { proxy in
                                        Color.clear
                                            .preference(key: _TopBarRightWidthKey.self, value: proxy.size.width)
                                    }
                                )
                            }

                            // Center AI HUD (only when AI is ON). Clamped to available width so it never overlaps.
                            if cameraManager.isAIFeaturesEnabled {
                                let available = max(0, outerGeo.size.width - topBarLeftWidth - topBarRightWidth - 2 * 16)
                                if available > 140 {
                                    AIDebugHUD(cameraManager: cameraManager, compact: true)
                                        .frame(maxWidth: available)
                                        .padding(.top, 2)
                                        .allowsHitTesting(false)
                                }
                            }
                        }
                        // ✅ notch-safe top padding (pulled slightly upward)
                        .padding(.top, topSafe + 2)
                        .padding(.horizontal)
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(key: _TopBarGlobalFrameKey.self, value: proxy.frame(in: .global))
                            }
                        )
                        .onPreferenceChange(_TopBarGlobalFrameKey.self) { topBarGlobalFrame = $0 }
                        .onPreferenceChange(_TopBarLeftWidthKey.self) { topBarLeftWidth = $0 }
                        .onPreferenceChange(_TopBarRightWidthKey.self) { topBarRightWidth = $0 }

                        Spacer()

                        // Scope view only when lock enabled
                        if isLandmarkLockEnabled, let advice = currentAdvice {
                            ScopeView(advice: advice)
                                .padding(.bottom, 10)
                        }

                        // --- ZOOM CONTROLS (Only if multiple lenses / Back Camera) ---
                        if cameraManager.zoomButtons.count > 1 {
                            ZStack(alignment: .bottom) {
                                if isZoomDialVisible {
                                    ArcZoomDial(
                                        currentZoom: cameraManager.currentZoomFactor,
                                        minZoom: cameraManager.minZoomFactor,
                                        maxZoom: cameraManager.maxZoomFactor,
                                        presets: cameraManager.zoomButtons
                                    )
                                    .transition(.opacity)
                                    .zIndex(1)
                                }

                                if !isZoomDialVisible {
                                    HStack(spacing: 20) {
                                        ForEach(cameraManager.zoomButtons, id: \.self) { preset in
                                            ZoomBubble(
                                                label: preset == 0.5 ? ".5" : String(format: "%.0f", preset),
                                                isSelected: abs(cameraManager.currentZoomFactor - preset) < 0.1
                                            )
                                            .onTapGesture { withAnimation { cameraManager.setZoomSmooth(preset) } }
                                        }
                                    }
                                    .padding(.bottom, 20)
                                    .transition(.opacity)
                                    .zIndex(2)
                                }
                            }
                            .frame(height: 100)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if !isZoomDialVisible {
                                            withAnimation { isZoomDialVisible = true }
                                            startZoomValue = cameraManager.currentZoomFactor
                                        }
                                        let delta = -value.translation.width / 150.0
                                        let rawZoom = startZoomValue * pow(2, delta)
                                        let clamped = max(cameraManager.minZoomFactor, min(cameraManager.maxZoomFactor, rawZoom))
                                        cameraManager.setZoomInstant(clamped)
                                    }
                                    .onEnded { _ in
                                        startZoomValue = cameraManager.currentZoomFactor
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                            withAnimation { isZoomDialVisible = false }
                                        }
                                    }
                            )
                        } else {
                            Color.clear.frame(height: 100)
                        }

                        // --- BOTTOM BAR (Apple style) ---
                        HStack {
                            // Album (bottom-left)
                            Button { showPhotoReview = true } label: {
                                if let image = cameraManager.capturedImage {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 52, height: 52)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.white, lineWidth: 2)
                                        )
                                        .scaleEffect(thumbnailScale)
                                } else {
                                    Image(systemName: "photo.stack")
                                        .font(.title3)
                                        .foregroundColor(.white)
                                        .frame(width: 52, height: 52)
                                        .background(.ultraThinMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }

                            Spacer()

                            // Shutter (center)
                            Button { takePhoto() } label: {
                                ZStack {
                                    Circle()
                                        .stroke(.white, lineWidth: 4)
                                        .frame(width: 78, height: 78)

                                    Circle()
                                        .fill(.white)
                                        .frame(width: 66, height: 66)
                                        .scaleEffect(isCapturing ? 0.85 : 1.0)
                                }
                            }

                            Spacer()

                            // Flip (bottom-right)
                            Button { cameraManager.switchCamera() } label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.title3)
                                    .foregroundColor(.white)
                                    .frame(width: 52, height: 52)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.horizontal, 36)
                        .padding(.bottom, 40)
                    }
                    .ignoresSafeArea(edges: .top)

                    // Full screen overlays
                    if showFlashAnimation {
                        Color.white.ignoresSafeArea().transition(.opacity).zIndex(100)
                    }

                    if cameraManager.isTimerRunning {
                        Color.black.opacity(0.4).ignoresSafeArea()
                        Text("\(cameraManager.timerCount)")
                            .font(.system(size: 100, weight: .bold))
                            .foregroundColor(.white)
                            .transition(.scale.combined(with: .opacity))
                            .zIndex(200)
                    }


                    // --- SETTINGS SHEET OVERLAY (on top of everything; does not push layout) ---
                    if showSettings {
                        // Leave the top menu bar clickable; block interactions below it.
                        VStack(spacing: 0) {
                            Color.clear.frame(height: max(topSafe + 54, topBarGlobalFrame.maxY))
                            Color.black.opacity(0.001)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .ignoresSafeArea()
                        .zIndex(800)

                        VStack(spacing: 0) {
                            Color.clear.frame(height: max(topSafe + 54, topBarGlobalFrame.maxY) + 8)
                            VStack(spacing: 14) {
                                // Toggles row 1
                                HStack(spacing: 12) {
                                    ToggleButton(icon: "grid", label: "Grid", isOn: $isGridEnabled)
                                    ToggleButton(icon: "gyroscope", label: "Level", isOn: $isLevelerEnabled)
                                    ToggleButton(icon: "timer", label: "3s Timer", isOn: $isTimerEnabled)
                                }

                                // Toggles row 2
                                HStack(spacing: 12) {
                                    ToggleButton(icon: "scope", label: "Lock", isOn: $isLandmarkLockEnabled)
                                        .onChange(of: isLandmarkLockEnabled) { _, on in
                                            if !on {
                                                withAnimation { currentAdvice = nil }
                                            } else {
                                                updateNavigationLogic(force: true)
                                            }
                                        }

                                    ToggleButton(icon: "sparkles", label: "AI", isOn: $cameraManager.isAIFeaturesEnabled)
                                }

                                // Floating AI HUD toggle
                                HStack {
                                    Spacer()
                                    ToggleButton(icon: "rectangle.and.hand.point.up.left", label: "HUD", isOn: $showFloatingAIHUD)
                                    Spacer()
                                }

                                // Aspect Ratio (moved from the top bar into Settings)
                                HStack {
                                    Spacer()
                                    Button { toggleAspectRatio() } label: {
                                        Text(currentAspectRatio.rawValue)
                                            .font(.footnote.bold())
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(
                                                .ultraThinMaterial,
                                                in: Capsule(style: .continuous)
                                            )
                                            .overlay(
                                                Capsule(style: .continuous)
                                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    Spacer()
                                }

                                // Exposure
                                HStack {
                                    Image(systemName: "sun.max.fill")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                    Slider(value: $exposureValue, in: -2...2)
                                        .tint(.yellow)
                                        .onChange(of: exposureValue) { _, val in
                                            cameraManager.setExposure(ev: val)
                                        }
                                    Text(String(format: "%.1f", exposureValue))
                                        .font(.caption.monospacedDigit())
                                        .foregroundColor(.white)
                                        .frame(width: 34)
                                }

                                // WB
                                if cameraManager.isWBSupported {
                                    HStack {
                                        Image(systemName: "thermometer")
                                            .font(.caption)
                                            .foregroundColor(.white)
                                        Slider(value: $whiteBalanceValue, in: 3000...8000)
                                            .tint(.orange)
                                            .onChange(of: whiteBalanceValue) { _, val in
                                                cameraManager.setWhiteBalance(kelvin: val)
                                            }
                                        Text("\(Int(whiteBalanceValue))K")
                                            .font(.caption.monospacedDigit())
                                            .foregroundColor(.white)
                                            .frame(width: 55)
                                    }
                                }

                                // Focus
                                if cameraManager.isFocusSupported {
                                    HStack {
                                        Image(systemName: "flower")
                                            .font(.caption)
                                            .foregroundColor(.white)
                                        Slider(value: $focusValue, in: 0.0...1.0)
                                            .tint(.cyan)
                                            .onChange(of: focusValue) { _, val in
                                                cameraManager.setLensPosition(val)
                                            }
                                        Image(systemName: "mountain.2")
                                            .font(.caption)
                                            .foregroundColor(.white)
                                    }
                                }

                                // Torch
                                if cameraManager.isTorchSupported {
                                    HStack {
                                        Image(systemName: "bolt.slash.fill")
                                            .font(.caption)
                                            .foregroundColor(.white)
                                        Slider(value: $torchValue, in: 0.0...1.0)
                                            .tint(.white)
                                            .onChange(of: torchValue) { _, val in
                                                cameraManager.setTorchLevel(val)
                                            }
                                        Image(systemName: "bolt.fill")
                                            .font(.caption)
                                            .foregroundColor(.yellow)
                                    }
                                }

                                // Reset
                                Button("Reset All") {
                                    exposureValue = 0
                                    whiteBalanceValue = 5500
                                    focusValue = 0.5
                                    torchValue = 0.0
                                    cameraManager.resetSettings()
                                }
                                .font(.caption.bold())
                                .foregroundColor(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.yellow)
                                .cornerRadius(8)
                            }
                            .padding(14)
                            .background(
                                .ultraThinMaterial,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.25), radius: 14, x: 0, y: 6)
                            .padding(.horizontal)
                            .zIndex(700)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            Spacer()
                        }
                        .ignoresSafeArea()
                        .zIndex(900)
                    }
                }
                .navigationDestination(isPresented: $showMap) {
                    MapScreen(locationManager: locationManager, landmark: targetLandmarkBinding)
                }
                .sheet(isPresented: $showPhotoReview) {
                    PhotoReviewView()
                }
                .onPreferenceChange(_PreviewGlobalFrameKey.self) { previewGlobalFrame = $0 }
                .onReceive(locationManager.$heading) { _ in
                    updateNavigationLogic(force: false)
                }
                .onReceive(locationManager.$location) { _ in
                    updateNavigationLogic(force: false)
                }
                .onReceive(cameraManager.captureDidFinish) { _ in
                    withAnimation(.easeInOut(duration: 0.1)) { isCapturing = false }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { thumbnailScale = 1.2 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation { thumbnailScale = 1.0 }
                    }
                }
                .onChange(of: showFloatingAIHUD) { _, on in
                    // When toggled on, default to the top-left corner of the camera preview.
                    if on {
                        floatingHUDOffset = .zero
                    }
                }
                .onChange(of: cameraManager.isAIFeaturesEnabled) { _, isOn in
                    if !isOn {
                        showFloatingAIHUD = false
                    }
                }
                .onAppear {
                    updateNavigationLogic(force: true)
                }
            }
        }
    }

    // MARK: - Actions

    private func toggleAspectRatio() {
        withAnimation {
            let allCases = AspectRatio.allCases
            if let currentIndex = allCases.firstIndex(of: currentAspectRatio) {
                let nextIndex = (currentIndex + 1) % allCases.count
                currentAspectRatio = allCases[nextIndex]
            }
        }
    }

    private func takePhoto() {
        // Always animate the shutter press
        isCapturing = true

        if !isTimerEnabled {
            withAnimation(.easeOut(duration: 0.1)) { showFlashAnimation = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation { showFlashAnimation = false }
            }
        }

        cameraManager.capturePhoto(
            location: locationManager.location,
            aspectRatioValue: currentAspectRatio.value,
            useTimer: isTimerEnabled
        )
    }

    // ✅ Landmark guidance logic with toggle + throttle
    private func updateNavigationLogic(force: Bool) {
        guard isLandmarkLockEnabled else { return }
        guard let userLoc = locationManager.location,
              let rawHeading = locationManager.heading?.trueHeading else { return }

        let now = Date()
        if !force, now.timeIntervalSince(lastNavUpdateTime) < navUpdateMinInterval {
            return
        }
        lastNavUpdateTime = now

        let smooth = smoother.smooth(rawHeading)
        let advice = PhotoDirector.guideToLandmark(
            userHeading: smooth,
            userLocation: userLoc.coordinate,
            target: targetLandmark
        )
        withAnimation { currentAdvice = advice }
    }
}

// MARK: - Helpers

struct ZoomBubble: View {
    let label: String
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.5))
            if isSelected { Circle().stroke(.yellow, lineWidth: 1) }
            Text(label + "x")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(isSelected ? .yellow : .white)
        }
        .frame(width: 38, height: 38)
    }
}

struct ToggleButton: View {
    let icon: String
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(label).font(.caption.bold())
            }
            .foregroundColor(isOn ? .yellow : .white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isOn ? Color.yellow.opacity(0.85) : Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.20), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preferences

private struct _TopBarGlobalFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct _TopBarLeftWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct _TopBarRightWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct _PreviewGlobalFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct _ViewSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct GridOverlay: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.width / 3, y: 0))
        path.addLine(to: CGPoint(x: rect.width / 3, y: rect.height))

        path.move(to: CGPoint(x: 2 * rect.width / 3, y: 0))
        path.addLine(to: CGPoint(x: 2 * rect.width / 3, y: rect.height))

        path.move(to: CGPoint(x: 0, y: rect.height / 3))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height / 3))

        path.move(to: CGPoint(x: 0, y: 2 * rect.height / 3))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height * 2 / 3))

        return path
    }
}
