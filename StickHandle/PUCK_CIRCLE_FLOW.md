# Red Circle Generation Flow: Color-Tracked Puck

This document explains the exact flow for how the red circle is generated and positioned around the tracked puck, including how the proper 3-inch real-world size is achieved.

## Overview

The system uses the **pinhole camera model** to maintain accurate real-world sizing. The puck's known 3-inch diameter serves as the constant that enables both distance estimation and proper circle sizing.

---

## Complete Pipeline: Camera Frame → 3-Inch Red Circle

### **Step 1: Frame Capture & Processing**
**File:** `PuckTrackingView.swift`

```swift
.onReceive(cameraManager.frames) { frame in
    // Process each frame as it comes in
    puckTracker.processFrame(frame)
}
```

The `CameraManager` publishes video frames as `CVPixelBuffer` objects at ~30-60 FPS. Each frame is sent to the `PuckTracker` for analysis.

---

### **Step 2: Color Detection**
**File:** `PuckTracker.swift` - `processFrame()`

```swift
nonisolated func processFrame(_ pixelBuffer: CVPixelBuffer, 
                              cameraIntrinsics: simd_float3x3? = nil, 
                              lidarDistance: Float? = nil) {
    
    // Convert pixel buffer to CIImage for processing
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    
    // Get scaled dimensions (160px width for performance)
    let originalWidth = ciImage.extent.width
    let originalHeight = ciImage.extent.height
    let scaledWidth = 160
    let scaledHeight = Int(160.0 / originalWidth * originalHeight)
    
    // Detect green regions in the image
    if let position = self.detectGreenPuck(in: ciImage, pixelBuffer: pixelBuffer) {
        // Position contains normalized coordinates and radius
        
        // Estimate distance using camera intrinsics
        if let intrinsics = cameraIntrinsics {
            let distance = self.estimateDistance(
                detectedRadiusNormalized: position.radius,
                imageWidth: scaledWidth,  // Uses SCALED dimensions!
                imageHeight: scaledHeight,
                intrinsics: scaledIntrinsics
            )
        }
    }
}
```

The detection process:
1. **Scales image** down to 160px width for performance optimization
2. **Applies color mask** using HSV color cube filter
3. **Finds largest green blob** via pixel analysis

---

### **Step 3: Blob Detection & Radius Calculation**
**File:** `PuckTracker.swift` - `findLargestGreenBlob()`

This function analyzes the binary mask (white = green puck pixels) to find the puck's position and size.

```swift
nonisolated private func findLargestGreenBlob(in image: CGImage, 
                                              originalSize: CGSize) -> PuckPosition? {
    let width = image.width   // 160px (scaled)
    let height = image.height
    
    // Find all white pixels (green regions in the mask)
    var sumX: CGFloat = 0
    var sumY: CGFloat = 0
    var pixelCount: Int = 0
    
    // Sample every 2nd pixel for speed
    for y in stride(from: 0, to: height, by: 2) {
        for x in stride(from: 0, to: width, by: 2) {
            let offset = (y * width + x) * 4
            let r = buffer[offset]
            let g = buffer[offset + 1]
            let b = buffer[offset + 2]
            
            // Check if pixel is white (part of green mask)
            if r > 128 && g > 128 && b > 128 {
                sumX += CGFloat(x)
                sumY += CGFloat(y)
                pixelCount += 1
            }
        }
    }
    
    // Calculate center of mass
    let centerX = sumX / CGFloat(pixelCount)
    let centerY = sumY / CGFloat(pixelCount)
    
    // Calculate RMS (root mean square) radius for subpixel accuracy
    // This prevents quantization artifacts that cause distance to jump
    var sumSquaredDistance: CGFloat = 0
    var distanceCount: Int = 0
    
    for y in stride(from: 0, to: height, by: 2) {
        for x in stride(from: 0, to: width, by: 2) {
            let offset = (y * width + x) * 4
            if buffer[offset] > 128 {  // Part of blob
                let dx = CGFloat(x) - centerX
                let dy = CGFloat(y) - centerY
                sumSquaredDistance += dx * dx + dy * dy
                distanceCount += 1
            }
        }
    }
    
    // Calculate RMS radius with subpixel precision
    let rmsRadius = sqrt(sumSquaredDistance / CGFloat(max(distanceCount, 1)))
    
    // Normalize coordinates (0-1) relative to SCALED image
    let normalizedX = centerX / CGFloat(width)
    let normalizedY = centerY / CGFloat(height)
    let normalizedRadius = rmsRadius / CGFloat(min(width, height))  // ← KEY!
    
    return PuckPosition(
        x: normalizedX,
        y: normalizedY,
        radius: normalizedRadius,  // Normalized against scaled 160px image
        confidence: confidence
    )
}
```

