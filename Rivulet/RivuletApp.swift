//
//  RivuletApp.swift
//  Rivulet
//
//  Created by Bain Gurley on 11/28/25.
//

import SwiftUI
import SwiftData

@main
struct RivuletApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ServerConfiguration.self,
            PlexServer.self,
            IPTVSource.self,
            Channel.self,
            FavoriteChannel.self,
            WatchProgress.self,
            EPGProgram.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)  // Force dark mode
        }
        .modelContainer(sharedModelContainer)
    }
}
