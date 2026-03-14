# PuckTracker.swift

## Purpose
Real-time computer vision system that detects and tracks a bright green hockey puck in video frames using color-based detection.

## What It Does

### Input
- `CVPixelBuffer`: Raw camera frames from AVFoundation or ARKit
- `cameraIntrinsics`: Camera parameters (focal length, principal point)
- `lidarDistance`: Optional LiDAR depth data for accurate distance

### Transformation
1. **Color Filtering**: Converts RGB to HSV and filters for target green color
2. **Blob Detection**: Identifies connected regions of green pixels
3. **Size Filtering**: Accepts any blob above minimum threshold (works at long distances)
4. **Position Calculation**: Computes center of mass and radius of detected blob
5. **Distance Estimation**: Uses LiDAR or intrinsics to estimate puck distance
6. **Temporal Smoothing**: Reduces jitter with exponential moving average

### Output
- `PuckPosition?`: Normalized coordinates (0-1), radius, confidence, and distance
- `isTracking`: Boolean tracking state
- `trackingConfidence`: 0-1 confidence score
- `debugImage`: Optional color mask visualization

## Key Algorithms

### Color-Based Detection
Uses HSV color space for robust color detection:
```swift
Hue: 0.20-0.50 (green range, 72°-180°)
Saturation: 0.3-1.0 (vibrant colors)
Brightness: 0.3-1.0 (well-lit)
```

**Why HSV?**
- More robust to lighting changes than RGB
- Hue represents pure color (independent of brightness)
- Saturation represents color intensity
- Separates color from lighting conditions

### Distance Estimation

#### Method 1: LiDAR (iPhone 12 Pro+)
- Most accurate: Directly measures depth at puck position
- Extracts depth value from ARKit's scene depth map
- Accounts for device orientation when mapping coordinates
- Valid range: 0-10 meters

#### Method 2: Camera Intrinsics (Fallback)
```swift
distance = (realDiameter × focalLength) / apparentDiameterPixels
```
Uses pinhole camera model:
- Real puck diameter: 3 inches (0.0762 m)
- Focal length from camera intrinsics matrix
- Detected radius converted to diameter in pixels
- Returns distance in meters

### Temporal Smoothing
```swift
smoothedPosition = previousPosition × (1 - α) + newPosition × α
```
- Smoothing factor α = 0.5 (balanced between smoothness and responsiveness)
- Applied separately to x, y, and radius
- Reduces jitter from frame-to-frame variations

### Blob Detection Pipeline

1. **Downscale**: Resize to 160px width for performance
2. **Color Cube Filter**: 3D lookup table for HSV filtering
   - Creates 64×64×64 cube mapping input RGB to output (white = match, black = no match)
   - GPU-accelerated via Core Image
3. **Threshold**: Binary mask (black/white)
4. **Median Filter**: Removes noise
5. **Connected Components**: Finds contiguous regions
6. **Size Filter**: Accepts blobs above minimum area
7. **Center of Mass**: Calculates weighted average position
8. **Edge Fitting**: Finds average radius from edge pixels

## Performance Optimizations

### Image Processing
- **Downscaling**: 160px width reduces processing by ~95%
- **GPU Acceleration**: Core Image filters run on Metal
- **Cached Color Cube**: Reused across frames (regenerated on color change)
- **Background Queue**: Processing on dedicated `userInitiated` QoS queue

### Frame Throttling
```swift
processEveryNthFrame = 1  // Currently processes every frame
```
Can be increased if performance issues occur.

### Memory Efficiency
- Reused Core Image context
- CVPixelBuffer direct access (no copies)
- Cached filter objects

## Configuration & Persistence

### Color Settings (UserDefaults)
All HSV ranges persist across app launches:
```swift
"com.stickhandle.puck.hue.min"
"com.stickhandle.puck.hue.max"
"com.stickhandle.puck.sat.min"
"com.stickhandle.puck.sat.max"
"com.stickhandle.puck.bright.min"
"com.stickhandle.puck.bright.max"
```

