import SwiftUI
import CoreLocation
import AVFoundation

enum AspectRatio: String, CaseIterable {
    case fourThree = "4:3"
    case sixteenNine = "16:9"
    case square = "1:1"

    var value: CGFloat {
        switch self {
        case .fourThree: return 4.0 / 3.0
        case .sixteenNine: return 16.0 / 9.0
        case .square: return 1.0
        }
    }
}

struct ContentView: View {
    @StateObject var cameraManager = CameraManager()
    @StateObject var locationManager = LocationManager()
    let smoother = CompassSmoother()

    @State var currentAdvice: DirectorAdvice?
    @State private var showMap = false
    @State private var showFlashAnimation = false
    @State private var isCapturing = false
    @State private var isZoomDialVisible = false

    // Landmark lock
    @State private var isLockEnabled: Bool = true

    // ✅ Apple-ish: lock control hidden until user taps viewfinder
    @State private var showLockControl: Bool = false
    @State private var lockHideWorkItem: DispatchWorkItem?

    // ✅ Toast when toggled
    @State private var showLockToast: Bool = false
    @State private var lockToastText: String = ""

    @State private var currentAspectRatio: AspectRatio = .fourThree

    @State private var showPhotoReview = false
    @State private var thumbnailScale: CGFloat = 1.0

    @State private var showSettings = false
    @State private var exposureValue: Float = 0.0
    @State private var whiteBalanceValue: Float = 5500.0
    @State private var focusValue: Float = 0.5
    @State private var torchValue: Float = 0.0

    @State private var isGridEnabled = false
    @State private var isTimerEnabled = false

    @State var targetLandmark = Landmark(
        name: "The Campanile",
        coordinate: CLLocationCoordinate2D(latitude: 37.8720, longitude: -122.2578)
    )

    var targetLandmarkBinding: Binding<MapLandmark> {
        Binding(
            get: { MapLandmark(name: targetLandmark.name, coordinate: targetLandmark.coordinate) },
            set: { new in targetLandmark = Landmark(name: new.name, coordinate: new.coordinate) }
        )
    }

    @State private var startZoomValue: CGFloat = 1.0

