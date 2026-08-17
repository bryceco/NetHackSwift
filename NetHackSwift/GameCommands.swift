import AppKit
import SwiftUI

/// Removes the default File, Edit, and View menus that SwiftUI creates automatically.
/// CommandsBuilder supports at most 10 items per body, so this lives in its own struct.
struct DefaultMenuRemovals: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .saveItem) {}
        CommandGroup(replacing: .printItem) {}
        CommandGroup(replacing: .undoRedo) {}
        CommandGroup(replacing: .pasteboard) {}
        CommandGroup(replacing: .textEditing) {}
        CommandGroup(replacing: .textFormatting) {}
        CommandGroup(replacing: .toolbar) {}
    }
}

/// Defines the game-specific menu bar items that mirror the XIB-based Cocoa app's menu.
/// Game command items send key codes directly to NetHack via the controller; display-mode
/// items (ASCII / tile set) persist their state in UserDefaults via @AppStorage.
struct GameCommands: Commands {
    @AppStorage("mapUsesAsciiDisplay") private var mapUsesAsciiDisplay = false
    @AppStorage("selectedTileSetIndex") private var selectedTileSetIndex = 0

    var body: some Commands {
        gameMenu
        moveMenu
        gearMenu
        actionMenu
        magicMenu
        infoMenu
        wizardMenu

        CommandGroup(after: .help) {
            Button("NetHack Help") { send(Int32(UInt8(ascii: "?"))) }
        }
    }

    // MARK: - Game

    private var gameMenu: some Commands {
        CommandMenu("Game") {
            Button("Version")          { send(Int32(UInt8(ascii: "v"))) }
            Button("Extended Version") { sendMeta(UInt8(ascii: "v")) }
            Button("History")          { send(Int32(UInt8(ascii: "V"))) }
            Button("Explore Mode")     { send(Int32(UInt8(ascii: "X"))) }

            Divider()

            Button("Options")             { send(Int32(UInt8(ascii: "O"))) }
            Button("Toggle Auto Pickup")  { send(Int32(UInt8(ascii: "@"))) }

            Divider()

            Toggle("Use ASCII Mode", isOn: Binding(
                get: { mapUsesAsciiDisplay },
                set: { setAsciiMode($0) }
            ))

            Menu("Tile Set") {
                ForEach(TileSetDescriptor.available.indices, id: \.self) { idx in
                    Toggle(TileSetDescriptor.available[idx].name,
                           isOn: Binding(
                               get: { !mapUsesAsciiDisplay && selectedTileSetIndex == idx },
                               set: { if $0 { selectTileSet(idx) } }
                           ))
                }
            }

            Divider()

            Button("Save & Quit") { NSApp.terminate(nil) }
        }
    }

    // MARK: - Move

    private var moveMenu: some Commands {
        CommandMenu("Move") {
            Button("North")      { send(Int32(UInt8(ascii: "k"))) }
            Button("South")      { send(Int32(UInt8(ascii: "j"))) }
            Button("East")       { send(Int32(UInt8(ascii: "l"))) }
            Button("West")       { send(Int32(UInt8(ascii: "h"))) }
            Button("North-East") { send(Int32(UInt8(ascii: "u"))) }
            Button("North-West") { send(Int32(UInt8(ascii: "y"))) }
            Button("South-East") { send(Int32(UInt8(ascii: "n"))) }
            Button("South-West") { send(Int32(UInt8(ascii: "b"))) }

            Divider()

            Button("Up")     { send(Int32(UInt8(ascii: "<"))) }
            Button("Down")   { send(Int32(UInt8(ascii: ">"))) }

            Divider()

            Button("Travel") { send(Int32(UInt8(ascii: "_"))) }
        }
    }

    // MARK: - Gear

