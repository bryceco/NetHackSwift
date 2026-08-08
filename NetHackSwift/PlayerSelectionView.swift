import SwiftUI

// MARK: - Data Types

struct PlayerRaceOption: Identifiable {
    var id = UUID()
    var name: String
    var image: NSImage?
    var isAvailable: Bool = true
}

struct PlayerRoleOption: Identifiable {
    var id = UUID()
    var name: String
    var image: NSImage?
    var isAvailable: Bool = true
}

enum PlayerSex: String, CaseIterable, Hashable, Identifiable {
    case male = "Male"
    case female = "Female"
    var id: Self { self }
}

enum PlayerAlignment: String, CaseIterable, Hashable, Identifiable {
    case lawful = "Lawful"
    case neutral = "Neutral"
    case chaotic = "Chaotic"
    var id: Self { self }
}

struct PlayerSelection {
    var name: String
    var raceID: PlayerRaceOption.ID?
    var roleID: PlayerRoleOption.ID?
    var sex: PlayerSex
    var alignment: PlayerAlignment
}

// MARK: - PlayerSelectionView

struct PlayerSelectionView: View {
    let races: [PlayerRaceOption]
    let roles: [PlayerRoleOption]
    let availableSexes: Set<PlayerSex>
    let availableAlignments: Set<PlayerAlignment>
    var onPlay: (PlayerSelection) -> Void
    var onQuit: () -> Void

    @State private var playerName: String
    @State private var selectedRaceID: PlayerRaceOption.ID?
    @State private var selectedRoleID: PlayerRoleOption.ID?
    @State private var sex: PlayerSex
    @State private var alignment: PlayerAlignment

    init(initialName: String = "",
         races: [PlayerRaceOption],
         roles: [PlayerRoleOption],
         availableSexes: Set<PlayerSex> = Set(PlayerSex.allCases),
         availableAlignments: Set<PlayerAlignment> = Set(PlayerAlignment.allCases),
         onPlay: @escaping (PlayerSelection) -> Void,
         onQuit: @escaping () -> Void) {
        self.races = races
        self.roles = roles
        self.availableSexes = availableSexes
        self.availableAlignments = availableAlignments
        self.onPlay = onPlay
        self.onQuit = onQuit
        _playerName = State(initialValue: initialName)
        _selectedRaceID = State(initialValue: races.first(where: { $0.isAvailable })?.id)
        _selectedRoleID = State(initialValue: roles.first(where: { $0.isAvailable })?.id)
        _sex = State(initialValue: availableSexes.contains(.male) ? .male : .female)
        _alignment = State(initialValue: availableAlignments.contains(.neutral) ? .neutral :
                          availableAlignments.contains(.lawful) ? .lawful : .chaotic)
    }

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
            HStack(alignment: .top, spacing: 0) {
                // Left: Race list (shorter, top-aligned)
                VStack(spacing: 0) {
                    raceTable
                        .frame(height: 197)
                    Spacer(minLength: 0)
                }
                .frame(width: 134)
                .padding(.trailing, 9)

                // Middle: Role list (full height)
                roleTable
                    .frame(width: 158, height: 370)
                    .padding(.trailing, 13)

                // Right: Sex, Alignment, Play/Quit
                rightPanel
                    .frame(width: 108)
            }
            .padding(.horizontal, 17)
        }
        .frame(width: 456, height: 441)
    }

    // MARK: - Race Table

    private var raceTable: some View {
        Table(races, selection: $selectedRaceID) {
            TableColumn("Race") { race in
                HStack(spacing: 4) {
                    if let image = race.image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                    }
                    Text(race.name)
                }
                .opacity(race.isAvailable ? 1.0 : 0.4)
            }
        }
        .onChange(of: selectedRaceID) { _, newID in
            guard let newID,
                  let race = races.first(where: { $0.id == newID }),
                  !race.isAvailable else { return }
            selectedRaceID = nil
        }
    }

    // MARK: - Role Table

    private var roleTable: some View {
        Table(roles, selection: $selectedRoleID) {
            TableColumn("Role") { role in
                HStack(spacing: 4) {
                    if let image = role.image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                    }
                    Text(role.name)
                }
                .opacity(role.isAvailable ? 1.0 : 0.4)
            }
        }
        .onChange(of: selectedRoleID) { _, newID in
            guard let newID,
                  let role = roles.first(where: { $0.id == newID }),
                  !role.isAvailable else { return }
            selectedRoleID = nil
        }
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupBox("Sex") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(PlayerSex.allCases) { option in
                        RadioButton(
                            label: option.rawValue,
                            isSelected: sex == option,
                            isEnabled: availableSexes.contains(option),
                            action: { sex = option }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer().frame(height: 16)

            GroupBox("Alignment") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(PlayerAlignment.allCases) { option in
                        RadioButton(
                            label: option.rawValue,
                            isSelected: alignment == option,
                            isEnabled: availableAlignments.contains(option),
                            action: { alignment = option }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            VStack(spacing: 8) {
                Button("Play") {
                    onPlay(PlayerSelection(
                        name: playerName,
                        raceID: selectedRaceID,
                        roleID: selectedRoleID,
                        sex: sex,
                        alignment: alignment
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
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: { if isEnabled { action() } }) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                    .foregroundStyle(isSelected && isEnabled ? Color.accentColor : Color.secondary)
                Text(label)
                    .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("All Available") {
    PlayerSelectionView(
        initialName: "Bryce",
        races: [
            PlayerRaceOption(name: "human"),
            PlayerRaceOption(name: "elf"),
            PlayerRaceOption(name: "dwarf"),
            PlayerRaceOption(name: "gnome"),
            PlayerRaceOption(name: "orc"),
        ],
        roles: [
            PlayerRoleOption(name: "Archeologist"),
            PlayerRoleOption(name: "Barbarian", isAvailable: false),
            PlayerRoleOption(name: "Caveman"),
            PlayerRoleOption(name: "Healer"),
            PlayerRoleOption(name: "Knight", isAvailable: false),
            PlayerRoleOption(name: "Monk", isAvailable: false),
            PlayerRoleOption(name: "Priest", isAvailable: false),
            PlayerRoleOption(name: "Rogue", isAvailable: false),
            PlayerRoleOption(name: "Ranger"),
            PlayerRoleOption(name: "Samurai", isAvailable: false),
            PlayerRoleOption(name: "Tourist", isAvailable: false),
            PlayerRoleOption(name: "Valkyrie", isAvailable: false),
            PlayerRoleOption(name: "Wizard"),
        ],
        availableSexes: Set(PlayerSex.allCases),
        availableAlignments: [.neutral],
        onPlay: { _ in },
        onQuit: { }
    )
}
