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

// MARK: - Window Data

/// Accumulates all data for a NetHack window between createNhwindow and displayNhwindow.
/// Once displayNhwindow is called the content is frozen and presented as a static view.
private final class NHWindowData {
    let type: NHWindowType
    var strings: [String] = []

    // Menu-specific fields, populated by start_menu / add_menu / end_menu.
    var menuTitle: String = ""
    var menuBehavior: UInt = 0
    var menuItems: [NHMenuItem] = []

    init(type: NHWindowType) {
        self.type = type
    }

    func resetMenu() {
        menuTitle = ""
        menuBehavior = 0
        menuItems = []
    }
}

private struct NHMenuItem {
    var accel: CChar
    var groupAccel: CChar
    var attr: Int32
    var color: Int32
    var string: String
    var flags: UInt32
}

// MARK: - Controller

/// Manages the NetHack bridge and exposes its state to SwiftUI.
/// All NetHackBridgeDelegate methods are guaranteed to arrive on the main thread.
@Observable final class NetHackController: NSObject {

    // At most one of these is non-nil at a time.
    // The completion stored here is called (on the main thread) to provide
    // the return value and unblock the NetHack thread.
    private var pendingKeyContinuation: CheckedContinuation<Int32, Never>?
    private var pendingKeyOrMouseContinuation: CheckedContinuation<(key: Int32, x: Int32, y: Int32, mod: Int32), Never>?
    private var pendingLineContinuation: CheckedContinuation<String?, Never>?

    /// Set by the app before calling start(). Injected into any windows the bridge opens.
    var gameState: GameState?

    /// Windows created by NetHack but not yet displayed (between createNhwindow and displayNhwindow).
    private var pendingWindows: [NHWindowID: NHWindowData] = [:]

    /// NSWindows opened on behalf of NetHack, keyed by their NHWindowID.
    /// Kept to maintain a strong reference so the windows aren't deallocated.
    private var nhWindows: [NHWindowID: NSWindow] = [:]

    private let bridge = NetHackBridge()

	private func copyTo(playgroundURL: URL, from fromURL: URL) {
		let fm = FileManager.default
		let items = try! fm.contentsOfDirectory(at: fromURL,
												includingPropertiesForKeys: nil,
												options: [.skipsHiddenFiles])
		for item in items {
			let dest = playgroundURL.appendingPathComponent(item.lastPathComponent)
			guard !fm.fileExists(atPath: dest.path) else { continue }
			try! fm.copyItem(at: item, to: dest)
		}
	}

    func start(playgroundURL: URL, resourcesURL: URL) {
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
        if let cont = pendingKeyContinuation {
            pendingKeyContinuation = nil
            cont.resume(returning: key)
        } else if let cont = pendingKeyOrMouseContinuation {
            pendingKeyOrMouseContinuation = nil
            cont.resume(returning: (key: key, x: 0, y: 0, mod: 0))
        }
    }

    /// Forward a mouse click to a pending nh_poskey request.
    func sendMouseClick(x: Int32, y: Int32, mod: Int32) {
        guard let cont = pendingKeyOrMouseContinuation else { return }
        pendingKeyOrMouseContinuation = nil
        cont.resume(returning: (key: 0, x: x, y: y, mod: mod))
    }

    /// Forward a line of text to a pending getlin request. Pass nil to cancel.
    func sendLine(_ line: String?) {
        guard let cont = pendingLineContinuation else { return }
        pendingLineContinuation = nil
        cont.resume(returning: line)
    }
}

// MARK: - NetHackBridgeDelegate

extension NetHackController: NetHackBridgeDelegate {

    func rawPrint(_ string: String) {
        print(string)
    }

    func rawPrintBold(_ string: String) {
        print(string)
    }

    func moveCursor(in window: NHWindowID, x: Int32, y: Int32) {
        // Ignore cursor positioning — not rendering a grid yet.
    }

    func putString(in window: NHWindowID, string: String, attribute: NHTextAttribute) {
        if let data = pendingWindows[window] {
            data.strings.append(string)
        } else {
            print(string)
        }
    }

    // MARK: Window lifecycle

	func createNhwindow(_ window: NHWindowID, type: NHWindowType) {
		pendingWindows[window] = NHWindowData(type: type)
	}

    func clearNhwindow(_ window: NHWindowID) {
        // Reset accumulated data so the window can be reused for new content.
        pendingWindows[window]?.strings = []
        pendingWindows[window]?.resetMenu()
        // Close the displayed window if it was already shown.
        nhWindows[window]?.close()
        nhWindows.removeValue(forKey: window)
    }

