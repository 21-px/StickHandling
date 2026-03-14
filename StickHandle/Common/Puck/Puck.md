# Puck.swift

## Purpose
Defines physical specifications for a standard hockey puck. Provides accurate dimensions used for distance estimation and AR visualization.

## What It Does

### Input
None - This is a pure data/constants file.

### Transformation
Provides standardized measurements in both imperial (inches) and metric (meters) units.

### Output
Static constants that can be accessed throughout the app:
- Puck diameter
- Puck height/thickness
- Unit conversion utilities

## Constants

### Dimensions in Inches
```swift
static let diameterInches: Float = 3.0
static let heightInches: Float = 1.0
```

**Standard Hockey Puck (NHL regulation):**
- Diameter: 3 inches
- Thickness: 1 inch
- Weight: 6 ounces (not tracked in this file)

### Dimensions in Meters
```swift
static let diameterMeters: Float = 0.0762
static let heightMeters: Float = 0.0254
static let radiusMeters: Float = 0.0381
```

**Conversions:**
- 3 inches = 0.0762 meters (76.2mm)
- 1 inch = 0.0254 meters (25.4mm)
- 1.5 inch radius = 0.0381 meters (38.1mm)

### Derived Values
```swift
radiusMeters = diameterMeters / 2
           = 0.0762 / 2
           = 0.0381 meters
```

## Utility Functions

### Inches to Meters
```swift
static func inchesToMeters(_ inches: Float) -> Float {
    return inches * 0.0254
}
```

**Example:**
```swift
let stickLength = Puck.inchesToMeters(60)  // 1.524 meters
```

### Meters to Inches
```swift
static func metersToInches(_ meters: Float) -> Float {
    return meters / 0.0254
}
```

**Example:**
```swift
let distance = Puck.metersToInches(2.0)  // 78.74 inches
```

## Usage in App

### Distance Estimation (PuckTracker)
```swift
// Pinhole camera model
let apparentDiameter = (Puck.diameterMeters * focalLength) / distance
```
Uses real puck diameter to calculate how large the puck should appear at a given distance.

### Distance from Apparent Size (Inverse)
```swift
let distance = (Puck.diameterMeters * focalLength) / apparentDiameterPixels
```
Given detected size in pixels, estimate distance to puck.

### PuckOverlay Sizing
```swift
// Calculate expected screen size at distance
let expectedSize = (Puck.diameterMeters * intrinsics.fx) / distance
```
Determines how large the overlay circle should be.

### AR Visualization (Future)
```swift
// Create 3D puck model
let puckMesh = MeshResource.generateCylinder(
    radius: Puck.radiusMeters,
    height: Puck.heightMeters
)
```
Could render a 3D puck in AR with accurate dimensions.

## Physical Context

### Standard Hockey Puck
- **Material:** Vulcanized rubber
- **Color:** Black (standard), various colors for training
- **Weight:** 5.5 to 6 ounces (~156-170 grams)
- **Temperature:** Frozen before games (reduces bouncing)

### Why These Dimensions Matter

#### Computer Vision
- Known real-world size enables distance estimation
- Consistent diameter aids in detection algorithms
- Size filtering helps distinguish puck from other objects

#### AR Accuracy
- Precise measurements ensure AR overlays align correctly
- Scale-accurate visualization for training feedback
- Realistic 3D models for simulation

#### Physics Simulation (Future)
- Accurate size for collision detection
- Proper radius for movement calculations
- Realistic proportions for skill training

## Unit Conversion Notes

### Conversion Factor
```
1 inch = 0.0254 meters (exact)
1 meter = 39.3701 inches
```

**Why 0.0254?**
This is the **exact** definition of an inch in the metric system (since 1959).

### Precision
All values use `Float` (32-bit):
- Precision: ~7 decimal digits
- Sufficient for AR/CV applications
- Matches ARKit's coordinate precision

## Data Structure

### Struct vs Class
```swift
struct Puck
```

**Why struct?**
- No instances needed (pure static constants)
- Value semantics (copyable, no references)
- Namespace for related constants
- Can't be instantiated

### Static Members Only
```swift
Puck.diameterMeters  // ✅ Correct
let puck = Puck()    // ❌ Cannot instantiate
```

All members are `static` - accessed directly on the type.

## Usage Examples

### Basic Access
```swift
import Foundation

// Get diameter in meters
let diameter = Puck.diameterMeters  // 0.0762

// Get radius in meters
let radius = Puck.radiusMeters  // 0.0381

// Get height in inches
let height = Puck.heightInches  // 1.0
```

