import AppKit
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

    // Equipment images keyed by slot; nil means the slot is empty
    var equipment: [EquipmentSlot: NSImage] = [:]

    var hpDisplay: String { "\(hp)(\(maxHp))" }
    var pwDisplay: String { "\(pw)(\(maxPw))" }
}

enum EquipmentSlot: CaseIterable, Hashable {
    case amulet, helmet, blindfold
    case weaponHand, armor, alternateHand
    case gloves, shirt, cloak
    case ringLeft, boots, ringRight
}
