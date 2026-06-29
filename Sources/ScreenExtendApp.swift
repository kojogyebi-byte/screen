//
//  ScreenExtendApp.swift
//  ScreenExtend
//

import SwiftUI

@main
struct ScreenExtendApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}   // no "New Window"
        }
    }
}
