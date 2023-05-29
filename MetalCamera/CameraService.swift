//
//  CameraService.swift
//  MetalCamera
//
//  Created by USER on 2023/05/29.
//

import AVFoundation
import Combine
import Foundation

final class CameraService: NSObject {
    // MARK: - Dependencies

    private let captureSession = AVCaptureSession()
    private let processingQueue = DispatchQueue(label: "CameraProcessingQueue", qos: .userInteractive)

    // MARK: - Properties

    @Published private var videoOutput: CVPixelBuffer?
    var videoOutputPublisher: AnyPublisher<CVPixelBuffer, Never> {
        $videoOutput.compactMap { $0 }.eraseToAnyPublisher()
    }

    // MARK: - Internal methods

    func start(with preset: AVCaptureSession.Preset) {
        Task {
            close()

            guard await checkAndRequestAuthorization() else { return }

            captureSession.beginConfiguration()
            captureSession.sessionPreset = preset

            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                  let videoInput = try? AVCaptureDeviceInput(device: camera),
                  captureSession.canAddInput(videoInput) else { return }
            captureSession.addInput(videoInput)

            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            guard captureSession.canAddOutput(videoOutput) else { return}
            captureSession.addOutput(videoOutput)

            captureSession.commitConfiguration()
            captureSession.startRunning()
            videoOutput.connection(with: .video)?.videoOrientation = .portrait
        }
    }

    func close() {
        captureSession.stopRunning()
    }

    // MARK: - Private Methods

    private func checkAndRequestAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted: return false
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { isGranted in
                    continuation.resume(returning: isGranted)
                }
            }
        default: return false
        }
    }
}

// MARK: - Extensions

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        videoOutput = CMSampleBufferGetImageBuffer(sampleBuffer)
    }
}
