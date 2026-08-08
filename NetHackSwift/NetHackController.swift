//
//  NetHackController.swift
//  NetHackSwift
//
//  Created by Bryce Cogswell on 8/6/26.
//

import AppKit
import Foundation
import Observation
import SwiftUI
import NetHackBridge

/// Bridges an observable MessageWindowModel to the static-text MessageWindowView.
/// Defined here (not in MessageWindowView.swift) because it is an implementation
/// detail of how NetHackController wires up the window.
private struct MessageWindowBridge: View {
    var model: MessageWindowModel
    var onClose: () -> Void
    var body: some View {
        MessageWindowView(text: model.text, onClose: onClose)
    }
}

/// Manages the NetHack bridge and exposes its state to SwiftUI.
/// All NetHackBridgeDelegate methods are guaranteed to arrive on the main thread.
@Observable final class NetHackController: NSObject {

    // At most one of these is non-nil at a time.
    var pendingLineRequest: NHLineInputRequest?
    var pendingKeyRequest: NHKeyInputRequest?
    var pendingKeyOrMouseRequest: NHKeyOrMouseInputRequest?

    /// Set by the app before calling start(). Injected into any windows the bridge opens.
    var gameState: GameState?

    /// NSWindows opened on behalf of NetHack, keyed by their NHWindowID.
    /// Kept to maintain a strong reference so the windows aren't deallocated.
    private var nhWindows: [NHWindowID: NSWindow] = [:]

    /// Data models for message windows, keyed by their NHWindowID.
    private var messageModels: [NHWindowID: MessageWindowModel] = [:]

    /// Data models for menu windows, keyed by their NHWindowID.
    /// The model is created here; the NSWindow is deferred until display_nhwindow.
    private var menuModels: [NHWindowID: MenuWindowModel] = [:]

    private let bridge = NetHackBridge()

	private func copyTo(playgroundURL: URL, from fromURL: URL) {
		let fm = FileManager.default
		let items = try! fm.contentsOfDirectory(at: fromURL,
												includingPropertiesForKeys: nil,
												options: [.skipsHiddenFiles])
		for item in items {
			let dest = playgroundURL.appendingPathComponent(item.lastPathComponent)
			guard
				!fm.fileExists(atPath: dest.path)
			else {
				continue
			}
			try! fm.copyItem(at: item, to: dest)
		}
	}