    private var gearMenu: some Commands {
        CommandMenu("Gear") {
            Button("Remove All Armor")  { send(Int32(UInt8(ascii: "A"))) }

            Divider()

            Button("Wield Weapon")      { send(Int32(UInt8(ascii: "w"))) }
            Button("Exchange Weapons")  { send(Int32(UInt8(ascii: "x"))) }
            Button("Two Weapon Combat") { sendMeta(UInt8(ascii: "2")) }
            Button("Load Quiver")       { send(Int32(UInt8(ascii: "Q"))) }

            Divider()

            Button("Wear Armor")        { send(Int32(UInt8(ascii: "W"))) }
            Button("Take Off Armor")    { send(Int32(UInt8(ascii: "T"))) }

            Divider()

            Button("Put On Non-Armor")  { send(Int32(UInt8(ascii: "P"))) }
            Button("Remove Non-Armor")  { send(Int32(UInt8(ascii: "R"))) }
        }
    }

    // MARK: - Action

    private var actionMenu: some Commands {
        CommandMenu("Action") {
            Button("Apply")                { send(Int32(UInt8(ascii: "a"))) }
            Button("Chat")                 { sendMeta(UInt8(ascii: "c")) }
            Button("Close Door")           { send(Int32(UInt8(ascii: "c"))) }
            Button("Dip")                  { sendMeta(UInt8(ascii: "d")) }
            Button("Drop Many")            { send(Int32(UInt8(ascii: "D"))) }
            Button("Drop")                 { send(Int32(UInt8(ascii: "d"))) }
            Button("Eat")                  { send(Int32(UInt8(ascii: "e"))) }
            Button("Engrave")              { send(Int32(UInt8(ascii: "E"))) }
            Button("Enhance Weapon Skill") { sendMeta(UInt8(ascii: "e")) }
            Button("Fight")                { send(Int32(UInt8(ascii: "F"))) }
            Button("Fire From Quiver")     { send(Int32(UInt8(ascii: "f"))) }
            Button("Force")                { sendMeta(UInt8(ascii: "f")) }
            Button("Jump")                 { sendMeta(UInt8(ascii: "j")) }
            Button("Kick")                 { sendCtrl(UInt8(ascii: "d")) }
            Button("Loot")                 { sendMeta(UInt8(ascii: "l")) }
            Button("Open Door")            { send(Int32(UInt8(ascii: "o"))) }
            Button("Pay")                  { send(Int32(UInt8(ascii: "p"))) }
            Button("Pick Up")              { send(Int32(UInt8(ascii: ","))) }
            Button("Rest")                 { send(Int32(UInt8(ascii: "."))) }
            Button("#Ride")                { sendExtCmd("ride") }
            Button("Search")               { send(Int32(UInt8(ascii: "s"))) }
            Button("Sit")                  { sendMeta(UInt8(ascii: "s")) }
            Button("Throw")                { send(Int32(UInt8(ascii: "t"))) }
            Button("Untrap")               { sendMeta(UInt8(ascii: "u")) }
            Button("Wipe Face")            { sendMeta(UInt8(ascii: "w")) }
        }
    }

    // MARK: - Magic

    private var magicMenu: some Commands {
        CommandMenu("Magic") {
            Button("Quaff Potion")      { send(Int32(UInt8(ascii: "q"))) }
            Button("Read Scroll/Book")  { send(Int32(UInt8(ascii: "r"))) }
            Button("Zap Wand")          { send(Int32(UInt8(ascii: "z"))) }
            Button("Zap Spell")         { send(Int32(UInt8(ascii: "Z"))) }
            Button("Dip")               { sendMeta(UInt8(ascii: "d")) }
            Button("Rub")               { sendMeta(UInt8(ascii: "r")) }
            Button("Invoke")            { sendMeta(UInt8(ascii: "i")) }

            Divider()

            Button("Offer Sacrifice")   { sendMeta(UInt8(ascii: "o")) }
            Button("Pray")              { sendMeta(UInt8(ascii: "p")) }

            Divider()

            Button("Teleport")          { sendCtrl(UInt8(ascii: "t")) }
            Button("Monster Action")    { sendMeta(UInt8(ascii: "m")) }
            Button("Turn Undead")       { sendMeta(UInt8(ascii: "t")) }
        }
    }

    // MARK: - Info

