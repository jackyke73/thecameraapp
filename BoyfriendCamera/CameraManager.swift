//
//  CameraManager.swift
//  BoyfriendCamera
//

import AVFoundation
import SwiftUI
import Combine
import Vision
import Photos
import UIKit
import CoreLocation
import AudioToolbox

final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {

    // MARK: - Published State
    @Published var permissionGranted = false

    // ✅ AI / Detection state
    @Published var isAIFeaturesEnabled: Bool = true
    @Published var isPersonDetected = false
    @Published var peopleCount: Int = 0
    @Published var expressions: [String] = []   // one per detected face (if any)

    @Published var capturedImage: UIImage?

    // Capabilities (Dynamic - updated when camera/lens changes)
    @Published var isWBSupported: Bool = false
    @Published var isFocusSupported: Bool = false
    @Published var isTorchSupported: Bool = false

    // Zoom
    @Published var minZoomFactor: CGFloat = 0.5
    @Published var maxZoomFactor: CGFloat = 15.0
    @Published var currentZoomFactor: CGFloat = 1.0
    @Published var zoomButtons: [CGFloat] = [0.5, 1.0, 2.0, 4.0]

    // Timer
    @Published var isTimerRunning = false
    @Published var timerCount = 0

    // Camera Position
    @Published var currentPosition: AVCaptureDevice.Position = .back

    // MARK: - Private
    private var zoomScaler: CGFloat = 2.0

    let session = AVCaptureSession()

    // Session/device control queue
    private let sessionQueue = DispatchQueue(label: "camera.sessionQueue")

    // Vision/frame processing queue (keep UI responsive)
    private let videoOutputQueue = DispatchQueue(label: "camera.videoOutputQueue", qos: .utility)

    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()

    private var activeDevice: AVCaptureDevice?
    private var deviceInput: AVCaptureDeviceInput?

    // ✅ Vision
    private let poseRequest = VNDetectHumanBodyPoseRequest()
    private let faceLandmarksRequest = VNDetectFaceLandmarksRequest()
    private let visionHandler = VNSequenceRequestHandler()

    private var frameCounter: Int = 0
    private let processEveryNFrames: Int = 6   // ✅ raise this if you want more battery savings
    private var isVisionBusy: Bool = false

    // For “only publish if changed” (reduces SwiftUI churn)
    private var lastPeopleCount: Int = -1
    private var lastPersonDetected: Bool = false
    private var lastExpressions: [String] = []

    private var pendingLocation: CLLocation?
    private var pendingAspectRatio: CGFloat = 4.0 / 3.0

    let captureDidFinish = PassthroughSubject<Void, Never>()

    // KVO: back camera (virtual device) can switch physical lenses dynamically.
    private var primaryConstituentObservation: NSKeyValueObservation?

    override init() {
        super.init()
        configureOutputs()
        checkPermissions()
    }

    deinit {
        primaryConstituentObservation = nil
    }

    // MARK: - Output Setup (one-time)
    private func configureOutputs() {
        videoOutput.alwaysDiscardsLateVideoFrames = true

        // ✅ Efficient format for Vision
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        ]
    }

    // MARK: - Virtual vs Physical Device Helpers (CRASH FIX)
    private func configurationDevice() -> AVCaptureDevice? {
        guard let device = activeDevice else { return nil }
        if #available(iOS 13.0, *) {
            return device.activePrimaryConstituent ?? device
        }
        return device
    }

    private func refreshCapabilities() {
        guard let d = configurationDevice() else { return }
        DispatchQueue.main.async {
            self.isWBSupported = d.isLockingWhiteBalanceWithCustomDeviceGainsSupported
            self.isFocusSupported = d.isLockingFocusWithCustomLensPositionSupported
            self.isTorchSupported = d.hasTorch
        }
    }

    private func startObservingPrimaryConstituentIfNeeded() {
        primaryConstituentObservation = nil
        guard let device = activeDevice else { return }
        if #available(iOS 13.0, *) {
            primaryConstituentObservation = device.observe(\.activePrimaryConstituent, options: [.initial, .new]) { [weak self] _, _ in
                self?.refreshCapabilities()
            }
        }
    }

    // MARK: - SWITCH CAMERA
    func switchCamera() {
        currentPosition = (currentPosition == .back) ? .front : .back
        sessionQueue.async {
            self.primaryConstituentObservation = nil

            self.session.stopRunning()
            if let input = self.deviceInput {
                self.session.removeInput(input)
                self.deviceInput = nil
            }
            self.activeDevice = nil

            self.setupCamera()
        }
    }

    // MARK: - PRO SETTINGS (Crash-proof)
    func setExposure(ev: Float) {
        sessionQueue.async {
            guard let device = self.configurationDevice() else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                device.setExposureTargetBias(ev, completionHandler: nil)
            } catch {
                print("Exposure error: \(error)")
            }
        }
    }

    private func clampGains(_ gains: AVCaptureDevice.WhiteBalanceGains, for device: AVCaptureDevice) -> AVCaptureDevice.WhiteBalanceGains {
        var g = gains
        let maxG = device.maxWhiteBalanceGain
        let safeMax = max(1.0, maxG - 0.01)

        g.redGain   = max(1.0, min(g.redGain,   safeMax))
        g.greenGain = max(1.0, min(g.greenGain, safeMax))
        g.blueGain  = max(1.0, min(g.blueGain,  safeMax))
        return g
    }

    func setWhiteBalance(kelvin: Float) {
        sessionQueue.async {
            guard let device = self.configurationDevice() else { return }
            guard device.isLockingWhiteBalanceWithCustomDeviceGainsSupported else { return }

            let k = max(1000.0, min(10000.0, kelvin))

            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                let tempTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: k, tint: 0)
                var gains = device.deviceWhiteBalanceGains(for: tempTint)
                gains = self.clampGains(gains, for: device)

                guard gains.redGain.isFinite, gains.greenGain.isFinite, gains.blueGain.isFinite else { return }
                device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
            } catch {
                print("WB error: \(error)")
            }
        }
    }

    func setLensPosition(_ position: Float) {
        sessionQueue.async {
            guard let device = self.configurationDevice() else { return }
            guard device.isLockingFocusWithCustomLensPositionSupported else { return }

            let p = max(0.0, min(1.0, position))

            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                device.setFocusModeLocked(lensPosition: p, completionHandler: nil)
            } catch {
                print("Focus error: \(error)")
            }
        }
    }

    func setTorchLevel(_ level: Float) {
        sessionQueue.async {
            guard let device = self.configurationDevice(), device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                if level <= 0.01 {
                    device.torchMode = .off
                } else {
                    try device.setTorchModeOn(level: max(0.01, min(1.0, level)))
                }
            } catch {
                print("Torch error: \(error)")
            }
        }
    }

    func resetSettings() {
        sessionQueue.async {
            guard let device = self.configurationDevice() else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                device.setExposureTargetBias(0, completionHandler: nil)
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                if device.hasTorch { device.torchMode = .off }
            } catch {
                print("Reset error: \(error)")
            }
        }
    }

    // MARK: - ZOOM
    func setZoomInstant(_ uiFactor: CGFloat) {
        sessionQueue.async {
            guard let device = self.activeDevice else { return }
            let nativeFactor = uiFactor * self.zoomScaler
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                let clamped = max(device.minAvailableVideoZoomFactor,
                                  min(nativeFactor, device.maxAvailableVideoZoomFactor))
                device.videoZoomFactor = clamped
            } catch { }

            DispatchQueue.main.async { self.currentZoomFactor = uiFactor }
            self.refreshCapabilities()
        }
    }

    func setZoomSmooth(_ uiFactor: CGFloat) {
        sessionQueue.async {
            guard let device = self.activeDevice else { return }
            let nativeFactor = uiFactor * self.zoomScaler
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                let clamped = max(device.minAvailableVideoZoomFactor,
                                  min(nativeFactor, device.maxAvailableVideoZoomFactor))
                device.ramp(toVideoZoomFactor: clamped, withRate: 5.0)
            } catch { }

            DispatchQueue.main.async { self.currentZoomFactor = uiFactor }
            self.refreshCapabilities()
        }
    }

    // MARK: - CAPTURE
    func capturePhoto(location: CLLocation?, aspectRatioValue: CGFloat, useTimer: Bool) {
        if useTimer {
            timerCount = 3
            isTimerRunning = true
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                self.timerCount -= 1
                if self.timerCount <= 0 {
                    timer.invalidate()
                    self.isTimerRunning = false
                    self.performCapture(location: location, ratio: aspectRatioValue)
                }
            }
        } else {
            performCapture(location: location, ratio: aspectRatioValue)
        }
    }

    private func performCapture(location: CLLocation?, ratio: CGFloat) {
        AudioServicesPlaySystemSound(1108)
        pendingLocation = location
        pendingAspectRatio = ratio

        sessionQueue.async {
            if let connection = self.photoOutput.connection(with: .video) {
                connection.videoOrientation = .portrait
            }
            let settings = AVCapturePhotoSettings()
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil else { return }
        guard let data = photo.fileDataRepresentation(),
              let originalImage = UIImage(data: data) else { return }

        var fixedImage = fixOrientation(img: originalImage)

        if currentPosition == .front, let cgImage = fixedImage.cgImage {
            fixedImage = UIImage(cgImage: cgImage, scale: fixedImage.scale, orientation: .upMirrored)
            fixedImage = fixOrientation(img: fixedImage)
        }

        let croppedImage = cropToRatio(fixedImage, ratio: pendingAspectRatio)

        DispatchQueue.main.async { self.capturedImage = croppedImage }

        if let jpegData = croppedImage.jpegData(compressionQuality: 1.0) {
            saveToCustomAlbum(imageData: jpegData, location: pendingLocation)
        }

        DispatchQueue.main.async { self.captureDidFinish.send(()) }
    }

    // MARK: - Image Helpers
    private func cropToRatio(_ image: UIImage, ratio: CGFloat) -> UIImage {
        let w = image.size.width
        let h = image.size.height

        var newW = w
        var newH = h

        let currentRatio = h / w
        if currentRatio > ratio {
            newH = w * ratio
        } else {
            newW = h / ratio
        }

        let x = (w - newW) / 2.0
        let y = (h - newH) / 2.0

        if let cg = image.cgImage?.cropping(to: CGRect(x: x, y: y, width: newW, height: newH)) {
            return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
        }
        return image
    }

    private func fixOrientation(img: UIImage) -> UIImage {
        if img.imageOrientation == .up { return img }
        UIGraphicsBeginImageContextWithOptions(img.size, false, img.scale)
        img.draw(in: CGRect(origin: .zero, size: img.size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext() ?? img
        UIGraphicsEndImageContext()
        return normalized
    }

    // MARK: - Save
    private func saveToCustomAlbum(imageData: Data, location: CLLocation?) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else { return }

            let name = "Boyfriend Camera"
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "title = %@", name)

            let collection = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
            if let album = collection.firstObject {
                self.saveAsset(data: imageData, location: location, to: album)
            } else {
                PHPhotoLibrary.shared().performChanges({
                    _ = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
                }, completionHandler: { success, _ in
                    if success {
                        let opts = PHFetchOptions()
                        opts.predicate = NSPredicate(format: "title = %@", name)
                        if let album = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: opts).firstObject {
                            self.saveAsset(data: imageData, location: location, to: album)
                        }
                    }
                })
            }
        }
    }

    private func saveAsset(data: Data, location: CLLocation?, to album: PHAssetCollection) {
        PHPhotoLibrary.shared().performChanges {
            let req = PHAssetCreationRequest.forAsset()
            req.addResource(with: .photo, data: data, options: nil)
            req.location = location

            guard let albumReq = PHAssetCollectionChangeRequest(for: album),
                  let placeholder = req.placeholderForCreatedAsset else { return }
            albumReq.addAssets([placeholder] as NSArray)
        }
    }

    // MARK: - SETUP
    private func setupCamera() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        var device: AVCaptureDevice?

        if currentPosition == .back {
            let types: [AVCaptureDevice.DeviceType] = [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInWideAngleCamera
            ]
            device = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .back).devices.first

            zoomScaler = 2.0
            if device?.deviceType == .builtInWideAngleCamera { zoomScaler = 1.0 }
        } else {
            device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            if device == nil { device = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) }
            zoomScaler = 1.0
        }

        guard let chosenDevice = device else {
            session.commitConfiguration()
            return
        }

        activeDevice = chosenDevice
        startObservingPrimaryConstituentIfNeeded()

        do {
            let input = try AVCaptureDeviceInput(device: chosenDevice)
            if session.canAddInput(input) {
                session.addInput(input)
                deviceInput = input
            }
        } catch {
            print("Input Error: \(error)")
        }

        if session.outputs.contains(videoOutput) == false, session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        if session.outputs.contains(photoOutput) == false, session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)

        if let conn = videoOutput.connection(with: .video) {
            conn.videoOrientation = .portrait
            conn.isVideoMirrored = (currentPosition == .front)
        }

        session.commitConfiguration()
        session.startRunning()

        DispatchQueue.main.async {
            if self.currentPosition == .back {
                self.minZoomFactor = 0.5
                self.maxZoomFactor = chosenDevice.maxAvailableVideoZoomFactor / self.zoomScaler
                self.zoomButtons = [0.5, 1.0, 2.0, 4.0]
            } else {
                self.minZoomFactor = 1.0
                self.maxZoomFactor = chosenDevice.maxAvailableVideoZoomFactor
                self.zoomButtons = [1.0]
            }

            self.setZoomInstant(1.0)
        }

        refreshCapabilities()
    }

    // MARK: - Permissions
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async { self.permissionGranted = true }
            sessionQueue.async { self.setupCamera() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { self.permissionGranted = granted }
                if granted {
                    self.sessionQueue.async { self.setupCamera() }
                }
            }
        default:
            DispatchQueue.main.async { self.permissionGranted = false }
        }
    }

    // MARK: - Vision (AI)
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        guard isAIFeaturesEnabled else { return }

        frameCounter += 1
        if frameCounter % processEveryNFrames != 0 { return }

        if isVisionBusy { return }
        isVisionBusy = true
        defer { isVisionBusy = false }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        autoreleasepool {
            do {
                // ✅ run both in one pass
                try visionHandler.perform([poseRequest, faceLandmarksRequest], on: pixelBuffer, orientation: .right)

                let poseCount = poseRequest.results?.count ?? 0
                let faces = (faceLandmarksRequest.results as? [VNFaceObservation]) ?? []
                let faceCount = faces.count

                // expressions from faces
                let exprs = faces.map { classifyExpression(face: $0) }

                // peopleCount = prefer face count (multiple faces), fallback to pose count
                let newPeopleCount = max(faceCount, poseCount)
                let newDetected = (newPeopleCount > 0)

                // ✅ only publish when values changed
                var shouldPublish = false
                if newPeopleCount != lastPeopleCount { lastPeopleCount = newPeopleCount; shouldPublish = true }
                if newDetected != lastPersonDetected { lastPersonDetected = newDetected; shouldPublish = true }
                if exprs != lastExpressions { lastExpressions = exprs; shouldPublish = true }

                if shouldPublish {
                    DispatchQueue.main.async {
                        self.peopleCount = newPeopleCount
                        self.isPersonDetected = newDetected
                        self.expressions = exprs
                    }
                }
            } catch {
                // ignore
            }
        }
    }

    // ✅ Simple heuristic expression classifier from mouth landmarks
    private func classifyExpression(face: VNFaceObservation) -> String {
        guard
            let lm = face.landmarks,
            let outer = lm.outerLips?.normalizedPoints,
            outer.count >= 6
        else { return "Unknown" }

        // mouth width
        let left = outer.min(by: { $0.x < $1.x })!
        let right = outer.max(by: { $0.x < $1.x })!
        let width = distance(left, right)

        // mouth openness (height)
        let minY = outer.map(\.y).min() ?? 0
        let maxY = outer.map(\.y).max() ?? 0
        let height = max(0, maxY - minY)

        if width <= 0.0001 { return "Unknown" }

        let openness = height / width

        // smile score: corners higher than center
        let centerY = outer.sorted(by: { $0.x < $1.x })[outer.count / 2].y
        let cornersAvgY = (left.y + right.y) / 2.0
        let smileScore = cornersAvgY - centerY

        // thresholds tuned for “good enough” UI indicator
        if openness > 0.30 { return "Surprised" }
        if smileScore > 0.03 { return "Smiling" }
        if openness < 0.08 { return "Neutral" }
        return "Talking"
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx*dx + dy*dy)
    }

    // MARK: - Focus Tap (Normalized point)
    func setFocus(point: CGPoint) {
        sessionQueue.async {
            guard let device = self.configurationDevice() else { return }
            let x = max(0.0, min(1.0, point.x))
            let y = max(0.0, min(1.0, point.y))
            let p = CGPoint(x: x, y: y)

            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = p
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = p
                    device.exposureMode = .autoExpose
                }
            } catch { }
        }
    }

    func setFocus(layerPoint: CGPoint, previewLayer: AVCaptureVideoPreviewLayer) {
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
        setFocus(point: devicePoint)
    }
}
