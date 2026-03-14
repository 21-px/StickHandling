# CourseValidator.swift

## Purpose
Validates course progress by detecting line crossings, tracking score, managing the timer, and determining course completion. The "game logic" component of the stickhandling drill.

## What It Does

### Input
- 3D puck positions over time (from `CoordinateMapper`)
- Course definition (lines, checkpoints, rules)

### Transformation
1. **Line Crossing Detection**: Checks if puck path crosses course lines
2. **Progress Tracking**: Maintains current score and active line
3. **Timer Management**: Counts down from course time limit
4. **Completion Logic**: Determines when course is successfully completed
5. **State Publishing**: Broadcasts state changes to UI

### Output
- `crossCount`: Number of successful line crosses
- `activeLine`: Index of current target line
- `isComplete`: Whether course is finished
- `timeRemaining`: Seconds left on timer

## Key Algorithms

### Line Crossing Detection

#### Line-Line Intersection (2D)
Uses computational geometry to detect when puck path crosses a line:

```swift
func lineSegmentsIntersect(a1, a2, b1, b2) -> Bool
```

**Algorithm: CCW (Counter-Clockwise) Test**
1. Calculate cross products to determine orientation
2. Segments intersect if endpoints are on opposite sides
3. Handle collinear edge cases

**Math:**
```
CCW(A, B, C) = (C.y - A.y) × (B.x - A.x) - (B.y - A.y) × (C.x - A.x)

Intersection if:
  CCW(A1, A2, B1) × CCW(A1, A2, B2) < 0
  AND
  CCW(B1, B2, A1) × CCW(B1, B2, A2) < 0
```

**Input:**
- `a1→a2`: Puck movement path (last position to current)
- `b1→b2`: Course line (start to end)

**Projection to 2D:**
Ignores Y-axis (height) since movement is on horizontal plane:
```swift
2D points = (X, Z) from 3D positions
```

#### Checkpoint Detection
For checkpoint elements:
```swift
distance = simd_distance(puckPosition, checkpointPosition)
isInside = distance <= checkpointRadius
```

### Score Tracking

#### Cross Counting
```swift
if lineWasCrossed && lastCrossedLine != currentLine {
    crossCount += 1
    lastCrossedLine = currentLine
}
```

**Anti-Bounce Logic:**
- Tracks last crossed line
- Prevents double-counting when puck hovers near line
- Resets when player moves to different line

#### Active Line Management

**Alternating Mode** (shuttle drills):
```swift
activeLine = (activeLine + 1) % lineCount
```
Switches between lines after each cross.

**Sequential Mode:**
```swift
activeLine = min(activeLine + 1, lineCount - 1)
```
Advances through lines in order.

**Continuous Mode:**
Cycles through all lines repeatedly.

### Timer Management

```swift
Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true)
```

**Update Logic:**
```swift
elapsed = Date().timeIntervalSince(startTime)
timeRemaining = max(0, timeLimit - elapsed)

if timeRemaining <= 0 {
    completeCourse()
}
```

**Update Frequency:** 0.1 seconds (10 Hz) for smooth countdown

### Completion Detection

#### Success Criteria Types

**Minimum Crosses:**
```swift
case .minimumCrosses(let required):
    return crossCount >= required
```

**All Elements Completed:**
```swift
case .allElementsCompleted:
    return crossCount >= course.elements.count
```

**Minimum Score:**
```swift
case .minimumScore(let required):
    return crossCount >= required
```

**Completion Conditions:**
1. Success criteria met AND time remaining > 0
2. OR time expired (shows completion UI, may be success/failure)

## State Management

### Published Properties
All observable by SwiftUI views:
```swift
@Published var crossCount: Int = 0
@Published var activeLine: Int = 0
@Published var isComplete: Bool = false
@Published var timeRemaining: TimeInterval = 0
```

### Internal State
```swift
private var lastPuckPosition: SIMD3<Float>?
private var lastCrossedLine: Int?
private var timer: Timer?
private var startTime: Date?
```

## Public API

### Lifecycle Methods

#### `startCourse()`
```swift
func startCourse()
```
**Actions:**
- Resets all counters to zero
- Starts timer from course time limit
- Sets initial active line
- Begins validation loop

