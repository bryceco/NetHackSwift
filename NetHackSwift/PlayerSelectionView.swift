import SwiftUI
import NetHackBridge

// MARK: - Data Types

struct PlayerOption: Identifiable {
    var id = UUID()
    var name: String
    var image: NSImage?
}

struct PlayerSelection {
    var name: String
    var raceID: PlayerOption.ID?
    var roleID: PlayerOption.ID?
    var genderID: PlayerOption.ID?
    var alignID: PlayerOption.ID?
}

// MARK: - PlayerSelectionView

struct PlayerSelectionView: View {
    let races: [PlayerOption]
    let roles: [PlayerOption]
    let genders: [PlayerOption]
    let aligns: [PlayerOption]
    var onPlay: (PlayerSelection) -> Void
    var onQuit: () -> Void

    @State private var playerName: String
    @State private var selectedRoleIndex: Int
    @State private var selectedRaceIndex: Int
    @State private var selectedGenderIndex: Int
    @State private var selectedAlignIndex: Int

    init(initialName: String = "",
         races: [PlayerOption],
         roles: [PlayerOption],
         genders: [PlayerOption],
         aligns: [PlayerOption],
         onPlay: @escaping (PlayerSelection) -> Void,
         onQuit: @escaping () -> Void) {
        self.races = races
        self.roles = roles
        self.genders = genders
        self.aligns = aligns
        self.onPlay = onPlay
        self.onQuit = onQuit
        _playerName = State(initialValue: initialName)

        // Find an initial valid role/race/gender/align combination.
        var ro = 0
        while ro < roles.count && !NetHackBridge.isValid(role: ro) { ro += 1 }
        var ra = 0
        while ra < races.count && !NetHackBridge.isValid(race: ra, forRole: ro) { ra += 1 }
        let g = genders.indices.first { NetHackBridge.isValid(gender: $0, forRole: ro, race: ra) } ?? 0
        let a = aligns.indices.first  { NetHackBridge.isValid(align:  $0, forRole: ro, race: ra) } ?? 0

        _selectedRoleIndex   = State(initialValue: ro < roles.count   ? ro : 0)
        _selectedRaceIndex   = State(initialValue: ra < races.count   ? ra : 0)
        _selectedGenderIndex = State(initialValue: g)
        _selectedAlignIndex  = State(initialValue: a)
    }

    // MARK: - Selection helpers

    /// Called when the user picks a role.  Snaps race to the first valid choice
    /// if it's no longer compatible, then snaps gender and alignment.
    private func selectRole(_ ro: Int) {
        selectedRoleIndex = ro
        if !NetHackBridge.isValid(race: selectedRaceIndex, forRole: ro) {
            selectedRaceIndex = races.indices.first {
                NetHackBridge.isValid(race: $0, forRole: ro)
            } ?? 0
        }
        snapGenderAndAlign()
    }

    /// Called when the user picks a race.  Snaps role to the first valid choice
    /// if it's no longer compatible, then snaps gender and alignment.
    private func selectRace(_ rc: Int) {
        selectedRaceIndex = rc
        if !NetHackBridge.isValid(race: rc, forRole: selectedRoleIndex) {
            selectedRoleIndex = roles.indices.first {
                NetHackBridge.isValid(race: rc, forRole: $0)
            } ?? 0
        }
        snapGenderAndAlign()
    }

