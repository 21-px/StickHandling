# CameraManager.swift

## Purpose
Manages the device camera session using AVFoundation, captures video frames, and provides them to the puck tracking system. Acts as the camera abstraction layer.

## What It Does

### Input
- Hardware back camera
- User permission for camera access

### Transformation
1. **Permission Handling**: Requests and manages camera authorization
2. **Session Configuration**: Sets up AVCaptureSession with optimal settings
3. **Frame Capture**: Captures video frames at 720p resolution
4. **Frame Publishing**: Delivers frames via Combine publisher
5. **Preview Layer**: Provides preview layer for SwiftUI display

### Output
- Stream of `CVPixelBuffer` frames (720p, 30fps)
- `AVCaptureVideoPreviewLayer` for UI display
- Camera permission status
- Error states

## Architecture

### Observable Object
```swift
@MainActor
class CameraManager: NSObject, ObservableObject
```
- Main actor isolated for thread safety
- SwiftUI-compatible via `ObservableObject`
- Subclass of `NSObject` for delegate conformance

### Combine Publisher
```swift
private let framePublisher = PassthroughSubject<CVPixelBuffer, Never>()

var frames: AnyPublisher<CVPixelBuffer, Never> {
    framePublisher
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
}
```

**Pattern:** Hot observable (like RxJS Subject)
- Publishes frames as they arrive
- Delivers on main thread for SwiftUI compatibility
- Never errors (fire-and-forget)

## Camera Configuration

### Session Settings
```swift
sessionPreset: .hd1280x720
```
**Resolution:** 1280×720 pixels (720p)

**Why 720p?**
- Good balance of quality and performance
- Sufficient detail for color-based tracking
- Lower processing overhead than 1080p
- ~2× faster than full resolution

### Pixel Format
```swift
videoSettings: [
    kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
]
```
**Format:** 32-bit BGRA (Blue, Green, Red, Alpha)

**Why BGRA?**
- Native format for Core Image filters
- No conversion overhead
- GPU-friendly
- Standard for iOS video processing

### Hardware Setup
```swift
AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
```
**Camera:** Back-facing wide-angle lens

**Characteristics:**
- Wider field of view than telephoto
- Better for tracking moving objects
- Standard on all iPhones

### Frame Rate
Default: 30 fps (frames per second)
- Smooth for visual tracking
- Standard for video capture
- Balances performance and battery

## Orientation Locking

### Critical Feature
```swift
connection.videoOrientation = .portrait
```
**Locked to portrait** - Does NOT rotate with device

**Why?**
1. Mimics ARKit behavior (camera feed stays fixed)
2. Prevents coordinate system confusion
3. Avoids flash/flicker during rotation
4. Simplifies coordinate transformations

**Effect:**
- Camera feed always in same orientation
- Only UI overlays rotate
- Tracking coordinates remain consistent

### Preview Layer Lock
```swift
previewLayer.connection?.videoOrientation = .portrait
```
Preview layer also locked to prevent rotation artifacts.

## Permission Handling

### Authorization States
```swift
enum AVAuthorizationStatus {
    case authorized      // Permission granted
    case notDetermined   // Never asked
    case denied          // User denied
    case restricted      // Parental controls, MDM
}
```

### Permission Flow
```swift
func requestAccess() async {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    
    switch status {
    case .authorized:
        await setupCamera()
        
    case .notDetermined:
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        if granted {
            await setupCamera()
        }
        
    case .denied, .restricted:
        self.error = .permissionDenied
    }
}
```

**First Launch:**
1. Check status → `.notDetermined`
2. Request permission → System alert
3. User grants → Setup camera
4. User denies → Show error

**Subsequent Launches:**
1. Check status → `.authorized` or `.denied`
2. Setup camera or show error

## Frame Capture Pipeline

### Delegate Pattern
```swift
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    )
}
```

**Flow:**
1. Camera captures frame → Sample buffer
2. Delegate callback → Extract pixel buffer
3. Publish frame → Subscribers receive
4. Process frame → Puck detection

### Frame Processing Queue
```swift
private let sessionQueue = DispatchQueue(label: "com.stickhandle.camera")
```
**Quality of Service:** `.userInitiated` (implied)

**Purpose:**
- Isolates camera operations from main thread
- Prevents UI blocking during setup/teardown
- Smooth frame capture without stuttering

### Delivery Queue
```swift
framePublisher.receive(on: DispatchQueue.main)
```
Ensures frames arrive on main thread for SwiftUI updates.

## Session Lifecycle

### Startup
```swift
func startSession() {
    sessionQueue.async {
        guard !self.captureSession.isRunning else { return }
        self.captureSession.startRunning()
    }
}
```
- Async to avoid blocking caller
- Guards against double-start
- Runs on background queue

### Shutdown
```swift
func stopSession() {
    sessionQueue.async {
        guard self.captureSession.isRunning else { return }
        self.captureSession.stopRunning()
    }
}
```
- Called on view disappear
- Releases camera for other apps
- Saves battery when not in use

### Configuration
```swift
captureSession.beginConfiguration()
// ... add inputs/outputs ...
captureSession.commitConfiguration()
```
Batches changes for atomic application.

## Preview Layer Management

### Lazy Creation
```swift
func getPreviewLayer() -> AVCaptureVideoPreviewLayer {
    if let existingLayer = previewLayer {
        return existingLayer
    }
    
    let newPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
    newPreviewLayer.videoGravity = .resizeAspectFill
    previewLayer = newPreviewLayer
    return newPreviewLayer
}
```

