import Foundation
import Vision
import CoreML
import CoreImage
import ImageIO
import CoreGraphics

struct CameraAIOutput: Equatable {
    let isPersonDetected: Bool
    let peopleCount: Int
    let expressions: [String]
    let nosePoint: CGPoint?
}

final class RollingLabelBuffer {
    private let size: Int
    private var arr: [String] = []
    init(size: Int) { self.size = max(3, size) }

    func push(_ s: String) {
        arr.append(s)
        if arr.count > size { arr.removeFirst(arr.count - size) }
    }
    func mode() -> String {
        guard !arr.isEmpty else { return "Neutral" }
        var counts: [String: Int] = [:]
        for s in arr { counts[s, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key ?? (arr.last ?? "Neutral")
    }
}

final class CameraAIEngine {
    // Queues
    private let aiQueue = DispatchQueue(label: "com.thecameraapp.aiQueue", qos: .userInteractive)
    
    // Requests
    private let poseRequest = VNDetectHumanBodyPoseRequest()
    private let faceRectRequest = VNDetectFaceRectanglesRequest()
    private let faceLandmarksRequest = VNDetectFaceLandmarksRequest()
    private let visionHandler = VNSequenceRequestHandler()

    private lazy var expressionModel: VNCoreMLModel? = {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            let coreML = try CNNEmotions_2(configuration: config).model
            return try VNCoreMLModel(for: coreML)
        } catch {
            print("⚠️ Failed to load CNNEmotions model:", error)
            return nil
        }
    }()

    private var frameCounter: Int = 0
    private let detectEveryNFrames: Int = 2 // Reduced frequency for performance
    private var isBusy: Bool = false
    
    private let maxFacesToClassify: Int = 2
    private var labelBuffers: [UUID: RollingLabelBuffer] = [:]

    private var lastOutput: CameraAIOutput = .init(
        isPersonDetected: false,
        peopleCount: 0,
        expressions: [],
        nosePoint: nil
    )

    // Completion handler for async updates
    var onOutputUpdated: ((CameraAIOutput) -> Void)?

    func process(pixelBuffer: CVPixelBuffer,
                 orientation: CGImagePropertyOrientation = .right,
                 isMirrored: Bool = false) {

        frameCounter += 1
        guard frameCounter % detectEveryNFrames == 0 else { return }
        guard !isBusy else { return }
        
        isBusy = true
        
        // Background AI processing
        aiQueue.async { [weak self] in
            guard let self = self else { return }
            
            let output = autoreleasepool { () -> CameraAIOutput? in
                do {
                    try self.visionHandler.perform([self.poseRequest, self.faceRectRequest],
                                              on: pixelBuffer,
                                              orientation: orientation)
                } catch {
                    return nil
                }

                let poseObs = (self.poseRequest.results ?? [])
                let faces = (self.faceRectRequest.results as? [VNFaceObservation]) ?? []

                let poseCount = poseObs.count
                let faceCount = faces.count
                let peopleCount = max(poseCount, faceCount)
                let isDetected = peopleCount > 0

                let primaryFace = faces.max(by: { self.area($0.boundingBox) < self.area($1.boundingBox) })

                var nosePoint: CGPoint? = nil
                if let primaryFace {
                    if let p = self.noseFromLandmarks(pixelBuffer: pixelBuffer,
                                                 face: primaryFace,
                                                 orientation: orientation,
                                                 isMirrored: isMirrored) {
                        nosePoint = p
                    } else {
                        nosePoint = self.noseFromBoundingBox(face: primaryFace,
                                                        orientation: orientation,
                                                        isMirrored: isMirrored)
                    }
                }

                if nosePoint == nil, let firstPose = poseObs.first {
                    nosePoint = self.noseFromBodyPose(pose: firstPose,
                                                 orientation: orientation,
                                                 isMirrored: isMirrored)
                }

                // Simplified expressions - classify every frame we process AI for now
                let exprs = self.classifyExpressions(pixelBuffer: pixelBuffer,
                                                faces: faces,
                                                orientation: orientation)

                return CameraAIOutput(isPersonDetected: isDetected,
                                            peopleCount: peopleCount,
                                            expressions: exprs,
                                            nosePoint: nosePoint)
            }

            DispatchQueue.main.async {
                if let output = output {
                    self.lastOutput = output
                    self.onOutputUpdated?(output)
                }
                self.isBusy = false
            }
        }
    }

    // MARK: - Coordinate helpers (Native Conversion Preferred)

    private func visionToPreview(_ vision: CGPoint, orientation: CGImagePropertyOrientation, isMirrored: Bool) -> CGPoint {
        // Vision: (0,0) is bottom-left
        // UI: (0,0) is top-left
        var p = CGPoint(x: vision.x, y: 1.0 - vision.y)
        
        // Handle .right orientation (standard camera)
        if orientation == .right {
            p = CGPoint(x: 1.0 - p.y, y: p.x)
        }
        
        if !isMirrored {
            p.x = 1.0 - p.x
            p.y = 1.0 - p.y
        } else {
            // Selfies are already mirrored horizontally by AVCapture
        }
        
        return CGPoint(x: max(0, min(1, p.x)), y: max(0, min(1, p.y)))
    }

    private func noseFromBoundingBox(face: VNFaceObservation,
                                     orientation: CGImagePropertyOrientation,
                                     isMirrored: Bool) -> CGPoint? {
        let bb = face.boundingBox
        let noseVision = CGPoint(x: bb.midX, y: bb.minY + bb.height * 0.60)
        return visionToPreview(noseVision, orientation: orientation, isMirrored: isMirrored)
    }

    private func noseFromLandmarks(pixelBuffer: CVPixelBuffer,
                                   face: VNFaceObservation,
                                   orientation: CGImagePropertyOrientation,
                                   isMirrored: Bool) -> CGPoint? {

        faceLandmarksRequest.inputFaceObservations = [face]
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        try? handler.perform([faceLandmarksRequest])

        guard let obs = faceLandmarksRequest.results?.first,
              let landmarks = obs.landmarks,
              let pts = landmarks.noseCrest?.normalizedPoints ?? landmarks.nose?.normalizedPoints,
              let tip = pts.max(by: { $0.y < $1.y }) else { return nil }

        let bb = obs.boundingBox
        let visionX = bb.origin.x + tip.x * bb.size.width
        let visionY = bb.origin.y + tip.y * bb.size.height

        return visionToPreview(CGPoint(x: visionX, y: visionY), orientation: orientation, isMirrored: isMirrored)
    }

    private func noseFromBodyPose(pose: VNHumanBodyPoseObservation,
                                  orientation: CGImagePropertyOrientation,
                                  isMirrored: Bool) -> CGPoint? {
        guard let nose = try? pose.recognizedPoint(.nose), nose.confidence > 0.2 else { return nil }
        return visionToPreview(nose.location, orientation: orientation, isMirrored: isMirrored)
    }

    private func classifyExpressions(pixelBuffer: CVPixelBuffer,
                                     faces: [VNFaceObservation],
                                     orientation: CGImagePropertyOrientation) -> [String] {

        guard let model = expressionModel, !faces.isEmpty else { return [] }
        let targets = Array(faces.sorted { area($0.boundingBox) > area($1.boundingBox) }.prefix(maxFacesToClassify))

        return targets.map { face in
            let request = VNCoreMLRequest(model: model)
            request.imageCropAndScaleOption = .centerCrop
            request.regionOfInterest = face.boundingBox

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
            try? handler.perform([request])

            guard let obs = request.results as? [VNClassificationObservation],
                  let top = obs.first else { return "Neutral" }
            
            let normalized = normalizeLabel(top.identifier, confidence: top.confidence)
            let buf = labelBuffers[face.uuid] ?? RollingLabelBuffer(size: 7)
            buf.push(normalized)
            labelBuffers[face.uuid] = buf
            return buf.mode()
        }
    }

    private func normalizeLabel(_ raw: String, confidence: Float) -> String {
        if confidence < 0.60 { return "Neutral" }
        let id = raw.lowercased()
        if id.contains("happy") { return "Happy" }
        if id.contains("surpris") { return "Surprised" }
        if id.contains("ang") { return "Angry" }
        if id.contains("sad") { return "Sad" }
        return "Neutral"
    }

    private func area(_ bb: CGRect) -> CGFloat {
        max(0, bb.width * bb.height)
    }
}