    func start(playgroundURL: URL, resourcesURL: URL) {
		// Copy default playground
		let fm = FileManager.default

		copyTo(playgroundURL: playgroundURL, from: resourcesURL.appendingPathComponent("Playground"))

		fm.changeCurrentDirectoryPath(playgroundURL.path)

        bridge.delegate = self
		bridge.run(withArguments: ["-d", playgroundURL.path]) { exitCode in
            print("--- NetHack exited (\(exitCode)) ---")
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

	func nethackBridge(_ bridge: NetHackBridge, createNhwindow window: NHWindowID, of type: NHWindowType) {
		switch type {
		case .message:
			let model = MessageWindowModel()
			messageModels[window] = model
			let windowID = window
			let view = MessageWindowBridge(model: model) { [weak self] in
				self?.nhWindows.removeValue(forKey: windowID)
			}
			let hosting = NSHostingController(rootView: view)
			let nsWindow = NSWindow(contentViewController: hosting)
			nsWindow.title = "Messages"
			nsWindow.styleMask = [.titled, .closable, .resizable]
			nsWindow.makeKeyAndOrderFront(nil)
			nhWindows[window] = nsWindow
		case .map:
			break
		case .menu:
			// Don't show the window yet — content is populated by start_menu/add_menu/end_menu
			// and the window is presented when display_nhwindow fires.
			menuModels[window] = MenuWindowModel()
		default:
			fatalError()
		}
	}

    func nethackBridge(_ bridge: NetHackBridge, rawPrint string: String) {
        print(string)
    }

    func nethackBridge(_ bridge: NetHackBridge, rawPrintBold string: String) {
        print(string)
    }

    func nethackBridge(_ bridge: NetHackBridge, didMoveCursorInWindow window: NHWindowID, x: Int32, y: Int32) {
        // Ignore cursor positioning — we're not rendering a grid yet.
    }

    func nethackBridge(_ bridge: NetHackBridge, window: NHWindowID, putstr string: String, attribute: NHTextAttribute) {
        if let model = messageModels[window] {
            model.messages.append(string)
        } else {
            print(string)
        }
    }

    // MARK: Window lifecycle

    func nethackBridge(_ bridge: NetHackBridge, clearNhwindow window: NHWindowID) {
        // TODO: clear the contents of the window
    }

    func nethackBridge(_ bridge: NetHackBridge, displayNhwindow window: NHWindowID) {
        // TODO: make the window visible
    }

    func nethackBridge(_ bridge: NetHackBridge, destroyNhwindow window: NHWindowID) {
        nhWindows.removeValue(forKey: window)
        messageModels.removeValue(forKey: window)
        menuModels.removeValue(forKey: window)
    }

    // MARK: Text output

    func nethackBridge(_ bridge: NetHackBridge, displayFile filename: String, complain: Bool) {
        print("display_file: \(filename)")
    }

    // MARK: Map

    func nethackBridge(_ bridge: NetHackBridge, window: NHWindowID, printGlyphAtX x: Int32, y: Int32, glyphInfo: UnsafeRawPointer, backgroundGlyphInfo: UnsafeRawPointer) {
        // TODO: render the glyph at (x, y) in the map window
    }

    func nethackBridge(_ bridge: NetHackBridge, cliparound x: Int32, y: Int32) {
        // TODO: scroll the map so (x, y) is visible
    }

    // MARK: Menus

    func nethackBridge(_ bridge: NetHackBridge, startMenu window: NHWindowID, behavior: UInt) {
        menuModels[window]?.reset()
    }

    func nethackBridge(_ bridge: NetHackBridge, window: NHWindowID, addMenuItemWithAccel accel: CChar, groupAccel: CChar, attr: Int32, color: Int32, string: String, flags: UInt32, glyphInfo: UnsafeRawPointer, identifier: UnsafeRawPointer) {
        // TODO: append item to menuModels[window]
    }

    func nethackBridge(_ bridge: NetHackBridge, endMenuInWindow window: NHWindowID, prompt: String?) {
        if let model = menuModels[window] {
            model.title = prompt ?? ""
        }
    }

    // MARK: Status bar

    func nethackBridge(_ bridge: NetHackBridge, enableStatusField fieldIndex: Int32, name: String, format: String, enabled: Bool) {
        // TODO: configure status field visibility
    }

    func nethackBridge(_ bridge: NetHackBridge, updateStatusField fieldIndex: Int32, ptr: UnsafeRawPointer, change: Int32, percent: Int32, color: Int32, colorMasks: UnsafePointer<UInt>?) {
        // TODO: update status bar field
    }

    // MARK: Misc output

    func nethackBridge(_ bridge: NetHackBridge, updatePositionBar positionBar: String) {
        // TODO: update position bar UI
    }

    func nethackBridgeUpdateInventory(_ bridge: NetHackBridge) {
        // TODO: refresh inventory display
    }

    func nethackBridge(_ bridge: NetHackBridge, putMessageHistory message: String?, restoring: Bool) {
        // TODO: replay message into history
    }

    func nethackBridgeRequestPlayerSelection(_ bridge: NetHackBridge) {
        // TODO: show character creation UI
    }

    func nethackBridgeInitWindows(_ bridge: NetHackBridge) {
        // TODO: perform any window-system setup
    }

    func nethackBridgeInitStatus(_ bridge: NetHackBridge) {
        // TODO: perform any status-bar setup
    }

    func nethackBridge(_ bridge: NetHackBridge, exitWindowsWithMessage message: String?) {
        print("exit_nhwindows: \(message ?? "")")
    }

    func nethackBridge(_ bridge: NetHackBridge, suspendWindowsWithMessage message: String?) {
        // TODO: suspend UI
    }

    func nethackBridgeResumeWindows(_ bridge: NetHackBridge) {
        // TODO: resume UI
    }

    // MARK: Blocking input

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