**Singleton Pattern:**
- Creates layer once
- Reuses on subsequent calls
- Avoids multiple layer instances

### Video Gravity
```swift
.videoGravity = .resizeAspectFill
```

**Options:**
- `.resizeAspectFill`: Fill screen, crop to fit (chosen)
- `.resizeAspect`: Fit with letterboxing
- `.resize`: Stretch to fill (distorted)

**Why AspectFill?**
- Edge-to-edge display (immersive)
- No black bars
- Matches ARKit appearance

## Published State

### Properties
```swift
@Published var error: CameraError?
@Published var previewLayerSize: CGSize = .zero
@Published var isAuthorized = false
```

**Usage:**
- `error`: Show alert to user
- `previewLayerSize`: Align debug mask overlay
- `isAuthorized`: Conditional camera start

### Error Types
```swift
enum CameraError: LocalizedError {
    case permissionDenied
    case cameraUnavailable
    case configurationFailed
    
    var errorDescription: String? { ... }
}
```

## Thread Safety

### Actor Isolation
```swift
@MainActor
class CameraManager
```
Main actor ensures published properties are always updated on main thread.

### Unsafe Access
```swift
nonisolated(unsafe) private let captureSession = AVCaptureSession()
nonisolated(unsafe) private let sessionQueue = DispatchQueue(...)
```

**Why unsafe?**
- AVFoundation objects are thread-safe
- Need to access from background queue
- Avoid actor reentrancy issues

### Safe Published Updates
```swift
private func setError(_ error: CameraError) {
    self.error = error  // MainActor isolated
}

Task { @MainActor [weak self] in
    await self?.setError(.configurationFailed)
}
```

## Usage Example

### In SwiftUI View
```swift
struct CameraView: View {
    @StateObject private var cameraManager = CameraManager()
    
    var body: some View {
        CameraPreview(cameraManager: cameraManager)
            .task {
                await cameraManager.requestAccess()
                if cameraManager.isAuthorized {
                    cameraManager.startSession()
                }
            }
            .onReceive(cameraManager.frames) { frame in
                // Process frame
                puckTracker.processFrame(frame)
            }
            .onDisappear {
                cameraManager.stopSession()
            }
    }
}
```

### Preview Layer Wrapping
```swift
struct CameraPreview: UIViewRepresentable {
    let cameraManager: CameraManager
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let previewLayer = cameraManager.getPreviewLayer()
        view.layer.addSublayer(previewLayer)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        previewLayer?.frame = uiView.bounds
    }
}
```

## Performance Characteristics

### Frame Rate
- Target: 30 fps
- Typical: 28-30 fps (depending on device)
- Can drop to ~20 fps under heavy load

### Latency
- Capture to delivery: ~33ms (1 frame at 30fps)
- Processing pipeline adds ~16-50ms
- Total latency: ~50-80ms

### Resource Usage
- CPU: ~5-10% (capture only)
- GPU: Minimal (format is native)
- Battery: ~100mW (typical for 720p capture)

## Optimization Techniques

### Frame Dropping
```swift
videoOutput.alwaysDiscardsLateVideoFrames = true
```
Drops frames if processing can't keep up (prevents backlog).

### Efficient Buffer Handling
- Direct `CVPixelBuffer` access (no copy)
- Reused buffers from camera pool
- Zero-copy publishing via Combine

### Background Processing
- Camera queue prevents main thread blocking
- Frame processing happens in PuckTracker's queue
- Only UI updates touch main thread

## Limitations & Edge Cases

### Device Compatibility
- Requires back camera (all iPhones have this)
- Some iPads only have front camera (unsupported)
- Simulators have no real camera (testing limited)

### Permission Edge Cases
- User can revoke permission in Settings → Requires app restart
- Screen recording affects preview (shows recording banner)
- Siri/Control Center can interrupt session

### Session Interruptions
- Phone calls pause the session
- Background apps (Siri, Spotlight) interrupt
- Need to handle `AVCaptureSessionWasInterrupted` notification (future)

## Related Files
- `PuckTrackingView.swift`: Primary consumer, displays preview and processes frames
- `PuckTracker.swift`: Processes frames for puck detection
- `ARCourseView.swift`: Uses ARKit camera instead (doesn't use this)

## Dependencies
- `AVFoundation`: Camera capture and session management
- `Combine`: Frame publishing
- `UIKit`: For orientation and screen info

## Platform Requirements
- iOS 13.0+ (Combine framework)
- Device with back camera

## Future Enhancements

### Advanced Configuration
```swift
func setFrameRate(_ fps: Int)
func setResolution(_ preset: AVCaptureSession.Preset)
func enableHDR(_ enabled: Bool)
```

### Session Interruption Handling
```swift
NotificationCenter.default.addObserver(
    forName: .AVCaptureSessionWasInterrupted,
    object: captureSession,
    queue: .main
) { notification in
    // Handle interruption
}
```

### Focus & Exposure Control
```swift
func setFocusMode(_ mode: AVCaptureDevice.FocusMode)
func lockExposure(at point: CGPoint)
func setWhiteBalance(_ mode: AVCaptureDevice.WhiteBalanceMode)
```

### Performance Monitoring
```swift
@Published var currentFPS: Double
@Published var droppedFrames: Int
@Published var bufferUtilization: Float
```
