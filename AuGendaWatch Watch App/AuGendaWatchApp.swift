//
//  AuGendaWatchApp.swift
//  AuGendaWatch Watch App
//
//  Single-screen orientation anchor for AuGenda on the wrist. The watch
//  The phone remains the source of truth; the Watch keeps a lightweight
//  App Group snapshot plus a durable mutation outbox for offline actions.
//

import SwiftUI

@main
struct AuGendaWatch_Watch_AppApp: App {

    @StateObject private var session = WatchSessionClient.shared

    var body: some Scene {
        WindowGroup {
            NowView()
                .environmentObject(session)
        }
    }
}