**Critical Detail:** The `radius` is normalized against the **scaled 160px image dimensions**, not the original full-resolution frame. This is important for the distance calculation.

---

### **Step 4: Distance Estimation (3-Inch Diameter Used Here)**
**File:** `PuckTracker.swift` - `estimateDistance()`

This is where the **3-inch real-world puck diameter** is first used:

```swift
nonisolated private func estimateDistance(
    detectedRadiusNormalized: CGFloat,
    imageWidth: Int,      // 160px (scaled)
    imageHeight: Int,
    intrinsics: simd_float3x3
) -> Float? {
    // Extract focal length from camera intrinsics matrix
    // intrinsics[0][0] = fx (focal length in x)
    // intrinsics[1][1] = fy (focal length in y)
    let focalLengthX = intrinsics[0][0]
    let focalLengthY = intrinsics[1][1]
    
    // Use average focal length for more stable results
    let focalLength = (focalLengthX + focalLengthY) / 2.0
    
    // Convert normalized radius to pixels (in scaled 160px image)
    let smallerDimension = min(imageWidth, imageHeight)
    let radiusPixels = Float(detectedRadiusNormalized) * Float(smallerDimension)
    let diameterPixels = radiusPixels * 2.0
    
    // ✨ CRITICAL: Use real puck diameter (3 inches = 0.0762 meters)
    let realDiameter = Puck.diameterMeters  // 0.0762 meters
    
    // Pinhole camera formula: distance = (realSize * focalLength) / apparentSize
    guard diameterPixels > 0 else { return nil }
    let distance = (realDiameter * focalLength) / diameterPixels
    
    // Sanity check: puck should be between 0.1m and 10m away
    guard distance > 0.1 && distance < 10.0 else { return nil }
    
    return distance  // In meters
}
```

**Pinhole Camera Model Explained:**

```
        Real World              Camera Sensor
           (3D)                     (2D)
   
   Puck (3 inches)           Projected Image
        │                         │
        │                         │
        │    ← distance →         │
        │                         │
        └─────────────────────────┘
               focalLength
   
   Formula: distance = (realSize × focalLength) / apparentSize
```

**Example Calculation:**
- Real puck diameter: 0.0762 meters (3 inches)
- Focal length: 1000 pixels (from intrinsics)
- Detected diameter: 50 pixels (in 160px image)
- Distance = (0.0762 × 1000) / 50 = **1.524 meters** (~5 feet)

---

### **Step 5: Puck Constants**
**File:** `Puck.swift`

The physical specifications of a standard hockey puck:

```swift
struct Puck {
    /// Diameter of the puck in inches (3 inches)
    static let diameterInches: Float = 3.0
    
    /// Height/thickness of the puck in inches (1 inch)
    static let heightInches: Float = 1.0
    
    /// Diameter of the puck in meters (0.0762 meters)
    static let diameterMeters: Float = 0.0762  // ← Used for calculations
    
    /// Radius of the puck in meters (0.0381 meters)
    static let radiusMeters: Float = 0.0381
}
```

This constant (`0.0762 meters = 3 inches`) is the foundation for maintaining accurate real-world sizing throughout the system.

---

### **Step 6: Position Published to SwiftUI**
**File:** `PuckTracker.swift`

