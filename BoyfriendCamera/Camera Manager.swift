import AVFoundation
import SwiftUI
import Combine
import Vision // <--- The AI Framework

class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var permissionGranted = false
    @Published var isPersonDetected = false // <--- Logic to tell UI if we see a human
    
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "cameraQueue")
    private let videoOutput = AVCaptureVideoDataOutput() // <--- The "Reader" that grabs frames
    
    // The AI Request to find bodies
    private let bodyPoseRequest = VNDetectHumanBodyPoseRequest()
    
    override init() {
        super.init()
        checkPermissions()
    }
    
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
            DispatchQueue.main.async { self.permissionGranted = true }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.setupCamera()
                    DispatchQueue.main.async { self.permissionGranted = true }
                }
            }
        case .denied, .restricted:
            print("User denied camera permission")
        @unknown default:
            break
        }
    }
    
    private func setupCamera() {
        sessionQueue.async {
            self.session.beginConfiguration()
            
            // 1. Input (Camera)
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                print("No back camera found")
                self.session.commitConfiguration()
                return
            }
            
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
            } catch {
                print("Error connecting camera: \(error.localizedDescription)")
                self.session.commitConfiguration()
                return
            }
            
            // 2. Output (Frame Reader) - THIS IS NEW
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
                // We process video on a separate background thread so the UI doesn't lag
                let videoQueue = DispatchQueue(label: "videoQueue")
                self.videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
                self.videoOutput.alwaysDiscardsLateVideoFrames = true // If computer is slow, drop old frames
            }
            
            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }
    
    // MARK: - The "Loop" that runs 30 times a second
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // 1. Convert the weird video data into a standard image buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // 2. Run the AI Request
        // Note: '.right' is usually the correct orientation for the back camera in portrait mode
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        
        do {
            try handler.perform([bodyPoseRequest])
            
            // 3. Check if we found anyone
            if let result = bodyPoseRequest.results?.first {
                // We found a body!
                DispatchQueue.main.async {
                    // Only update if the state changed (saves battery)
                    if !self.isPersonDetected { self.isPersonDetected = true }
                }
            } else {
                // No body found
                DispatchQueue.main.async {
                    if self.isPersonDetected { self.isPersonDetected = false }
                }
            }
        } catch {
            print("Vision error: \(error.localizedDescription)")
        }
    }
}
