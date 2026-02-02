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
    let depthData: [[Float]]? // Normalized 0..1 depth map
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

    // Models
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

    private lazy var depthModel: VNCoreMLModel? = {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            let coreML = try DepthAnythingV2SmallF16(configuration: config).model
            return try VNCoreMLModel(for: coreML)
        } catch {
            print("⚠️ Failed to load DepthAnythingV2 model:", error)
            return nil
        }
    }()

    private var frameCounter: Int = 0
    private let detectEveryNFrames: Int = 2
    private var isBusy: Bool = false
    
    private let maxFacesToClassify: Int = 2
    private var labelBuffers: [UUID: RollingLabelBuffer] = [:]

    private var lastOutput: CameraAIOutput = .init(
        isPersonDetected: false,
        peopleCount: 0,
        expressions: [],
        nosePoint: nil,
        depthData: nil
    )

    var onOutputUpdated: ((CameraAIOutput) -> Void)?

    func process(pixelBuffer: CVPixelBuffer,
                 orientation: CGImagePropertyOrientation = .right,
                 isMirrored: Bool = false) {

        frameCounter += 1
        guard frameCounter % detectEveryNFrames == 0 else { return }
        guard !isBusy else { return }
        
        isBusy = true
        
        aiQueue.async { [weak self] in
            guard let self = self else { return }
            
            let output = autoreleasepool { () -> CameraAIOutput? in
                // 1. Vision Analysis (Faces, Poses)
                do {
                    try self.visionHandler.perform([self.poseRequest, self.faceRectRequest],
                                              on: pixelBuffer,
                                              orientation: orientation)
                } catch {
                    return nil
                }

                let poseObs = (self.poseRequest.results ?? [])
                let faces = (self.faceRectRequest.results as? [VNFaceObservation]) ?? []
                let peopleCount = max(poseObs.count, faces.count)

                var nosePoint: CGPoint? = nil
                if let primaryFace = faces.max(by: { self.area($0.boundingBox) < self.area($1.boundingBox) }) {
                    nosePoint = self.noseFromLandmarks(pixelBuffer: pixelBuffer, face: primaryFace, orientation: orientation, isMirrored: isMirrored) ??
                                self.noseFromBoundingBox(face: primaryFace, orientation: orientation, isMirrored: isMirrored)
                }

                if nosePoint == nil, let firstPose = poseObs.first {
                    nosePoint = self.noseFromBodyPose(pose: firstPose, orientation: orientation, isMirrored: isMirrored)
                }

                let exprs = self.classifyExpressions(pixelBuffer: pixelBuffer, faces: faces, orientation: orientation)

                // 2. Depth Analysis (Scenic Shot Suggestions)
                var depthMap: [[Float]]? = nil
                if let dModel = self.depthModel {
                    depthMap = self.runDepthModel(model: dModel, pixelBuffer: pixelBuffer, orientation: orientation)
                }

                return CameraAIOutput(isPersonDetected: peopleCount > 0,
                                            peopleCount: peopleCount,
                                            expressions: exprs,
                                            nosePoint: nosePoint,
                                            depthData: depthMap)
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

    private func runDepthModel(model: VNCoreMLModel, 
                               pixelBuffer: CVPixelBuffer, 
                               orientation: CGImagePropertyOrientation) -> [[Float]]? {
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .centerCrop
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        try? handler.perform([request])
        
        guard let observations = request.results as? [VNCoreMLFeatureValueObservation],
              let multiArray = observations.first?.featureValue.multiArrayValue else { return nil }
        
        // Convert MLMultiArray to a simpler 2D array for the Swarm to work with
        // DepthAnythingV2Small usually outputs something like 1x518x518 or similar
        let rows = multiArray.shape[1].intValue
        let cols = multiArray.shape[2].intValue
        
        var result = [[Float]](repeating: [Float](repeating: 0, count: cols), count: rows)
        
        for y in 0..<rows {
            for x in 0..<cols {
                let index = [0, y, x] as [NSNumber]
                result[y][x] = multiArray[index].floatValue
            }
        }
        
        return result
    }

    // MARK: - Coordinate helpers (Native Conversion)

    private func visionToPreview(_ vision: CGPoint, orientation: CGImagePropertyOrientation, isMirrored: Bool) -> CGPoint {
        var p = CGPoint(x: vision.x, y: 1.0 - vision.y)
        if orientation == .right { p = CGPoint(x: 1.0 - p.y, y: p.x) }
        if !isMirrored { p.x = 1.0 - p.x; p.y = 1.0 - p.y }
        return CGPoint(x: max(0, min(1, p.x)), y: max(0, min(1, p.y)))
    }

    private func noseFromBoundingBox(face: VNFaceObservation, orientation: CGImagePropertyOrientation, isMirrored: Bool) -> CGPoint? {
        let bb = face.boundingBox
        return visionToPreview(CGPoint(x: bb.midX, y: bb.minY + bb.height * 0.60), orientation: orientation, isMirrored: isMirrored)
    }

    private func noseFromLandmarks(pixelBuffer: CVPixelBuffer, face: VNFaceObservation, orientation: CGImagePropertyOrientation, isMirrored: Bool) -> CGPoint? {
        faceLandmarksRequest.inputFaceObservations = [face]
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        try? handler.perform([faceLandmarksRequest])
        guard let obs = faceLandmarksRequest.results?.first, let landmarks = obs.landmarks,
              let pts = landmarks.noseCrest?.normalizedPoints ?? landmarks.nose?.normalizedPoints,
              let tip = pts.max(by: { $0.y < $1.y }) else { return nil }
        let bb = obs.boundingBox
        return visionToPreview(CGPoint(x: bb.origin.x + tip.x * bb.size.width, y: bb.origin.y + tip.y * bb.size.height), orientation: orientation, isMirrored: isMirrored)
    }

    private func noseFromBodyPose(pose: VNHumanBodyPoseObservation, orientation: CGImagePropertyOrientation, isMirrored: Bool) -> CGPoint? {
        guard let nose = try? pose.recognizedPoint(.nose), nose.confidence > 0.2 else { return nil }
        return visionToPreview(nose.location, orientation: orientation, isMirrored: isMirrored)
    }

    private func classifyExpressions(pixelBuffer: CVPixelBuffer, faces: [VNFaceObservation], orientation: CGImagePropertyOrientation) -> [String] {
        guard let model = expressionModel, !faces.isEmpty else { return [] }
        let targets = Array(faces.sorted { area($0.boundingBox) > area($1.boundingBox) }.prefix(maxFacesToClassify))
        return targets.map { face in
            let request = VNCoreMLRequest(model: model)
            request.imageCropAndScaleOption = .centerCrop
            request.regionOfInterest = face.boundingBox
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
            try? handler.perform([request])
            guard let obs = request.results as? [VNClassificationObservation], let top = obs.first else { return "Neutral" }
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

    private func area(_ bb: CGRect) -> CGFloat { max(0, bb.width * bb.height) }
}
