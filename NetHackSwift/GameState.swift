import AppKit
import NetHackBridge
import Observation

@Observable
final class GameState {
    // Player identity
    var playerName: String = ""
    var role: String = ""
    var dlvl: String = ""

    // Hit points
    var hp: Int = 0
    var maxHp: Int = 1

    // Power / mana
    var pw: Int = 0
    var maxPw: Int = 1

    // Level & experience
    var level: Int = 0
    var xp: Int = 0

    // Armor class and gold
    var ac: Int = 0
    var gold: Int = 0

    // Attributes — str is a String to support values like "18/01"
    var str: String = ""
    var dex: Int = 0
    var con: Int = 0
    var int_: Int = 0
    var wis: Int = 0
    var cha: Int = 0
    var turn: Int = 0

    // Status line shown in red (e.g. "Confused, Stunned")
    var statusEffects: String = ""

    // Scrolling message log
    var messages: [String] = []

    // Equipped items keyed by slot; missing key means the slot is empty
    var equipment: [NHEquipSlot: NHEquipItem] = [:]

    // Map grid — ROWNO×COLNO, stored row-major; glyph.glyph == -1 means empty
    static let mapRows = 21
    static let mapCols = 80
    // Ignored so that individual printGlyph writes don't trigger per-cell re-renders.
    // MapView re-renders when mapVersion is incremented at displayWindow time.
    @ObservationIgnored var mapGlyphs: [nhswift_glyph] = {
        var empty = nhswift_glyph()
        empty.glyph = -1
        return Array(repeating: empty, count: 21 * 80)
    }()
    @ObservationIgnored var mapBkGlyphs: [nhswift_glyph] = {
        var empty = nhswift_glyph()
        empty.glyph = -1
        return Array(repeating: empty, count: 21 * 80)
    }()
    var mapCursor: (x: Int32, y: Int32) = (0, 0)
    // Incremented by displayWindow(.map) to trigger a single Canvas redraw per frame.
    var mapVersion: Int = 0
    // Written by clipAround() before bumping clipAroundVersion.
    // @ObservationIgnored so writes don't trigger a re-render on their own;
    // the version bump is what causes MapView to read the updated coordinates.
    @ObservationIgnored var clipAround: (x: Int32, y: Int32) = (0, 0)
    // Incremented by clipAround() to trigger a scroll to the clip-around position.
    var clipAroundVersion: Int = 0

    // When true, MapView draws ttychar text instead of tile images.
    var mapUsesTextDisplay: Bool = false

    var hpDisplay: String { "\(hp)(\(maxHp))" }
    var pwDisplay: String { "\(pw)(\(maxPw))" }
}