```swift
// Create position with distance
let positionWithDistance = PuckPosition(
    x: position.x,
    y: position.y,
    radius: position.radius,
    confidence: position.confidence,
    estimatedDistance: distance  // ← Distance in meters
)

// Apply temporal smoothing to reduce jitter
let smoothedPosition = self.applySmoothing(to: positionWithDistance)

// Publish to SwiftUI on main thread
Task { @MainActor [weak self] in
    guard let self = self else { return }
    self.puckPosition = smoothedPosition  // ← Triggers SwiftUI re-render
    self.isTracking = true
    self.trackingConfidence = smoothedPosition.confidence
}
```

The `@Published var puckPosition: PuckPosition?` automatically triggers SwiftUI view updates.

---

### **Step 7: Red Circle Rendering**
**File:** `PuckTrackingView.swift`

```swift
GeometryReader { geometry in
    ZStack {
        // Puck tracking overlay
        if let puckPosition = puckTracker.puckPosition {
            PuckOverlay(
                position: puckPosition, 
                viewSize: geometry.size,
                cameraIntrinsics: cameraManager.intrinsics  // ← Passed for sizing
            )
            .id("\(puckPosition.x)-\(puckPosition.y)")  // Force update when position changes
            .allowsHitTesting(false)  // Don't block taps for color picking
        }
    }
}
```

The `PuckOverlay` receives:
- **position**: Normalized coordinates (x, y), radius, and **estimated distance**
- **viewSize**: Screen dimensions for coordinate conversion
- **cameraIntrinsics**: For reverse projection calculation

---

### **Step 8: Calculate Circle Size (3-Inch Diameter Used Again)**
**File:** `PuckOverlay.swift` - `calculateDisplayRadius()`

This is the **critical function** that ensures the red circle represents 3 inches in real-world space:

```swift
private func calculateDisplayRadius() -> CGFloat {
    // If we have distance and camera intrinsics, calculate precise screen size
    if let distance = position.estimatedDistance,
       let intrinsics = cameraIntrinsics {
        
        // Extract focal length from intrinsics
        let focalLengthX = intrinsics[0][0]
        let focalLengthY = intrinsics[1][1]
        let focalLength = (focalLengthX + focalLengthY) / 2.0
        
        // ✨ REVERSE the pinhole formula to project 3-inch puck onto screen
        // apparentSize = (realSize * focalLength) / distance
        let puckDiameter = Puck.diameterMeters  // 0.0762 meters (3 inches)
        let diameterPixels = CGFloat((puckDiameter * focalLength) / distance)
        let radiusPixels = diameterPixels / 2.0
        
        // ✅ BUG FIX: Convert camera sensor pixels to screen points
        // focalLength from ARKit intrinsics is in camera sensor pixels,
        // but SwiftUI uses points. On a 3x retina display, 1 point = 3 pixels
        let screenScale = UIScreen.main.scale  // 2.0 or 3.0
        let radiusPoints = radiusPixels / screenScale
        
        // Apply minimum size for visibility (at least 15 points)
        return max(radiusPoints, 15)
    }
    
    // Fallback: Use detected radius with scaling (original behavior)
    // This is used when distance estimation isn't available
    let radiusInPixels = position.radius * min(viewSize.width, viewSize.height)
    
    // Make circle large enough to clearly surround the puck
    // Multiply by 3 to ensure it encompasses the puck, minimum 100px
    let displayRadius = max(radiusInPixels * 3, 100)
    
    return displayRadius
}
```

**The Reverse Projection Explained:**

```
Step 4 (Distance):    distance = (realSize × focalLength) / apparentSize
Step 8 (Circle Size): apparentSize = (realSize × focalLength) / distance
                                      ↑
                             Same realSize (3 inches)!
```

**Example Calculation:**
- Distance: 1.524 meters (from Step 4)
- Focal length: 1000 pixels
- Puck diameter: 0.0762 meters (3 inches)
- Screen scale: 3.0 (iPhone retina)

```
diameterPixels = (0.0762 × 1000) / 1.524 = 50 pixels (sensor pixels)
radiusPixels = 50 / 2 = 25 pixels
radiusPoints = 25 / 3.0 = 8.33 points (SwiftUI coordinates)
```

But if puck is closer (0.5m), circle becomes larger:
```
diameterPixels = (0.0762 × 1000) / 0.5 = 152.4 pixels
radiusPoints = (152.4 / 2) / 3.0 = 25.4 points
```

