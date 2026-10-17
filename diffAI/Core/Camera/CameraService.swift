import AVFoundation
import Combine
import SwiftUI
import UIKit

enum CameraError: Error {
    case unavailable
}

/// Live back-camera capture. On the Simulator there is no camera: start() returns false
/// and the screen falls back to the photo picker and sample photos.
@MainActor
final class CameraService: NSObject, ObservableObject {
    let session = AVCaptureSession()

    private let photoOutput = AVCapturePhotoOutput()
    private var isConfigured = false
    private var captureContinuation: CheckedContinuation<UIImage?, Never>?

    /// True when this device has a back camera at all.
    static var deviceHasCamera: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    /// Asks for permission if needed, then starts the session and waits until it is running.
    /// Returns false when the camera cannot be used.
    func start() async -> Bool {
        guard Self.deviceHasCamera else { return false }
        var status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
            status = AVCaptureDevice.authorizationStatus(for: .video)
        }
        guard status == .authorized else { return false }

        if !isConfigured {
            do {
                try configure()
            } catch {
                return false
            }
        }
        let session = self.session
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                if !session.isRunning {
                    session.startRunning()
                }
                continuation.resume()
            }
        }
        return session.isRunning
    }

    func stop() {
        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    /// Takes one still photo. Returns nil if the camera is not ready, a capture is already in progress, or it fails.
    func capture() async -> UIImage? {
        guard captureContinuation == nil,
              session.isRunning,
              photoOutput.connection(with: .video)?.isActive == true else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            captureContinuation = continuation
            photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    private func configure() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.unavailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(photoOutput) else {
            throw CameraError.unavailable
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        isConfigured = true
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image: UIImage? = error == nil ? photo.fileDataRepresentation().flatMap { UIImage(data: $0) } : nil
        Task { @MainActor in
            self.captureContinuation?.resume(returning: image)
            self.captureContinuation = nil
        }
    }
}

/// Shows the live camera feed. Hidden from VoiceOver, because the screen describes what to do instead.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
