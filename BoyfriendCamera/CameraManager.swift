import AVFoundation
import SwiftUI
import Combine
import Vision
import Photos
import UIKit

class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {

    @Published var permissionGranted = false
    @Published var isPersonDetected = false
    @Published var capturedImage: UIImage?
    
    // Zoom State
    @Published var minZoomFactor: CGFloat = 0.5
    @Published var maxZoomFactor: CGFloat = 15.0
    @Published var currentZoomFactor: CGFloat = 1.0
    
    // FORCED BUTTON LAYOUT
    @Published var zoomButtons: [CGFloat] = [0.5, 1.0, 2.0, 4.0, 8.0]

    // SCALER: On Pro iPhones, Native 1.0 is the UltraWide.
    // So we must multiply UI Zoom by 2 to get Native Zoom.
    // UI 0.5 * 2 = Native 1.0 (Ultra)
    // UI 1.0 * 2 = Native 2.0 (Wide)
    private var zoomScaler: CGFloat = 2.0

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "cameraQueue")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    
    private var activeDevice: AVCaptureDevice?
    private var deviceInput: AVCaptureDeviceInput?
    private let bodyPoseRequest = VNDetectHumanBodyPoseRequest()
    
    private var pendingLocation: CLLocation?
    private var pendingAspectRatio: CGFloat = 4.0/3.0
    
    let captureDidFinish = PassthroughSubject<Void, Never>()

    override init() {
        super.init()
        checkPermissions()
    }

    // MARK: - ZOOM LOGIC (Precision Mode)
    
    func setZoom(_ uiFactor: CGFloat) {
        sessionQueue.async {
            guard let device = self.activeDevice else { return }
            
            // MATH: UI 1.0 -> Native 2.0
            let nativeFactor = uiFactor * self.zoomScaler
            
            do {
                try device.lockForConfiguration()
                // Clamp to safe limits
                let clamped = max(device.minAvailableVideoZoomFactor, min(nativeFactor, device.maxAvailableVideoZoomFactor))
                device.ramp(toVideoZoomFactor: clamped, withRate: 5.0)
                device.unlockForConfiguration()
                
                DispatchQueue.main.async { self.currentZoomFactor = uiFactor }
            } catch {
                print("Zoom error: \(error)")
            }
        }
    }

    // MARK: - CAPTURE
    
    func capturePhoto(location: CLLocation?, aspectRatioValue: CGFloat) {
        AudioServicesPlaySystemSound(1108)
        pendingLocation = location
        pendingAspectRatio = aspectRatioValue
        
        sessionQueue.async {
            if let connection = self.photoOutput.connection(with: .video) {
                connection.videoOrientation = .portrait
            }
            let settings = AVCapturePhotoSettings()
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(), let originalImage = UIImage(data: data) else { return }
        let croppedImage = cropToRatio(originalImage, ratio: pendingAspectRatio)
        DispatchQueue.main.async { self.capturedImage = croppedImage }
        if let jpegData = croppedImage.jpegData(compressionQuality: 1.0) {
            saveToCustomAlbum(imageData: jpegData, location: pendingLocation)
        }
        DispatchQueue.main.async { self.captureDidFinish.send(()) }
    }
    
    private func cropToRatio(_ image: UIImage, ratio: CGFloat) -> UIImage {
        let w = image.size.width
        let h = image.size.height
        let currentRatio = w / h
        var newW = w
        var newH = h
        if currentRatio > ratio { newW = h * ratio } else { newH = w / ratio }
        let x = (w - newW) / 2.0
        let y = (h - newH) / 2.0
        guard let cg = image.cgImage?.cropping(to: CGRect(x: x, y: y, width: newW, height: newH)) else { return image }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }

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
                var placeholder: PHObjectPlaceholder?
                PHPhotoLibrary.shared().performChanges({
                    let req = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
                    placeholder = req.placeholderForCreatedAssetCollection
                }, completionHandler: { success, _ in
                    if success, let id = placeholder?.localIdentifier {
                        if let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject {
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
            guard let albumReq = PHAssetCollectionChangeRequest(for: album) else { return }
            albumReq.addAssets([req.placeholderForCreatedAsset!] as NSArray)
        }
    }

    // MARK: - HARDWARE SETUP (Forced 0.5x Base)

    private func setupCamera() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        
        // 1. FORCE TRIPLE CAMERA (The one with 0.5x base)
        let deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera]
        guard let device = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: .back).devices.first else {
            // Fallback for single lens phones (Scaling 1:1)
            setupStandardCamera()
            return
        }
        self.activeDevice = device
        
        // 2. SET SCALER TO 2.0
        // Because Native 1.0 is UltraWide, we need UI 1.0 to be Native 2.0
        self.zoomScaler = 2.0
        
        // 3. FORCE BUTTONS (Double check they are set)
        DispatchQueue.main.async {
            self.zoomButtons = [0.5, 1.0, 2.0, 4.0, 8.0]
            self.minZoomFactor = 0.5
            // Max native is often ~15. 15 / 2 = 7.5x UI max.
            self.maxZoomFactor = device.maxAvailableVideoZoomFactor / self.zoomScaler
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
            deviceInput = input
        } catch { print("Input Error: \(error)") }
        
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        videoOutput.connection(with: .video)?.videoOrientation = .portrait
        
        session.commitConfiguration()
        session.startRunning()
        
        // 4. Force Start at 1.0x (Main Wide)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.setZoom(1.0)
        }
    }
    
    // Fallback for non-Pro phones
    private func setupStandardCamera() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
        self.activeDevice = device
        self.zoomScaler = 1.0 // 1:1 mapping
        self.zoomButtons = [1.0, 2.0] // Simplified buttons
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
            deviceInput = input
        } catch { return }
        
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        videoOutput.connection(with: .video)?.videoOrientation = .portrait
        
        session.commitConfiguration()
        session.startRunning()
    }
    
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: sessionQueue.async { self.setupCamera() }
        default: AVCaptureDevice.requestAccess(for: .video) { if $0 { self.sessionQueue.async { self.setupCamera() } } }
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        try? handler.perform([bodyPoseRequest])
        DispatchQueue.main.async { self.isPersonDetected = (self.bodyPoseRequest.results?.first != nil) }
    }
    
    // Missing focus function restored
    func setFocus(point: CGPoint) {
        sessionQueue.async {
            guard let device = self.activeDevice else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = point
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = point
                    device.exposureMode = .autoExpose
                }
                device.unlockForConfiguration()
            } catch { print("Focus error: \(error)") }
        }
    }
}
