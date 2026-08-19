//
//  NetHackController.swift
//  NetHackSwift
//
//  Created by Bryce Cogswell on 8/6/26.
//

import AppKit
import Foundation
import Observation
import QuartzCore
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
    var color: NHColor
    var string: String
    var flags: UInt32
	var glyph: Int32
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
    // Keys pressed before NetHack has asked for input (e.g. typed while a message
    // modal was open). Consumed in FIFO order by needKeyInput/needKeyOrMouseInput.
    @ObservationIgnored private var pendingKeyInputQueue: [Int32] = []
    // Non-blocking text panels shown for the user to read and dismiss themselves.
    // Not tracked in nhWindows so destroyNhwindow doesn't close them prematurely.
    @ObservationIgnored private var userDismissedPanels: Set<NSWindow> = []

    /// Set by the app before calling start(). Injected into any windows the bridge opens.
    var gameState: GameState?

    /// Windows created by NetHack but not yet displayed (between createNhwindow and displayNhwindow).
    @ObservationIgnored private var windowData: [NHWindowID: NHWindowData] = [:]

    /// NSWindows opened on behalf of NetHack, keyed by their NHWindowID.
    /// Kept to maintain a strong reference so the windows aren't deallocated.
    @ObservationIgnored private var nhWindows: [NHWindowID: NSWindow] = [:]

    private let bridge: NetHackBridge?
    var isInitialized = false

    /// A SwiftUI view that captures key events for the game window.
    /// Embed it once (as a `.background`) in the main game view hierarchy.
    var keyInputView: some View { GameKeyViewRepresentable(handler: keyboard) }

    override init() {
        let isPreview = getenv("XCODE_RUNNING_FOR_PREVIEWS") != nil
                     || (getenv("XCODE_RUNNING_FOR_PLAYGROUNDS").map { String(cString: $0) == "1" } ?? false)
        bridge = isPreview ? nil : NetHackBridge()
        super.init()
        keyboard.isWaitingForInput = { [weak self] in
            self?.pendingKeyCompletion != nil || self?.pendingKeyOrMouseCompletion != nil
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
		print("Playground at \(playgroundURL.path)")
        bridge.run(withHackdirURL: resourcesURL,
				   playgroundURL: playgroundURL,
				   completion: { exitCode in
            print("--- NetHack exited (\(exitCode)) ---")
        })
    }

    /// Send the save-and-quit command to NetHack. NetHack will save and call exit().
    func saveAndQuit() {
        sendKey(Int32(UInt8(ascii: "S")))
    }

    /// Forward a keypress to whichever blocking key-input request is pending,
    /// or enqueue it if NetHack has not yet asked for input.
    func sendKey(_ key: Int32) {
        if let completion = pendingKeyCompletion {
            pendingKeyCompletion = nil
            completion(key)
        } else if let completion = pendingKeyOrMouseCompletion {
            pendingKeyOrMouseCompletion = nil
            completion(key, 0, 0, 0)
        } else {
            pendingKeyInputQueue.append(key)
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
            let panel = makeModalPanel(
                styleMask: hasTitle ? [.titled, .closable, .resizable] : [.closable, .resizable],
                title: hasTitle ? data.menuTitle : nil
            )
            if blocking {
                nhWindows[window] = panel
                let view = MessageWindowView(
                    text: text,
                    onClose: { NSApp.stopModal() },
                    onAnyKey: { [weak self] key in
                        // Queue the key so it is consumed by the next input request,
                        // then close the modal (the user has "typed through" it).
                        self?.pendingKeyInputQueue.append(key)
                        NSApp.stopModal()
                    }
                )
                runModal(panel, view: view, minSize: CGSize(width: 259, height: 100))
                nhWindows.removeValue(forKey: window)
            } else {
                userDismissedPanels.insert(panel)
                let view = MessageWindowView(text: text) { [weak self, weak panel] in
                    panel?.close()
                    if let panel { self?.userDismissedPanels.remove(panel) }
                }
                preparePanel(panel, view: view, minSize: CGSize(width: 259, height: 100))
                // Don't store in nhWindows — destroyNhwindow must not close this panel
                // before the user has had a chance to read it.
                panel.makeKeyAndOrderFront(nil)
            }
        case .menu:
            // Non-blocking: do nothing here — selectMenu will create the window.
            // Blocking: show display-only and wait for dismiss.
			assert(blocking)
			assert(false)	// not sure this path is ever used
			showMenuWindow(window: window, selectionMode: .none, onAccept: nil, onCancel: nil)
		case .map:
            gameState?.clipAroundVersion += 1
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
        // clipAroundVersion is bumped in displayNhwindow(.map) so the scroll
        // and Canvas redraw happen together, after glyphs are flushed.
    }

    // MARK: Menus

    func startMenu(in window: NHWindowID, behavior: UInt) {
        windowData[window]!.resetMenu()
        windowData[window]!.menuBehavior = behavior
    }

    func addMenuItem(in window: NHWindowID, accel: CChar, groupAccel: CChar, attr: Int32, color: NHColor, string: String, flags: UInt32, glyph: Int32, identifier: UInt) {
        windowData[window]!.menuItems.append(NHMenuItem(
            accel: accel,
            groupAccel: groupAccel,
            attr: attr,
            color: color,
            string: string,
			flags: flags,
			glyph: glyph,
            identifier: identifier
        ))
    }

    func endMenu(in window: NHWindowID, prompt: String?) {
        windowData[window]!.menuTitle = prompt ?? ""
    }

    // MARK: Status bar

    func enable(_ fieldIndex: NHStatusField, name: String, format: String, enabled: Bool) {
        // nothing to do
    }

    func update(_ fieldIndex: NHStatusField, text: String?, condBits: Int, change: Int32, percent: Int32, color: NHColor, colorMasks: UnsafePointer<UInt>?) {
        guard let state = gameState else { return }
        // Parse text as Int, skipping any leading non-numeric prefix (e.g. "$:" on gold).
        let intVal: Int = {
            guard let text else { return 0 }
            let s = text.drop(while: { !$0.isNumber && $0 != "-" })
            return Int(s) ?? 0
        }()
        switch fieldIndex {
        case .title:     state.playerName    = text ?? ""
        case .str:       state.str           = text ?? ""               // may be "18/01"
        case .dex:       state.dex           = intVal
        case .con:       state.con           = intVal
        case .int:       state.int_          = intVal
        case .wis:       state.wis           = intVal
        case .cha:       state.cha           = intVal
        case .gold:      state.gold          = intVal
        case .energy:    state.pw            = intVal
        case .energyMax: state.maxPw         = intVal
        case .xp:        state.level         = intVal
        case .ac:        state.ac            = intVal
        case .time:      state.turn          = intVal
        case .hp:        state.hp            = intVal
        case .hpMax:     state.maxHp         = intVal
        case .align:     state.alignRaceRole = text ?? ""
        case .levelDesc: state.dlvl          = text ?? ""
        case .exp:       state.xp            = intVal
        case .condition: state.statusEffects = statusEffectsString(from: condBits)
        default: break  // score, cap, hd, hunger, weapon, armor, terrain, version,
                        // flush, reset, characteristics
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

    func requestPlayerSelection(withRoles roleNames: [String],
                                roleGlyphs: [NSNumber],
                                races raceNames: [String],
                                raceGlyphs: [NSNumber],
                                genders genderNames: [String],
                                aligns alignNames: [String]) -> NHPlayerSelection? {
        let tileSet = TileSet.shared
        let roles   = zip(roleNames, roleGlyphs).map { name, glyph in
            PlayerOption(name: name, image: tileSet?.image(forGlyph: glyph.intValue))
        }
        let races   = zip(raceNames, raceGlyphs).map { name, glyph in
            PlayerOption(name: name, image: tileSet?.image(forGlyph: glyph.intValue))
        }
        let genders = genderNames.map { PlayerOption(name: $0) }
        let aligns  = alignNames.map  { PlayerOption(name: $0) }

        let panel = makeModalPanel(styleMask: [.titled],
								   title: "Character Selection")

        var playerSelection: PlayerSelection? = nil
        let view = PlayerSelectionView(
            initialName: gameState?.playerName ?? "",
            races: races,
            roles: roles,
            genders: genders,
            aligns: aligns,
            onPlay: { selection in
                playerSelection = selection
                NSApp.stopModal()
            },
            onQuit: {
                NSApp.stopModal()
                NSApp.terminate(nil)
            }
        )
        runModal(panel, view: view)

        guard let sel = playerSelection else { return nil }

        let result = NHPlayerSelection()
        if let raceID = sel.raceID, let idx = races.firstIndex(where: { $0.id == raceID }) {
            result.raceIndex = idx
        }
        if let roleID = sel.roleID, let idx = roles.firstIndex(where: { $0.id == roleID }) {
            result.roleIndex = idx
        }
        result.genderIndex = genders.firstIndex(where: { $0.id == sel.genderID }) ?? Int(NHSWIFT_ROLE_RANDOM)
        result.alignIndex  = aligns.firstIndex(where:  { $0.id == sel.alignID  }) ?? Int(NHSWIFT_ROLE_RANDOM)
        result.playerName = sel.name.isEmpty ? nil : sel.name
        return result
    }

    func waitSynch() {
        // Glyphs were already flushed by the bridge before this call.
        // Bump version counters so MapView redraws with the current state.
        gameState?.clipAroundVersion += 1
        gameState?.mapVersion += 1
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
        let panel = makeModalPanel(
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            title: nil
        )
        var result: String? = nil
        let view = InputWindowView(
            prompt: prompt,
            onAccept: { text in
                result = text
                NSApp.stopModal()
            },
            onCancel: {
                NSApp.stopModal()
            }
        )
        runModal(panel, view: view, minSize: CGSize(width: 363, height: 115))
        completion(result)
    }

    func needKeyInput(_ completion: @escaping (Int32) -> Void) {
        if !pendingKeyInputQueue.isEmpty {
            completion(pendingKeyInputQueue.removeFirst())
            return
        }
        keyboard.resetChordState()
        pendingKeyCompletion = completion
    }

    func needKeyOrMouseInput(_ completion: @escaping (Int32, Int32, Int32, Int32) -> Void) {
        if !pendingKeyInputQueue.isEmpty {
            completion(pendingKeyInputQueue.removeFirst(), 0, 0, 0)
            return
        }
        keyboard.resetChordState()
        pendingKeyOrMouseCompletion = completion
    }

    func needYnInput(_ query: String, responses: String, defaultResponse: Int32, completion: @escaping (Int32) -> Void) {
        // Auto-confirm specific questions without showing any UI.
        let alwaysYes = ["Really save?", "Overwrite the old file?"]
        if alwaysYes.contains(query) {
            completion(Int32(UInt8(ascii: "y")))
            return
        }

        // Direction questions get a dedicated direction-picker panel.
        if responses.isEmpty && query.lowercased().contains("direction") {
            showDirectionModal(completion: completion)
            return
        }

        // Well-known answer sets (yn, ynq, lr) get a modal button panel.
        if let buttons = YesNoWindowView.makeButtons(from: responses) {
            // Strip the embedded "[y/n/…]" hint — the button labels make it redundant.
            let displayQuestion = Self.strippingBracketedContent(query)
            // Cancel (ESC and close button) is only supported when 'q' is a valid response.
            let cancelValue: Int32 = responses.contains("q") ? Int32(UInt8(ascii: "q")) : 0
            var styleMask: NSWindow.StyleMask = [.titled, .utilityWindow]
            if cancelValue != 0 { styleMask.insert(.closable) }
			let panel = makeModalPanel(styleMask: styleMask,
									   title: nil)
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
            runModal(panel, view: view)
            completion(result)
            return
        }

        // Fallback: print the question with choices and default to the messages window,
        // then wait for a valid keystroke.
        gameState?.messages.append(query)

        func waitForValidKey() {
            keyboard.resetChordState()
            pendingKeyCompletion = { key in
                let asciiReturn: Int32 = 13
                if key == asciiReturn && defaultResponse != 0 {
                    completion(defaultResponse)
                } else if responses.isEmpty || responses.unicodeScalars.contains(where: { Int32($0.value) == key }) {
                    completion(key)
                } else {
                    // Invalid key — keep waiting.
                    waitForValidKey()
                }
            }
        }
        waitForValidKey()
    }

    private func showDirectionModal(completion: @escaping (Int32) -> Void) {
        let panel = makeModalPanel(
            styleMask: [.titled, .closable, .utilityWindow],
            title: "Which direction?"
        )
        var result = asciiESC
        let view = DirectionModalView { key in
            result = key
            NSApp.stopModal()
        }
        runModal(panel, view: view)
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
        showMenuWindow(window: window,
					   selectionMode: selectionMode,
					   onAccept: { selected in
							completion(selected.map { NHMenuSelection(identifier: $0.identifier, count: 1) })
						},
					   onCancel: {
							completion(nil)
						}
        )
    }

    // MARK: - Configuration

    /// Opens a modal text editor for the NetHack configuration file (the .nethackrc equivalent).
    /// Creates the file with starter content if it does not yet exist, then writes back the
    /// edited text when the user accepts.  Cancel leaves the file unchanged.
	func editNethackrc() {
		let fileURL = Self.nethackrcURL
		let fm = FileManager.default

		do {
			if !fm.fileExists(atPath: fileURL.path) {
				try fm.createDirectory(at: fileURL.deletingLastPathComponent(),
									   withIntermediateDirectories: true)
				let defaultContent = """
				# NetHack configuration file.
				# Changes take effect the next time you start a new game.
				#
				# Example:
				# OPTIONS=autopickup,color,time,showexp
				
				"""
				try defaultContent.write(to: fileURL, atomically: false, encoding: .utf8)
			}

			let content = (try String(contentsOf: fileURL, encoding: .utf8))
			let panel = makeModalPanel(styleMask: [.titled, .closable, .resizable],
									   title: "NetHack Defaults")
			var accepted = false
			var editedContent = content
			let view = NethackrcEditorView(
				initialText: content,
				onAccept: { text in
					editedContent = text
					accepted = true
					NSApp.stopModal()
				},
				onCancel: {
					NSApp.stopModal()
				}
			)
			runModal(panel, view: view, minSize: CGSize(width: 500, height: 400))
			if accepted {
				try editedContent.write(to: fileURL, atomically: false, encoding: .utf8)
			}
		} catch {
			let alert = NSAlert(error: error)
			alert.runModal()
		}
	}

    private static var nethackrcURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Preferences/NetHack Defaults.txt")
    }

    // MARK: Modal Helpers

    /// Creates a `KeyablePanel` with the standard boilerplate applied to all NetHack modal windows.
    private func makeModalPanel(
        styleMask: NSWindow.StyleMask,
        title: String?
    ) -> KeyablePanel {
        let panel = KeyablePanel(
            contentRect: .zero,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        if let title { panel.title = title }
        panel.animationBehavior = .none
        panel.isRestorable = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        return panel
    }

    /// Installs `view` as the panel's content, sizes it to fit (clamped by `maxHeightFraction`
    /// of the visible screen height, floored by `minSize`), and centers the panel.
    private func preparePanel<V: View>(
        _ panel: NSWindow,
        view: V,
        minSize: CGSize = .zero,
        maxHeightFraction: CGFloat = 1.0
    ) {
        let hc = NSHostingController(rootView: view)
        panel.contentViewController = hc
        if minSize != .zero { panel.contentMinSize = minSize }
        let fitting = hc.view.fittingSize
        let maxH = (NSScreen.main?.visibleFrame.height ?? 800) * maxHeightFraction
        panel.setContentSize(CGSize(
            width:  max(fitting.width,  minSize.width),
            height: max(min(fitting.height, maxH), minSize.height)
        ))
        panel.center()
    }

    /// Installs `view`, sizes and centers the panel, runs it modally, then closes it.
    private func runModal<V: View>(
        _ panel: NSWindow,
        view: V,
        minSize: CGSize = .zero,
        maxHeightFraction: CGFloat = 1.0
    ) {
        preparePanel(panel, view: view, minSize: minSize, maxHeightFraction: maxHeightFraction)
        // If the user dismisses via the title-bar close button, stop the modal loop
        // so runModal(for:) returns. The observer is removed before panel.close() to
        // avoid a redundant stopModal() call on the normal accept/cancel path.
        let closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { _ in NSApp.stopModal() }
        NSApp.runModal(for: panel)
        NotificationCenter.default.removeObserver(closeObserver)
        panel.close()
    }

    /// Creates and presents a menu window modally. `onAccept`/`onCancel` are called after dismiss.
    /// Pass nil for both when the menu is display-only and no completion needs to be called.
    private func showMenuWindow(window: NHWindowID,
                                selectionMode: MenuSelectionMode,
                                onAccept: (([MenuItemData]) -> Void)?,
                                onCancel: (() -> Void)?)
	{
		let data = windowData[window]!
        let tileSet = TileSet.shared
        let rawItems = data.menuItems

        // Collect accels already assigned by NetHack so auto-assignment skips them.
        var usedAccels = Set<UInt8>(rawItems.compactMap { $0.accel > 0 ? UInt8($0.accel) : nil })
        let accelPool: [UInt8] = Array(UInt8(ascii: "a")...UInt8(ascii: "z"))
                                + Array(UInt8(ascii: "A")...UInt8(ascii: "Z"))
        var accelPoolIndex = 0

        var items: [MenuItemData] = []
        items.reserveCapacity(rawItems.count)
        for (idx, raw) in rawItems.enumerated() {
            let selectable = raw.identifier != 0

            // Determine accelerator: use the one NetHack supplied, or auto-assign a–zA-Z.
            var accelStr = ""
            if selectable {
                if raw.accel > 0 {
                    accelStr = String(UnicodeScalar(UInt8(raw.accel)))
                } else {
                    if let idx = accelPool[accelPoolIndex...].firstIndex(where: { !usedAccels.contains($0) }) {
                        let c = accelPool[idx]
                        accelPoolIndex = idx + 1
                        usedAccels.insert(c)
                        accelStr = String(UnicodeScalar(c))
                    }
                }
            }

            // For header items, look ahead at the items in their group.
            // If every item in the group shares the same non-zero group accelerator,
            // append that character to the header text so the user can see it at a glance.
            var displayText = raw.string
            if !selectable && !raw.string.isEmpty {
                let groupStart = idx + 1
                var groupEnd = groupStart
                while groupEnd < rawItems.count && rawItems[groupEnd].identifier != 0 {
                    groupEnd += 1
                }
                let groupSlice = rawItems[groupStart..<groupEnd]
                if !groupSlice.isEmpty {
                    let gacs = Set(groupSlice.map { $0.groupAccel })
                    if gacs.count == 1, let gac = gacs.first, gac != 0 {
                        displayText += "  \(Character(UnicodeScalar(UInt8(gac))))"
                    }
                }
            }

            items.append(MenuItemData(
                key: accelStr,
                groupAccel: raw.groupAccel > 0 ? String(UnicodeScalar(UInt8(raw.groupAccel))) : "",
                image: tileSet?.image(forGlyph: Int(raw.glyph)),
                text: displayText,
                color: raw.color.nsColor() ?? .black,
                identifier: raw.identifier
            ))
        }
        let categories = [MenuCategory(title: data.menuTitle, items: items)]
        // Note: fittingSize is used (via runModal) rather than sizingOptions = .preferredContentSize
        // because preferredContentSize triggers a setNeedsUpdateConstraints re-entrancy crash
        // inside the modal run loop when used with this view.
		let panel = makeModalPanel(styleMask: [.titled, .closable, .resizable],
								   title: nil)
        panel.titleVisibility = .hidden
        nhWindows[window] = panel
        var accepted: [MenuItemData]? = nil
        let view = MenuWindowView(
            categories: categories,
            selectionMode: selectionMode,
            onAccept: { selected in accepted = selected; NSApp.stopModal() },
            onCancel: { NSApp.stopModal() }
        )
        runModal(panel, view: view,
                 minSize: CGSize(width: 300, height: 100),
                 maxHeightFraction: 0.7)
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

