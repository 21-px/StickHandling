# ContentView.swift

## Purpose
The root SwiftUI view that serves as the app's entry point. Currently routes directly to the AR course experience for testing and development.

## What It Does

### Input
None - This is the top-level view in the app hierarchy.

### Transformation
Simply displays the AR course view with a pre-selected course.

### Output
Full-screen AR experience showing the Side Shuttle beginner course.

## Implementation

### Code
```swift
struct ContentView: View {
    var body: some View {
        ARCourseView(course: .sideShuttleBeginner)
    }
}
```

### Simplicity
This is intentionally minimal for rapid development:
- No navigation wrapper
- No course selection
- Direct to AR experience
- Single hardcoded course

## Current Behavior

### App Launch Flow
```
App Launch
    ↓
AppDelegate creates ContentView
    ↓
ContentView displays ARCourseView
    ↓
ARCourseView shows Side Shuttle course
    ↓
User sees AR camera with course lines
```

### Selected Course
```swift
.sideShuttleBeginner
```

**Details:**
- Difficulty: Beginner
- Mode: Alternating shuttle
- Time: 30 seconds
- Goal: 10 line crosses

## Future Production Implementation

### Course Selection Screen
```swift
struct ContentView: View {
    @State private var selectedCourse: Course?
    
    var body: some View {
        NavigationStack {
            if let course = selectedCourse {
                ARCourseView(course: course)
            } else {
                CourseSelectionView(selection: $selectedCourse)
            }
        }
    }
}
```

### Tab-Based Navigation
```swift
struct ContentView: View {
    var body: some View {
        TabView {
            CourseListView()
                .tabItem {
                    Label("Courses", systemImage: "figure.hockey")
                }
            
            ProgressView()
                .tabItem {
                    Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}
```

### Onboarding Flow
```swift
struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasOnboarded = false
    
    var body: some View {
        if hasOnboarded {
            MainAppView()
        } else {
            OnboardingView(onComplete: {
                hasOnboarded = true
            })
        }
    }
}
```

## Planned Features

### Course Selection
**UI Components:**
- List of available courses
- Difficulty badges
- Course descriptions
- Preview images/videos
- Estimated time
- Success rate statistics

**Example:**
```swift
struct CourseSelectionView: View {
    @Binding var selection: Course?
    
    var body: some View {
        List(Course.allCourses) { course in
            CourseRow(course: course)
                .onTapGesture {
                    selection = course
                }
        }
        .navigationTitle("Choose a Course")
    }
}
```

### Progress Tracking
**Features:**
- Course completion history
- Personal bests
- Streak tracking
- Achievement badges
- Skill progression

**Example:**
```swift
struct ProgressView: View {
    @StateObject private var progressManager = ProgressManager()
    
    var body: some View {
        ScrollView {
            VStack {
                StatsCard(stats: progressManager.overallStats)
                RecentCoursesView(courses: progressManager.recentCourses)
                AchievementsView(achievements: progressManager.achievements)
            }
        }
    }
}
```

### Settings
**Options:**
- Puck color calibration
- Distance units (feet/meters)
- Difficulty preference
- Audio feedback
- Haptic feedback
- LiDAR enable/disable

**Example:**
```swift
struct SettingsView: View {
    @AppStorage("useLidar") private var useLidar = true
    @AppStorage("distanceUnit") private var distanceUnit = "feet"
    
    var body: some View {
        Form {
            Section("Tracking") {
                Toggle("Use LiDAR", isOn: $useLidar)
                Button("Calibrate Puck Color") {
                    // Show PuckTrackingView
                }
            }
            
            Section("Display") {
                Picker("Distance Unit", selection: $distanceUnit) {
                    Text("Feet").tag("feet")
                    Text("Meters").tag("meters")
                }
            }
        }
    }
}
```

## Navigation Patterns

### Option 1: NavigationStack (Modern)
```swift
NavigationStack {
    CourseListView()
        .navigationDestination(for: Course.self) { course in
            ARCourseView(course: course)
        }
}
```

