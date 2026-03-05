//
//  ContentView.swift
//  StickHandle
//
//  Created by Tyson on 3/3/26.
//

/// Input: None (app entry point)
/// Transformation: Routes to the main puck tracking view for development/testing
/// Output: Displays PuckTrackingView with live camera and puck detection

import SwiftUI

struct ContentView: View {
    
    var body: some View {
        PuckTrackingView()
    }
}

#Preview {
    ContentView()
}
