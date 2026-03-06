# Claude AI Instructions for StickHandle Project

## Developer Context
The developer using this AI assistant is a frontend/JavaScript engineer with extensive frontend experience but **no prior iOS/Swift development experience**. Please provide clear explanations, avoid assuming Swift/iOS knowledge, and draw parallels to web/JavaScript concepts when helpful.

## Code Documentation Standard
Every function and file must include a comment block at the top explaining its purpose in the following format:

```swift
/// Input: [Describe input parameters and their types]
/// Transformation: [Explain what the function/file does and how it processes the data]
/// Output: [Describe what is returned or the result of the operation]
```

Example:
```swift
/// Input: User's location (CLLocation), search radius (Double in meters)
/// Transformation: Queries CoreLocation for nearby points of interest, filters by radius, sorts by distance
/// Output: Array of POI objects sorted nearest to farthest
func findNearbyLocations(from location: CLLocation, radius: Double) -> [PointOfInterest] {
    // implementation
}
```

## General Guidelines

### 1. Do Not Create .md Files for Explanations
- **Do not create markdown files to explain what you're doing** unless explicitly requested
- Only use .md files when the developer asks, or if you need it for context on long running tasks
- Keep explanations in chat responses instead of creating documentation files
- Focus on code changes, not documentation generation

### 2. Always Verify No Build Errors
- **Double check that there will be no build errors** after completing tasks
- Verify all method calls exist before using them
- Ensure all properties are declared in the correct classes
- Check that all types are properly defined and imported
- Confirm syntax is correct before finishing

### 3. Do Not Build or Edit Tests
- **Do not create test files** unless explicitly requested
- **Do not modify existing test files** 
- Focus on production code only
- Testing will be handled separately by the developer

### 4. Reuse Existing Functionality
- **Always check if functionality already exists** before creating new code
- Search the codebase for similar functions, views, or utilities
- Extend or refactor existing code rather than duplicating
- If you find existing functionality, reference it and ask if it should be reused
- DRY principle: Don't Repeat Yourself

### 5. Explain iOS/Swift Concepts
When introducing iOS/Swift concepts, provide brief explanations:
- **SwiftUI**: Like React - declarative UI framework
- **@State**: Like React's useState - local component state
- **@Binding**: Like passing state setters as props
- **Combine**: Like RxJS - reactive programming
- **async/await**: Same concept as JavaScript promises
- **Actors**: Like having thread-safe singleton classes
- **View Protocol**: Like React component interface
- **Modifiers**: Like CSS or method chaining for styling

### 6. Code Organization
- Keep views small and composable (like React components)
- Extract reusable components into separate files
- Use meaningful file and function names
- Group related functionality together

### 7. Prefer Modern Swift
- Use Swift Concurrency (async/await) over older patterns
- Use SwiftUI over UIKit when possible
- Use native Apple frameworks and APIs

## File Structure Guidelines
- **Views**: SwiftUI view components (like React components)
- **Models**: Data structures and business logic (like TypeScript interfaces/classes)
- **ViewModels**: State management for views (like React hooks or state management)
- **Services**: API calls, data fetching, external integrations (like service layers)
- **Utilities**: Helper functions and extensions (like utils folder)

## Communication
- Ask clarifying questions when requirements are unclear
- Explain trade-offs between different approaches
- Provide context for iOS-specific decisions
- Suggest improvements but respect the developer's choices

---
*This file helps Claude AI understand the project context and development preferences.*
