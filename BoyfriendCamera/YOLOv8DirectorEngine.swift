import CoreML
import Vision
import CoreImage
import Combine
import SwiftUI

class YOLOv8DirectorEngine: ObservableObject {
    private var request: VNCoreMLRequest?
    
    // Published state for UI feedback
    @Published var detectedObjects: [VNRecognizedObjectObservation] = []
    @Published var directorCommand: String = "" // e.g., "Step back"

    init() {
        setupModel()
    }
    
    private func setupModel() {
        do {
            // Load the YOLOv8 model
            // Note: Ensure 'yolov8n.mlpackage' is added to your target in Xcode to auto-generate the class.
            let config = MLModelConfiguration()
            let model = try yolov8n(configuration: config) 
            
            guard let visionModel = try? VNCoreMLModel(for: model.model) else {
                print("Failed to create VNCoreMLModel")
                return
            }
            
            self.request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
                self?.handleDetections(request, error: error)
            }
            // YOLOv8 typically uses 640x640, fit behavior is crucial
            self.request?.imageCropAndScaleOption = .scaleFill
            
        } catch {
            print("Failed to load YOLOv8 model: \(error)")
        }
    }
    
    func analyze(pixelBuffer: CVPixelBuffer) {
        guard let request = self.request else { return }
        
        // Run on background thread to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("Failed to perform Vision request: \(error)")
            }
        }
    }
    
    private func handleDetections(_ request: VNRequest, error: Error?) {
        guard let results = request.results as? [VNRecognizedObjectObservation] else { return }
        
        DispatchQueue.main.async {
            self.detectedObjects = results
            self.generateDirectorFeedback(results)
        }
    }
    
    private func generateDirectorFeedback(_ observations: [VNRecognizedObjectObservation]) {
        // High-Level Logic: What should the user do based on objects?
        
        // Example 1: Detect if subject is too far (bounding box small)
        if let person = observations.first(where: { $0.labels.first?.identifier == "person" }) {
            let boxArea = person.boundingBox.width * person.boundingBox.height
            
            if boxArea < 0.1 {
                self.directorCommand = "Move Closer"
            } else if boxArea > 0.8 {
                self.directorCommand = "Step Back"
            } else {
                // Check centering
                let centerX = person.boundingBox.midX
                if centerX < 0.4 {
                    self.directorCommand = "Turn Right ->"
                } else if centerX > 0.6 {
                    self.directorCommand = "<- Turn Left"
                } else {
                    self.directorCommand = "Hold Steady"
                }
            }
        } else {
            self.directorCommand = "Searching for Subject..."
        }
    }
}
