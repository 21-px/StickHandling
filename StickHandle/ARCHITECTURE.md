# StickHandle App - Architecture Document

## Project Overview
StickHandle is a mobile training app that helps users improve their hockey stickhandling skills through gamified daily challenges, similar to Duolingo's learning approach. The app uses computer vision, AR, and gamification to create an engaging practice experience.

## Core Concept
Users complete daily stickhandling challenges by navigating a puck through AR-placed obstacles while being tracked by their iPhone's camera. Progress is tracked with streaks, difficulty levels, and leaderboards.

---

## Development Phases

### Phase 1: Color-Based Puck Tracking
**Goal**: Enable real-time puck tracking using computer vision

#### Technical Components
- **Framework**: Vision framework (Apple's computer vision API)
- **Camera Integration**: AVFoundation for camera capture
- **Color Detection**: HSB color space filtering to identify bright puck color
- **Object Tracking**: Vision's VNDetectRectanglesRequest or VNTrackObjectRequest
- **Coordinate Mapping**: Convert camera coordinates to screen/AR coordinates

#### Key Files to Create
- `PuckTracker.swift` - Main tracking logic
- `CameraManager.swift` - Camera session management
- `ColorFilter.swift` - Color detection and filtering utilities
- `TrackingView.swift` - SwiftUI view showing camera feed with overlay

#### Similar Web Concept
Like using JavaScript's Canvas API or WebRTC with TensorFlow.js for object detection in the browser.

#### Dependencies
- AVFoundation
- Vision
- CoreImage (for color processing)

---

### Phase 2: AR Course Setup & Line-Based Navigation
**Goal**: Use AR to show users where cross-lines are placed and validate puck movement through the course

#### Technical Components
- **Framework**: ARKit for spatial tracking and plane detection
- **Plane Detection**: Horizontal plane detection for floor mapping
- **Course System**: Line-based course definition with cross-lines perpendicular to movement
- **Virtual Lines**: AR visualization showing glowing lines on floor that must be crossed
- **Course Definition**: Data models for line-based courses (start, end, direction)
- **Line Crossing Detection**: Validate when puck crosses lines in correct order/direction
- **Coordinate Transform**: Map 2D puck tracking to 3D AR world space

#### Course Element Types
```swift
enum CourseElement {
    case checkpoint(position: Vector3, radius: Float)        // Start/finish points
    case crossLine(start: Vector3, end: Vector3, direction: CrossDirection)  // Lines to cross
}

enum CrossDirection {
    case forward, backward, leftToRight, rightToLeft, any
}
```

#### Why Line-Based?
- ✅ **No corner-cutting** - Must physically cross each line
- ✅ **Works for any shape** - Zigzags, circles, figure-8s all use same elements
- ✅ **Minimal elements** - 4-6 lines define complex courses
- ✅ **Easy AR visualization** - Draw glowing lines on floor
- ✅ **Direction enforcement** - Can require specific crossing direction
- ✅ **Real training analog** - Like agility cones, timing gates, slalom poles

#### Example Courses

**Beginner - Simple Zigzag:**
- Checkpoint (start) → 3 cross-lines → Checkpoint (finish)
- Lines placed perpendicular to forward movement

**Intermediate - Circle Course:**
- 8 radial lines emanating from center point
- Must cross all 8 in clockwise order
- Teaches smooth circular stickhandling

**Expert - Figure-8:**
- Two circles connected by crossing lines
- Requires tight directional changes
- Fast time limit

#### Key Files to Create
- `ARCourseView.swift` - Main AR view for course visualization
- `Course.swift` - Course data model with line-based elements
- `CourseElement.swift` - Enum for checkpoint vs crossLine types
- `CourseValidator.swift` - Validates line crossings in correct order/direction
- `LineCrossingDetector.swift` - Geometric intersection logic for line crosses
- `ARLineRenderer.swift` - Renders glowing lines in AR space
- `CoordinateMapper.swift` - Maps 2D puck position to 3D AR space
- `CourseRepository.swift` - Stores and retrieves course definitions

#### Line Crossing Validation Logic
```swift
func checkLineCross(from: Vector3, to: Vector3, line: CrossLine) -> Bool {
    // 1. Check if puck path intersects line segment
    if segmentsIntersect(a1: from, a2: to, b1: line.start, b2: line.end) {
        // 2. Verify crossing direction (if required)
        if line.direction != .any {
            let crossDirection = determineCrossDirection(from, to, line)
            return crossDirection == line.direction
        }
        return true
    }
    return false
}
```

#### Similar Web Concept
Like using WebXR or AR.js to place 3D objects in real space, combined with 2D line intersection algorithms (like game hitbox detection).

#### Dependencies
- ARKit
- RealityKit (for 3D rendering)
- Combine (for reactive updates)
- SceneKit (for line rendering)

---

### Phase 3: Puck Occlusion Handling
**Goal**: Maintain tracking accuracy when puck is temporarily obstructed by hockey stick or hand

#### Technical Components
- **Temporal Smoothing**: Track position history to predict during occlusion
- **Velocity-Based Prediction**: Estimate puck position based on recent movement
- **Obstruction Tolerance**: Allow brief detection gaps without losing tracking
- **Smart Interpolation**: Fill gaps between last known and newly detected positions
- **Course-Aware Logic**: For line-based courses, only validate positions before/after obstruction

#### Why This Is Critical
Hockey stickhandling requires the stick to frequently pass over/near the puck, causing:
- Brief detection loss (0.1-0.3 seconds)
- Partial occlusion (puck partially visible)
- Rapid movement that's hard to track

#### Occlusion Handling Strategy

**Scenario 1: Brief Obstruction (< 0.1s)**
- Use last known position
- No prediction needed
- Resume tracking when puck reappears

**Scenario 2: Stick Drag (0.1-0.3s)**
- Predict position using velocity from last 3-5 frames
- Show predicted position with lower confidence
- Validate line crossing using interpolated path

**Scenario 3: Extended Obstruction (> 0.3s)**
- Mark as "tracking lost"
- Pause course timer (optional)
- Resume when puck reappears

**Key Insight for Line-Based Courses:**
You only need to know:
1. Position **before** line
2. Position **after** line
3. Did the path cross the line?

Brief obstruction **during** crossing is acceptable!

#### Key Files to Create/Modify
- `PuckTracker.swift` (modify) - Add position history and prediction
- `PositionPredictor.swift` - Velocity-based position estimation
- `OcclusionDetector.swift` - Detect and classify occlusion events
- `PositionHistory.swift` - Circular buffer of recent positions
- `PathInterpolator.swift` - Interpolate path between known positions

#### Algorithm Overview
```swift
class PuckTracker {
    private var positionHistory: [PuckPosition] = []  // Last 10 positions
    private var lastValidDetection: Date = Date()
    private let obstructionTolerance: TimeInterval = 0.3
    
    func processFrame() {
        if let detected = detectPuck() {
            // Valid detection
            positionHistory.append(detected)
            lastValidDetection = Date()
            publishPosition(detected)
        } else {
            // No detection - possibly obstructed
            let gapDuration = Date().timeIntervalSince(lastValidDetection)
            
            if gapDuration < obstructionTolerance {
                // Predict position
                if let predicted = predictPosition() {
                    publishPosition(predicted, confidence: 0.7)
                }
            } else {
                // Lost tracking
                publishTrackingLost()
            }
        }
    }
    
    func predictPosition() -> PuckPosition? {
        guard positionHistory.count >= 3 else { return positionHistory.last }
        
        let velocity = calculateVelocity(from: positionHistory.suffix(3))
        let lastPos = positionHistory.last!
        let timeDelta = Date().timeIntervalSince(lastValidDetection)
        
        return PuckPosition(
            x: lastPos.x + velocity.x * timeDelta,
            y: lastPos.y + velocity.y * timeDelta,
            confidence: lastPos.confidence * 0.7
        )
    }
}
```

#### Validation with Occlusion
```swift
class CourseValidator {
    func checkLineCross(currentPosition: Vector3?, previousPosition: Vector3?) {
        // Even if some frames were missed due to obstruction,
        // we can still validate if the line was crossed
        
        if let prev = previousPosition, let curr = currentPosition {
            if didCrossLine(from: prev, to: curr, line: currentLine) {
                markLineCompleted()
            }
        }
    }
}
```

#### Similar Web Concept
Like Kalman filtering used in video games for smoothing player movement, or predictive algorithms in video conferencing when packets are dropped.

#### Dependencies
- Foundation (for date/time calculations)
- Accelerate (for vector math if needed)

#### Performance Considerations
- Keep history size small (5-10 frames)
- Prediction should be lightweight (< 1ms)
- Only predict during active course runs

---

### Phase 4: Audio Feedback & Voice Control
**Goal**: Provide real-time audio announcements and hands-free voice commands

#### Technical Components
- **Text-to-Speech**: AVSpeechSynthesizer for announcements
- **Speech Recognition**: Speech framework for voice commands
- **Audio Cues**: Sound effects for events (line crossed, time warnings)
- **Background Audio**: Proper audio session configuration
- **Commands**: "Start", "Stop", "Restart", "Pause", etc.

#### Key Files to Create
- `AudioManager.swift` - Centralized audio management
- `VoiceCommandHandler.swift` - Speech recognition and command processing
- `SoundEffects.swift` - Sound effect player
- `TimerAnnouncer.swift` - Countdown and time announcement logic

#### Similar Web Concept
Like using the Web Speech API for speech recognition and synthesis.

#### Dependencies
- AVFoundation (AVSpeechSynthesizer, AVAudioPlayer)
- Speech framework
- AudioToolbox (for system sounds)

#### Permissions Required
- Microphone access (for voice commands)

---

### Phase 5: Duolingo-Style Course Structure
**Goal**: Create a progressive learning system with difficulty levels, streaks, and daily challenges

#### Technical Components
- **Course Progression**: Unlock system based on completion
- **Difficulty Levels**: Beginner, Intermediate, Expert
- **Daily Challenges**: One new challenge per day
- **Streak Tracking**: Consecutive days completed
- **Performance Metrics**: Time, accuracy, completion stats
- **Local Storage**: SwiftData for persisting user progress

#### Key Files to Create
- `CourseManager.swift` - Manages course progression and unlocking
- `DifficultyLevel.swift` - Enum and configuration for difficulty levels
- `Challenge.swift` - Model for individual challenges
- `StreakTracker.swift` - Tracks daily completion streaks
- `ProgressView.swift` - UI showing user progress and streaks
- `DailyChallengeView.swift` - Main view for daily challenge
- `UserProgress.swift` - SwiftData model for user's progress

#### Data Structure
```swift
// Example structure
Course {
    id, name, difficulty, challenges[], requiredPreviousCourse
}

Challenge {
    id, courseId, obstacles[], timeLimit, successCriteria
}

UserProgress {
    completedChallenges[], currentStreak, longestStreak, lastCompletionDate
}
```

#### Similar Web Concept
Like a React app with Redux/Context for state management, localStorage for persistence, and a skill tree/progression system.

#### Dependencies
- SwiftData (local database)
- Foundation (Date handling for streaks)

---

### Phase 6: Leaderboards
**Goal**: Enable competition through global and friend leaderboards

#### Technical Components
- **Backend Integration**: API calls to leaderboard service
- **Game Center**: Apple's gaming social network (optional alternative)
- **Score Submission**: Submit times and challenge completions
- **Ranking Display**: Show top players and user's rank
- **Friend System**: Filter leaderboard by friends
- **Score Types**: Daily, weekly, all-time rankings

#### Key Files to Create
- `LeaderboardService.swift` - API calls for leaderboard data
- `LeaderboardView.swift` - UI displaying rankings
- `ScoreSubmission.swift` - Model and logic for submitting scores
- `GameCenterManager.swift` - Optional Game Center integration
- `FriendManager.swift` - Friend list management

#### Similar Web Concept
Like making REST API calls with fetch/axios and displaying data in a sorted table/list component.

#### Dependencies
- URLSession (for API calls)
- GameKit (optional, for Game Center)
- Combine (for reactive data loading)

#### Backend Requirements
- REST API endpoints for:
  - GET `/leaderboard` - Fetch rankings
  - POST `/score` - Submit score
  - GET `/leaderboard/friends` - Friend rankings

---

### Phase 7: Signup & Authentication
**Goal**: User account creation and authentication

#### Technical Components
- **Sign in with Apple**: Primary authentication method (required for App Store)
- **Email/Password**: Secondary authentication option
- **Backend Auth**: JWT tokens or similar
- **Profile Management**: User profile data
- **Onboarding Flow**: First-time user experience

#### Key Files to Create
- `AuthenticationManager.swift` - Handles login/logout/session
- `SignInWithAppleButton.swift` - Apple Sign-In integration
- `SignupView.swift` - Signup form UI
- `LoginView.swift` - Login form UI
- `OnboardingView.swift` - First-time user tutorial
- `UserProfile.swift` - Model for user data
- `KeychainManager.swift` - Secure credential storage

#### Similar Web Concept
Like implementing OAuth, JWT authentication with React forms, and using localStorage/cookies for session tokens.

#### Dependencies
- AuthenticationServices (Sign in with Apple)
- Security framework (Keychain)
- URLSession (for auth API calls)

#### Backend Requirements
- POST `/auth/signup` - Create account
- POST `/auth/login` - Login
- POST `/auth/apple` - Apple Sign-In verification
- GET `/user/profile` - Get user data

---

### Phase 8: Invite/Referral System
**Goal**: Viral growth through user invitations

#### Technical Components
- **Share Sheet**: Native iOS sharing
- **Referral Codes**: Unique codes per user
- **Deep Links**: App links that open app with referral info
- **Referral Tracking**: Track who invited whom
- **Rewards**: Incentives for referrals (optional)

#### Key Files to Create
- `ReferralManager.swift` - Generate and track referral codes
- `ShareManager.swift` - Handle iOS share sheet
- `DeepLinkHandler.swift` - Process app deep links
- `InviteView.swift` - UI for inviting friends
- `ReferralRewards.swift` - Reward logic for successful referrals

#### Similar Web Concept
Like using the Web Share API or social share buttons, with UTM parameters for tracking referral sources.

#### Dependencies
- UIKit (UIActivityViewController for sharing)
- Universal Links (for deep linking)

#### Backend Requirements
- POST `/referral/create` - Generate referral code
- POST `/referral/redeem` - Redeem referral code
- GET `/referral/stats` - Referral statistics

---

### Phase 9: Push Notifications
**Goal**: Re-engage users with daily reminders and achievements

#### Technical Components
- **Local Notifications**: For daily challenge reminders
- **Remote Notifications**: For social interactions, achievements
- **APNs**: Apple Push Notification service
- **Notification Categories**: Different types of notifications
- **Permission Handling**: Request user permission

#### Key Files to Create
- `NotificationManager.swift` - Centralized notification handling
- `LocalNotificationScheduler.swift` - Schedule daily reminders
- `RemoteNotificationHandler.swift` - Handle APNs messages
- `NotificationPermissions.swift` - Permission request flow

#### Notification Types
- Daily challenge reminder
- Streak at risk (missed a day)
- Friend beat your score
- New level unlocked
- Achievement earned

#### Similar Web Concept
Like using service workers for push notifications on web, with notification permissions API.

#### Dependencies
- UserNotifications framework
- APNs (server-side)

#### Backend Requirements
- POST `/notifications/register` - Register device token
- POST `/notifications/send` - Send push notification

---

### Phase 10: App Store Review Prompt
**Goal**: Encourage positive App Store reviews at optimal moments

#### Technical Components
- **StoreKit**: SKStoreReviewController for native review prompt
- **Trigger Logic**: Show after positive experiences
- **Rate Limiting**: Don't spam users (iOS limits to 3 times per year)
- **Tracking**: Record when prompts shown

#### Key Files to Create
- `ReviewPromptManager.swift` - Logic for when to show prompt
- `ReviewTriggers.swift` - Conditions that trigger review request

#### Trigger Conditions
- After completing 5 challenges
- After achieving a personal best
- After maintaining a 7-day streak
- Never show if user recently had a failed attempt
- Respect Apple's automatic rate limiting

#### Similar Web Concept
Like showing a modal asking for feedback after positive user actions.

#### Dependencies
- StoreKit (SKStoreReviewController)

---

### Phase 11: Logging & Analytics
**Goal**: Track usage, errors, and user behavior for improvement

#### Technical Components
- **Crash Reporting**: Track app crashes
- **Analytics Events**: User actions and feature usage
- **Performance Monitoring**: App performance metrics
- **Privacy-Compliant**: Respect user privacy preferences

#### Key Files to Create
- `Logger.swift` - Centralized logging utility
- `AnalyticsManager.swift` - Track events
- `ErrorReporter.swift` - Error and crash reporting
- `PerformanceMonitor.swift` - Track performance metrics

#### Events to Track
- Challenge started/completed/failed
- Features used (AR setup, voice commands)
- User progression (level ups, streaks)
- Errors and crashes
- Performance (tracking FPS, detection accuracy)

#### Similar Web Concept
Like using Google Analytics, Sentry for error tracking, or custom logging with console.log/server logging.

#### Dependencies
- OSLog (Apple's logging system)
- Third-party options: Firebase Analytics, Mixpanel, or Sentry

#### Privacy Considerations
- Get user consent for analytics tracking
- Anonymous data collection where possible
- Privacy policy compliance

---

## Potential Future Features

### A/B Testing for Monetization
**Goal**: Test different monetization strategies to maximize revenue

#### Approaches to Test
- Freemium: Free basic courses, paid advanced courses
- Subscription: Monthly/yearly subscription for all features
- One-time purchase: Pay once for lifetime access
- Ads: Free with ads, paid to remove
- Trial periods: Different trial lengths (3 days vs 7 days vs 14 days)

#### Technical Components
- **Feature Flags**: Toggle features per user cohort
- **User Segmentation**: Assign users to test groups
- **Conversion Tracking**: Track purchase events
- **Analytics**: Compare conversion rates between groups

#### Key Files
- `ABTestManager.swift` - A/B test assignment and tracking
- `PaywallView.swift` - Purchase screen with variants
- `SubscriptionManager.swift` - In-app purchase handling

#### Dependencies
- StoreKit 2 (for in-app purchases)
- Third-party A/B testing (Firebase Remote Config, Optimizely, or custom)

---

## Technical Architecture Overview

### Design Pattern: MVVM (Model-View-ViewModel)
```
View (SwiftUI) 
    ↕
ViewModel (ObservableObject)
    ↕
Model (Data structures)
    ↕
Services (API calls, data persistence)
```

**Why MVVM?**
- Similar to React's component + hooks pattern
- Separates UI from business logic
- Easy to test and maintain
- Standard pattern for SwiftUI apps

### Data Flow
1. **User Action** → View captures tap/gesture
2. **View** → Calls ViewModel method
3. **ViewModel** → Updates state, calls Service if needed
4. **Service** → Makes API call or database query
5. **Service** → Returns data to ViewModel
6. **ViewModel** → Publishes state change
7. **View** → Automatically re-renders with new data

### Key Technologies
- **SwiftUI**: UI framework (like React)
- **Combine**: Reactive programming (like RxJS)
- **async/await**: Asynchronous operations (like JS promises)
- **SwiftData**: Local database (like SQLite/IndexedDB)
- **Vision**: Computer vision (like TensorFlow.js)
- **ARKit**: Augmented reality (like WebXR)

### Project Structure
```
StickHandle/
├── App/
│   ├── StickHandleApp.swift (entry point)
│   └── AppDelegate.swift
├── Views/
│   ├── Onboarding/
│   ├── Authentication/
│   ├── Challenge/
│   ├── Progress/
│   └── Leaderboard/
├── ViewModels/
│   ├── ChallengeViewModel.swift
│   ├── ProgressViewModel.swift
│   └── LeaderboardViewModel.swift
├── Models/
│   ├── User.swift
│   ├── Challenge.swift
│   ├── Course.swift
│   └── UserProgress.swift
├── Services/
│   ├── PuckTracker.swift
│   ├── ARCourseManager.swift
│   ├── APIService.swift
│   ├── AuthenticationManager.swift
│   └── NotificationManager.swift
├── Utilities/
│   ├── Extensions/
│   ├── Logger.swift
│   └── Constants.swift
└── Resources/
    ├── Assets.xcassets
    └── Sounds/
```

---

## API Endpoints Summary

### Authentication
- `POST /auth/signup` - Create account
- `POST /auth/login` - Login
- `POST /auth/apple` - Apple Sign-In
- `GET /user/profile` - Get user profile

### Challenges & Progress
- `GET /challenges` - Get available challenges
- `POST /challenge/complete` - Submit challenge completion
- `GET /progress` - Get user progress

### Leaderboard
- `GET /leaderboard` - Global rankings
- `GET /leaderboard/friends` - Friend rankings
- `POST /score` - Submit score

### Social
- `POST /referral/create` - Generate referral code
- `POST /referral/redeem` - Redeem code
- `GET /friends` - Get friend list
- `POST /friends/add` - Add friend

### Notifications
- `POST /notifications/register` - Register device
- `POST /notifications/preferences` - Update notification preferences

---

## Privacy & Permissions

### Required Permissions
1. **Camera** - For puck tracking and AR (Phase 1 & 2)
2. **Microphone** - For voice commands (Phase 3)
3. **Notifications** - For daily reminders (Phase 8)

### Optional Permissions
1. **Photo Library** - To save challenge completion videos (future feature)
2. **Location** - For local leaderboards (future feature)

### Privacy Policy Must Cover
- Camera usage (puck tracking, no recording unless user saves)
- Microphone usage (voice commands only)
- Data collection (analytics, performance data)
- Account information storage
- Third-party services (analytics, crash reporting)

---

## Testing Strategy

### Manual Testing Focus
- Camera tracking accuracy in different lighting
- AR placement accuracy on different surfaces
- Voice command recognition accuracy
- UI/UX flow for new users
- Challenge difficulty balance

### Key Test Scenarios
1. First-time user onboarding flow
2. Complete a challenge start-to-finish
3. Losing streak vs maintaining streak
4. Referral code sharing and redemption
5. Offline mode (what works without internet?)

---

## Development Order Recommendations

### Why This Order?
1. **Phase 1 (Tracking)** - Core tech that everything else depends on ✅ COMPLETE
2. **Phase 2 (AR Lines)** - Extends tracking with line-based course gameplay
3. **Phase 3 (Occlusion)** - Handles real-world stick obstruction
4. **Phase 4 (Audio)** - Improves UX of gameplay
5. **Phase 5 (Progression)** - Makes it a game, not just a tech demo
6. **Phase 6-11** - Growth and retention features

### MVP (Minimum Viable Product)
**Phases 1-5** create a functional, engaging app that users can enjoy.
**Phases 6-11** add growth, monetization, and polish.

### Potential Shortcuts
- Use Game Center instead of custom leaderboard (saves backend work)
- Use Firebase for auth, database, and analytics (reduces backend needs)
- Start with just "Beginner" difficulty and add others later
- Launch without voice commands, add later

---

## Technical Challenges & Solutions

### Challenge: Puck Tracking Accuracy
**Problem**: Color-based tracking may fail in poor lighting or with similar colors in frame
**Solutions**:
- Allow user to calibrate puck color on first use
- Use multiple detection methods (color + shape + motion)
- Show confidence indicator to user
- Provide good lighting recommendations in onboarding

### Challenge: AR Obstacle Placement
**Problem**: ARKit plane detection can be slow or inaccurate
**Solutions**:
- Show clear instructions for camera movement
- Provide visual feedback during scanning
- Allow manual adjustment of obstacle positions
- Save successful placements for that physical space

### Challenge: Voice Command Reliability
**Problem**: Speech recognition may misinterpret commands during active gameplay
**Solutions**:
- Use simple, distinct command words
- Show visual confirmation of recognized commands
- Provide button alternatives for all voice commands
- Allow customization of command words

### Challenge: Backend Costs
**Problem**: Running servers for leaderboards, auth, notifications can be expensive
**Solutions**:
- Use Firebase (generous free tier, scales automatically)
- Use CloudKit (Apple's free backend for iOS apps)
- Use Game Center for leaderboards (free, but Apple-only)
- Start with local-only mode, add backend later

---

## Glossary (iOS/Swift → JavaScript/Web)

| iOS/Swift | JavaScript/Web Equivalent |
|-----------|---------------------------|
| SwiftUI View | React Component |
| @State | useState() |
| @Binding | Props with setter function |
| @ObservedObject | useContext() / Redux state |
| Combine | RxJS |
| URLSession | fetch() / axios |
| Codable | JSON.parse() / JSON.stringify() |
| UserDefaults | localStorage |
| SwiftData | IndexedDB / SQLite |
| async/await | async/await (same!) |
| Protocol | Interface / Abstract class |
| Extension | Adding methods to prototype |
| Guard statement | Early return with if (!condition) |
| Optional (?) | Variable that might be null/undefined |

---

*This architecture document is a living document and will be updated as development progresses and requirements evolve.*
