# Course.swift

## Purpose
Defines the data structures and configuration for stickhandling courses. Represents the "what" and "rules" of a drill.

## What It Does

### Input
Course configuration data defining:
- Course metadata (name, difficulty, description)
- Physical elements (lines, checkpoints)
- Game rules (time limit, success criteria, repeat mode)

### Transformation
Provides structured, type-safe representation of courses that can be:
- Encoded/decoded (Codable)
- Validated by `CourseValidator`
- Rendered in AR by `ARCourseView`
- Extended with new course designs

### Output
Immutable `Course` instances with well-defined structure and behavior.

## Data Structures

### Course
```swift
struct Course: Identifiable, Codable {
    let id: String
    let name: String
    let difficulty: Difficulty
    let description: String
    let elements: [CourseElement]
    let repeatMode: RepeatMode
    let timeLimit: TimeInterval
    let successCriteria: SuccessCriteria
}
```

**Properties:**
- `id`: Unique identifier (e.g., "side-shuttle-beginner")
- `name`: Display name (e.g., "Side Shuttle")
- `difficulty`: Beginner/Intermediate/Expert
- `description`: User-facing instructions
- `elements`: Array of lines/checkpoints
- `repeatMode`: How to progress through elements
- `timeLimit`: Total time allowed (seconds)
- `successCriteria`: Win condition

### CourseElement
```swift
enum CourseElement: Codable {
    case crossLine(start: SIMD3<Float>, end: SIMD3<Float>, direction: CrossDirection)
    case checkpoint(position: SIMD3<Float>, radius: Float)
}
```

**Line Element:**
- `start`: 3D position of line start (meters)
- `end`: 3D position of line end (meters)
- `direction`: Required crossing direction (or `.any`)

**Checkpoint Element:**
- `position`: 3D center point (meters)
- `radius`: Trigger distance (meters)

### CrossDirection
```swift
enum CrossDirection: String, Codable {
    case forward       // Must cross from behind
    case backward      // Must cross from front
    case leftToRight   // Must cross left to right
    case rightToLeft   // Must cross right to left
    case any           // Either direction works
}
```

**Usage:**
Currently `.any` for all courses. Future enhancement for directional validation.

### RepeatMode
```swift
enum RepeatMode: String, Codable {
    case sequential    // Complete once in order
    case alternating   // Alternate between elements (shuttle drills)
    case continuous    // Repeat until time expires
}
```

**Examples:**
- **Sequential:** Line1 → Line2 → Line3 → Done
- **Alternating:** Line1 ↔ Line2 ↔ Line1 ↔ Line2...
- **Continuous:** Line1 → Line2 → Line3 → Line1 → Line2...

### SuccessCriteria
```swift
enum SuccessCriteria: Codable {
    case minimumCrosses(Int)      // Require N crosses
    case allElementsCompleted      // Complete all elements once
    case minimumScore(Int)         // Achieve minimum score
}
```

**Examples:**
- `.minimumCrosses(10)`: Must cross lines 10 times
- `.allElementsCompleted`: Touch all checkpoints
- `.minimumScore(25)`: Achieve 25 points (with scoring system)

### Difficulty
```swift
enum Difficulty: String, Codable {
    case beginner
    case intermediate
    case expert
}
```

**Inspiration:** Duolingo-style progression system
**Future Use:** Course selection UI, adaptive difficulty

## Predefined Courses

### Side Shuttle (Beginner)
```swift
static let sideShuttleBeginner = Course(
    id: "side-shuttle-beginner",
    name: "Side Shuttle",
    difficulty: .beginner,
    description: "Move the puck side-to-side between two lines as fast as you can!",
    elements: [
        .crossLine(
            start: SIMD3<Float>(0.2, 0, 0.3),   // Left line
            end: SIMD3<Float>(0.2, 0, 1.0),
            direction: .any
        ),
        .crossLine(
            start: SIMD3<Float>(0.81, 0, 0.3),  // Right line (0.61m away)
            end: SIMD3<Float>(0.81, 0, 1.0),
            direction: .any
        )
    ],
    repeatMode: .alternating,
    timeLimit: 30.0,
    successCriteria: .minimumCrosses(10)
)
```

**Dimensions:**
- Line spacing: 0.61m (~2 feet)
- Line length: 0.7m (~2.3 feet)
- Play area: ~0.6m × 0.7m

**Rules:**
- 30 second time limit
- Alternate between lines
- Must cross at least 10 times to succeed

### Course Collection
```swift
static let allCourses: [Course] = [
    .sideShuttleBeginner
]
```

**Future Courses:**
- Figure-8 pattern
- Triangle weave
- Speed ladder
- Freestyle zone

## Codable Implementation

