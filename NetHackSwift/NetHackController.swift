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

	// MARK: Initialize/shutdown

	func initWindows() {
		// Nothing to do
	}

	 func initStatus() {
		 // Nothing to do
	 }

	 func exitWindows(withMessage message: String?) {
		 print("exit_nhwindows: \(message ?? "")")
	 }

	 func suspendWindows(withMessage message: String?) {
		 // TODO: suspend UI
		 fatalError()
	 }

	 func resumeWindows() {
		 // TODO: resume UI
		 fatalError()
	 }

	// MARK: Text output

	func displayFile(_ filename: String, complain: Bool) {
		print("display_file: \(filename)")
		fatalError()
	}

	func rawPrint(_ string: String) {
		print(string)
	}

	func rawPrintBold(_ string: String) {
		print(string)
	}

	// MARK: Window lifecycle

	func createNhwindow(_ window: NHWindowID, type: NHWindowType) {
		print("createNhWindow(\(window), \(type))")
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

	func moveCursor(in window: NHWindowID, x: Int32, y: Int32) {
        // Ignore cursor positioning — we're not rendering a grid yet.
		fatalError()
    }

    func clearNhwindow(_ window: NHWindowID) {
        // TODO: clear the contents of the window
		fatalError()
    }

    func displayNhwindow(_ window: NHWindowID) {
        // TODO: make the window visible
		fatalError()
    }

    func destroyNhwindow(_ window: NHWindowID) {
        nhWindows.removeValue(forKey: window)
        messageModels.removeValue(forKey: window)
        menuModels.removeValue(forKey: window)
    }

	func putString(in window: NHWindowID, string: String, attribute: NHTextAttribute) {
		if let model = messageModels[window] {
			model.messages.append(string)
		} else {
			print(string)
			fatalError()
		}
	}

    // MARK: Map

    func printGlyph(in window: NHWindowID, x: Int32, y: Int32, glyphInfo: UnsafeRawPointer, backgroundGlyphInfo: UnsafeRawPointer) {
        // TODO: render the glyph at (x, y) in the map window
		fatalError()
    }

    func clipAround(_ x: Int32, y: Int32) {
        // TODO: scroll the map so (x, y) is visible
		fatalError()
    }

    // MARK: Menus

    func startMenu(in window: NHWindowID, behavior: UInt) {
        menuModels[window]?.reset()
    }

    func addMenuItem(in window: NHWindowID, accel: CChar, groupAccel: CChar, attr: Int32, color: Int32, string: String, flags: UInt32, glyphInfo: UnsafeRawPointer, identifier: UnsafeRawPointer) {
        // TODO: append item to menuModels[window]
		fatalError()
    }

    func endMenu(in window: NHWindowID, prompt: String?) {
		guard let model = menuModels[window] else {
			fatalError()
		}
		model.title = prompt ?? ""
    }

    // MARK: Status bar

    func enableStatusField(_ fieldIndex: Int32, name: String, format: String, enabled: Bool) {
        // TODO: configure status field visibility
		fatalError()
    }

    func updateStatusField(_ fieldIndex: Int32, ptr: UnsafeRawPointer, change: Int32, percent: Int32, color: Int32, colorMasks: UnsafePointer<UInt>?) {
        // TODO: update status bar field
		fatalError()
    }

    // MARK: Misc output

    func updatePositionBar(_ positionBar: String) {
        // TODO: update position bar UI
		fatalError()
    }

    func updateInventory() {
        // TODO: refresh inventory display
		fatalError()
    }

    func putMessageHistory(_ message: String?, restoring: Bool) {
        // TODO: replay message into history
		fatalError()
    }

    func requestPlayerSelection() {
        // TODO: show character creation UI
		fatalError()
    }

    // MARK: Blocking input

    func needsLineInput(_ request: NHLineInputRequest) {
        pendingLineRequest = request
    }

    func needsKeyInput(_ request: NHKeyInputRequest) {
        pendingKeyRequest = request
    }

    func needsKeyOrMouseInput(_ request: NHKeyOrMouseInputRequest) {
        pendingKeyOrMouseRequest = request
    }
}
