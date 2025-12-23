import SwiftUI
import AVFoundation
import UIKit

struct CameraPreview: UIViewRepresentable {
    let cameraManager: CameraManager

    var onUserInteraction: (() -> Void)? = nil
    var onPreviewSizeChange: ((CGSize) -> Void)? = nil

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.session = cameraManager.session

        // Give CameraManager access to the previewLayer if you use it elsewhere
        cameraManager.previewLayer = view.videoPreviewLayer

        // Hook size callback
        view.onSizeChange = { size in
            onPreviewSizeChange?(size)
        }

        // Tap Gesture
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        view.addGestureRecognizer(tap)

        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject {
        var parent: CameraPreview
        init(_ parent: CameraPreview) { self.parent = parent }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            parent.onUserInteraction?()

            guard let view = gesture.view as? CameraPreviewView else { return }
            let point = gesture.location(in: view)

            // 1) Visual feedback
            view.showFocusBox(at: point)

            // 2) Convert & Focus
            let capturePoint = view.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: point)
            parent.cameraManager.setFocus(point: capturePoint)

            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

final class CameraPreviewView: UIView {
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    var onSizeChange: ((CGSize) -> Void)?

    var session: AVCaptureSession? {
        get { videoPreviewLayer.session }
        set { videoPreviewLayer.session = newValue }
    }

    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    override func layoutSubviews() {
        super.layoutSubviews()
        videoPreviewLayer.frame = bounds
        videoPreviewLayer.videoGravity = .resizeAspectFill
        onSizeChange?(bounds.size)
    }

    func showFocusBox(at point: CGPoint) {
        let box = UIView(frame: CGRect(x: 0, y: 0, width: 70, height: 70))
        box.center = point
        box.layer.borderWidth = 1.5
        box.layer.borderColor = UIColor.systemYellow.cgColor
        box.backgroundColor = UIColor.clear
        box.alpha = 0

        addSubview(box)

        box.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
        box.alpha = 1.0

        UIView.animate(withDuration: 0.25, animations: {
            box.transform = .identity
        }) { _ in
            UIView.animate(withDuration: 0.2, delay: 0.5, options: [], animations: {
                box.alpha = 0
            }) { _ in
                box.removeFromSuperview()
            }
        }
    }
}
