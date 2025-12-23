//
//  String+SHA256.swift
//  Rivulet
//
//  SHA256 hash extension for generating safe cache filenames
//

import Foundation
import CryptoKit

extension String {
    /// Returns a SHA256 hash of the string, suitable for use as a cache filename
    func sha256Hash() -> String {
        let data = Data(self.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