    private var infoMenu: some Commands {
        CommandMenu("Info") {
            Button("Inventory")            { send(Int32(UInt8(ascii: "i"))) }
            Button("Inventory By Type")    { send(Int32(UInt8(ascii: "I"))) }

            Divider()

            Button("Look Here")            { send(Int32(UInt8(ascii: ":"))) }
            Button("What Is?")             { send(Int32(UInt8(ascii: "/"))) }
            Button("Show")                 { send(Int32(UInt8(ascii: ";"))) }
            Button("Type Of Trap")         { send(Int32(UInt8(ascii: "^"))) }
            Button("What Does?")           { send(Int32(UInt8(ascii: "&"))) }

            Divider()

            Button("Current Equipment")    { send(Int32(UInt8(ascii: "*"))) }
            Button("Current Weapon")       { send(Int32(UInt8(ascii: ")"))) }
            Button("Current Armor")        { send(Int32(UInt8(ascii: "["))) }
            Button("Current Rings")        { send(Int32(UInt8(ascii: "="))) }
            Button("Current Amulet")       { send(Int32(UInt8(ascii: "\""))) }
            Button("Current Tools")        { send(Int32(UInt8(ascii: "("))) }
            Button("Count Gold")           { send(Int32(UInt8(ascii: "$"))) }

            Divider()

            Button("Attributes")           { sendCtrl(UInt8(ascii: "x")) }
            Button("#Conduct")             { sendExtCmd("conduct") }
            Button("Discoveries")          { send(Int32(UInt8(ascii: "\\"))) }
            Button("List Known Spells")    { send(Int32(UInt8(ascii: "+"))) }
            Button("Adjust Letters")       { sendMeta(UInt8(ascii: "a")) }

            Divider()

            Button("Name Object")          { sendMeta(UInt8(ascii: "n")) }
            Button("Call (name) Creature") { send(Int32(UInt8(ascii: "C"))) }

            Divider()

            Button("Qualifications")       { sendMeta(UInt8(ascii: "e")) }
        }
    }

    // MARK: - Wizard Mode

    private var wizardMenu: some Commands {
        CommandMenu("Wizard Mode") {
            Button("Detect")         { sendCtrl(UInt8(ascii: "e")) }
            Button("Map")            { sendCtrl(UInt8(ascii: "f")) }
            Button("Genesis")        { sendCtrl(UInt8(ascii: "g")) }
            Button("Identify")       { sendCtrl(UInt8(ascii: "i")) }
            Button("Where")          { sendCtrl(UInt8(ascii: "o")) }
            Button("Level Teleport") { sendCtrl(UInt8(ascii: "v")) }
            Button("Wish")           { sendCtrl(UInt8(ascii: "w")) }
            Button("#ChangeLevel")   { sendExtCmd("changelevel") }
        }
    }

    // MARK: - Key sending

    private func send(_ key: Int32) {
        (NSApp.delegate as? AppDelegate)?.controller?.sendKey(key)
    }

    /// Sends an ESC prefix followed by `key`, the Unix convention for Meta/Option combos.
    private func sendMeta(_ key: UInt8) {
        send(27)
        send(Int32(key))
    }

    /// Sends the control-character equivalent of the given ASCII letter (A–Z).
    private func sendCtrl(_ key: UInt8) {
        send(Int32(key) & 0x1F)
    }

    /// Sends the `#<name>\r` key sequence to trigger a NetHack extended command.
    private func sendExtCmd(_ name: String) {
        send(Int32(UInt8(ascii: "#")))
        for ch in name.utf8 {
            send(Int32(ch))
        }
        send(13) // Return / Enter
    }

    // MARK: - Display mode

    private func setAsciiMode(_ enabled: Bool) {
        mapUsesAsciiDisplay = enabled
        (NSApp.delegate as? AppDelegate)?.controller?.gameState?.mapUsesAsciiDisplay = enabled
    }

    private func selectTileSet(_ index: Int) {
        mapUsesAsciiDisplay = false
        selectedTileSetIndex = index
        let desc = TileSetDescriptor.available[index]
        TileSet.shared = desc.load()
        (NSApp.delegate as? AppDelegate)?.controller?.gameState?.mapVersion += 1
    }
}
