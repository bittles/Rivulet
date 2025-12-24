//
//  MetalLayer.swift
//  Rivulet
//
//  Custom CAMetalLayer for MPV rendering
//

import Foundation
import UIKit

class MetalLayer: CAMetalLayer {

    // Workaround for MoltenVK setting drawableSize to 1x1 to forcefully complete
    // the presentation, which causes flicker
    // https://github.com/mpv-player/mpv/pull/13651
    override var drawableSize: CGSize {
        get { return super.drawableSize }
        set {
            if Int(newValue.width) > 1 && Int(newValue.height) > 1 {
                super.drawableSize = newValue
            }
        }
    }
}