**Pros:**
- Modern SwiftUI API
- Type-safe navigation
- Deep linking support
- Programmatic navigation

**Cons:**
- iOS 16+ only
- Learning curve

### Option 2: NavigationView (Compatible)
```swift
NavigationView {
    CourseListView()
        .navigationBarTitle("Courses")
}
```

**Pros:**
- iOS 13+ compatible
- Well-documented
- Familiar pattern

**Cons:**
- Deprecated in iOS 16+
- Less flexible

### Option 3: Full Screen Covers
```swift
.fullScreenCover(item: $selectedCourse) { course in
    ARCourseView(course: course)
}
```

**Pros:**
- No navigation bar
- Immersive AR experience
- Gesture-free dismissal

**Cons:**
- No back navigation
- Requires manual dismiss

## State Management

### Current: Stateless
No state stored in ContentView (hardcoded course).

### Future: App-Level State
```swift
@StateObject private var appState = AppState()

var body: some View {
    MainAppView()
        .environmentObject(appState)
}
```

**AppState could include:**
- Current user
- Selected course
- Progress data
- Settings
- Authentication state

## Testing

### Preview Provider
```swift
#Preview {
    ContentView()
}
```

**Shows:** AR course view in Xcode preview

**Limitations:**
- AR doesn't work in preview
- Camera unavailable
- Use mock data for development

### Mock Development View
```swift
#Preview {
    ContentView()
        .environment(\.mockData, true)
}
```

Could inject mock data for preview testing.

## Performance Considerations

### Lazy Loading
Future implementation should lazy-load AR view:
```swift
if let course = selectedCourse {
    ARCourseView(course: course)
        .task {
            // Initialize AR session only when needed
        }
}
```

### Memory Management
AR/camera resources are heavy:
- Don't keep ARCourseView in memory when not visible
- Use `.fullScreenCover` or conditional rendering
- Release resources on navigation away

## App Architecture

### Current: Single-Screen
```
ContentView
  └── ARCourseView (always visible)
```

### Future: Multi-Screen
```
ContentView
  ├── TabView
  │   ├── CourseListView
  │   │   └── NavigationStack
  │   │       └── ARCourseView (on selection)
  │   ├── ProgressView
  │   └── SettingsView
  └── Onboarding (conditional)
```

## Design Philosophy

### Why Start Simple?
1. **Rapid prototyping:** Get to AR experience quickly
2. **Core feature focus:** Test tracking and validation first
3. **Avoid premature architecture:** Build UI once tracking works
4. **Faster iteration:** No navigation to click through

### When to Add Complexity?
- Multiple courses available
- User testing begins
- Feature set stabilizes
- App structure becomes clear

## Related Files
- `AppDelegate.swift`: Creates ContentView on launch
- `ARCourseView.swift`: The main AR experience
- `Course.swift`: Defines available courses

## Dependencies
- `SwiftUI`: For view rendering

## Platform Requirements
- iOS 13.0+ (SwiftUI)

## Migration Path

### Phase 1: Current (Development)
Direct to AR with hardcoded course

### Phase 2: Course Selection
```swift
NavigationStack {
    CourseListView()
}
```

### Phase 3: Full App
```swift
TabView {
    CoursesTab()
    ProgressTab()
    SettingsTab()
}
```

### Phase 4: Polish
- Onboarding
- Authentication
- Cloud sync
- Social features

## Best Practices

### Keep Root Simple
- Minimal logic in ContentView
- Delegate to child views
- Use environment objects for shared state
- Avoid complex state management here

### Separation of Concerns
- ContentView: Navigation/routing only
- Feature views: Specific functionality
- ViewModels: Business logic
- Models: Data structures

### Testability
```swift
struct ContentView: View {
    let initialCourse: Course
    
    init(course: Course = .sideShuttleBeginner) {
        self.initialCourse = course
    }
    
    var body: some View {
        ARCourseView(course: initialCourse)
    }
}
```

Dependency injection enables testing different courses.
