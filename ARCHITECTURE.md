# Architecture

DropShelf is a native macOS AppKit app. No SwiftUI — the cross-app drag APIs we rely on (`NSDraggingSource`, `NSDraggingDestination`, `NSCollectionView` drag delegate hooks) are lower-level than SwiftUI exposes.

## High-level shape

```
main.swift
  └── AppDelegate
        ├── ShelfStore                   (model, single instance)
        ├── ShelfWindowController        (owns the NSPanel + window lifecycle)
        │     └── ShelfPanel             (NSPanel subclass: floating, HUD, all Spaces)
        │           └── ShelfViewController
        │                 ├── ShelfDropView            (root container, accepts drops, key events)
        │                 ├── NSVisualEffectView       (HUD background)
        │                 ├── DraggableHeaderView      (count label + action buttons)
        │                 ├── search bar               (NSSearchField + NSPopUpButton)
        │                 ├── NSCollectionView         (items; ShelfItemCell per item)
        │                 └── DockedTabView            (collapsed tray icon + badge)
        ├── HotkeyManager                (KeyboardShortcuts.Name.toggleShelf)
        ├── ShakeDetector                (NSEvent global + local mouse monitors)
        └── NSStatusItem                 (menu bar icon + menu)
```

## Modules

### `Model/`

| File | Purpose |
| --- | --- |
| [ShelfItem.swift](DropShelf/Model/ShelfItem.swift) | `struct ShelfItem` (id + URL). Also declares `FileTypeFilter` enum and `URL.fileTypeFilter` UTType-based classifier (PDF / Image / Document / Media / Other) |
| [ShelfStore.swift](DropShelf/Model/ShelfStore.swift) | Source of truth for items. Exposes `items`, `filteredItems`, `typeCounts`, mutation methods, plus `searchQuery` / `typeFilter` that trigger `onChange` when they change |

`ShelfStore` uses a single `onChange: (() -> Void)?` rather than a publisher/notification stack — the only observer is `ShelfViewController`, so a closure is enough.

### `Shelf/`

| File | Purpose |
| --- | --- |
| [ShelfPanel.swift](DropShelf/Shelf/ShelfPanel.swift) | `NSPanel` subclass. `level = .floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`, transparent titlebar, movable-by-background, `canBecomeKey = true` |
| [ShelfWindowController.swift](DropShelf/Shelf/ShelfWindowController.swift) | Owns the panel. Drives dock / undock / show / hide / summon-near-cursor. Animation + state guards (`isDocked`, `isAnimating`, `preDockFrame`). Observes `NSWindow.didMoveNotification` for drag-to-edge auto-dock |
| [ShelfViewController.swift](DropShelf/Shelf/ShelfViewController.swift) | Builds and wires the entire panel UI. Owns `ShelfDropView`, `DockedTabView`, `DraggableHeaderView`, `PassThroughTextField`. Implements `NSCollectionViewDataSource`, `NSCollectionViewDelegate`, `QLPreviewPanelDataSource`, `NSSearchFieldDelegate`, `ShelfItemCellDelegate` |
| [ShelfItemCell.swift](DropShelf/Shelf/ShelfItemCell.swift) | `NSCollectionViewItem` per file: icon, filename, hover-revealed remove button, right-click context menu (Quick Look / Reveal / Copy Path / Remove) |

### `Hotkey/`, `Shake/`, `QuickLook/`

| File | Purpose |
| --- | --- |
| [HotkeyManager.swift](DropShelf/Hotkey/HotkeyManager.swift) | `KeyboardShortcuts.Name.toggleShelf` with default `⌘⇧Space` |
| [ShakeDetector.swift](DropShelf/Shake/ShakeDetector.swift) | Global + local `NSEvent` monitors for `.mouseMoved` and `.leftMouseDragged`. Ring buffer of the last ~350 ms; counts direction reversals and average speed. Fires `onShake` with a 0.8s debounce. Requires Accessibility (`AXIsProcessTrustedWithOptions`) |
| [QuickLook/QuickLookController.swift](DropShelf/QuickLook/QuickLookController.swift) | Placeholder — actual `QLPreviewPanelDataSource` conformance lives on `ShelfViewController` to coordinate with collection-view selection |

