import Foundation
import SwiftUI

// MARK: - Categorías de Tipo de Archivo
enum FileCategory: String, CaseIterable, Identifiable, Sendable {
    case video = "Videos"
    case image = "Imágenes y Diseño"
    case audio = "Audio y Música"
    case archive = "Comprimidos e Imágenes (DMG/ZIP)"
    case document = "Documentos y Ofimática"
    case code = "Código y Datos"
    case app = "Aplicaciones y Binarios"
    case other = "Otros y Sistema"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .video: return "film.fill"
        case .image: return "photo.fill"
        case .audio: return "waveform.circle.fill"
        case .archive: return "archivebox.fill"
        case .document: return "doc.richtext.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .app: return "app.badge.fill"
        case .other: return "doc.fill"
        }
    }

    var color: Color {
        switch self {
        case .video: return Color(red: 0.95, green: 0.35, blue: 0.40)
        case .image: return Color(red: 0.98, green: 0.62, blue: 0.20)
        case .audio: return Color(red: 0.65, green: 0.38, blue: 0.95)
        case .archive: return Color(red: 0.25, green: 0.72, blue: 0.88)
        case .document: return Color(red: 0.22, green: 0.55, blue: 0.96)
        case .code: return Color(red: 0.20, green: 0.78, blue: 0.50)
        case .app: return Color(red: 0.90, green: 0.45, blue: 0.75)
        case .other: return Color(red: 0.58, green: 0.62, blue: 0.68)
        }
    }

    static func categorize(extension ext: String) -> FileCategory {
        switch ext.lowercased() {
        case "mp4", "mov", "mkv", "avi", "webm", "m4v", "flv", "wmv", "mpeg", "mpg", "3gp", "mts", "m2ts", "vob", "ogv", "braw", "prproj":
            return .video
        case "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "svg", "raw", "cr2", "nef", "arw", "dng", "psd", "ai", "eps", "tiff", "tif", "bmp", "ico", "icns", "sketch", "fig", "xd", "afdesign", "afphoto":
            return .image
        case "mp3", "wav", "flac", "aac", "m4a", "ogg", "wma", "aiff", "aif", "alac", "opus", "mid", "midi", "caf":
            return .audio
        case "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "dmg", "iso", "pkg", "deb", "rpm", "cab", "jar", "war", "toast", "sparseimage", "sparsebundle":
            return .archive
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "md", "rtf", "rtfd", "csv", "tsv", "pages", "numbers", "key", "epub", "mobi", "odt", "ods", "odp", "tex":
            return .document
        case "py", "swift", "js", "ts", "jsx", "tsx", "html", "htm", "css", "scss", "less", "json", "xml", "yaml", "yml", "toml", "ini", "cfg", "conf", "sh", "zsh", "bash", "c", "cpp", "cc", "h", "hpp", "m", "mm", "java", "kt", "go", "rs", "rb", "php", "sql", "db", "sqlite", "sqlite3", "realm", "plist", "lock", "ipynb", "r", "dart", "lua", "vue", "svelte":
            return .code
        case "app", "dylib", "so", "dll", "exe", "bin", "o", "a", "framework", "kext", "plugin", "bundle", "ipa", "apk", "wasm":
            return .app
        default:
            return .other
        }
    }
}

// MARK: - Elemento de Archivo
struct FileItem: Identifiable, Hashable, Sendable {
    let id: String // Ruta absoluta única
    let url: URL
    let name: String
    let path: String
    let parentPath: String
    let fileExtension: String
    let category: FileCategory
    let size: Int64
    let modificationDate: Date
    var md5Hash: String?

    var formattedSize: String {
        ByteFormatting.string(fromByteCount: size)
    }

    var formattedDate: String {
        DateFormatting.shortString(from: modificationDate)
    }
}

// MARK: - Nodo Jerárquico de Carpeta (para Explorador y Treemap)
final class FolderNode: Identifiable, ObservableObject {
    let id: String // Ruta absoluta
    let url: URL
    let name: String
    let path: String
    var totalSize: Int64 = 0
    var fileCount: Int = 0
    var subfolders: [FolderNode] = []
    var files: [FileItem] = []
    weak var parent: FolderNode?

    // Distribución por categoría dentro de esta carpeta
    var categorySizes: [FileCategory: Int64] = [:]

