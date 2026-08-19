import AppKit
import SwiftUI

/// Translates NSEvents into NetHack character codes, including diagonal
/// arrow-key chord detection.  Wire up the two callbacks; the handler does the rest.
///
/// Key events are delivered via `handleKeyDown` / `handleKeyUp`, which are called
/// from `GameKeyView` — a window-scoped NSView first responder.  Unlike a global
/// event monitor, this approach only receives events while the game window is key,
/// so modals and other panels naturally stop delivery without any extra guard code.
final class KeyboardHandler {
    /// Called when a translated key should be forwarded to NetHack.
    var onKey: ((Int32) -> Void)?
    /// Returns true when NetHack is currently blocking for key input.
    var isWaitingForInput: (() -> Bool)?

    private var pressedDirectionKeys: Set<Int> = []
    private var pendingDirectionKeys: Set<Int> = []

    /// Clears accumulated arrow-key state. Call at the start of each new blocking
    /// input request so stale state cannot corrupt the next chord.
    func resetChordState() {
        pressedDirectionKeys.removeAll()
        pendingDirectionKeys.removeAll()
    }

    // MARK: - Event handling (called by GameKeyView)

    /// Processes a keyDown event.  Returns true if the event was consumed.
    @discardableResult
    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard isWaitingForInput?() == true else { return false }

        // Let Command-key shortcuts (Cmd-Q, Cmd-H, …) reach the app menu.
        if event.modifierFlags.contains(.command) { return false }

