//
//  ContentView.swift
//  StickHandle
//
//  Created by Tyson on 3/3/26.
//

/// Input: None (app entry point)
/// Transformation: Routes to AR course view for testing
/// Output: Displays ARCourseView with Side Shuttle course

import SwiftUI

struct ContentView: View {
    
    var body: some View {
        ARCourseView(course: .sideShuttleBeginner)
    }
}

#Preview {
    ContentView()
}
