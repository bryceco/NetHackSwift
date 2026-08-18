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

/// Defines the game-specific menu bar items.
/// Game command items send key codes directly to NetHack via the controller; display-mode
/// items (ASCII / tile set) persist their state in UserDefaults via @AppStorage.
struct GameCommands: Commands {
    let controller: NetHackController?
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
                .keyboardShortcut("?", modifiers: [])
        }
    }

    // MARK: - Game

    private var gameMenu: some Commands {
        CommandMenu("Game") {
            Button("Version")          { send(Int32(UInt8(ascii: "v"))) }.keyboardShortcut("v", modifiers: [])
            Button("Extended Version") { sendOption(UInt8(ascii: "v")) }.keyboardShortcut("v", modifiers: .option)
            Button("History")          { send(Int32(UInt8(ascii: "V"))) }.keyboardShortcut("v", modifiers: .shift)
            Button("Explore Mode")     { send(Int32(UInt8(ascii: "X"))) }.keyboardShortcut("x", modifiers: .shift)

            Divider()

            Button("Options")             { send(Int32(UInt8(ascii: "O"))) }.keyboardShortcut("o", modifiers: .shift)
            Button("Toggle Auto Pickup")  { send(Int32(UInt8(ascii: "@"))) }.keyboardShortcut("@", modifiers: [])

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
            Button("North")      { send(Int32(UInt8(ascii: "k"))) }.keyboardShortcut("k", modifiers: [])
            Button("South")      { send(Int32(UInt8(ascii: "j"))) }.keyboardShortcut("j", modifiers: [])
            Button("East")       { send(Int32(UInt8(ascii: "l"))) }.keyboardShortcut("l", modifiers: [])
            Button("West")       { send(Int32(UInt8(ascii: "h"))) }.keyboardShortcut("h", modifiers: [])
            Button("North-East") { send(Int32(UInt8(ascii: "u"))) }.keyboardShortcut("u", modifiers: [])
            Button("North-West") { send(Int32(UInt8(ascii: "y"))) }.keyboardShortcut("y", modifiers: [])
            Button("South-East") { send(Int32(UInt8(ascii: "n"))) }.keyboardShortcut("n", modifiers: [])
            Button("South-West") { send(Int32(UInt8(ascii: "b"))) }.keyboardShortcut("b", modifiers: [])

            Divider()

            Button("Up")     { send(Int32(UInt8(ascii: "<"))) }.keyboardShortcut("<", modifiers: [])
            Button("Down")   { send(Int32(UInt8(ascii: ">"))) }.keyboardShortcut(">", modifiers: [])

            Divider()

            Button("Travel") { send(Int32(UInt8(ascii: "_"))) }.keyboardShortcut("_", modifiers: [])
        }
    }

    // MARK: - Gear

    private var gearMenu: some Commands {
        CommandMenu("Gear") {
            Button("Remove All Armor")  { send(Int32(UInt8(ascii: "A"))) }.keyboardShortcut("a", modifiers: .shift)

            Divider()

            Button("Wield Weapon")      { send(Int32(UInt8(ascii: "w"))) }.keyboardShortcut("w", modifiers: [])
            Button("Exchange Weapons")  { send(Int32(UInt8(ascii: "x"))) }.keyboardShortcut("x", modifiers: [])
            Button("Two Weapon Combat") { sendOption(UInt8(ascii: "2")) }.keyboardShortcut("2", modifiers: .option)
            Button("Load Quiver")       { send(Int32(UInt8(ascii: "Q"))) }.keyboardShortcut("q", modifiers: .shift)

            Divider()

            Button("Wear Armor")        { send(Int32(UInt8(ascii: "W"))) }.keyboardShortcut("w", modifiers: .shift)
            Button("Take Off Armor")    { send(Int32(UInt8(ascii: "T"))) }.keyboardShortcut("t", modifiers: .shift)

            Divider()

            Button("Put On Non-Armor")  { send(Int32(UInt8(ascii: "P"))) }.keyboardShortcut("p", modifiers: .shift)
            Button("Remove Non-Armor")  { send(Int32(UInt8(ascii: "R"))) }.keyboardShortcut("r", modifiers: .shift)
        }
    }

    // MARK: - Action

    private var actionMenu: some Commands {
        CommandMenu("Action") {
            Button("Apply")                { send(Int32(UInt8(ascii: "a"))) }.keyboardShortcut("a", modifiers: [])
            Button("Chat")                 { sendOption(UInt8(ascii: "c")) }.keyboardShortcut("c", modifiers: .option)
            Button("Close Door")           { send(Int32(UInt8(ascii: "c"))) }.keyboardShortcut("c", modifiers: [])
            Button("Dip")                  { sendOption(UInt8(ascii: "d")) }.keyboardShortcut("d", modifiers: .option)
            Button("Drop Many")            { send(Int32(UInt8(ascii: "D"))) }.keyboardShortcut("d", modifiers: .shift)
            Button("Drop")                 { send(Int32(UInt8(ascii: "d"))) }.keyboardShortcut("d", modifiers: [])
            Button("Eat")                  { send(Int32(UInt8(ascii: "e"))) }.keyboardShortcut("e", modifiers: [])
            Button("Engrave")              { send(Int32(UInt8(ascii: "E"))) }.keyboardShortcut("e", modifiers: .shift)
            Button("Enhance Weapon Skill") { sendOption(UInt8(ascii: "e")) }.keyboardShortcut("e", modifiers: .option)
            Button("Fight")                { send(Int32(UInt8(ascii: "F"))) }.keyboardShortcut("f", modifiers: .shift)
            Button("Fire From Quiver")     { send(Int32(UInt8(ascii: "f"))) }.keyboardShortcut("f", modifiers: [])
            Button("Force")                { sendOption(UInt8(ascii: "f")) }.keyboardShortcut("f", modifiers: .option)
            Button("Jump")                 { sendOption(UInt8(ascii: "j")) }.keyboardShortcut("j", modifiers: .option)
            Button("Kick")                 { sendCtrl(UInt8(ascii: "d")) }.keyboardShortcut("d", modifiers: .control)
            Button("Loot")                 { sendOption(UInt8(ascii: "l")) }.keyboardShortcut("l", modifiers: .option)
            Button("Open Door")            { send(Int32(UInt8(ascii: "o"))) }.keyboardShortcut("o", modifiers: [])
            Button("Pay")                  { send(Int32(UInt8(ascii: "p"))) }.keyboardShortcut("p", modifiers: [])
            Button("Pick Up")              { send(Int32(UInt8(ascii: ","))) }.keyboardShortcut(",", modifiers: [])
            Button("Rest")                 { send(Int32(UInt8(ascii: "."))) }.keyboardShortcut(".", modifiers: [])
            Button("#Ride")                { sendExtCmd("ride") }
            Button("Search")               { send(Int32(UInt8(ascii: "s"))) }.keyboardShortcut("s", modifiers: [])
            Button("Sit")                  { sendOption(UInt8(ascii: "s")) }.keyboardShortcut("s", modifiers: .option)
            Button("Throw")                { send(Int32(UInt8(ascii: "t"))) }.keyboardShortcut("t", modifiers: [])
            Button("Untrap")               { sendOption(UInt8(ascii: "u")) }.keyboardShortcut("u", modifiers: .option)
            Button("Wipe Face")            { sendOption(UInt8(ascii: "w")) }.keyboardShortcut("w", modifiers: .option)
        }
    }

    // MARK: - Magic

    private var magicMenu: some Commands {
        CommandMenu("Magic") {
            Button("Quaff Potion")      { send(Int32(UInt8(ascii: "q"))) }.keyboardShortcut("q", modifiers: [])
            Button("Read Scroll/Book")  { send(Int32(UInt8(ascii: "r"))) }.keyboardShortcut("r", modifiers: [])
            Button("Zap Wand")          { send(Int32(UInt8(ascii: "z"))) }.keyboardShortcut("z", modifiers: [])
            Button("Zap Spell")         { send(Int32(UInt8(ascii: "Z"))) }.keyboardShortcut("z", modifiers: .shift)
            Button("Dip")               { sendOption(UInt8(ascii: "d")) } // ⌥d: shortcut is on Action > Dip
            Button("Rub")               { sendOption(UInt8(ascii: "r")) }.keyboardShortcut("r", modifiers: .option)
            Button("Invoke")            { sendOption(UInt8(ascii: "i")) }.keyboardShortcut("i", modifiers: .option)

            Divider()

            Button("Offer Sacrifice")   { sendOption(UInt8(ascii: "o")) }.keyboardShortcut("o", modifiers: .option)
            Button("Pray")              { sendOption(UInt8(ascii: "p")) }.keyboardShortcut("p", modifiers: .option)

            Divider()

            Button("Teleport")          { sendCtrl(UInt8(ascii: "t")) }.keyboardShortcut("t", modifiers: .control)
            Button("Monster Action")    { sendOption(UInt8(ascii: "m")) }.keyboardShortcut("m", modifiers: .option)
            Button("Turn Undead")       { sendOption(UInt8(ascii: "t")) }.keyboardShortcut("t", modifiers: .option)
        }
    }

    // MARK: - Info

    private var infoMenu: some Commands {
        CommandMenu("Info") {
            Button("Inventory")            { send(Int32(UInt8(ascii: "i"))) }.keyboardShortcut("i", modifiers: [])
            Button("Inventory By Type")    { send(Int32(UInt8(ascii: "I"))) }.keyboardShortcut("i", modifiers: .shift)

            Divider()

            Button("Look Here")            { send(Int32(UInt8(ascii: ":"))) }.keyboardShortcut(":", modifiers: [])
            Button("What Is?")             { send(Int32(UInt8(ascii: "/"))) }.keyboardShortcut("/", modifiers: [])
            Button("Show")                 { send(Int32(UInt8(ascii: ";"))) }.keyboardShortcut(";", modifiers: [])
            Button("Type Of Trap")         { send(Int32(UInt8(ascii: "^"))) }.keyboardShortcut("^", modifiers: [])
            Button("What Does?")           { send(Int32(UInt8(ascii: "&"))) }.keyboardShortcut("&", modifiers: [])

            Divider()

            Button("Current Equipment")    { send(Int32(UInt8(ascii: "*"))) }.keyboardShortcut("*", modifiers: [])
            Button("Current Weapon")       { send(Int32(UInt8(ascii: ")"))) }.keyboardShortcut(")", modifiers: [])
            Button("Current Armor")        { send(Int32(UInt8(ascii: "["))) }.keyboardShortcut("[", modifiers: [])
            Button("Current Rings")        { send(Int32(UInt8(ascii: "="))) }.keyboardShortcut("=", modifiers: [])
            Button("Current Amulet")       { send(Int32(UInt8(ascii: "\""))) }.keyboardShortcut("\"", modifiers: [])
            Button("Current Tools")        { send(Int32(UInt8(ascii: "("))) }.keyboardShortcut("(", modifiers: [])
            Button("Count Gold")           { send(Int32(UInt8(ascii: "$"))) }.keyboardShortcut("$", modifiers: [])

            Divider()

            Button("Attributes")           { sendCtrl(UInt8(ascii: "x")) }.keyboardShortcut("x", modifiers: .control)
            Button("#Conduct")             { sendExtCmd("conduct") }
            Button("Discoveries")          { send(Int32(UInt8(ascii: "\\"))) }.keyboardShortcut("\\", modifiers: [])
            Button("List Known Spells")    { send(Int32(UInt8(ascii: "+"))) }.keyboardShortcut("+", modifiers: [])
            Button("Adjust Letters")       { sendOption(UInt8(ascii: "a")) }.keyboardShortcut("a", modifiers: .option)

            Divider()

            Button("Name Object")          { sendOption(UInt8(ascii: "n")) }.keyboardShortcut("n", modifiers: .option)
            Button("Call (name) Creature") { send(Int32(UInt8(ascii: "C"))) }.keyboardShortcut("c", modifiers: .shift)

            Divider()

            Button("Qualifications")       { sendOption(UInt8(ascii: "e")) } // ⌥e: shortcut is on Action > Enhance Weapon Skill
        }
    }

    // MARK: - Wizard Mode

    private var wizardMenu: some Commands {
        CommandMenu("Wizard Mode") {
            Button("Detect")         { sendCtrl(UInt8(ascii: "e")) }.keyboardShortcut("e", modifiers: .control)
            Button("Map")            { sendCtrl(UInt8(ascii: "f")) }.keyboardShortcut("f", modifiers: .control)
            Button("Genesis")        { sendCtrl(UInt8(ascii: "g")) }.keyboardShortcut("g", modifiers: .control)
            Button("Identify")       { sendCtrl(UInt8(ascii: "i")) }.keyboardShortcut("i", modifiers: .control)
            Button("Where")          { sendCtrl(UInt8(ascii: "o")) }.keyboardShortcut("o", modifiers: .control)
            Button("Level Teleport") { sendCtrl(UInt8(ascii: "v")) }.keyboardShortcut("v", modifiers: .control)
            Button("Wish")           { sendCtrl(UInt8(ascii: "w")) }.keyboardShortcut("w", modifiers: .control)
            Button("#ChangeLevel")   { sendExtCmd("changelevel") }
        }
    }

    // MARK: - Key sending

    private func send(_ key: Int32) {
        controller?.sendKey(key)
    }

    /// Sends an ESC prefix followed by `key`, the Unix convention for Meta/Option combos.
    private func sendOption(_ key: UInt8) {
        send(Int32(key | 0x80))
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