### Unit Conversion
```swift
// Convert stick length to meters
let stickLengthInches: Float = 60
let stickLengthMeters = Puck.inchesToMeters(stickLengthInches)
// Result: 1.524 meters

// Convert rink width to inches
let rinkWidthMeters: Float = 26
let rinkWidthInches = Puck.metersToInches(rinkWidthMeters)
// Result: 1023.62 inches
```

### Distance Estimation
```swift
// Given: Detected puck appears 50 pixels wide
// Given: Camera focal length is 1000 pixels
let apparentSize: Float = 50.0
let focalLength: Float = 1000.0

// Calculate distance
let distance = (Puck.diameterMeters * focalLength) / apparentSize
// Result: 1.524 meters (~5 feet)
```

### AR Scaling
```swift
// Create puck with accurate proportions
let puckAspectRatio = Puck.heightMeters / Puck.diameterMeters
// Result: 0.333 (height is 1/3 of diameter)
```

## Related Files

### Direct Usage
- `PuckTracker.swift`: Uses diameter for distance estimation
- `PuckOverlay.swift`: Uses diameter to calculate display size
- `ARCourseView.swift` (potentially): Could use for 3D puck rendering

### Indirect Usage
- Any file that needs physical puck dimensions
- Future AR visualization components
- Physics simulation (if implemented)

## Platform Requirements
- iOS 13.0+ (uses `Float` type)
- No special framework dependencies

## Future Enhancements

### Additional Specifications
```swift
struct Puck {
    // Current constants...
    
    // Weight
    static let weightGrams: Float = 163.0  // ~6 oz
    static let weightOunces: Float = 6.0
    
    // Material properties
    static let coefficientOfRestitution: Float = 0.3  // Bounciness
    static let frictionCoefficient: Float = 0.4      // Ice friction
    
    // Visual properties
    static let standardColor: UIColor = .black
    static let trainingColors: [UIColor] = [.yellow, .orange, .green]
}
```

### Temperature Effects
```swift
struct Puck {
    static func densityAt(temperatureCelsius: Float) -> Float {
        // Frozen pucks are denser and less bouncy
        // Could model temperature-dependent behavior
    }
}
```

### Variants
```swift
enum PuckType {
    case standard      // 6 oz, black
    case light         // 4 oz, for youth
    case heavy         // 10 oz, for training
    case smart         // With tracking sensor
}

extension Puck {
    static func diameter(for type: PuckType) -> Float {
        // All same diameter, different weights
        return 0.0762
    }
}
```

### 3D Model Properties
```swift
extension Puck {
    // For RealityKit/SceneKit
    static var cylinderDimensions: (radius: Float, height: Float) {
        return (radiusMeters, heightMeters)
    }
    
    // Bounding box
    static var boundingBox: (width: Float, height: Float, depth: Float) {
        return (diameterMeters, heightMeters, diameterMeters)
    }
}
```

## Design Rationale

### Why Static Struct?
1. **No state:** Just constants, no need for instances
2. **Namespace:** Groups related constants logically
3. **Discoverability:** Autocomplete shows `Puck.` options
4. **Type safety:** Better than global constants
5. **Documentation:** Can document the type itself

### Why Both Units?
1. **Imperial:** Hockey is traditionally measured in inches
2. **Metric:** ARKit and most frameworks use meters
3. **Convenience:** Avoid manual conversions throughout code
4. **Accuracy:** Pre-calculated exact conversions

### Why Float Not Double?
1. **Consistency:** ARKit uses `Float` for coordinates
2. **Performance:** Half the memory of `Double`
3. **Precision:** 7 digits is more than sufficient for puck size
4. **Compatibility:** SIMD types use `Float` by default

## Testing Considerations

### Unit Tests
```swift
import Testing

@Suite("Puck Dimensions")
struct PuckTests {
    
    @Test("Diameter conversion is accurate")
    func testDiameterConversion() async throws {
        let inches = Puck.diameterInches
        let meters = Puck.inchesToMeters(inches)
        #expect(abs(meters - Puck.diameterMeters) < 0.0001)
    }
    
    @Test("Radius is half of diameter")
    func testRadiusCalculation() async throws {
        #expect(Puck.radiusMeters == Puck.diameterMeters / 2)
    }
}
```

### Reality Checks
```swift
// Verify values make sense
assert(Puck.diameterMeters > 0.05 && Puck.diameterMeters < 0.10)
assert(Puck.heightMeters < Puck.diameterMeters)  // Puck is wider than tall
```

## Internationalization

While dimensions are fixed, display strings could be localized:
```swift
var localizedDiameter: String {
    let formatter = MeasurementFormatter()
    let measurement = Measurement(
        value: Double(Puck.diameterMeters),
        unit: UnitLength.meters
    )
    return formatter.string(from: measurement)
}
```

**Output:**
- US: "3 in" or "0.076 m"
- Metric regions: "76 mm"
