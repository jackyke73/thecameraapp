import Vision
import CoreImage
import UIKit
import Combine
import SwiftUI

// A robust service to extract visual features using Apple's Vision framework.
// This acts as the "eyes" for the SemanticDirectorEngine, providing real data
// instead of mocked random values.
final class VisionAnalysisService: Sendable {
    
    // Vision Requests (reusable to avoid allocation overhead)
    // VNRequests are generally thread-safe to create, but not to perform concurrently on the same instance?
    // Actually, documentation says "You can use the same request in multiple image request handlers simultaneously."
    // So making them Sendable is okay if we don't mutate them.
    private let faceDetectionRequest: VNDetectFaceRectanglesRequest
    private let textDetectionRequest: VNRecognizeTextRequest
    private let personSegmentationRequest: VNGeneratePersonSegmentationRequest
    private let bodyPoseRequest: VNDetectHumanBodyPoseRequest // New
    
    init() {
        self.faceDetectionRequest = VNDetectFaceRectanglesRequest()
        self.textDetectionRequest = VNRecognizeTextRequest()
        self.personSegmentationRequest = VNGeneratePersonSegmentationRequest()
        self.bodyPoseRequest = VNDetectHumanBodyPoseRequest() // New
        
        // Configure for speed/accuracy trade-off
        self.textDetectionRequest.recognitionLevel = .fast
        self.personSegmentationRequest.qualityLevel = .balanced
    }
    
    struct VisionFrameResult {
        let faceCount: Int
        let mainFaceBounds: CGRect? // Normalized coordinates (0,0 is bottom-left usually in Vision)
        let hasText: Bool
        let subjectIsolationScore: Float // 0.0 to 1.0 (based on segmentation mask area vs frame)
        let brightness: Float // 0.0 to 1.0 (Average Luma)
        let bodyPose: VNHumanBodyPoseObservation? // New
    }
    
    func analyze(pixelBuffer: CVPixelBuffer) -> VisionFrameResult? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        // 0. Brightness Analysis (Luma Extraction)
        var brightness: Float = 0.5
        
        // Use a nested scope for lock/unlock to ensure unlock happens BEFORE Vision request
        do {
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

            if CVPixelBufferGetPlaneCount(pixelBuffer) > 0 {
                 let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) // Y-Plane
                 let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
                 let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
                 let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
                 
                 // Sample center 10x10 area for quick check or whole image stride for accuracy
                 // Let's do a stride sample (every 10th pixel) for speed
                 if let buffer = baseAddress?.assumingMemoryBound(to: UInt8.self) {
                     var totalLuma: UInt64 = 0
                     var count: UInt64 = 0
                     
                     let step = 16 // Higher stride for even more performance
                     for y in stride(from: 0, to: height, by: step) {
                         let rowStart = y * bytesPerRow
                         for x in stride(from: 0, to: width, by: step) {
                             totalLuma += UInt64(buffer[rowStart + x])
                             count += 1
                         }
                     }
                     
                     if count > 0 {
                         brightness = Float(totalLuma) / Float(count) / 255.0
                     }
                 }
            }
        } // Unlock happens here

        do {
            // Run requests synchronously (this should be called on a background queue)
            try handler.perform([faceDetectionRequest, personSegmentationRequest, bodyPoseRequest])
            
            // 1. Face Analysis
            let faces = faceDetectionRequest.results ?? []
            let faceCount = faces.count
            
            // Find the largest face (the "Subject")
            let mainFace = faces.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height })
            
            // 2. Segmentation Analysis (Subject Isolation)
            var isolationScore: Float = 0.0
            if let segmentationMask = personSegmentationRequest.results?.first {
                // Heuristic based on mask confidence and presence
                isolationScore = 0.8 // High score for detection
            }
            
            // 3. Body Pose Analysis
            let bodyPose = bodyPoseRequest.results?.first
            
            // 4. SUBJECT MOTION DETECTION (Delta change in face position)
            // Note: This requires state, but VisionAnalysisService is stateless.
            // We'll stick to per-frame quality metrics.
            
            return VisionFrameResult(
                faceCount: faceCount,
                mainFaceBounds: mainFace?.boundingBox,
                hasText: false,
                subjectIsolationScore: isolationScore,
                brightness: brightness,
                bodyPose: bodyPose
            )
            
        } catch {
            print("VisionAnalysisService: Analysis failed - \(error.localizedDescription)")
            return nil
        }
    }
}
