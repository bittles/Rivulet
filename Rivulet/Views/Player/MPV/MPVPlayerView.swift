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
    var containerSize: CGSize = .zero  // Explicit size from parent (for multi-stream)

    @Binding var playerController: MPVMetalViewController?

    func makeUIViewController(context: Context) -> MPVMetalViewController {
        let controller = MPVMetalViewController()
        controller.playUrl = url
        controller.httpHeaders = headers
        controller.startTime = startTime
        controller.delegate = delegate
        controller.isLiveStreamMode = isLiveStream

        // Set explicit size if provided (for multi-stream layout)
        if containerSize != .zero {
            controller.setExplicitSize(containerSize)
        }

        DispatchQueue.main.async {
            self.playerController = controller
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: MPVMetalViewController, context: Context) {
        // Update explicit size when container size changes
        // Pass .zero to disable transform scaling (reverts to normal frame-based sizing)
        uiViewController.setExplicitSize(containerSize)
    }
}
