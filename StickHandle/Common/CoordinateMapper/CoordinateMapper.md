# CoordinateMapper.swift

## Purpose
Maps between 2D camera/screen coordinates and 3D AR world space coordinates. Bridges the gap between computer vision detection (2D) and augmented reality positioning (3D).

## What It Does

### Input
- Normalized 2D puck position (0-1 range from puck tracker)
- AR camera transform (4×4 matrix from ARKit)
- Plane anchor (detected horizontal surface in AR)

### Transformation
Converts 2D screen coordinates to 3D world coordinates by:
1. Projecting 2D position onto detected horizontal plane
2. Transforming from plane-local space to AR world space
3. Applying camera and plane transforms

### Output
- `SIMD3<Float>`: 3D position in AR world space (meters)
- Coordinate system: ARKit world space (Y-up, meters)

## Key Methods

### `mapToPlaneSpace(normalizedPosition:)`
**Simplified mapping for testing:**
```swift
func mapToPlaneSpace(normalizedPosition: CGPoint) -> SIMD3<Float>
```

**What it does:**
- Maps normalized (0-1) coordinates to a ~1.5m × 1.5m play area
- Centers at origin (0.5, 0.5) → (0, 0, 0)
- Assumes floor plane at Y = 0

**Calculation:**
```swift
x = (normalizedX - 0.5) × 1.5  // Range: -0.75 to +0.75 meters
z = (normalizedY - 0.5) × 1.5  // Range: -0.75 to +0.75 meters
y = 0                          // On the plane
```

**Used by:** `ARCourseView` for puck position validation

### `mapToWorldSpace(normalizedPosition:viewportSize:)`
**Full AR world space mapping (currently unused):**
```swift
func mapToWorldSpace(normalizedPosition: CGPoint, viewportSize: CGSize) -> SIMD3<Float>?
```

**What it does:**
- Converts screen position to world coordinates using plane transform
- Accounts for detected plane position and orientation
- Returns nil if no plane detected yet

**Process:**
1. Convert normalized (0-1) to screen pixels
2. Map screen position to plane-local coordinates
3. Apply plane transform to get world position
4. Return 3D world coordinates

### Update Methods

#### `updatePlane(_:)`
```swift
func updatePlane(_ anchor: ARAnchor)
```
Stores the horizontal plane anchor detected by ARKit.

#### `updateCamera(_:)`
```swift
func updateCamera(_ transform: simd_float4x4)
```
Stores the current AR camera transform matrix.

## Coordinate Systems Explained

### 2D Normalized (Input)
- **Origin**: Top-left (0, 0)
- **Range**: X and Y from 0.0 to 1.0
- **Units**: Normalized (resolution-independent)
- **Source**: `PuckTracker.puckPosition`

### 3D Plane-Local
- **Origin**: Center of detected plane
- **Axes**: X (right), Y (up), Z (forward)
- **Units**: Meters
- **Reference**: Relative to plane anchor

### 3D World Space (Output)
- **Origin**: ARKit world origin
- **Axes**: X (right), Y (up), Z (toward user)
- **Units**: Meters
- **Reference**: ARKit's global coordinate system

## Transformations

### Normalized → Plane-Local
```swift
// Center normalized coordinates (0-1) around origin
planeX = (normalizedX - 0.5) × playAreaWidth
planeZ = (normalizedY - 0.5) × playAreaDepth
planeY = 0  // On the plane
```

### Plane-Local → World Space
```swift
// Apply plane transform (4×4 matrix)
localPosition = SIMD4<Float>(planeX, planeY, planeZ, 1)
worldPosition = planeTransform × localPosition
```

## Usage Example

```swift
// In ARCourseView
let coordinateMapper = CoordinateMapper()

// Update with ARKit data
coordinateMapper.updatePlane(detectedPlane)
coordinateMapper.updateCamera(arFrame.camera.transform)

// Map puck position to 3D
let puckPosition2D = puckTracker.puckPosition // CGPoint(x: 0.5, y: 0.6)
let puckPosition3D = coordinateMapper.mapToPlaneSpace(
    normalizedPosition: puckPosition2D
)
// Result: SIMD3(0.0, 0.0, 0.15) meters in AR world space

// Use for course validation
validator.updatePuckPosition(puckPosition3D)
```

## State Management

### Observable Object
```swift
class CoordinateMapper: ObservableObject
```
- SwiftUI-compatible for reactive updates
- No `@Published` properties (stateless utility)
- Stores internal state for transforms

### Internal State
```swift
private var planeAnchor: ARAnchor?
private var cameraTransform: simd_float4x4?
```

## Technical Details

### Play Area Dimensions
Current simplified mapping:
- Width: 1.5 meters (~5 feet)
- Depth: 1.5 meters (~5 feet)
- Total area: 2.25 m² (~24 ft²)

Suitable for:
- Side shuttle drills
- Small agility courses
- Tabletop demos

### Matrix Mathematics
Uses SIMD (Single Instruction Multiple Data) for efficient vector math:
```swift
simd_float4x4  // 4×4 transformation matrix
SIMD3<Float>   // 3D vector (x, y, z)
SIMD4<Float>   // Homogeneous coordinates (x, y, z, w)
```

### Transform Composition
```swift
worldPoint = planeTransform × localPoint
```
Standard homogeneous transformation matrix multiplication.

## Future Enhancements

### Perspective Projection
More accurate mapping could use:
1. Camera intrinsics (focal length, principal point)
2. Ray casting from screen point through camera
3. Intersection with detected plane
4. Proper perspective-correct positioning

### Depth-Aware Mapping
With LiDAR:
1. Get depth at puck screen position
2. Unproject screen point to 3D using depth
3. More accurate than plane assumption
4. Handles uneven surfaces

### Multi-Plane Support
Track multiple planes:
- Floor plane
- Table plane
- Wall planes
- Automatically select closest plane to puck

## Related Files
- `ARCourseView.swift`: Primary consumer of coordinate mapping
- `PuckTracker.swift`: Provides 2D input coordinates
- `CourseValidator.swift`: Uses 3D coordinates for validation
- `Course.swift`: Defines course elements in 3D space

## Dependencies
- `ARKit`: For AR anchors and transforms
- `simd`: For vector and matrix math
- `Combine`: For `ObservableObject` conformance

## Platform Requirements
- iOS 13.0+ (ARKit 3)
- Device with ARKit support (A9 chip or later)

## Notes
- Currently uses simplified mapping for reliability
- Full world-space mapping available but not active
- Designed for horizontal plane detection only
- Assumes puck is on the detected plane (Y = 0)