        let keyCode = Int(event.keyCode)
        if let mapping = Self.numpadKeyMap[keyCode] {
            let shift = event.modifierFlags.contains(.shift)
            onKey?(Int32(shift ? mapping.shifted : mapping.plain))
        } else if Self.arrowKeyCodes.contains(keyCode) {
            pressedDirectionKeys.insert(keyCode)
            pendingDirectionKeys.insert(keyCode)
        } else {
            onKey?(Self.keyCode(from: event))
        }
        return true
    }

    /// Processes a keyUp event.  Returns true if the event was consumed.
    @discardableResult
    func handleKeyUp(_ event: NSEvent) -> Bool {
        guard isWaitingForInput?() == true else { return false }

        let keyCode = Int(event.keyCode)
        if Self.arrowKeyCodes.contains(keyCode) {
            if pendingDirectionKeys.contains(keyCode) {
                let shift = event.modifierFlags.contains(.shift)
                let ch = Self.chordCharacter(keys: pendingDirectionKeys, shift: shift)
                pendingDirectionKeys.removeAll()
                onKey?(ch)
            }
            pressedDirectionKeys.remove(keyCode)
        }
        return true  // consume all keyUp events while waiting for input
    }

    // MARK: - Key translation

    /// Arrow key codes on macOS (left=123, right=124, down=125, up=126).
    private static let arrowKeyCodes: Set<Int> = [123, 124, 125, 126]

    /// Maps numeric-keypad hardware key codes to (plain, shifted) vi-motion ASCII values.
    /// Shift uppercases direction keys for run mode; KP5 (wait) is unaffected by shift.
    ///
    ///   KP layout       key code   plain / shifted
    ///   7  8  9         89 91 92   y/Y  k/K  u/U
    ///   4  5  6         86 87 88   h/H  .    l/L
    ///   1  2  3         83 84 85   b/B  j/J  n/N
    private static let numpadKeyMap: [Int: (plain: UInt8, shifted: UInt8)] = [
        89: (121,  89),   // KP7 → y/Y northwest
        91: (107,  75),   // KP8 → k/K north
        92: (117,  85),   // KP9 → u/U northeast
        86: (104,  72),   // KP4 → h/H west
        87: ( 46,  46),   // KP5 → .   wait (shift has no effect)
        88: (108,  76),   // KP6 → l/L east
        83: ( 98,  66),   // KP1 → b/B southwest
        84: (106,  74),   // KP2 → j/J south
        85: (110,  78),   // KP3 → n/N southeast
    ]

    /// Resolves a set of simultaneously-pressed arrow key codes into a single
    /// vi-motion character. Diagonal chords (e.g. left+down) map to the
    /// corresponding intercardinal direction. Shift uppercases for run mode.
    private static func chordCharacter(keys: Set<Int>, shift: Bool) -> Int32 {
        let up    = keys.contains(126)
        let down  = keys.contains(125)
        let left  = keys.contains(123)
        let right = keys.contains(124)
        let ascii: UInt8
        switch (up, down, left, right) {
        case (true,  _,     true,  _    ): ascii = shift ? 89 : 121  // Y/y northwest
        case (true,  _,     _,     true ): ascii = shift ? 85 : 117  // U/u northeast
        case (_,     true,  true,  _    ): ascii = shift ? 66 : 98   // B/b southwest
        case (_,     true,  _,     true ): ascii = shift ? 78 : 110  // N/n southeast
        case (true,  _,     _,     _    ): ascii = shift ? 75 : 107  // K/k north
        case (_,     true,  _,     _    ): ascii = shift ? 74 : 106  // J/j south
        case (_,     _,     true,  _    ): ascii = shift ? 72 : 104  // H/h west
        case (_,     _,     _,     true ): ascii = shift ? 76 : 108  // L/l east
        default:                           return 0
        }
        return Int32(ascii)
    }

    /// Translates a non-arrow key-down NSEvent into the NetHack character code.
    /// Arrow keys are handled separately via chord detection and never reach here.
    static func keyCode(from event: NSEvent) -> Int32 {
        let flags = event.modifierFlags.intersection([.control, .option])
        switch flags {
        case .control:
            // macOS may intercept some Ctrl combos before characters is populated,
            // so read the base character and compute the control code directly.
            if let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first,
               scalar.value >= 64, scalar.value < 128
            {
                return Int32(scalar.value) & 0x1F
            }
        case .option:
            // Meta is represented as the base character with the high bit set.
            if let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first,
               scalar.value > 0, scalar.value < 128
            {
                return Int32(scalar.value | 0x80)
            }
        default:
            // Plain key: macOS encodes shift into characters already (e.g. 'A' for Shift-A).
            if let scalar = event.characters?.unicodeScalars.first,
               scalar.value > 0, scalar.value < 128
            {
                return Int32(scalar.value)
            }
        }
        return 0
    }
}

// MARK: - GameKeyView

/// A zero-visible-size NSView that maintains first-responder status in the game
/// window and forwards key events to the KeyboardHandler.
///
/// Because events arrive through the responder chain (not a global monitor), key
/// delivery is automatically scoped to the game window.  When a modal panel becomes
/// key (e.g. a NetHack popup or the .nethackrc editor) this view is no longer first
/// responder and does not intercept those events.
final class GameKeyView: NSView {
    var keyboardHandler: KeyboardHandler?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.makeFirstResponder(self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        super.viewWillMove(toWindow: newWindow)
    }

    @objc private func windowDidBecomeKey() {
        // Reclaim first responder whenever the game window regains key status
        // (e.g. after a modal panel closes).
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if keyboardHandler?.handleKeyDown(event) != true {
            // Command keys must propagate so app-menu shortcuts keep working.
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if keyboardHandler?.handleKeyUp(event) != true {
            super.keyUp(with: event)
        }
    }
}

/// Embeds `GameKeyView` in the SwiftUI hierarchy.  Place this once (typically as a
/// `.background` of the main game view) so the game window captures key events.
struct GameKeyViewRepresentable: NSViewRepresentable {
    let handler: KeyboardHandler

    func makeNSView(context: Context) -> GameKeyView {
        let view = GameKeyView()
        view.keyboardHandler = handler
        return view
    }

    func updateNSView(_ nsView: GameKeyView, context: Context) {}
}
