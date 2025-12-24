//
//  RivuletApp.swift
//  Rivulet
//
//  Created by Bain Gurley on 11/28/25.
//

import SwiftUI
import SwiftData
// import Sentry  // TODO: Add Sentry package when SPM issue is resolved

@main
struct RivuletApp: App {

    // TODO: Uncomment when Sentry package is added
    // init() {
    //     SentrySDK.start { options in
    //         options.dsn = "YOUR_SENTRY_DSN_HERE"
    //         options.debug = false
    //         options.tracesSampleRate = 1.0
    //         options.attachStacktrace = true
    //         options.enableAutoSessionTracking = true
    //     }
    // }

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
