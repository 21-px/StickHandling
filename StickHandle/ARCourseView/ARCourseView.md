# ARCourseView.swift

## Purpose
The main AR experience view that combines puck tracking, course visualization, and gameplay validation into a complete augmented reality stickhandling drill.

## What It Does

### Input
- Selected `Course` object (defines the drill/course structure)
- Live camera feed from ARKit
- Puck position data from computer vision tracking

### Transformation
1. **AR Scene Setup**: Creates an ARKit session with horizontal plane detection
2. **Course Visualization**: Renders course lines as 3D entities in AR space
3. **Real-time Tracking**: Processes camera frames to detect and track the puck
4. **Coordinate Mapping**: Converts 2D puck positions to 3D AR world coordinates
5. **Progress Validation**: Tracks line crossings and validates course completion
6. **UI Overlay**: Displays timer, score, and interactive controls

### Output
- Full-screen AR view with camera feed
- 3D course lines rendered in AR space
- Visual puck tracking overlay (red circle)
- Real-time statistics (timer, cross count)
- Course completion feedback

## Key Components

### ARCourseView (Main View)
- **Type**: SwiftUI View
- **Responsibilities**:
  - Orchestrates all subcomponents (tracker, validator, mapper)
  - Manages app lifecycle (start, pause, resume)
  - Handles user interactions (start button, recenter gesture)
  - Provides debug access to `PuckTrackingView`

### ARViewContainer (UIViewRepresentable)
- **Type**: SwiftUI wrapper for RealityKit's ARView
- **Responsibilities**:
  - Configures ARKit session with world tracking
  - Manages AR scene (anchors, entities)
  - Handles plane detection and course positioning
  - Passes camera frames to puck tracker
  - Enables LiDAR scene depth on supported devices

### Coordinator (ARSessionDelegate)
- **Type**: AR session delegate and scene manager
- **Responsibilities**:
  - Creates and updates 3D line entities
  - Handles plane detection events
  - Manages course repositioning (recenter feature)
  - Extracts depth data from LiDAR when available
  - Transforms coordinates for puck tracking

## State Management

### Observable Objects
- `PuckTracker`: Detects puck position using computer vision
- `CourseValidator`: Tracks progress and validates line crossings
- `CoordinateMapper`: Maps 2D screen coordinates to 3D AR space

### Local State
- `hasStarted`: Whether the drill has been started
- `isRecalibrating`: Temporary flag shown during recenter
- `showPuckTrackingView`: Controls debug view presentation
- `arSession`: Reference to ARKit session for lifecycle control
- `cameraIntrinsics`: Camera parameters for distance estimation

## Features

### Course Positioning
- **Initial Placement**: Automatically places course on first detected horizontal plane
- **Recenter**: Long-press gesture repositions course at current camera aim point
- **Raycast-based**: Uses ARKit raycasting for accurate 3D placement

### Puck Tracking Integration
- **Computer Vision**: Processes ARKit camera frames for color-based puck detection
- **LiDAR Enhancement**: Uses scene depth on iPhone 12 Pro+ for accurate distance
- **Coordinate Transformation**: Accounts for device orientation (portrait/landscape)
- **Debug Mode**: Full-screen debug view accessible via button overlay

### Visual Feedback
- **Active Line Highlighting**: Green for current line, orange for inactive
- **Puck Overlay**: Red circle follows detected puck position
- **Timer Display**: Real-time countdown with visual urgency (red when < 5s)
- **Completion UI**: Shows success/failure with cross count

## Technical Details

### AR Configuration
```swift
ARWorldTrackingConfiguration
- Plane detection: .horizontal
- Scene reconstruction: .meshWithClassification (LiDAR devices)
- Frame semantics: .sceneDepth (for distance estimation)
```

### Coordinate Systems
- **Screen Space**: Normalized (0-1) from puck tracker
- **Camera Space**: ARKit camera transform
- **World Space**: 3D AR coordinates (meters)

### Performance Optimizations
- Frame throttling in puck tracker
- Efficient line segment intersection tests
- Reuses 3D entities during recenter
- Background processing queues

## Related Files
- `PuckTracker.swift`: Computer vision detection
- `CourseValidator.swift`: Game logic and scoring
- `CoordinateMapper.swift`: 2D/3D coordinate conversion
- `Course.swift`: Course data models
- `PuckOverlay.swift`: Visual tracking indicator
- `PuckTrackingView.swift`: Debug/calibration view

## Platform Requirements
- iOS 13.0+ (ARKit 3)
- Device with A12+ chip (ARKit support)
- LiDAR features require iPhone 12 Pro or later
