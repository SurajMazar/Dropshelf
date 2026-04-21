import AppKit
import UniformTypeIdentifiers

enum FileTypeFilter: String, CaseIterable {
    case all = "All"
    case pdf = "PDF"
    case image = "Image"
    case document = "Document"
    case media = "Media"
    case other = "Other"
}

extension URL {
    var fileTypeFilter: FileTypeFilter {
        guard let type = try? resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return .other
        }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .audiovisualContent) { return .media }
        if type.conforms(to: .text) || type.conforms(to: .rtf) || type.conforms(to: .html) {
            return .document
        }
        let id = type.identifier.lowercased()
        if id.contains("officedocument") || id.contains("ms-word") ||
           id.contains("ms-excel") || id.contains("ms-powerpoint") ||
           id.contains("opendocument") {
            return .document
        }
        return .other
    }
}

struct ShelfItem: Identifiable, Hashable {
    let id: UUID
    let url: URL

    init(url: URL) {
        self.id = UUID()
        self.url = url
    }

    var displayName: String {
        url.lastPathComponent
    }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    var typeFilter: FileTypeFilter {
        url.fileTypeFilter
    }
}