    // ✅ throttle landmark guidance updates (prevents UI jank)
    @State private var lastNavUpdateTime: TimeInterval = 0
    private let navMinInterval: TimeInterval = 0.12

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                // CAMERA
                GeometryReader { geo in
                    let width = geo.size.width
                    let sensorRatio: CGFloat = 4.0 / 3.0
                    let sensorHeight = width * sensorRatio
                    let targetHeight = width * currentAspectRatio.value
                    let scaleFactor: CGFloat = currentAspectRatio.value > sensorRatio
                    ? (currentAspectRatio.value / sensorRatio)
                    : 1.0

                    ZStack {
                        CameraPreview(
                            cameraManager: cameraManager,
                            onUserInteraction: { revealLockControlTemporarily() }
                        )
                        .frame(width: width, height: sensorHeight)
                        .scaleEffect(scaleFactor)

                        if isGridEnabled {
                            GridOverlay()
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                .frame(width: width, height: targetHeight)
                        }
                    }
                    .frame(width: width, height: targetHeight)
                    .clipped()
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { val in
                                guard cameraManager.currentPosition == .back else { return }
                                revealLockControlTemporarily()
                                cameraManager.setZoomInstant(cameraManager.currentZoomFactor * val)
                            }
                    )
                }
                .ignoresSafeArea()

                // OVERLAYS (only when lock enabled)
                if isLockEnabled, let advice = currentAdvice {
                    FloatingTargetView(angleDiff: advice.turnAngle, isLocked: abs(advice.turnAngle) < 3)
                }

                // ✅ Toast indicator (Apple-ish)
                if showLockToast {
                    Text(lockToastText)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())
                        .padding(.top, 60)
                        .transition(.opacity)
                        .zIndex(999)
                }

                // UI
                VStack {
                    // TOP BAR
                    HStack {
                        HStack(spacing: 8) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(locationManager.permissionGranted ? Color.green : Color.red)
                                    .frame(width: 6, height: 6)
                                Text(locationManager.permissionGranted ? "GPS" : "NO GPS")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.4))
                            .cornerRadius(12)

                            // Map moved to top (bottom now Apple style)
                            Button {
                                revealLockControlTemporarily()
                                showMap = true
                            } label: {
                                Image(systemName: "map.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                        }

                        Spacer()

                        // ✅ hidden lock button (appears after viewfinder tap)
                        Button {
                            revealLockControlTemporarily()
                            toggleLandmarkLock()
                        } label: {
                            Image(systemName: "scope")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(isLockEnabled ? .black : .white)
                                .frame(width: 36, height: 36)
                                .background(isLockEnabled ? Color.yellow : Color.black.opacity(0.35))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(isLockEnabled ? 0.0 : 0.35), lineWidth: 1))
                        }
                        .opacity(showLockControl ? 1 : 0)
                        .animation(.easeInOut(duration: 0.18), value: showLockControl)
                        .allowsHitTesting(showLockControl)

                        // Settings
                        Button {
                            revealLockControlTemporarily()
                            withAnimation { showSettings.toggle() }
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.headline)
                                .foregroundColor(showSettings ? .yellow : .white)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }

                        // Aspect Ratio
                        Button {
                            revealLockControlTemporarily()
                            toggleAspectRatio()
                        } label: {
                            Text(currentAspectRatio.rawValue)
                                .font(.footnote.bold())
                                .foregroundColor(.white)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.yellow, lineWidth: currentAspectRatio != .fourThree ? 1 : 0))
                        }
                    }
                    .padding(.top, 50)
                    .padding(.horizontal)

                    // SETTINGS PANEL
                    if showSettings {
                        VStack(spacing: 15) {
                            HStack(spacing: 12) {
                                ToggleButton(icon: "grid", label: "Grid", isOn: $isGridEnabled)
                                ToggleButton(icon: "timer", label: "3s Timer", isOn: $isTimerEnabled)

                                // ✅ NEW: AI toggle (battery / responsiveness)
                                ToggleButton(
                                    icon: "sparkles",
                                    label: "AI",
                                    isOn: Binding(
                                        get: { cameraManager.isAIFeaturesEnabled },
                                        set: { cameraManager.isAIFeaturesEnabled = $0 }
                                    )
                                )
                            }

                            HStack {
                                Image(systemName: "sun.max.fill").font(.caption).foregroundColor(.white)
                                Slider(value: $exposureValue, in: -2...2)
                                    .tint(.yellow)
                                    .onChange(of: exposureValue) { _, val in
                                        cameraManager.setExposure(ev: val)
                                    }
                                Text(String(format: "%.1f", exposureValue))
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.white)
                                    .frame(width: 30)
                            }

                            if cameraManager.isWBSupported {
                                HStack {
                                    Image(systemName: "thermometer").font(.caption).foregroundColor(.white)
                                    Slider(value: $whiteBalanceValue, in: 3000...8000)
                                        .tint(.orange)
                                        .onChange(of: whiteBalanceValue) { _, val in
                                            cameraManager.setWhiteBalance(kelvin: val)
                                        }
                                    Text("\(Int(whiteBalanceValue))K")
                                        .font(.caption.monospacedDigit())
                                        .foregroundColor(.white)
                                        .frame(width: 45)
                                }
                            }

                            if cameraManager.isFocusSupported {
                                HStack {
                                    Image(systemName: "flower").font(.caption).foregroundColor(.white)
                                    Slider(value: $focusValue, in: 0.0...1.0)
                                        .tint(.cyan)
                                        .onChange(of: focusValue) { _, val in
                                            cameraManager.setLensPosition(val)
                                        }
                                    Image(systemName: "mountain.2").font(.caption).foregroundColor(.white)
                                }
                            }

                            if cameraManager.isTorchSupported {
                                HStack {
                                    Image(systemName: "bolt.slash.fill").font(.caption).foregroundColor(.white)
                                    Slider(value: $torchValue, in: 0.0...1.0)
                                        .tint(.white)
                                        .onChange(of: torchValue) { _, val in
                                            cameraManager.setTorchLevel(val)
                                        }
                                    Image(systemName: "bolt.fill").font(.caption).foregroundColor(.yellow)
                                }
                            }

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
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(15)
                        .padding(.horizontal)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    Spacer()

                    if isLockEnabled, let advice = currentAdvice {
                        ScopeView(advice: advice)
                            .padding(.bottom, 10)
                    }

                    // ZOOM DIAL
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
                                        .onTapGesture {
                                            revealLockControlTemporarily()
                                            withAnimation { cameraManager.setZoomSmooth(preset) }
                                        }
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
                                    revealLockControlTemporarily()
                                    if !isZoomDialVisible {
                                        withAnimation { isZoomDialVisible = true }
                                        startZoomValue = cameraManager.currentZoomFactor
                                    }
                                    let delta = -value.translation.width / 150.0
                                    let rawZoom = startZoomValue * pow(2, delta)
                                    let clampedZoom = max(cameraManager.minZoomFactor, min(cameraManager.maxZoomFactor, rawZoom))
                                    cameraManager.setZoomInstant(clampedZoom)
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

                    // ✅ BOTTOM BAR (Apple style): Album - Shutter - Flip
                    HStack {
                        // Album
                        Button {
                            revealLockControlTemporarily()
                            showPhotoReview = true
                        } label: {
                            if let image = cameraManager.capturedImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 52, height: 52)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white, lineWidth: 2))
                                    .scaleEffect(thumbnailScale)
                            } else {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 52, height: 52)
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .frame(width: 70)

                        Spacer()

                        // Shutter
                        Button {
                            revealLockControlTemporarily()
                            takePhoto()
                        } label: {
                            ZStack {
                                Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                                Circle().fill(.white).frame(width: 66, height: 66)
                                    .scaleEffect(isCapturing ? 0.85 : 1.0)
                            }
                        }
                        .frame(width: 90)

                        Spacer()

                        // Flip
                        Button {
                            revealLockControlTemporarily()
                            cameraManager.switchCamera()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 52, height: 52)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .frame(width: 70)
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 36)
                }

                // Flash
                if showFlashAnimation {
                    Color.white.ignoresSafeArea()
                        .transition(.opacity)
                        .zIndex(100)
                }

                // Timer
                if cameraManager.isTimerRunning {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    Text("\(cameraManager.timerCount)")
                        .font(.system(size: 100, weight: .bold))
                        .foregroundColor(.white)
                        .transition(.scale.combined(with: .opacity))
                        .zIndex(200)
                }
            }
            .navigationDestination(isPresented: $showMap) {
                MapScreen(locationManager: locationManager, landmark: targetLandmarkBinding)
            }
            .sheet(isPresented: $showPhotoReview) { PhotoReviewView() }

            // ✅ only update when lock enabled + throttled
            .onReceive(locationManager.$heading) { _ in
                if isLockEnabled { updateNavigationLogicThrottled() }
            }
            .onReceive(locationManager.$location) { _ in
                if isLockEnabled { updateNavigationLogicThrottled() }
            }

            .onReceive(cameraManager.captureDidFinish) { _ in
                withAnimation(.easeInOut(duration: 0.1)) { isCapturing = false }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { thumbnailScale = 1.2 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { withAnimation { thumbnailScale = 1.0 } }
            }

            .onAppear {
                // optional: start hidden like Apple
                showLockControl = false
            }
        }
    }

    // MARK: - Apple-ish hidden control behavior
    private func revealLockControlTemporarily() {
        lockHideWorkItem?.cancel()

        withAnimation(.easeOut(duration: 0.15)) {
            showLockControl = true
        }

        let work = DispatchWorkItem {
            withAnimation(.easeIn(duration: 0.2)) {
                showLockControl = false
            }
        }
        lockHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    private func toggleLandmarkLock() {
        isLockEnabled.toggle()
        if !isLockEnabled { currentAdvice = nil }
        showLockToastNow(text: isLockEnabled ? "LANDMARK LOCK ON" : "LANDMARK LOCK OFF")
    }

    private func showLockToastNow(text: String) {
        lockToastText = text
        withAnimation(.easeInOut(duration: 0.15)) { showLockToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.easeInOut(duration: 0.2)) { showLockToast = false }
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
        if !isTimerEnabled {
            isCapturing = true
            withAnimation(.easeOut(duration: 0.1)) { showFlashAnimation = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { withAnimation { showFlashAnimation = false } }
        }
        cameraManager.capturePhoto(location: locationManager.location, aspectRatioValue: currentAspectRatio.value, useTimer: isTimerEnabled)
    }

    private func updateNavigationLogicThrottled() {
        let now = Date().timeIntervalSince1970
        guard now - lastNavUpdateTime >= navMinInterval else { return }
        lastNavUpdateTime = now

        guard let userLoc = locationManager.location,
              let rawHeading = locationManager.heading?.trueHeading else { return }

        let smooth = smoother.smooth(rawHeading)
        let advice = PhotoDirector.guideToLandmark(
            userHeading: smooth,
            userLocation: userLoc.coordinate,
            target: targetLandmark
        )

        // ✅ no heavy animation spam (keeps UI responsive)
        var txn = Transaction()
        txn.animation = nil
        withTransaction(txn) {
            currentAdvice = advice
        }
    }
}

// Helpers
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
            .foregroundColor(isOn ? .black : .white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isOn ? Color.yellow : Color.black.opacity(0.5))
            .cornerRadius(8)
        }
    }
}

struct GridOverlay: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width/3, y: 0)); path.addLine(to: CGPoint(x: rect.width/3, y: rect.height))
        path.move(to: CGPoint(x: 2*rect.width/3, y: 0)); path.addLine(to: CGPoint(x: 2*rect.width/3, y: rect.height))
        path.move(to: CGPoint(x: 0, y: rect.height/3)); path.addLine(to: CGPoint(x: rect.width, y: rect.height/3))
        path.move(to: CGPoint(x: 0, y: 2*rect.height/3)); path.addLine(to: CGPoint(x: rect.width, y: 2*rect.height/3))
        return path
    }
}
