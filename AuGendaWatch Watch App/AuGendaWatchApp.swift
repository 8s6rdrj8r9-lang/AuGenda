//
//  AuGendaWatchApp.swift
//  AuGendaWatch Watch App
//
//  Single-screen orientation anchor for AuGenda on the wrist. The watch
//  app owns its own SwiftData container (Spec §12, §18 — offline-first),
//  with WatchConnectivity layered on top as live-state garnish.
//

import SwiftUI
import SwiftData

@main
struct AuGendaWatch_Watch_AppApp: App {

    @StateObject private var session = WatchSessionClient.shared

    var body: some Scene {
        WindowGroup {
            NowView()
                .environmentObject(session)
        }
        .modelContainer(WatchAppContainer.production)
    }
}