#### `stopCourse()`
```swift
func stopCourse()
```
**Actions:**
- Invalidates and releases timer
- Stops validation updates
- Called on view disappear

### Position Updates

#### `updatePuckPosition(_:)`
```swift
func updatePuckPosition(_ position: SIMD3<Float>)
```
**Process:**
1. Compares with last known position
2. Checks if path crosses active line
3. Updates score if crossing detected
4. Stores current position for next frame
5. Checks completion criteria

**Called:** Every frame by `ARCourseView` when puck is detected

### Completion Check

#### `checkCompletion()`
```swift
func checkCompletion() -> Bool
```
Returns whether success criteria is currently met.

## Course Element Types

### CrossLine
```swift
.crossLine(start: SIMD3<Float>, end: SIMD3<Float>, direction: CrossDirection)
```
**Properties:**
- `start`, `end`: 3D endpoints of line (Y typically 0)
- `direction`: Optional crossing direction requirement

**Validation:**
2D line-line intersection test (ignores Y axis)

### Checkpoint
```swift
.checkpoint(position: SIMD3<Float>, radius: Float)
```
**Properties:**
- `position`: 3D center point
- `radius`: Trigger distance in meters

**Validation:**
3D distance check

## Repeat Modes

### `.alternating`
**Behavior:** Switch between lines after each cross
**Use Case:** Shuttle drills (side-to-side)
**Example:** Line 1 → Line 2 → Line 1 → Line 2...

### `.sequential`
**Behavior:** Complete lines in order, once
**Use Case:** Obstacle courses
**Example:** Line 1 → Line 2 → Line 3 → Complete

### `.continuous`
**Behavior:** Cycle through all lines until time expires
**Use Case:** Endurance drills
**Example:** Line 1 → 2 → 3 → 1 → 2 → 3...

## Performance Considerations

### Efficient Intersection Tests
- O(1) time complexity for line-line intersection
- Minimal allocations (uses value types)
- Fast cross product calculations via SIMD

### Timer Frequency
- 0.1s updates balance smoothness and CPU usage
- Invalidated immediately on completion
- Runs on main thread (safe for UI updates)

### Position Caching
- Stores last position to avoid redundant checks
- Only validates when puck moves
- Early exit if course complete

## Usage Example

```swift
// Create validator
let validator = CourseValidator(course: .sideShuttleBeginner)

// Start course
validator.startCourse()

// Update in real-time
func onPuckDetected(position: SIMD3<Float>) {
    validator.updatePuckPosition(position)
}

// Observe in SwiftUI
Text("\(validator.crossCount) crosses")
Text("Time: \(validator.timeRemaining)")

if validator.isComplete {
    Text("Course Complete!")
}
```

## Edge Cases Handled

### Hovering Near Line
Prevents double-counting via `lastCrossedLine` tracking.

### Rapid Crosses
Each cross only counted once until player moves away.

### Time Expiration
Course completes even if criteria not met (shown as failure).

### First Frame
Guards against nil `lastPuckPosition` on first update.

### Completion During Cross
Checks completion immediately after score update.

## Related Files
- `Course.swift`: Defines course structure and rules
- `ARCourseView.swift`: Displays validator state in UI
- `CoordinateMapper.swift`: Provides 3D positions for validation

## Dependencies
- `Foundation`: For `Timer`, `Date`, `TimeInterval`
- `Combine`: For `ObservableObject`
- `simd`: For 3D vector math

## Platform Requirements
- iOS 13.0+ (Combine framework)

## Future Enhancements

### Direction Validation
Implement `CrossDirection` checking:
- `.forward` / `.backward`
- `.leftToRight` / `.rightToLeft`
- Requires velocity/momentum tracking

### Combo System
Track consecutive crosses without mistakes:
- Bonus points for combos
- Streak tracking
- Perfect run detection

### Analytics
Track performance metrics:
- Average cross time
- Fastest cross
- Consistency score
- Path efficiency

### Adaptive Difficulty
Adjust based on performance:
- Speed up time limit if doing well
- Add more lines for advanced players
- Dynamic success criteria
