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

    @Binding var playerController: MPVMetalViewController?

    func makeUIViewController(context: Context) -> MPVMetalViewController {
        let controller = MPVMetalViewController()
        controller.playUrl = url
        controller.httpHeaders = headers
        controller.startTime = startTime
        controller.delegate = delegate

        DispatchQueue.main.async {
            self.playerController = controller
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: MPVMetalViewController, context: Context) {
        // Updates handled through the controller reference
    }
}
