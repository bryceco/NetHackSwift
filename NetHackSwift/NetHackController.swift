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

// MARK: - Keyable Panel

/// NSPanel without a title bar can't become the key window by default.
/// This subclass overrides that so blocking (modal) panels receive key events.
private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

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
    var identifier: Data  // opaque copy of NetHack's 'anything' value
}

// MARK: - Controller

/// Manages the NetHack bridge and exposes its state to SwiftUI.
/// All NetHackBridgeDelegate methods are guaranteed to arrive on the main thread.
@Observable final class NetHackController: NSObject {

    // At most one of these is non-nil at a time.
    // The completion stored here is called on the main thread to provide
    // the input value and unblock the NetHack thread.
    @ObservationIgnored private var pendingKeyCompletion: ((Int32) -> Void)?
    @ObservationIgnored private var pendingKeyOrMouseCompletion: ((Int32, Int32, Int32, Int32) -> Void)?
    @ObservationIgnored private var pendingLineCompletion: ((String?) -> Void)?

    /// Set by the app before calling start(). Injected into any windows the bridge opens.
    var gameState: GameState?

    /// Windows created by NetHack but not yet displayed (between createNhwindow and displayNhwindow).
    @ObservationIgnored private var pendingWindows: [NHWindowID: NHWindowData] = [:]

    /// NSWindows opened on behalf of NetHack, keyed by their NHWindowID.
    /// Kept to maintain a strong reference so the windows aren't deallocated.
    @ObservationIgnored private var nhWindows: [NHWindowID: NSWindow] = [:]

