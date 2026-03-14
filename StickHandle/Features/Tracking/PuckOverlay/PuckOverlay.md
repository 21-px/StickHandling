# PuckOverlay.swift

## Purpose
Shared SwiftUI component that renders a visual tracking indicator (red circle) at the detected puck position. Used in both debug view and AR experience.

## What It Does

### Input
- `PuckPosition`: Normalized coordinates, radius, confidence, distance
- `viewSize`: CGSize of the containing view
- `transformForARKit`: Whether to apply ARKit coordinate transformation
- `orientation`: Device orientation for coordinate mapping
- `cameraIntrinsics`: Optional camera parameters for precise sizing

### Transformation
1. **Coordinate Conversion**: Maps normalized (0-1) to screen pixels
2. **Orientation Handling**: Transforms coordinates based on device orientation
3. **Size Calculation**: Determines overlay radius from distance or detected size
4. **Visual Rendering**: Draws multi-layer circle with effects

### Output
SwiftUI view with:
- Red circle at puck screen position
- Distance label in feet
- Glow/shadow effects
- Responsive sizing based on distance

## Visual Design

### Circle Layers (Z-order)
```
1. Outer stroke: Red circle, 5pt line width, shadow glow
2. Inner fill: Semi-transparent red (15% opacity)
3. Center dot: Solid red circle, 12pt diameter, shadow
4. Distance label: Text below circle, black background
```

### Visual Effects
```swift
.shadow(color: .red.opacity(0.6), radius: 8, x: 0, y: 0)
```
Creates glowing halo effect around circle.

### Color Scheme
- Primary: `.red` (high visibility)
- Fill: `.red.opacity(0.15)` (subtle presence)
- Label background: `.black.opacity(0.7)` (readable)

## Size Calculation

### Method 1: LiDAR + Intrinsics (Most Accurate)
```swift
if let distance = position.estimatedDistance,
   let intrinsics = cameraIntrinsics {
    
    // Pinhole camera projection
    apparentSize = (realSize × focalLength) / distance
    
    // Convert camera pixels to screen points
    screenPoints = apparentSize / screenScale
}
```

**Math:**
- Real puck diameter: 3 inches (0.0762m) from `Puck.diameterMeters`
- Focal length: From intrinsics `fx` and `fy` (averaged)
- Distance: From LiDAR depth map
- Screen scale: Retina scaling (1x, 2x, 3x)

**Example:**
```
Distance = 1.0 meter
Focal length = 1500 pixels (camera sensor)
Puck diameter = 0.0762m
Screen scale = 3x

Apparent pixels = (0.0762 × 1500) / 1.0 = 114.3 pixels
Screen points = 114.3 / 3 = 38.1 points
```

### Method 2: Detected Size (Fallback)
```swift
let radiusInPoints = position.radius × smallerDimension
let displayDiameter = radiusInPoints × 2.0
```

**Process:**
1. `position.radius` is normalized relative to image size
2. Multiply by smaller dimension (width or height)
3. Double to get diameter (radius → diameter)
4. Apply minimum size threshold

**Why smaller dimension?**
Ensures consistent sizing regardless of screen aspect ratio.

### Minimum Size
```swift
return max(calculatedDiameter, 30)  // At least 30 points
```
Ensures visibility even for distant/small pucks.

## Coordinate Transformations

### Normal Mode (PuckTrackingView)
```swift
func toScreenCoordinates(viewSize: CGSize) -> CGPoint {
    return CGPoint(
        x: x × viewSize.width,
        y: y × viewSize.height
    )
}
```
Direct mapping from normalized to screen pixels.

### ARKit Mode (ARCourseView)
```swift
func toScreenCoordinates(
    viewSize: CGSize, 
    transformForARKit: true, 
    orientation: .portrait
) -> CGPoint
```

**Transformation for Portrait:**
```swift
// ARKit camera is landscape-right, screen is portrait
// Rotate coordinates 90° counterclockwise
screenX = (1.0 - normalizedY) × viewSize.width
screenY = normalizedX × viewSize.height
```

**Why?**
ARKit camera frames are always in landscape-right orientation, but the device is held in portrait. Coordinates must be rotated to align.

### Orientation Cases
```swift
switch orientation {
case .portrait:
    // Rotate 90° CCW
    screenX = (1.0 - y) × width
    screenY = x × height
    
case .landscapeLeft:
    // Rotate 180°
    screenX = (1.0 - x) × width
    screenY = (1.0 - y) × height
    
case .landscapeRight:
    // No rotation needed
    screenX = x × width
    screenY = y × height
    
// ... other cases
}
```

