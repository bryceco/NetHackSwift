import AppKit

/// Owns the global key-down/key-up event monitor and translates NSEvents into
/// NetHack character codes, including diagonal arrow-key chord detection.
///
/// Wire up the three callbacks and call `resetDirectionState()` at the start
/// of each blocking input request; the handler does the rest.
final class KeyboardHandler {
    /// Called when a key should be forwarded to NetHack.
    var onKey: ((Int32) -> Void)?
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
                // Let Command-key shortcuts (Cmd-Q, Cmd-H, Cmd-W, …) reach the app menu.
                if event.modifierFlags.contains(.command) { return event }

                if let mapping = Self.numpadKeyMap[keyCode] {
                    // Numpad keys encode a single direction each — fire immediately.
                    let shift = event.modifierFlags.contains(.shift)
                    self.onKey?(Int32(shift ? mapping.shifted : mapping.plain))
                } else if isArrow {
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
    func resetChordState() {
        pressedDirectionKeys.removeAll()
        pendingDirectionKeys.removeAll()
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
