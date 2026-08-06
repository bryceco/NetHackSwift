//
//  NetHackController.swift
//  NetHackSwift
//
//  Created by Bryce Cogswell on 8/6/26.
//

import Foundation
import Observation
import NetHackBridge

/// Manages the NetHack bridge and exposes its state to SwiftUI.
/// All NetHackBridgeDelegate methods are guaranteed to arrive on the main thread.
@Observable final class NetHackController: NSObject {

    var outputLines: [String] = []

    // At most one of these is non-nil at a time.
    var pendingLineRequest: NHLineInputRequest?
    var pendingKeyRequest: NHKeyInputRequest?
    var pendingKeyOrMouseRequest: NHKeyOrMouseInputRequest?

    private let bridge = NetHackBridge()

    func start(dataPath: String) {
        bridge.delegate = self
        bridge.run(withArguments: ["-d", dataPath]) { [weak self] exitCode in
            self?.outputLines.append("--- NetHack exited (\(exitCode)) ---")
        }
    }

    /// Forward a keypress to whichever blocking key-input request is pending.
    func sendKey(_ key: Int32) {
        if let req = pendingKeyRequest {
            pendingKeyRequest = nil
            req.fulfill(withKey: key)
        } else if let req = pendingKeyOrMouseRequest {
            pendingKeyOrMouseRequest = nil
            req.fulfill(withKey: key)
        }
    }

    /// Forward a line of text to a pending getlin request. Pass nil to cancel.
    func sendLine(_ line: String?) {
        guard let req = pendingLineRequest else { return }
        pendingLineRequest = nil
        if let line {
            req.fulfill(line)
        } else {
            req.cancel()
        }
    }
}

// MARK: - NetHackBridgeDelegate

extension NetHackController: NetHackBridgeDelegate {

    func nethackBridge(_ bridge: NetHackBridge, didPrint string: String) {
        outputLines.append(string)
    }

    func nethackBridge(_ bridge: NetHackBridge, didPrintBoldString string: String) {
        outputLines.append(string)
    }

    func nethackBridge(_ bridge: NetHackBridge, didMoveCursorInWindow window: NHWindowID, x: Int32, y: Int32) {
        // Ignore cursor positioning — we're not rendering a grid yet.
    }

    func nethackBridge(_ bridge: NetHackBridge, window: NHWindowID, didPut string: String, attribute: NHTextAttribute) {
        outputLines.append(string)
    }

    func nethackBridge(_ bridge: NetHackBridge, needsLineInput request: NHLineInputRequest) {
        pendingLineRequest = request
    }

    func nethackBridge(_ bridge: NetHackBridge, needsKeyInput request: NHKeyInputRequest) {
        pendingKeyRequest = request
    }

    func nethackBridge(_ bridge: NetHackBridge, needsKeyOrMouseInput request: NHKeyOrMouseInputRequest) {
        pendingKeyOrMouseRequest = request
    }
}
