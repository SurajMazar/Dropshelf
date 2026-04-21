import Foundation

final class ShelfStore {
    private(set) var items: [ShelfItem] = []
    var searchQuery: String = "" {
        didSet { if oldValue != searchQuery { onChange?() } }
    }
    var typeFilter: FileTypeFilter = .all {
        didSet { if oldValue != typeFilter { onChange?() } }
    }
    var onChange: (() -> Void)?

    var filteredItems: [ShelfItem] {
        items.filter { item in
            if typeFilter != .all && item.typeFilter != typeFilter { return false }
            if !searchQuery.isEmpty,
               !item.displayName.localizedCaseInsensitiveContains(searchQuery) {
                return false
            }
            return true
        }
    }

    var typeCounts: [FileTypeFilter: Int] {
        var counts: [FileTypeFilter: Int] = [:]
        for item in items {
            counts[item.typeFilter, default: 0] += 1
        }
        counts[.all] = items.count
        return counts
    }

    func add(url: URL) {
        guard !items.contains(where: { $0.url == url }) else { return }
        items.append(ShelfItem(url: url))
        onChange?()
    }

    func addAll(urls: [URL]) {
        var changed = false
        for url in urls where !items.contains(where: { $0.url == url }) {
            items.append(ShelfItem(url: url))
            changed = true
        }
        if changed { onChange?() }
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        onChange?()
    }

    func clear() {
        guard !items.isEmpty else { return }
        items.removeAll()
        onChange?()
    }
}