    private let bridge = NetHackBridge()
    var isInitialized = false

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
        if let completion = pendingKeyCompletion {
            pendingKeyCompletion = nil
            completion(key)
        } else if let completion = pendingKeyOrMouseCompletion {
            pendingKeyOrMouseCompletion = nil
            completion(key, 0, 0, 0)
        }
    }

    /// Forward a mouse click to a pending nh_poskey request.
    func sendMouseClick(x: Int32, y: Int32, mod: Int32) {
        guard let completion = pendingKeyOrMouseCompletion else { return }
        pendingKeyOrMouseCompletion = nil
        completion(0, x, y, mod)
    }

    /// Forward a line of text to a pending getlin request. Pass nil to cancel.
    func sendLine(_ line: String?) {
        guard let completion = pendingLineCompletion else { return }
        pendingLineCompletion = nil
        completion(line)
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
        pendingWindows[window]!.strings = []
        pendingWindows[window]!.resetMenu()
        // Close the displayed window if it was already shown.
        nhWindows[window]?.close()
        nhWindows.removeValue(forKey: window)
    }

	func displayNhwindow(_ window: NHWindowID, blocking: Bool) {
		let data = pendingWindows[window]!

        switch data.type {
        case .message:
            // NHW_MESSAGE is the top-line message log — append to the scrolling message list.
            gameState?.messages.append(contentsOf: data.strings)
        case .menu where data.menuItems.isEmpty, .text:
            let text = data.strings.joined(separator: "\n")
            let hasTitle = !data.menuTitle.isEmpty
            let panelClass: NSPanel.Type = blocking ? KeyablePanel.self : NSPanel.self
            let panel = panelClass.init(
                contentRect: NSRect(x: 0, y: 0, width: 259, height: 100),
                styleMask: hasTitle ? [.titled, .closable, .resizable] : (blocking ? [.closable, .resizable] : [.closable, .resizable, .nonactivatingPanel]),
                backing: .buffered,
                defer: false
            )
            if hasTitle { panel.title = data.menuTitle }
            panel.animationBehavior = .none
            panel.isRestorable = false
            panel.isReleasedWhenClosed = false
            panel.isMovableByWindowBackground = true
            nhWindows[window] = panel
            let view = MessageWindowView(text: text) { NSApp.stopModal() }
            let hc = NSHostingController(rootView: view)
            hc.sizingOptions = .preferredContentSize
            panel.contentViewController = hc
            panel.contentMinSize = NSSize(width: 259, height: 100)
            if blocking {
                NSApp.runModal(for: panel)
                panel.close()
                nhWindows.removeValue(forKey: window)
            } else {
                panel.orderFront(nil)
            }
        case .menu:
            // Non-blocking: do nothing here — selectMenu will create the window.
            // Blocking: show display-only and wait for dismiss.
			assert(blocking)
			assert(false)	// not sure this path is ever used
			showMenuWindow(window: window, selectionMode: .none, onAccept: nil, onCancel: nil)
		case .map:
			print("display map")
            break
		case .status:
			print("display status")
			break
			default:
			fatalError()
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
		fatalError()
    }

    // MARK: Map

    func printGlyph(in window: NHWindowID, x: Int32, y: Int32, glyphInfo: UnsafeRawPointer, backgroundGlyphInfo: UnsafeRawPointer) {
        // TODO: render the glyph at (x, y) in the map window
		print("printGlyph")
    }

    func clipAround(x: Int32, y: Int32) {
        // TODO: scroll the map so (x, y) is visible
		print("cliparound")
    }

    // MARK: Menus

    func startMenu(in window: NHWindowID, behavior: UInt) {
        pendingWindows[window]!.resetMenu()
        pendingWindows[window]!.menuBehavior = behavior
    }

    func addMenuItem(in window: NHWindowID, accel: CChar, groupAccel: CChar, attr: Int32, color: Int32, string: String, flags: UInt32, glyphInfo: UnsafeRawPointer, identifier: Data) {
        pendingWindows[window]!.menuItems.append(NHMenuItem(
            accel: accel,
            groupAccel: groupAccel,
            attr: attr,
            color: color,
            string: string,
            flags: flags,
            identifier: identifier
        ))
    }

    func endMenu(in window: NHWindowID, prompt: String?) {
        pendingWindows[window]!.menuTitle = prompt ?? ""
    }

    // MARK: Status bar

    func enableStatusField(_ fieldIndex: Int32, name: String, format: String, enabled: Bool) {
        // TODO: configure status field visibility
		fatalError()
    }

    func updateStatusField(_ fieldIndex: Int32, ptr: UnsafeRawPointer, change: Int32, percent: Int32, color: Int32, colorMasks: UnsafePointer<UInt>?) {
        // TODO: update status bar field
		print("updateStatusField")
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
		print("putMessageHistory")
    }

    func requestPlayerSelection() {
        // TODO: show character creation UI
		print("requestPlayerSelection")
    }

    func initWindows() {
        isInitialized = true
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
        pendingLineCompletion = completion
    }

    func needsKeyInput(_ completion: @escaping (Int32) -> Void) {
        pendingKeyCompletion = completion
    }

    func needsKeyOrMouseInput(_ completion: @escaping (Int32, Int32, Int32, Int32) -> Void) {
        pendingKeyOrMouseCompletion = completion
    }

    func selectMenu(in window: NHWindowID,
					how: Int32,
                    completion: @escaping ([NHMenuSelection]?) -> Void) {
        let selectionMode: MenuSelectionMode = how == 0 ? .none : how == 1 ? .one : .any
        showMenuWindow(
            window: window,
            selectionMode: selectionMode,
            onAccept: { selected in
                completion(selected.map { NHMenuSelection(identifier: $0.identifier, count: 1) })
            },
            onCancel: { completion(nil) }
        )
    }

    /// Creates and presents a menu window modally. `onAccept`/`onCancel` are called after dismiss.
    /// Pass nil for both when the menu is display-only and no completion needs to be called.
    private func showMenuWindow(window: NHWindowID,
                                selectionMode: MenuSelectionMode,
                                onAccept: (([MenuItemData]) -> Void)?,
                                onCancel: (() -> Void)?)
	{
		let data = pendingWindows[window]!
        let items = data.menuItems.map { item in
            MenuItemData(
                key: item.accel > 0 ? String(UnicodeScalar(UInt8(item.accel))) : "",
                text: item.string,
                identifier: item.identifier
            )
        }
        let categories = [MenuCategory(title: data.menuTitle, items: items)]
        let nsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 250, height: 100),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        nsWindow.title = data.menuTitle.isEmpty ? "Menu" : data.menuTitle
        nsWindow.animationBehavior = .none
        nsWindow.isRestorable = false
        nsWindow.isReleasedWhenClosed = false
        nhWindows[window] = nsWindow
        // Use a local to capture what the user did; actual callbacks fire after runModal returns.
        var accepted: [MenuItemData]? = nil
        let view = MenuWindowView(
            categories: categories,
            selectionMode: selectionMode,
            onAccept: { selected in accepted = selected; NSApp.stopModal() },
            onCancel: { NSApp.stopModal() }
        )
        let hc = NSHostingController(rootView: view)
        hc.sizingOptions = .preferredContentSize
        nsWindow.contentViewController = hc
        nsWindow.contentMinSize = NSSize(width: 250, height: 100)
        NSApp.runModal(for: nsWindow)
        if let accepted {
            onAccept?(accepted)
        } else {
            onCancel?()
        }
    }
}