    init(url: URL, name: String? = nil, parent: FolderNode? = nil) {
        self.url = url
        self.path = url.path
        self.id = url.path
        self.name = name ?? (url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent)
        self.parent = parent
    }

    var dominantCategory: FileCategory {
        categorySizes.max(by: { $0.value < $1.value })?.key ?? .other
    }

    var formattedSize: String {
        ByteFormatting.string(fromByteCount: totalSize)
    }
}

// MARK: - Resumen por Categoría
struct CategorySummary: Identifiable {
    let category: FileCategory
    let totalSize: Int64
    let fileCount: Int
    let files: [FileItem] // Ya ordenados de más pesado a más liviano
    let extensionBreakdown: [(ext: String, size: Int64, count: Int)]

    var id: String { category.id }

    var formattedSize: String {
        ByteFormatting.string(fromByteCount: totalSize)
    }
}

// MARK: - Sección 1 de analyze_dupes.py: Grupo de Duplicados por Contenido (Mismo Hash)
struct DuplicateGroup: Identifiable {
    let id: String // Hash MD5
    let hash: String
    let fileSize: Int64
    var files: [FileItem]

    var wastedSpace: Int64 {
        guard files.count > 1 else { return 0 }
        return fileSize * Int64(files.count - 1)
    }

    var totalSpace: Int64 {
        fileSize * Int64(files.count)
    }

    var formattedFileSize: String {
        ByteFormatting.string(fromByteCount: fileSize)
    }

    var formattedWastedSpace: String {
        ByteFormatting.string(fromByteCount: wastedSpace)
    }
}

// MARK: - Sección 2 de analyze_dupes.py: Mismo Nombre pero Diferente Contenido
struct SameNameGroup: Identifiable {
    let id: String // Nombre de archivo
    let fileName: String
    var files: [FileItem] // Ordenados de mayor a menor tamaño
    let distinctHashesCount: Int
    let minSize: Int64
    let maxSize: Int64

    var totalSize: Int64 {
        files.reduce(0) { $0 + $1.size }
    }

    var formattedTotalSize: String {
        ByteFormatting.string(fromByteCount: totalSize)
    }

    var sizeRangeText: String {
        if minSize == maxSize {
            return ByteFormatting.string(fromByteCount: maxSize)
        } else {
            return "\(ByteFormatting.string(fromByteCount: minSize)) – \(ByteFormatting.string(fromByteCount: maxSize))"
        }
    }
}

// MARK: - Información de Espacio del Disco
struct DiskSpaceInfo {
    let volumeName: String
    let totalBytes: Int64
    let freeBytes: Int64
    var usedBytes: Int64 { max(0, totalBytes - freeBytes) }
    var usedPercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    static func current(for url: URL = URL(fileURLWithPath: "/")) -> DiskSpaceInfo {
        do {
            let values = try url.resourceValues(forKeys: [
                .volumeNameKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ])
            let name = values.volumeName ?? "Macintosh HD"
            let total = Int64(values.volumeTotalCapacity ?? 0)
            let free = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
            return DiskSpaceInfo(volumeName: name, totalBytes: total, freeBytes: free)
        } catch {
            return DiskSpaceInfo(volumeName: "Macintosh HD", totalBytes: 0, freeBytes: 0)
        }
    }
}

// MARK: - Estrategias de Auto-Selección de Duplicados
enum AutoSelectStrategy: String, CaseIterable, Identifiable {
    case keepNewest = "Conservar el más reciente (marcar más antiguos)"
    case keepOldest = "Conservar el más antiguo (marcar más recientes)"
    case keepShortestPath = "Conservar ruta más corta (marcar rutas anidadas)"
    case keepLongestPath = "Conservar ruta más larga"

    var id: String { rawValue }
}

// MARK: - Utilidades de Formato
enum ByteFormatting {
    static func string(fromByteCount bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    static func exactBytes(_ bytes: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return (formatter.string(from: NSNumber(value: bytes)) ?? "\(bytes)") + " bytes"
    }
}

enum DateFormatting {
    private static let formatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        df.locale = Locale(identifier: "es_ES")
        return df
    }()

    static func shortString(from date: Date) -> String {
        formatter.string(from: date)
    }
}
