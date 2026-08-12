import AppKit

/// Owns the global key-down/key-up event monitor and translates NSEvents into
/// NetHack character codes, including diagonal arrow-key chord detection.
///
/// Wire up the three callbacks and call `resetDirectionState()` at the start
/// of each blocking input request; the handler does the rest.
final class KeyboardHandler {
    /// Called when a key should be forwarded to NetHack.
    var onKey: ((Int32) -> Void)?
    /// Called when Cmd-Q is pressed.
    var onSaveAndQuit: (() -> Void)?
    /// Returns true when NetHack is currently blocking for key input.
    var isWaitingForInput: (() -> Bool)?

    private var keyEventMonitor: Any?
    private var pressedDirectionKeys: Set<Int> = []
    private var pendingDirectionKeys: Set<Int> = []

    init() {
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, self.isWaitingForInput?() == true else { return event }

            let keyCode = Int(event.keyCode)
            let isArrow = Self.arrowKeyCodes.contains(keyCode)

            if event.type == .keyDown {
                // Cmd-Q: ask NetHack to save, then auto-confirm and terminate.
                if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                   event.characters == "q"
                {
                    self.onSaveAndQuit?()
                    return nil
                }
                // Let other Command-key shortcuts (Cmd-H, Cmd-W, …) reach the app menu.
                if event.modifierFlags.contains(.command) { return event }

                if isArrow {
                    // Accumulate arrow keys; resolve the chord on key-up.
                    self.pressedDirectionKeys.insert(keyCode)
                    self.pendingDirectionKeys.insert(keyCode)
                } else {
                    self.onKey?(Self.keyCode(from: event))
                }
                return nil  // consume

            } else {  // .keyUp
                if isArrow {
                    if self.pendingDirectionKeys.contains(keyCode) {
                        // First key-up of this chord — resolve and send.
                        let shift = event.modifierFlags.contains(.shift)
                        let ch = Self.chordCharacter(keys: self.pendingDirectionKeys, shift: shift)
                        self.pendingDirectionKeys.removeAll()
                        self.onKey?(ch)
                    }
                    self.pressedDirectionKeys.remove(keyCode)
                }
                return nil
            }
        }
    }

    deinit {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    /// Clears accumulated arrow-key state. Call at the start of each new blocking
    /// input request so stale state cannot corrupt the next chord.
    func resetDirectionState() {
        pressedDirectionKeys.removeAll()
        pendingDirectionKeys.removeAll()
    }

    // MARK: - Key translation

    /// Arrow key codes on macOS (left=123, right=124, down=125, up=126).
    private static let arrowKeyCodes: Set<Int> = [123, 124, 125, 126]

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
    /// The system-provided character already encodes modifiers (Ctrl+C → 3, etc.).
    /// When macOS intercepts a Ctrl combo before we see it, compute it directly.
    static func keyCode(from event: NSEvent) -> Int32 {
        let flags = event.modifierFlags
        if let scalar = event.characters?.unicodeScalars.first, scalar.value > 0, scalar.value < 128 {
            return Int32(scalar.value)
        }
        if flags.contains(.control),
           let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first,
           scalar.value >= 64, scalar.value < 128
        {
            return Int32(scalar.value) & 0x1F
        }
        return 0
    }
}