## Distance Display

### Formatting
```swift
private var distanceText: String {
    if let distance = position.estimatedDistance {
        let distanceFeet = distance × 3.28084  // Meters to feet
        return String(format: "%.1fft", distanceFeet)
    } else {
        return "0ft"  // Default if unavailable
    }
}
```

**Examples:**
- 1.0m → "3.3ft"
- 2.5m → "8.2ft"
- nil → "0ft"

### Positioning
```swift
.offset(y: displayRadius / 2 + 20)
```
Placed 20 points below circle edge.

## SwiftUI Layout

### Structure
```swift
ZStack {
    Circle()  // Outer stroke
    Circle()  // Inner fill
    Circle()  // Center dot
    Text()    // Distance label
}
.position(screenPosition)
```

### Positioning
`.position()` places the ZStack's center at the puck screen coordinates.

### Frame Sizing
```swift
.frame(width: displayRadius, height: displayRadius)
```
Note: `displayRadius` is actually diameter (naming convention from earlier versions).

## Usage Examples

### In PuckTrackingView
```swift
if let puckPosition = puckTracker.puckPosition {
    PuckOverlay(
        position: puckPosition,
        viewSize: geometry.size
    )
}
```
Simple usage with defaults.

### In ARCourseView
```swift
if let puckPosition = puckTracker.puckPosition {
    PuckOverlay(
        position: puckPosition,
        viewSize: geometry.size,
        transformForARKit: true,
        orientation: orientation,
        cameraIntrinsics: cameraIntrinsics
    )
    .allowsHitTesting(false)
}
```
Full configuration with AR transforms and hit testing disabled.

## Properties

### Required
- `position: PuckPosition` - Puck location and metadata
- `viewSize: CGSize` - Container view dimensions

### Optional
- `transformForARKit: Bool = false` - Enable ARKit coordinate rotation
- `orientation: UIDeviceOrientation = .portrait` - Current device orientation
- `cameraIntrinsics: simd_float3x3? = nil` - Camera parameters for sizing

## Performance Considerations

### Efficient Rendering
- Simple shapes (circles) are GPU-accelerated
- No complex gradients or images
- Minimal view hierarchy (4 views)

### Dynamic Updates
```swift
.id("\(puckPosition.x)-\(puckPosition.y)")
```
Forces view update when position changes (used in PuckTrackingView).

### Hit Testing
```swift
.allowsHitTesting(false)
```
Allows taps to pass through (important for color picker in PuckTrackingView).

## Visual Accessibility

### High Visibility
- Bright red color contrasts with most backgrounds
- Glow effect makes it stand out
- Large minimum size ensures visibility

### Multiple Visual Cues
1. Outer circle - shows approximate size
2. Center dot - precise position
3. Shadow/glow - depth perception
4. Distance text - quantitative feedback

## Coordinate System Notes

### Normalized Input (0-1)
- `(0, 0)` = Top-left
- `(1, 1)` = Bottom-right
- Resolution-independent

### Screen Output (Points)
- `(0, 0)` = Top-left
- `(width, height)` = Bottom-right
- Uses SwiftUI points (not pixels)

### ARKit Camera Space
- `(0, 0)` = Top-left when device is landscape-right
- Requires rotation for portrait mode
- Must account for device orientation changes

## Related Files
- `PuckTracker.swift`: Provides `PuckPosition` data
- `PuckTrackingView.swift`: Uses overlay for debug visualization
- `ARCourseView.swift`: Uses overlay in AR experience
- `Puck.swift`: Defines physical puck dimensions for sizing

## Dependencies
- `SwiftUI`: For view rendering
- `ARKit`: For coordinate transformation types
- `UIKit`: For `UIDeviceOrientation`, `UIScreen.main.scale`

## Platform Requirements
- iOS 13.0+ (SwiftUI)

## Future Enhancements

### Customization Options
```swift
struct PuckOverlay: View {
    var color: Color = .red
    var showDistance: Bool = true
    var showConfidence: Bool = false
    var animateOnDetection: Bool = true
}
```

### Confidence Visualization
- Change opacity based on confidence
- Pulse animation for high confidence
- Warning color for low confidence

### 3D Effect
- Parallax based on distance
- Scale animation based on movement
- Shadow depth based on distance

### Prediction Arrow
- Show velocity/direction
- Predicted path visualization
- Trajectory arc for fast movement