### Custom Encoding/Decoding
Both `CourseElement` and `SuccessCriteria` implement custom Codable logic for enum cases with associated values.

#### CourseElement Coding
```swift
enum CodingKeys: String, CodingKey {
    case type, start, end, direction, position, radius
}
```

**Encoded JSON Example:**
```json
{
  "type": "crossLine",
  "start": [0.2, 0.0, 0.3],
  "end": [0.2, 0.0, 1.0],
  "direction": "any"
}
```

#### SuccessCriteria Coding
```swift
enum CodingKeys: String, CodingKey {
    case type, value
}
```

**Encoded JSON Example:**
```json
{
  "type": "minimumCrosses",
  "value": 10
}
```

## 3D Coordinate System

### Units
All positions in **meters** (SI units)

### Axes
- **X**: Left (-) to Right (+)
- **Y**: Down (-) to Up (+), typically 0 for floor
- **Z**: Back (-) to Front (+)

### Origin
Centered on detected AR plane anchor

### Example Positions
```swift
// Left line at (0.2m from center, floor level, 0.3m-1.0m forward)
start: SIMD3(0.2, 0, 0.3)
end: SIMD3(0.2, 0, 1.0)

// Right line at (0.81m from center, floor level, same depth)
start: SIMD3(0.81, 0, 0.3)
end: SIMD3(0.81, 0, 1.0)
```

## Design Patterns

### Value Semantics
```swift
struct Course  // Copied on assignment, thread-safe
```

### Composition
Courses composed of simple element types (lines, checkpoints)

### Extensibility
Easy to add new:
- Course definitions (static properties)
- Element types (new enum cases)
- Success criteria (new cases)
- Repeat modes (new cases)

## Usage Examples

### Creating Custom Course
```swift
let customCourse = Course(
    id: "figure-8",
    name: "Figure 8 Weave",
    difficulty: .intermediate,
    description: "Weave the puck in a figure-8 pattern",
    elements: [
        .checkpoint(position: SIMD3(0, 0, 0.5), radius: 0.15),
        .checkpoint(position: SIMD3(0.4, 0, 0.8), radius: 0.15),
        .checkpoint(position: SIMD3(-0.4, 0, 0.8), radius: 0.15)
    ],
    repeatMode: .continuous,
    timeLimit: 60.0,
    successCriteria: .minimumScore(20)
)
```

### Accessing Courses
```swift
// Use predefined course
let course = Course.sideShuttleBeginner

// Browse all courses
for course in Course.allCourses {
    print(course.name)
}

// Load from JSON
let decoder = JSONDecoder()
let course = try decoder.decode(Course.self, from: jsonData)
```

### Iterating Elements
```swift
for (index, element) in course.elements.enumerated() {
    switch element {
    case .crossLine(let start, let end, let dir):
        print("Line \(index): \(start) to \(end)")
    case .checkpoint(let pos, let radius):
        print("Checkpoint \(index): at \(pos)")
    }
}
```

## Validation Rules

### Course Requirements
- Must have at least 1 element
- Time limit must be > 0
- Success criteria must be achievable
- Element positions should be within reasonable play area

### Element Constraints
- Lines must have different start/end points
- Checkpoint radius must be > 0
- Positions should be reachable

## File Organization

### Static Course Library
All predefined courses as static properties:
```swift
extension Course {
    static let sideShuttleBeginner = ...
    static let figureEight = ...
    static let speedLadder = ...
    
    static let allCourses = [...]
}
```

### Future: External Storage
Could load from:
- JSON files in app bundle
- Remote server (downloadable courses)
- User-created custom courses
- Cloud sync

## Related Files
- `CourseValidator.swift`: Validates course progress
- `ARCourseView.swift`: Renders course in AR
- `CoordinateMapper.swift`: Maps course elements to AR space

## Dependencies
- `Foundation`: For `Identifiable`, `Codable`, `TimeInterval`
- `simd`: For 3D vector types (`SIMD3<Float>`)

## Platform Requirements
- iOS 13.0+ (SIMD support)

## Future Enhancements

### Dynamic Courses
- Procedurally generated patterns
- Adaptive difficulty based on skill level
- Randomized element positions

### Course Editor
- Visual course builder
- Drag-and-drop element placement
- Live AR preview

### Community Features
- Share courses with other users
- Browse community-created courses
- Rating and favoriting system
- Leaderboards per course

### Advanced Elements
```swift
case movingTarget(path: [SIMD3<Float>], speed: Float)
case avoidZone(center: SIMD3<Float>, radius: Float)
case sequence(elements: [CourseElement], order: Bool)
```

### Scoring Systems
- Points per element
- Time bonuses
- Combo multipliers
- Penalty zones
