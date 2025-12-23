import Foundation
import Vision
import CoreML
import CoreImage
import ImageIO
import CoreGraphics

// MARK: - AI Output (RENAMED to avoid collisions)
struct CameraAIResult: Equatable {
    let isPersonDetected: Bool
    let peopleCount: Int
    let expressions: [String]

    // CaptureDevice coords: x 0...1 left->right, y 0...1 top->bottom
    let nosePoint: CGPoint?
}

// MARK: - Rolling label smoother
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

// MARK: - AI Engine
final class CameraAIEngine {

    // Vision requests
    private let poseRequest = VNDetectHumanBodyPoseRequest()
    private let faceLandmarksRequest = VNDetectFaceLandmarksRequest()
    private let visionHandler = VNSequenceRequestHandler()

    // CoreML model
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

    // Throttling
    private var frameCounter: Int = 0
    private let detectEveryNFrames: Int = 6

    private var emotionCounter: Int = 0
    private let emotionEveryNDetections: Int = 2

    private var isBusy: Bool = false

    // Limits
    private let maxFacesToClassify: Int = 2

    // Smoothing per face
    private var labelBuffers: [UUID: RollingLabelBuffer] = [:]

    // Cache last output
    private var lastOutput: CameraAIResult = .init(
        isPersonDetected: false,
        peopleCount: 0,
        expressions: [],
        nosePoint: nil
    )

    func process(pixelBuffer: CVPixelBuffer,
                 orientation: CGImagePropertyOrientation = .right,
                 isMirrored: Bool = false) -> CameraAIResult? {

        frameCounter += 1
        guard frameCounter % detectEveryNFrames == 0 else { return nil }
        guard !isBusy else { return nil }
        isBusy = true
        defer { isBusy = false }

        return autoreleasepool { () -> CameraAIResult? in
            do {
                try visionHandler.perform([poseRequest, faceLandmarksRequest],
                                          on: pixelBuffer,
                                          orientation: orientation)
            } catch {
                return nil
            }

            let poseCount = poseRequest.results?.count ?? 0
            let faces = (faceLandmarksRequest.results as? [VNFaceObservation]) ?? []
            let faceCount = faces.count

            let peopleCount = max(poseCount, faceCount)
            let isDetected = peopleCount > 0

            // Primary face = largest
            let primaryFace = faces.max(by: { area($0.boundingBox) < area($1.boundingBox) })

            // Nose point from landmarks (best effort)
            let nosePoint = primaryFace.flatMap { extractNosePoint(face: $0, isMirrored: isMirrored) }

            // Emotion (less frequently)
            var exprs: [String] = lastOutput.expressions
            emotionCounter += 1
            if emotionCounter % emotionEveryNDetections == 0 {
                exprs = classifyExpressions(pixelBuffer: pixelBuffer,
                                            faces: faces,
                                            orientation: orientation)
            }

            let output = CameraAIResult(
                isPersonDetected: isDetected,
                peopleCount: peopleCount,
                expressions: exprs,
                nosePoint: nosePoint
            )

            if output != lastOutput {
                lastOutput = output
                return output
            } else {
                return nil
            }
        }
    }

    // MARK: - Nose extraction (landmarks -> image norm -> captureDevice point)
    private func extractNosePoint(face: VNFaceObservation, isMirrored: Bool) -> CGPoint? {
        guard let lm = face.landmarks else { return nil }

        // Try the most reliable regions first
        let region =
            lm.noseCrest ??
            lm.nose ??
            lm.medianLine

        guard let reg = region else { return nil }
        let pts = reg.normalizedPoints
        guard !pts.isEmpty else { return nil }

        // Average landmark points in face-local coords (0..1)
        var sx: CGFloat = 0
        var sy: CGFloat = 0
        for p in pts { sx += p.x; sy += p.y }
        let ax = sx / CGFloat(pts.count)
        let ay = sy / CGFloat(pts.count)

        // Convert face-local coords into image-normalized coords (Vision bb origin is bottom-left)
        let bb = face.boundingBox
        let xImg = bb.origin.x + ax * bb.size.width
        let yImg = bb.origin.y + ay * bb.size.height

        // Convert to captureDevice coords (top-left origin)
        var deviceP = CGPoint(x: xImg, y: 1.0 - yImg)

        // Front camera preview is mirrored; Vision results are not.
        if isMirrored { deviceP.x = 1.0 - deviceP.x }

        // Clamp to safe range
        deviceP.x = max(0, min(1, deviceP.x))
        deviceP.y = max(0, min(1, deviceP.y))

        return deviceP
    }

    // MARK: - Expression inference
    private func classifyExpressions(pixelBuffer: CVPixelBuffer,
                                     faces: [VNFaceObservation],
                                     orientation: CGImagePropertyOrientation) -> [String] {

        guard !faces.isEmpty else { return [] }
        guard let model = expressionModel else {
            return Array(repeating: "Unknown", count: min(faces.count, maxFacesToClassify))
        }

        let targets = faces.sorted { area($0.boundingBox) > area($1.boundingBox) }
        let chosen = Array(targets.prefix(maxFacesToClassify))

        var results: [String] = []
        for face in chosen {
            let (rawLabel, conf) = runEmotionModel(model: model,
                                                  pixelBuffer: pixelBuffer,
                                                  roi: face.boundingBox,
                                                  orientation: orientation)

            let normalized = normalizeLabel(rawLabel, confidence: conf)

            let id = face.uuid
            let buf = labelBuffers[id] ?? RollingLabelBuffer(size: 7)
            buf.push(normalized)
            labelBuffers[id] = buf

            results.append(buf.mode())
        }

        if labelBuffers.count > 16 {
            labelBuffers = Dictionary(uniqueKeysWithValues: Array(labelBuffers.prefix(12)))
        }

        return results
    }

    private func runEmotionModel(model: VNCoreMLModel,
                                 pixelBuffer: CVPixelBuffer,
                                 roi: CGRect,
                                 orientation: CGImagePropertyOrientation) -> (String, Float) {

        var bestLabel = "Unknown"
        var bestConf: Float = 0

        let request = VNCoreMLRequest(model: model) { req, _ in
            guard let obs = req.results as? [VNClassificationObservation],
                  let top = obs.first else { return }
            bestLabel = top.identifier
            bestConf = top.confidence
        }

        request.imageCropAndScaleOption = .centerCrop
        request.regionOfInterest = roi

        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                orientation: orientation,
                                                options: [:])
            try handler.perform([request])
        } catch {
            return ("Unknown", 0)
        }

        return (bestLabel, bestConf)
    }

    private func normalizeLabel(_ raw: String, confidence: Float) -> String {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if confidence < 0.60 { return "Neutral" }

        if id.contains("happy") { return "Happy" }
        if id.contains("neutral") { return "Neutral" }
        if id.contains("surpris") { return "Surprised" }
        if id.contains("ang") { return "Angry" }
        if id.contains("sad") { return "Sad" }
        if id.contains("fear") { return "Fear" }
        if id.contains("disgust") { return "Disgust" }

        return raw.capitalized
    }

    private func area(_ bb: CGRect) -> CGFloat {
        max(0, bb.width * bb.height)
    }
}