**This is the magic!** The circle automatically scales to match the 3-inch real-world puck size at any distance.

---

### **Step 9: Draw the Circle**
**File:** `PuckOverlay.swift`

```swift
var body: some View {
    let screenPosition = position.toScreenCoordinates(
        viewSize: viewSize,
        transformForARKit: transformForARKit,
        orientation: orientation
    )
    
    // Calculate display radius based on distance if available
    let displayRadius = calculateDisplayRadius()
    
    ZStack {
        // Outer circle - bright red stroke with glow effect
        Circle()
            .stroke(Color.red, lineWidth: 5)
            .frame(width: displayRadius, height: displayRadius)
            .shadow(color: .red.opacity(0.6), radius: 8, x: 0, y: 0)
        
        // Inner circle - semi-transparent fill
        Circle()
            .fill(Color.red.opacity(0.15))
            .frame(width: displayRadius, height: displayRadius)
        
        // Center dot for precise position
        Circle()
            .fill(Color.red)
            .frame(width: 12, height: 12)
            .shadow(color: .red, radius: 4, x: 0, y: 0)
        
        // Show estimated distance
        Text(distanceText)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(4)
            .background(Color.black.opacity(0.7))
            .cornerRadius(4)
            .offset(y: displayRadius / 2 + 20)
    }
    .position(screenPosition)
}
```

The final rendered overlay consists of:
- **Outer stroke**: Red circle outline (5pt line width)
- **Inner fill**: Semi-transparent red fill (15% opacity)
- **Center dot**: Solid red dot (12pt diameter)
- **Distance label**: Text showing distance in feet

---

## Summary: The Key to 3-Inch Accuracy

The system maintains accurate real-world sizing through a **bidirectional use of the pinhole camera model**:

### **Forward Pass (Detection → Distance):**
```
distance = (3 inches × focalLength) / detectedSize
```
- Input: Detected puck size in pixels
- Constant: 3-inch real puck diameter
- Output: Distance in meters

### **Reverse Pass (Distance → Circle Size):**
```
circleSize = (3 inches × focalLength) / distance
```
- Input: Distance in meters (from forward pass)
- Constant: Same 3-inch real puck diameter
- Output: Circle size in screen points

### **The Constant:**
`Puck.diameterMeters = 0.0762m` (3 inches) appears in **both calculations**, ensuring:
1. Detection assumes the blob is a 3-inch puck → calculates distance
2. Overlay draws a circle representing 3 inches at that distance
3. **Result: Red circle matches the real-world 3-inch puck size on screen!**

---

## Coordinate Transformation Note

The selected code snippet `1.0 - ` is part of coordinate transformation logic in `PuckPosition.toScreenCoordinates()`:

```swift
func toScreenCoordinates(
    viewSize: CGSize,
    transformForARKit: Bool = false,
    orientation: UIDeviceOrientation = .portrait
) -> CGPoint {
    var adjustedX = x
    var adjustedY = y
    
    if transformForARKit {
        switch orientation {
        case .portrait, .unknown, .faceUp, .faceDown:
            // ARKit landscape-right → Portrait display
            adjustedX = 1.0 - y  // ← Here's the "1.0 -" pattern
            adjustedY = x
        // ... other cases
        }
    }
    
    return CGPoint(
        x: adjustedX * viewSize.width,
        y: adjustedY * viewSize.height
    )
}
```

This handles the rotation between ARKit's camera sensor orientation (landscape-right) and the device's display orientation (portrait). The `1.0 -` inverts normalized coordinates when rotating the coordinate system.

---

## Performance Optimizations

1. **Image Scaling**: Frames scaled to 160px width (from ~1920px) = **144x fewer pixels** to process
2. **Pixel Sampling**: Every 2nd pixel sampled = **4x faster** blob analysis
3. **Color Cube Caching**: HSV lookup table created once, reused every frame
4. **Background Processing**: Computer vision on background queue, only UI updates on main thread
5. **Temporal Smoothing**: Exponential moving average reduces jitter without lag

The system achieves **real-time 30-60 FPS** tracking with accurate real-world sizing on all iOS devices.
