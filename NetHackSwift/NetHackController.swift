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

private let asciiESC: Int32 = 27

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

    /// Set when clearNhwindow fires on the message window. The next putString
    /// will insert a "-----" delimiter before its content, then clear this flag.
    /// Multiple consecutive clears still produce only one delimiter.
    var pendingClear: Bool = false

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
    var identifier: UInt  // anything value (as uintptr_t) passed through from addMenu
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
    @ObservationIgnored private let keyboard = KeyboardHandler()
    // Set when Cmd-Q triggers a save-and-quit; auto-confirms the "Really save?" prompt.
    @ObservationIgnored private var isSavingAndQuitting = false

    /// Set by the app before calling start(). Injected into any windows the bridge opens.
    var gameState: GameState?

    /// Windows created by NetHack but not yet displayed (between createNhwindow and displayNhwindow).
    @ObservationIgnored private var windowData: [NHWindowID: NHWindowData] = [:]

    /// NSWindows opened on behalf of NetHack, keyed by their NHWindowID.
    /// Kept to maintain a strong reference so the windows aren't deallocated.
    @ObservationIgnored private var nhWindows: [NHWindowID: NSWindow] = [:]

    private let bridge: NetHackBridge?
    var isInitialized = false

    override init() {
        let isPreview = getenv("XCODE_RUNNING_FOR_PREVIEWS") != nil
                     || (getenv("XCODE_RUNNING_FOR_PLAYGROUNDS").map { String(cString: $0) == "1" } ?? false)
        bridge = isPreview ? nil : NetHackBridge()
        super.init()
        keyboard.isWaitingForInput = { [weak self] in
            self?.pendingKeyCompletion != nil || self?.pendingKeyOrMouseCompletion != nil
        }
        keyboard.onSaveAndQuit = { [weak self] in
            self?.isSavingAndQuitting = true
            self?.sendKey(Int32(UInt8(ascii: "S")))
        }
        keyboard.onKey = { [weak self] key in
            self?.sendKey(key)
        }
    }

    func start(playgroundURL: URL,
			   resourcesURL: URL)
	{
        guard let bridge else { return }
        bridge.delegate = self
        bridge.run(withHackdirURL: resourcesURL,
				   playgroundURL: playgroundURL,
				   completion: { [weak self] exitCode in
            print("--- NetHack exited (\(exitCode)) ---")
            if self?.isSavingAndQuitting == true {
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        })
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

	private func windowName(for window: NHWindowID) -> String {
		guard let data = windowData[window] else {
			return "undefined"
		}

		switch data.type {
		case .message: return "Message"
		case .status: return "Status"
		case .map: return "Map"
		case .menu: return "Menu"
		case .text: return "Text"
		@unknown default:
			fatalError()
		}
	}

    func rawPrint(_ string: String) {
        print(string)
    }

    func rawPrintBold(_ string: String) {
        print(string)
    }

    func moveCursor(in window: NHWindowID, x: Int32, y: Int32) {
		guard windowData[window]?.type == .map else {
			print("bad moveCursor")
			return
		}
		gameState?.mapCursor = (x, y)
    }

    func putString(in window: NHWindowID, string: String, attribute: NHTextAttribute) {
        guard let data = windowData[window] else {
            print(string)
            return
        }
        switch data.type {
        case .message:
            // Message window is always visible; append immediately rather than
            // waiting for displayNhwindow, which may not be called for this type.
            if data.pendingClear {
                data.pendingClear = false
                if !(gameState?.messages.isEmpty ?? true) {
                    gameState?.messages.append("-----")
                }
            }
            gameState?.messages.append(string)
        case .status:
            // Status content arrives via updateStatusField; putString on the
            // status window is not expected, but log it rather than silently drop.
            print("status putString (unexpected): \(string)")
        default:
            // Text and menu windows accumulate strings until displayNhwindow.
            data.strings.append(string)
        }
    }

    // MARK: Window lifecycle

	func createNhwindow(_ window: NHWindowID, type: NHWindowType) {
		windowData[window] = NHWindowData(type: type)
	}

    func clearNhwindow(_ window: NHWindowID) {
		if windowData[window]?.type == .message {
			windowData[window]?.pendingClear = true
			return
		}
        // Reset accumulated data so the window can be reused for new content.
        windowData[window]!.strings = []
        windowData[window]!.resetMenu()
		#if false
        // Close the displayed window if it was already shown.
        nhWindows[window]?.close()
        nhWindows.removeValue(forKey: window)
		#endif
    }

	func displayNhwindow(_ window: NHWindowID, blocking: Bool) {
		let data = windowData[window]!

        switch data.type {
        case .message:
            // Strings were already forwarded to gameState.messages in putString; nothing to flush.
            break
        case .menu where data.menuItems.isEmpty, .text:
            let text = data.strings.joined(separator: "\n")
            let hasTitle = !data.menuTitle.isEmpty
			assert(blocking) // pretty sure there are always blocking, fix later if we're wrong
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
			gameState?.mapVersion += 1
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
        windowData.removeValue(forKey: window)
    }

    // MARK: Text output

    func displayFile(_ filename: String, complain: Bool) {
        print("display_file: \(filename)")
		fatalError()
    }

    // MARK: Map

    func printGlyph(in window: NHWindowID, x: Int32, y: Int32,
					glyphInfo: UnsafePointer<nhswift_glyph>,
					backgroundGlyphInfo: UnsafePointer<nhswift_glyph>)
	{
        guard let state = gameState,
              x >= 0, x < Int32(GameState.mapCols),
              y >= 0, y < Int32(GameState.mapRows) else { return }
        let idx = Int(y) * GameState.mapCols + Int(x)
        state.mapGlyphs[idx]   = glyphInfo.pointee
        state.mapBkGlyphs[idx] = backgroundGlyphInfo.pointee
    }

    func clipAround(x: Int32, y: Int32) {
        gameState?.clipAround = (x, y)
        gameState?.clipAroundVersion += 1
    }

    // MARK: Menus

    func startMenu(in window: NHWindowID, behavior: UInt) {
        windowData[window]!.resetMenu()
        windowData[window]!.menuBehavior = behavior
    }

    func addMenuItem(in window: NHWindowID, accel: CChar, groupAccel: CChar, attr: Int32, color: Int32, string: String, flags: UInt32, glyphInfo: UnsafeRawPointer, identifier: UInt) {
        windowData[window]!.menuItems.append(NHMenuItem(
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
        windowData[window]!.menuTitle = prompt ?? ""
    }

    // MARK: Status bar

    func enableStatusField(_ fieldIndex: Int32, name: String, format: String, enabled: Bool) {
        // nothing to do
    }

    func updateStatusField(_ fieldIndex: Int32, text: String?, condBits: Int, change: Int32, percent: Int32, color: Int32, colorMasks: UnsafePointer<UInt>?) {
        guard let state = gameState else { return }
        // Parse text as Int, skipping any leading non-numeric prefix (e.g. "$:" on gold).
        let intVal: Int = {
            guard let text else { return 0 }
            let s = text.drop(while: { !$0.isNumber && $0 != "-" })
            return Int(s) ?? 0
        }()
        switch fieldIndex {
        case  0: state.playerName   = text ?? ""                        // BL_TITLE
        case  1: state.str          = text ?? ""                        // BL_STR (may be "18/01")
        case  2: state.dex          = intVal                            // BL_DX
        case  3: state.con          = intVal                            // BL_CO
        case  4: state.int_         = intVal                            // BL_IN
        case  5: state.wis          = intVal                            // BL_WI
        case  6: state.cha          = intVal                            // BL_CH
        case 10: state.gold         = intVal                            // BL_GOLD
        case 11: state.pw           = intVal                            // BL_ENE
        case 12: state.maxPw        = intVal                            // BL_ENEMAX
        case 13: state.level        = intVal                            // BL_XP (experience level)
        case 14: state.ac           = intVal                            // BL_AC
        case 16: state.turn         = intVal                            // BL_TIME
        case 18: state.hp           = intVal                            // BL_HP
        case 19: state.maxHp        = intVal                            // BL_HPMAX
        case 20: state.dlvl         = text ?? ""                        // BL_LEVELDESC
        case 21: state.xp           = intVal                            // BL_EXP
        case 22: state.statusEffects = statusEffectsString(from: condBits) // BL_CONDITION
        default: break  // BL_ALIGN, BL_SCORE, BL_CAP, BL_HD, BL_HUNGER,
                        // BL_WEAPON, BL_ARMOR, BL_TERRAIN, BL_VERS, flush/reset
        }
    }

    // MARK: Misc output

    func updatePositionBar(_ positionBar: String) {
        // TODO: update position bar UI
		fatalError()
    }

    func updateInventory(_ slots: [NHEquipItem]) {
        var equip: [NHEquipSlot: NHEquipItem] = [:]
        for item in slots where item.glyph.glyph != -1 {  // -1 == NO_GLYPH
            equip[item.slot] = item
        }
        gameState?.equipment = equip
    }

    func putMessageHistory(_ message: String?, restoring: Bool) {
        if let message, !message.isEmpty {
            gameState?.messages.append(message)
        }
    }

    func requestPlayerSelection() {
        // TODO: show character creation UI
		print("requestPlayerSelection")
    }

    func initWindows() {
        isInitialized = true
    }

    func initStatus() {
        // nothing to do
    }

    func exitWindows(withMessage message: String?) {
		guard let message else {
			return
		}
		guard let messageWin = windowData.first(where: { (k,v) in v.type == .message })?.key else {
			rawPrint(message)
			return
		}
		self.putString(in: messageWin, string: message, attribute: .none)
        print("exit_nhwindows: \(message)")
    }

    func suspendWindows(withMessage message: String?) {
        // not supported
    }

    func resumeWindows() {
        // not supported
    }

    // MARK: Blocking input

    func needLineInput(_ prompt: String, completion: @escaping (String?) -> Void) {
        pendingLineCompletion = completion
    }

    func needKeyInput(_ completion: @escaping (Int32) -> Void) {
        keyboard.resetDirectionState()
        pendingKeyCompletion = completion
    }

    func needKeyOrMouseInput(_ completion: @escaping (Int32, Int32, Int32, Int32) -> Void) {
        keyboard.resetDirectionState()
        pendingKeyOrMouseCompletion = completion
    }

    func needYnInput(_ query: String, responses: String, defaultResponse: Int32, completion: @escaping (Int32) -> Void) {
        print("yn_function: \(query) [\(responses)]")
        if isSavingAndQuitting {
            completion(Int32(UInt8(ascii: "y")))
            return
        }

        // Direction questions get a dedicated direction-picker panel.
		if responses.isEmpty && query.lowercased().contains("direction") {
            showDirectionModal(completion: completion)
            return
        }

        let (items, specials) = YesNoWindowView.parseYnChoices(responses)

        // For known sequences the button labels are self-explanatory, so strip the
        // embedded "[y/n/…]" hint from the question. For unknown sequences keep it —
        // the brackets are the only indication of what each character means.
        let displayQuestion = YesNoWindowView.knownLabels[items] != nil
            ? Self.strippingBracketedContent(query)
            : query

        // Multi-item list with '?' option: let NetHack show its own comprehensive list.
        if specials.contains("?") && items.count > 1 {
            completion(Int32(UInt8(ascii: "?")))
            return
        }

        // Show a Yes/No panel for simple choices like "yn", "ynq", "rl".
        let buttons = YesNoWindowView.makeButtons(from: responses)
        // Cancel (ESC and close button) is only supported when 'q' is a valid response.
        let cancelValue: Int32 = items.contains("q") ? Int32(UInt8(ascii: "q")) : 0
        var styleMask: NSWindow.StyleMask = [.titled, .utilityWindow]
        if cancelValue != 0 {
			styleMask.insert(.closable)
		}
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 115),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        panel.animationBehavior = .none
        panel.isRestorable = false
        panel.isReleasedWhenClosed = false
        var result: Int32 = cancelValue
        let view = YesNoWindowView(
            question: displayQuestion,
            buttons: buttons,
            defaultValue: defaultResponse,
            cancelValue: cancelValue,
            onSelect: { value in
                result = value
                NSApp.stopModal()
            }
        )
        let hc = NSHostingController(rootView: view)
        panel.contentViewController = hc
        NSApp.runModal(for: panel)
        panel.close()
        completion(result)
    }

    private func showDirectionModal(completion: @escaping (Int32) -> Void) {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Which direction?"
        panel.animationBehavior = .none
        panel.isRestorable = false
        panel.isReleasedWhenClosed = false
        var result = asciiESC
        let view = DirectionModalView { key in
            result = key
            NSApp.stopModal()
        }
        let hostingView = NSHostingView(rootView: view)
        panel.setContentSize(hostingView.fittingSize)
        panel.contentView = hostingView

        // Pre-measure the size to avoid a preferredContentSize resize loop with Grid.
        let contentSize = NSHostingView(rootView: view).fittingSize
        let hc = NSHostingController(rootView: view)
        panel.setContentSize(contentSize)
        panel.contentViewController = hc
        NSApp.runModal(for: panel)
        panel.close()
        completion(result)
    }

    /// Removes the first `[…]` bracketed substring from `text`, trimming whitespace.
	/// Skip if there are multiple bracketed items.
    private static func strippingBracketedContent(_ text: String) -> String {
        guard
			text.count(where: { $0 == "[" }) == 1,
			let open = text.firstIndex(of: "["),
			let close = text[open...].firstIndex(of: "]")
        else { return text }
        var result = text
        result.removeSubrange(open...close)
        return result.trimmingCharacters(in: .whitespaces)
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
		let data = windowData[window]!
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
// MARK: - Direction Modal View

/// Wraps DirectionView for modal presentation with keyboard support.
private struct DirectionModalView: View {
    let onKey: (Int32) -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        DirectionView(onKey: onKey)
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            .onAppear { isFocused = true }
            .onKeyPress { press in
                guard let key = Self.directionKey(from: press) else { return .ignored }
                onKey(key)
                return .handled
            }
    }

    /// Translates a SwiftUI KeyPress into the NetHack direction key code it represents,
    /// or nil if the key is not a recognised direction input.
    private static func directionKey(from press: KeyPress) -> Int32? {
        let shift = press.modifiers.contains(.shift)
        switch press.key {
        case .upArrow:    return Int32(UInt8(ascii: shift ? "K" : "k"))
        case .downArrow:  return Int32(UInt8(ascii: shift ? "J" : "j"))
        case .leftArrow:  return Int32(UInt8(ascii: shift ? "H" : "h"))
        case .rightArrow: return Int32(UInt8(ascii: shift ? "L" : "l"))
        default: break
        }
        guard let char = press.characters.first else { return nil }
        if char.asciiValue == UInt8(asciiESC) { return asciiESC }
        let valid = Set<Character>("yYkKuUhHlLbBjJnN<>.")
        return valid.contains(char) ? Int32(char.asciiValue ?? 0) : nil
    }
}

// MARK: - Status helpers

/// Converts a BL_CONDITION bitmask into a human-readable comma-separated string.
private func statusEffectsString(from condBits: Int) -> String {
    // (mask, display name) — ordered by rough importance for display
    let conditions: [(Int, String)] = [
        (0x00000002, "Blind"),
        (0x00000008, "Confused"),
        (0x00000400, "Hallucinating"),
        (0x00400000, "Stunned"),
        (0x00008000, "Paralyzed"),
        (0x08000000, "Unconscious"),
        (0x00020000, "Sleeping"),
        (0x00100000, "Stoning"),
        (0x00200000, "Strangling"),
        (0x00000080, "FoodPois"),
        (0x00000010, "Deaf"),
        (0x00040000, "Slimed"),
        (0x00800000, "Submerged"),
        (0x00002000, "InLava"),
        (0x00004000, "Levitating"),
        (0x00000040, "Flying"),
        (0x00010000, "Riding"),
        (0x10000000, "WoundedLegs"),
        (0x04000000, "Trapped"),
        (0x00000200, "Grabbed"),
        (0x00000800, "Held"),
    ]
    return conditions
        .filter { condBits & $0.0 != 0 }
        .map(\.1)
        .joined(separator: ", ")
}

