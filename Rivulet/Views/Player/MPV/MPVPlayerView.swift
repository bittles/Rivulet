//
//  MPVPlayerView.swift
//  Rivulet
//
//  SwiftUI wrapper for MPVMetalViewController
//

import Foundation
import SwiftUI

struct MPVPlayerView: UIViewControllerRepresentable {
    let url: URL
    let headers: [String: String]?
    let startTime: Double?
    let delegate: MPVPlayerDelegate?
    var isLiveStream: Bool = false
    var containerSize: CGSize = .zero  // Explicit size from parent

    @Binding var playerController: MPVMetalViewController?

    func makeUIViewController(context: Context) -> MPVMetalViewController {
        let controller = MPVMetalViewController()
        controller.playUrl = url
        controller.httpHeaders = headers
        controller.startTime = startTime
        controller.delegate = delegate
        controller.isLiveStreamMode = isLiveStream

        DispatchQueue.main.async {
            self.playerController = controller
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: MPVMetalViewController, context: Context) {
        // Size updates are handled explicitly via StreamSlotView's onChange(of: containerSize)
        // Do NOT update size here - SwiftUI may call this with stale containerSize values
        // during intermediate render passes, causing incorrect sizing
    }
}
