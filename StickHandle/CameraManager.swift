//
//  CameraManager.swift
//  StickHandle
//
//  Created by Tyson on 3/4/26.
//

/// Input: None (starts camera session on initialization)
/// Transformation: Manages AVCaptureSession, captures video frames from back camera, converts frames to CVPixelBuffer for processing
/// Output: Publishes video frames as CVPixelBuffer through Combine publisher for Vision processing

import AVFoundation
import Combine
import UIKit

/// Manages the camera session and provides video frames for processing
/// Similar to navigator.mediaDevices.getUserMedia() in JavaScript
@MainActor
class CameraManager: NSObject, ObservableObject {
    
    // Published property that other components can subscribe to
    // Like a React Context value or RxJS Subject
    @Published var error: CameraError?
    
    // Combine subject to publish each video frame
    // Like an RxJS BehaviorSubject
    nonisolated(unsafe) private let framePublisher = PassthroughSubject<CVPixelBuffer, Never>()
    
    // Expose as a regular Publisher (read-only)
    // Use receive(on:) to ensure frames are delivered on main thread
    var frames: AnyPublisher<CVPixelBuffer, Never> {
        framePublisher
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    nonisolated(unsafe) private let captureSession = AVCaptureSession()
    nonisolated(unsafe) private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated(unsafe) private let sessionQueue = DispatchQueue(label: "com.stickhandle.camera")
    
    // Permission status
    @Published var isAuthorized = false
    
    override init() {
        super.init()
    }
    
    /// Request camera permission and setup the camera session
    func requestAccess() async {
        // Check camera permission (like asking for navigator permissions in web)
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            await setupCamera()
            
        case .notDetermined:
            // Request permission
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                await setupCamera()
            } else {
                self.error = .permissionDenied
            }
            
        case .denied, .restricted:
            self.error = .permissionDenied
            
        @unknown default:
            self.error = .permissionDenied
        }
    }
    
    /// Configure the camera session with back camera and video output
    nonisolated private func setupCamera() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                // Get the back camera (wide angle lens)
                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                    Task { @MainActor [weak self] in
                        await self?.setError(.cameraUnavailable)
                        continuation.resume()
                    }
                    return
                }
                
                do {
                    // Create input from camera
                    let input = try AVCaptureDeviceInput(device: camera)
                    
                    // Configure session
                    self.captureSession.beginConfiguration()
                    
                    // Set session preset for quality (720p is good balance of quality and performance)
                    self.captureSession.sessionPreset = .hd1280x720
                    
                    // Add camera input
                    if self.captureSession.canAddInput(input) {
                        self.captureSession.addInput(input)
                    }
                    
                    // Configure video output
                    self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
                    self.videoOutput.alwaysDiscardsLateVideoFrames = true
                    self.videoOutput.videoSettings = [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                    ]
                    
                    // Add video output
                    if self.captureSession.canAddOutput(self.videoOutput) {
                        self.captureSession.addOutput(self.videoOutput)
                    }
                    
                    // Set video orientation
                    if let connection = self.videoOutput.connection(with: .video) {
                        connection.videoOrientation = .portrait
                    }
                    
                    self.captureSession.commitConfiguration()
                    
                    Task { @MainActor [weak self] in
                        await self?.setAuthorized(true)
                        continuation.resume()
                    }
                    
                } catch {
                    Task { @MainActor [weak self] in
                        await self?.setError(.configurationFailed)
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    // Helper methods to set published properties - these are @MainActor isolated
    private func setError(_ error: CameraError) {
        self.error = error
    }
    
    private func setAuthorized(_ authorized: Bool) {
        self.isAuthorized = authorized
    }
    
    /// Start the camera session
    nonisolated func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
        }
    }
    
    /// Stop the camera session
    nonisolated func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
        }
    }
    
    /// Get the capture session for preview layer (used by the view)
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer {
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        // Use .resizeAspect to show the full camera frame without cropping
        // This ensures tracking coordinates match what's visible in the preview
        previewLayer.videoGravity = .resizeAspect
        return previewLayer
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    /// Called for each video frame captured
    /// Similar to requestAnimationFrame() callback in JavaScript
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        // Extract the pixel buffer from the sample buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        // Publish the frame for processing
        framePublisher.send(pixelBuffer)
    }
}

// MARK: - Error Types
enum CameraError: LocalizedError {
    case permissionDenied
    case cameraUnavailable
    case configurationFailed
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera permission denied. Please enable camera access in Settings."
        case .cameraUnavailable:
            return "Camera is not available on this device."
        case .configurationFailed:
            return "Failed to configure camera."
        }
    }
}