	func displayNhwindow(_ window: NHWindowID, blocking: Bool) {
		guard let data = pendingWindows[window] else {
			fatalError()
		}
        switch data.type {
        case .message:
            let text = data.strings.joined(separator: "\n")
            let view = MessageWindowView(text: text) { [weak self] in
                self?.nhWindows.removeValue(forKey: window)
            }
            let hosting = NSHostingController(rootView: view)
            let nsWindow = NSWindow(contentViewController: hosting)
            nsWindow.title = "Messages"
            nsWindow.styleMask = [.titled, .closable, .resizable]
            nsWindow.makeKeyAndOrderFront(nil)
            nhWindows[window] = nsWindow
        case .menu:
            let items = data.menuItems.map { item in
                MenuItemData(
                    key: item.accel > 0 ? String(UnicodeScalar(UInt8(item.accel))) : "",
                    text: item.string
                )
            }
            let categories = [MenuCategory(title: data.menuTitle, items: items)]
            let view = MenuWindowView(
                categories: categories,
                isSelectable: false,  // TODO: determine from menuBehavior flags
                onAccept: { [weak self] _ in self?.nhWindows.removeValue(forKey: window) },
                onCancel: { [weak self] in self?.nhWindows.removeValue(forKey: window) }
            )
            let hosting = NSHostingController(rootView: view)
            let nsWindow = NSWindow(contentViewController: hosting)
            nsWindow.styleMask = [.titled, .closable, .resizable]
            nsWindow.makeKeyAndOrderFront(nil)
            nhWindows[window] = nsWindow
        default:
            break
        }
    }

    func destroyNhwindow(_ window: NHWindowID) {
        nhWindows[window]?.close()
        nhWindows.removeValue(forKey: window)
        pendingWindows.removeValue(forKey: window)
    }

    // MARK: Text output

    func displayFile(_ filename: String, complain: Bool) {
        print("display_file: \(filename)")
    }

    // MARK: Map

    func printGlyph(in window: NHWindowID, x: Int32, y: Int32, glyphInfo: UnsafeRawPointer, backgroundGlyphInfo: UnsafeRawPointer) {
        // TODO: render the glyph at (x, y) in the map window
    }

    func clipAround(_ x: Int32, y: Int32) {
        // TODO: scroll the map so (x, y) is visible
    }

    // MARK: Menus

    func startMenu(in window: NHWindowID, behavior: UInt) {
        pendingWindows[window]!.resetMenu()
        pendingWindows[window]!.menuBehavior = behavior
    }

    func addMenuItem(in window: NHWindowID, accel: CChar, groupAccel: CChar, attr: Int32, color: Int32, string: String, flags: UInt32, glyphInfo: UnsafeRawPointer, identifier: UnsafeRawPointer) {
        pendingWindows[window]!.menuItems.append(NHMenuItem(
            accel: accel,
            groupAccel: groupAccel,
            attr: attr,
            color: color,
            string: string,
            flags: flags
        ))
    }

    func endMenu(in window: NHWindowID, prompt: String?) {
        pendingWindows[window]!.menuTitle = prompt ?? ""
    }

    // MARK: Status bar

    func enableStatusField(_ fieldIndex: Int32, name: String, format: String, enabled: Bool) {
        // TODO: configure status field visibility
    }

    func updateStatusField(_ fieldIndex: Int32, ptr: UnsafeRawPointer, change: Int32, percent: Int32, color: Int32, colorMasks: UnsafePointer<UInt>?) {
        // TODO: update status bar field
    }

    // MARK: Misc output

    func updatePositionBar(_ positionBar: String) {
        // TODO: update position bar UI
    }

    func updateInventory() {
        // TODO: refresh inventory display
    }

    func putMessageHistory(_ message: String?, restoring: Bool) {
        // TODO: replay message into history
    }

    func requestPlayerSelection() {
        // TODO: show character creation UI
    }

    func initWindows() {
        // TODO: perform any window-system setup
    }

    func initStatus() {
        // TODO: perform any status-bar setup
    }

    func exitWindows(withMessage message: String?) {
        print("exit_nhwindows: \(message ?? "")")
    }

    func suspendWindows(withMessage message: String?) {
        // TODO: suspend UI
    }

    func resumeWindows() {
        // TODO: resume UI
    }

    // MARK: Blocking input

    func needsLineInput(_ prompt: String, completion: @escaping (String?) -> Void) {
        Task { @MainActor in
            let response = await withCheckedContinuation { cont in
                pendingLineContinuation = cont
            }
            completion(response)
        }
    }

    func needsKeyInput(_ completion: @escaping (Int32) -> Void) {
        Task { @MainActor in
            let key = await withCheckedContinuation { cont in
                pendingKeyContinuation = cont
            }
            completion(key)
        }
    }

    func needsKeyOrMouseInput(_ completion: @escaping (Int32, Int32, Int32, Int32) -> Void) {
        Task { @MainActor in
            let result = await withCheckedContinuation {
                (cont: CheckedContinuation<(key: Int32, x: Int32, y: Int32, mod: Int32), Never>) in
                pendingKeyOrMouseContinuation = cont
            }
            completion(result.key, result.x, result.y, result.mod)
        }
    }
}