## State machine

The panel has four user-visible states:

```
     hidden ◄──── Esc / ⌘⇧Space (visible)
       │
       │ ⌘⇧Space / shake / status-menu show
       ▼
   floating ◄──── click tab / hover tab
       │                     ▲
       │ dock button         │ undock (animated)
       │ OR drag to edge     │
       ▼                     │
    docked ──────────────────┘
    (+ optional) search      
    overlay visible inside floating state
```

**Transition rules (enforced in `ShelfWindowController`):**

- `isDocked` + `isAnimating` are synchronized so dock / undock / auto-dock never overlap
- `setDocked(true)` is applied *before* the shrink animation — docked UI appears promptly
- `setDocked(false)` is applied *after* the expand animation — the full floating UI never shows inside a still-shrunken window
- `summonNearCursor()` (shake / hotkey) always undocks and animates the window to the cursor position; the floating UI reveals at the end
- `windowDidMove` for auto-dock is **debounced 120 ms** and re-checked against the frame snapshot — it only fires once the user's drag has actually settled and the mouse is released

## Drag flow

### In

`ShelfDropView` (root NSView) and `NSCollectionView` both register `NSPasteboard.PasteboardType.fileURL`. Root view handles the empty-state case (drop onto an empty shelf); collection view handles drops once items exist.

```swift
container.registerForDraggedTypes([.fileURL])
collectionView.registerForDraggedTypes([.fileURL])

// Root view:
override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
    onDrop?(urls ?? []); return true
}

// Collection view delegate:
func collectionView(_:acceptDrop:indexPath:dropOperation:) -> Bool {
    let urls = draggingInfo.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
    store.addAll(urls: urls ?? []); return true
}
```

### Out

`NSCollectionViewDelegate.collectionView(_:pasteboardWriterForItemAt:)` returns the item's `URL as NSURL` — macOS's pasteboard handles the rest. The mask is set for non-local copy so Finder, browsers, Mail, Slack etc. treat the drop as a file copy:

```swift
collectionView.setDraggingSourceOperationMask(.copy, forLocal: false)
```

## Window states and geometry

- **Floating**: 360 × 180 at cursor or center. `preDockFrame` saved on dock, clamped to `screen.visibleFrame` on undock so the window is never partially off-screen.
- **Docked**: 48 × 180 flush with the right edge of `screen.visibleFrame`, vertically centered.
- **Search overlay**: reduces scrollview height by `searchBarHeight` (32pt), animated; `emptyLabel` re-centers via its frame.

## App icon

[Assets.xcassets/AppIcon.appiconset](DropShelf/Assets.xcassets/AppIcon.appiconset) — generated by the Swift script at [scripts/make_icon.swift](scripts/make_icon.swift). Purple-to-indigo gradient squircle (Apple corner ratio 22.37%), white pill "shelf", three colored item rectangles. Rerun the script if you tweak the design.

## Packaging

No signing identity, ad-hoc codesigned (`CODE_SIGN_IDENTITY: "-"`). For a real distribution you'd:
1. Set `CODE_SIGN_STYLE = Automatic` with a Developer ID in `project.yml`
2. Rebuild, re-sign, and notarize (`xcrun notarytool submit`)
3. Staple the ticket onto the DMG (`xcrun stapler staple`)

Current DMG is built with a simple `hdiutil create -format UDZO` from a staging folder containing the app + a symlink to `/Applications`.

## Dependencies

- **[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)** (SwiftPM, 2.0+) — global hotkey registration and the optional `Recorder` UI. Single third-party dependency.
- Everything else is AppKit / UniformTypeIdentifiers / Quartz (Quick Look).