    /// After a role or race change, ensures gender and alignment are still valid
    /// for the new combination, snapping to the first valid choice if not.
    private func snapGenderAndAlign() {
        let ro = selectedRoleIndex
        let rc = selectedRaceIndex
        if !NetHackBridge.isValid(gender: selectedGenderIndex, forRole: ro, race: rc) {
            selectedGenderIndex = genders.indices.first {
                NetHackBridge.isValid(gender: $0, forRole: ro, race: rc)
            } ?? 0
        }
        if !NetHackBridge.isValid(align: selectedAlignIndex, forRole: ro, race: rc) {
            selectedAlignIndex = aligns.indices.first {
                NetHackBridge.isValid(align: $0, forRole: ro, race: rc)
            } ?? 0
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Name field row
            HStack(spacing: 4) {
                Text("Name:")
                TextField("name", text: $playerName)
                    .frame(minWidth: 150)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 17)
            .padding(.top, 17)
            .padding(.bottom, 12)

            // Three-column layout
            HStack(alignment: .top, spacing: 12) {
                racePanel
                    .fixedSize(horizontal: true, vertical: false)
                rolePanel
                    .frame(maxWidth: .infinity)
                rightPanel
                    .frame(width: 108)
            }
            .padding(.horizontal, 17)
            .padding(.bottom, 17)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(width: 456)
    }

    // MARK: - Race Panel

    private var racePanel: some View {
        GroupBox("Race") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(races.indices, id: \.self) { i in
                    RadioButton(
                        label: races[i].name.capitalized,
                        image: races[i].image,
                        isSelected: selectedRaceIndex == i,
                        isEnabled: NetHackBridge.isValid(race: i, forRole: selectedRoleIndex),
                        action: { selectRace(i) }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Role Panel

    private var rolePanel: some View {
        GroupBox("Role") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(roles.indices, id: \.self) { i in
                    RadioButton(
                        label: roles[i].name,
                        image: roles[i].image,
                        isSelected: selectedRoleIndex == i,
                        isEnabled: NetHackBridge.isValid(race: selectedRaceIndex, forRole: i),
                        action: { selectRole(i) }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupBox("Gender") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(genders.indices, id: \.self) { i in
                        RadioButton(
                            label: genders[i].name.capitalized,
                            isSelected: selectedGenderIndex == i,
                            isEnabled: NetHackBridge.isValid(gender: i, forRole: selectedRoleIndex, race: selectedRaceIndex),
                            action: { selectedGenderIndex = i }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer().frame(height: 16)

            GroupBox("Alignment") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(aligns.indices, id: \.self) { i in
                        RadioButton(
                            label: aligns[i].name.capitalized,
                            isSelected: selectedAlignIndex == i,
                            isEnabled: NetHackBridge.isValid(align: i, forRole: selectedRoleIndex, race: selectedRaceIndex),
                            action: { selectedAlignIndex = i }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer().frame(height: 16)

            VStack(spacing: 8) {
                Button("Play") {
                    onPlay(PlayerSelection(
                        name: playerName,
                        raceID:   races.indices.contains(selectedRaceIndex)   ? races[selectedRaceIndex].id     : nil,
                        roleID:   roles.indices.contains(selectedRoleIndex)   ? roles[selectedRoleIndex].id     : nil,
                        genderID: genders.indices.contains(selectedGenderIndex) ? genders[selectedGenderIndex].id : nil,
                        alignID:  aligns.indices.contains(selectedAlignIndex)  ? aligns[selectedAlignIndex].id   : nil
                    ))
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

                Button("Quit", action: onQuit)
                    .keyboardShortcut(.escape, modifiers: [])
                    .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 20)
        }
    }
}

// MARK: - RadioButton

private struct RadioButton: View {
    let label: String
    var image: NSImage? = nil
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: { if isEnabled { action() } }) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                if let image {
                    Image(nsImage: image)
                        .interpolation(.none)
                }
                Text(label)
            }
            .opacity(isEnabled ? 1.0 : 0.35)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Player Selection") {
    PlayerSelectionView(
        initialName: "Bryce",
        races: [
            PlayerOption(name: "human"),
            PlayerOption(name: "elf"),
            PlayerOption(name: "dwarf"),
            PlayerOption(name: "gnome"),
            PlayerOption(name: "orc"),
        ],
        roles: [
            PlayerOption(name: "Archeologist"),
            PlayerOption(name: "Barbarian"),
            PlayerOption(name: "Caveman"),
            PlayerOption(name: "Healer"),
            PlayerOption(name: "Knight"),
            PlayerOption(name: "Monk"),
            PlayerOption(name: "Priest"),
            PlayerOption(name: "Rogue"),
            PlayerOption(name: "Ranger"),
            PlayerOption(name: "Samurai"),
            PlayerOption(name: "Tourist"),
            PlayerOption(name: "Valkyrie"),
            PlayerOption(name: "Wizard"),
        ],
        genders: [
            PlayerOption(name: "male"),
            PlayerOption(name: "female"),
        ],
        aligns: [
            PlayerOption(name: "lawful"),
            PlayerOption(name: "neutral"),
            PlayerOption(name: "chaotic"),
        ],
        onPlay: { _ in },
        onQuit: { }
    )
}
