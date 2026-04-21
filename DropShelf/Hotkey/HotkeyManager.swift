import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleShelf = Self(
        "toggleShelf",
        default: .init(.space, modifiers: [.command, .shift])
    )
}