### LiDAR Setting
```swift
"com.stickhandle.puck.lidar.enabled"
```

### Color Calibration
```swift
func updateTargetColor(hsv: (h: CGFloat, s: CGFloat, v: CGFloat))
```
- Expands color range around selected HSV value
- Hue: ±0.15 (±54° tolerance)
- Saturation: ±0.35
- Brightness: ±0.35
- Regenerates color cube filter
- Saves to UserDefaults

## Public API

### Core Methods
```swift
func processFrame(_ pixelBuffer: CVPixelBuffer, 
                  cameraIntrinsics: simd_float3x3? = nil, 
                  lidarDistance: Float? = nil)
```
Main entry point - processes a single frame.

```swift
func getColorAt(normalizedPoint: CGPoint) -> (h: CGFloat, s: CGFloat, v: CGFloat)?
```
Samples HSV color at a point (for calibration).

```swift
func updateTargetColor(hsv: (h: CGFloat, s: CGFloat, v: CGFloat))
```
Updates the tracking color range.

```swift
func setDebugMode(_ enabled: Bool)
```
Enables/disables mask visualization.

```swift
func setLidarEnabled(_ enabled: Bool)
```
Toggles LiDAR distance estimation.

### Published Properties
All `@Published` for SwiftUI observation:
- `puckPosition: PuckPosition?`
- `isTracking: Bool`
- `trackingConfidence: Float`
- `debugImage: UIImage?`
- `targetHue`, `targetSaturation`, `targetBrightness`
- `lidarEnabled: Bool`

## Data Structures

### PuckPosition
```swift
struct PuckPosition {
    let x: CGFloat              // Normalized 0-1 (left to right)
    let y: CGFloat              // Normalized 0-1 (top to bottom)
    let radius: CGFloat         // Normalized radius
    let confidence: Float       // 0-1 confidence score
    let estimatedDistance: Float? // Meters from camera
}
```

Includes helper methods:
- `toScreenCoordinates(viewSize:)`: Converts to pixel coordinates
- Handles ARKit orientation transformations

### Coordinate Systems

#### Normalized (0-1)
- Origin: Top-left
- X: 0 (left) to 1 (right)
- Y: 0 (top) to 1 (bottom)
- Independent of screen resolution

#### ARKit Transformation
When `transformForARKit = true`:
- Accounts for camera sensor orientation (landscape-right)
- Maps portrait screen coordinates to camera coordinates
- Used in `ARCourseView` for AR integration

## Detection Parameters

### Minimum Blob Size
```swift
minBlobArea = 1.0 pixels²  // Very permissive for long-distance tracking
```

### Confidence Calculation
```swift
confidence = min(1.0, blobArea / targetBlobArea)
```
- Based on blob size relative to expected size
- 1.0 = perfect match
- Lower = smaller/larger than expected

### Detection Timeout
```swift
detectionTimeout = 0.5 seconds
```
If no puck detected for 0.5s, sets `isTracking = false`.

## Related Files
- `PuckTrackingView.swift`: UI for debugging and calibration
- `ARCourseView.swift`: Integrates tracking into AR experience
- `PuckOverlay.swift`: Visualization component
- `CameraManager.swift`: Frame source (standalone mode)
- `Puck.swift`: Physical puck specifications (diameter for distance estimation)

## Technical Requirements
- iOS 13.0+ (Core Image with Metal)
- Concurrent queues for async processing
- LiDAR requires iPhone 12 Pro or later

## Limitations & Future Improvements

### Current Limitations
- Color-based detection only (no ML/object detection)
- Requires good lighting conditions
- Green puck required (configurable via calibration)
- Can be confused by other green objects

### Potential Improvements
- Core ML object detection model
- Optical flow for motion tracking
- Kalman filtering for prediction
- Multi-object tracking (multiple pucks)
- Automatic lighting adjustment
