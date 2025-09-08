//
//  Scream_O_ClockApp.swift
//  Scream O Clock
//
//  Created by Tyler Zacharias on 9/4/25.
//

import SwiftUI

@main
struct ScareRotationsApp: App {
    // NotificationManager is defined in ContentView.swift
    @StateObject private var notifier = NotificationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(notifier)
                .onAppear {notifier.requestAuthorization()}
                .preferredColorScheme(.dark) // force dark
                .tint(.red)
        }
    }
}
