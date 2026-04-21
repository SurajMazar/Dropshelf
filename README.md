# DropShelf

A floating file shelf for macOS — drop files in, carry them across apps, drop them out.

Think [Dropover](https://dropoverapp.com/), but native, minimal, and free.

Summon the shelf with **⌘⇧Space** or a mouse shake, pile up files from Finder or any app, then drag them into the next app you need. Park it on the right edge when you're not using it; hover to pop it back out.

---

## Features

- **Floating shelf** — stays on top across Spaces and full-screen apps
- **Drag in** from Finder, Mail, browsers, anywhere files come from
- **Drag out** to Finder, upload fields, chat apps — via the native macOS pasteboard
- **Global hotkey** (⌘⇧Space by default, rebindable)
- **Shake-to-summon** — shake your cursor near a file to pop the shelf open
- **Dock to edge** — the shelf collapses into a thin tab on the right side of your screen; hover or click to expand
- **Drag-to-edge auto-dock** — drag the shelf near the right edge and it snaps into docked state
- **Search + filter** (⌘F) — search by filename, filter by type (PDF, Image, Document, Media, Other)
- **Quick Look** — select an item and press Space
- **Keyboard** — ⌫ removes selected, Esc hides the shelf, ⌘F toggles search
- **Per-item actions** — right-click for Reveal in Finder, Copy Path, Quick Look, Remove
- **Menu bar only** — no Dock icon, uses `LSUIElement`

---

## Install

### DMG (recommended)

Download `DropShelf-0.1.dmg`, open it, and drag **DropShelf** to the Applications folder.

First launch: macOS may warn about an unidentified developer. Right-click **DropShelf.app** → **Open** → confirm. After that it launches normally.

Grant **Accessibility** permission when prompted (required for the shake gesture — the hotkey works without it).

### Build from source

Requirements: macOS 13+, Xcode 15+ (tested on Xcode 26), Homebrew.

```bash
brew install xcodegen
git clone git@github.com:SurajMazar/Dropshelf.git
cd Dropshelf
xcodegen generate
xcodebuild -project DropShelf.xcodeproj -scheme DropShelf -configuration Release \
    CONFIGURATION_BUILD_DIR="$PWD/build/Release" build
cp -R build/Release/DropShelf.app /Applications/
open /Applications/DropShelf.app
```

---

## Usage

| Action                                    | Shortcut / gesture                            |
| ----------------------------------------- | --------------------------------------------- |
| Show/hide shelf                           | ⌘⇧Space (rebindable)                          |
| Summon near cursor                        | Shake mouse                                   |
| Search                                    | ⌘F                                            |
| Hide shelf                                | Esc                                           |
| Quick Look selected item                  | Space                                         |
| Remove selected item                      | ⌫ / Delete                                    |
| Dock to right edge                        | Click the purple sidebar icon; or drag to edge|
| Expand from docked                        | Hover or click the docked tab                 |
| Reveal in Finder                          | Right-click → Reveal in Finder                |

---

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for module breakdown, state flow, and the AppKit APIs the app leans on.

## Contributing / agents

See [AGENTS.md](AGENTS.md) for instructions aimed at AI coding agents (and humans). Covers build commands, project conventions, and known gotchas.

---

## License

MIT
