import SwiftUI

// MARK: - Elemento de Bloque del Treemap
struct TreemapBlockItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let size: Int64
    let category: FileCategory
    let isFolder: Bool
    let folderNode: FolderNode?
    let fileItem: FileItem?
}

struct PlacedTreemapRect: Identifiable {
    let item: TreemapBlockItem
    let rect: CGRect
    var id: String { item.id }
}

// MARK: - Algoritmo Slice-and-Dice / Squarified Híbrido para Treemap Rápido
enum TreemapLayoutEngine {
    static func computeLayout(items: [TreemapBlockItem], in bounds: CGRect) -> [PlacedTreemapRect] {
        let validItems = items.filter { $0.size > 0 }
        guard !validItems.isEmpty, bounds.width > 4, bounds.height > 4 else { return [] }

        var result: [PlacedTreemapRect] = []
        subdivide(items: validItems, rect: bounds, output: &result)
        return result
    }

    private static func subdivide(items: [TreemapBlockItem], rect: CGRect, output: inout [PlacedTreemapRect]) {
        guard !items.isEmpty, rect.width > 1, rect.height > 1 else { return }

        if items.count == 1 {
            output.append(PlacedTreemapRect(item: items[0], rect: rect))
            return
        }

        let totalSize = items.reduce(Int64(0)) { $0 + $1.size }
        guard totalSize > 0 else { return }

        if items.count == 2 {
            let ratio = CGFloat(items[0].size) / CGFloat(totalSize)
            if rect.width >= rect.height {
                let w1 = max(1, rect.width * ratio)
                let r1 = CGRect(x: rect.minX, y: rect.minY, width: w1, height: rect.height)
                let r2 = CGRect(x: rect.minX + w1, y: rect.minY, width: max(0, rect.width - w1), height: rect.height)
                output.append(PlacedTreemapRect(item: items[0], rect: r1))
                output.append(PlacedTreemapRect(item: items[1], rect: r2))
            } else {
                let h1 = max(1, rect.height * ratio)
                let r1 = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: h1)
                let r2 = CGRect(x: rect.minX, y: rect.minY + h1, width: rect.width, height: max(0, rect.height - h1))
                output.append(PlacedTreemapRect(item: items[0], rect: r1))
                output.append(PlacedTreemapRect(item: items[1], rect: r2))
            }
            return
        }

        // Partición balanceada por peso (Binary Treemap / Squarified)
        let halfSize = totalSize / 2
        var running: Int64 = 0
        var splitIndex = 1

        for i in 0..<(items.count - 1) {
            running += items[i].size
            if running >= halfSize {
                splitIndex = i + 1
                break
            }
        }

        let leftItems = Array(items[0..<splitIndex])
        let rightItems = Array(items[splitIndex..<items.count])
        let leftSize = leftItems.reduce(Int64(0)) { $0 + $1.size }
        let ratio = CGFloat(leftSize) / CGFloat(totalSize)

        if rect.width >= rect.height {
            let w1 = max(1, rect.width * ratio)
            let r1 = CGRect(x: rect.minX, y: rect.minY, width: w1, height: rect.height)
            let r2 = CGRect(x: rect.minX + w1, y: rect.minY, width: max(0, rect.width - w1), height: rect.height)
            subdivide(items: leftItems, rect: r1, output: &output)
            subdivide(items: rightItems, rect: r2, output: &output)
        } else {
            let h1 = max(1, rect.height * ratio)
            let r1 = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: h1)
            let r2 = CGRect(x: rect.minX, y: rect.minY + h1, width: rect.width, height: max(0, rect.height - h1))
            subdivide(items: leftItems, rect: r1, output: &output)
            subdivide(items: rightItems, rect: r2, output: &output)
        }
    }
}

// MARK: - Vista Interactiva de Mapa de Bloques (Treemap)
struct TreemapView: View {
    @ObservedObject var scanner: DiskScanner
    @State private var currentNode: FolderNode?
    @State private var hoveredItem: TreemapBlockItem?
    @State private var selectedItem: TreemapBlockItem?
    @State private var viewMode: TreemapDisplayMode = .folderHierarchy
    @State private var maxBlocks: Int = 80

    enum TreemapDisplayMode: String, CaseIterable, Identifiable {
        case folderHierarchy = "Por Carpetas y Archivos (Interactivo)"
        case topFilesFlat = "Top Archivos Más Pesados Directos"
        case byCategory = "Bloques por Tipo de Archivo"

        var id: String { rawValue }
    }

    private var activeNode: FolderNode? {
        currentNode ?? scanner.rootFolderNode
    }

    private var breadcrumbNodes: [FolderNode] {
        var list: [FolderNode] = []
        var cursor = activeNode
        while let node = cursor {
            list.insert(node, at: 0)
            cursor = node.parent
        }
        return list
    }

    private var currentBlockItems: [TreemapBlockItem] {
        switch viewMode {
        case .folderHierarchy:
            guard let node = activeNode else { return [] }
            var items: [TreemapBlockItem] = []

            for sub in node.subfolders where sub.totalSize > 0 {
                items.append(
                    TreemapBlockItem(
                        id: "folder_\(sub.id)",
                        title: "📁 \(sub.name)",
                        subtitle: "\(sub.fileCount) archivos • \(sub.formattedSize)",
                        size: sub.totalSize,
                        category: sub.dominantCategory,
                        isFolder: true,
                        folderNode: sub,
                        fileItem: nil
                    )
                )
            }

            for file in node.files where file.size > 0 {
                items.append(
                    TreemapBlockItem(
                        id: "file_\(file.id)",
                        title: file.name,
                        subtitle: "\(file.category.rawValue) • \(file.formattedSize)",
                        size: file.size,
                        category: file.category,
                        isFolder: false,
                        folderNode: nil,
                        fileItem: file
                    )
                )
            }

            items.sort { $0.size > $1.size }
            return Array(items.prefix(maxBlocks))

        case .topFilesFlat:
            return Array(scanner.allFiles.prefix(maxBlocks)).map { file in
                TreemapBlockItem(
                    id: "flat_\(file.id)",
                    title: file.name,
                    subtitle: "\(file.parentPath) • \(file.formattedSize)",
                    size: file.size,
                    category: file.category,
                    isFolder: false,
                    folderNode: nil,
                    fileItem: file
                )
            }

        case .byCategory:
            return scanner.categorySummaries.map { summary in
                TreemapBlockItem(
                    id: "cat_\(summary.id)",
                    title: summary.category.rawValue,
                    subtitle: "\(summary.fileCount) archivos • \(summary.formattedSize)",
                    size: summary.totalSize,
                    category: summary.category,
                    isFolder: false,
                    folderNode: nil,
                    fileItem: nil
                )
            }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Barra Superior de Controles del Treemap y Breadcrumb
            HStack(spacing: 12) {
                Picker("Modo:", selection: $viewMode) {
                    ForEach(TreemapDisplayMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 520)

                Spacer()

                HStack(spacing: 6) {
                    Text("Bloques máx:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $maxBlocks) {
                        Text("40").tag(40)
                        Text("80").tag(80)
                        Text("150").tag(150)
                    }
                    .frame(width: 75)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Barra de Navegación Breadcrumb cuando estamos en modo Jerarquía de Carpetas
            if viewMode == .folderHierarchy, !breadcrumbNodes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if breadcrumbNodes.count > 1 {
                            Button {
                                if let parent = activeNode?.parent {
                                    currentNode = parent
                                    selectedItem = nil
                                }
                            } label: {
                                Label("Subir nivel", systemImage: "arrow.up.left")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        ForEach(Array(breadcrumbNodes.enumerated()), id: \.element.id) { idx, node in
                            if idx > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Button {
                                currentNode = node
                                selectedItem = nil
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: idx == 0 ? "externaldrive.fill" : "folder.fill")
                                        .foregroundStyle(idx == breadcrumbNodes.count - 1 ? .blue : .secondary)
                                    Text(node.name)
                                        .fontWeight(idx == breadcrumbNodes.count - 1 ? .bold : .regular)
                                    Text("(\(node.formattedSize))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(idx == breadcrumbNodes.count - 1 ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            // Leyenda de Colores por Tipo de Archivo
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(FileCategory.allCases) { cat in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(cat.color)
                                .frame(width: 10, height: 10)
                            Text(cat.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            // Lienzo Principal del Treemap
            GeometryReader { geo in
                let placedRects = TreemapLayoutEngine.computeLayout(
                    items: currentBlockItems,
                    in: CGRect(origin: .zero, size: geo.size)
                )

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.underPageBackgroundColor))

                    ForEach(placedRects) { placed in
                        let isHovered = hoveredItem?.id == placed.item.id
                        let isSelected = selectedItem?.id == placed.item.id
                        let isMarkedForTrash = placed.item.fileItem.map { scanner.isSelected($0) } ?? false

                        TreemapTileView(
                            placed: placed,
                            isHovered: isHovered,
                            isSelected: isSelected,
                            isMarkedForTrash: isMarkedForTrash
                        )
                        .frame(width: max(0, placed.rect.width), height: max(0, placed.rect.height))
                        .position(x: placed.rect.midX, y: placed.rect.midY)
                        .onHover { hovering in
                            if hovering {
                                hoveredItem = placed.item
                            } else if hoveredItem?.id == placed.item.id {
                                hoveredItem = nil
                            }
                        }
                        .onTapGesture(count: 2) {
                            if let subFolder = placed.item.folderNode {
                                currentNode = subFolder
                                selectedItem = nil
                            } else if let file = placed.item.fileItem {
                                scanner.revealInFinder(file)
                            }
                        }
                        .onTapGesture(count: 1) {
                            selectedItem = placed.item
                            if viewMode == .folderHierarchy, let subFolder = placed.item.folderNode {
                                currentNode = subFolder
                            }
                        }
                        .contextMenu {
                            if let folder = placed.item.folderNode {
                                Button {
                                    currentNode = folder
                                } label: {
                                    Label("Entrar en carpeta '\(folder.name)'", systemImage: "arrow.down.right.circle")
                                }
                                Button {
                                    scanner.revealURLInFinder(folder.url)
                                } label: {
                                    Label("Mostrar carpeta en Finder", systemImage: "folder")
                                }
                            }
                            if let file = placed.item.fileItem {
                                Button {
                                    scanner.toggleSelection(file)
                                } label: {
                                    Label(
                                        scanner.isSelected(file) ? "Desmarcar para Papelera" : "Marcar para enviar a Papelera",
                                        systemImage: scanner.isSelected(file) ? "checkmark.circle.fill" : "trash"
                                    )
                                }
                                Button {
                                    scanner.revealInFinder(file)
                                } label: {
                                    Label("Mostrar en Finder", systemImage: "folder")
                                }
                                Button {
                                    scanner.openFile(file)
                                } label: {
                                    Label("Abrir / Vista Previa", systemImage: "eye")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    scanner.moveSingleFileToTrash(file)
                                } label: {
                                    Label("Mover a la Papelera ahora", systemImage: "trash.fill")
                                }
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 16)

            // Panel Inspector Inferior del Bloque Seleccionado o bajo el Cursor
            inspectorFooter
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .onChange(of: scanner.rootFolderNode?.id) { _, _ in
            currentNode = scanner.rootFolderNode
        }
    }

    @ViewBuilder
    private var inspectorFooter: some View {
        let activeItem = hoveredItem ?? selectedItem
        HStack(spacing: 14) {
            if let item = activeItem {
                RoundedRectangle(cornerRadius: 6)
                    .fill(item.category.color)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: item.isFolder ? "folder.fill" : item.category.icon)
                            .foregroundStyle(.white)
                            .font(.caption)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(item.title)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                        Text(ByteFormatting.string(fromByteCount: item.size))
                            .font(.caption.monospacedDigit().bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(item.category.color.opacity(0.2)))
                    }
                    Text(item.fileItem?.path ?? item.folderNode?.path ?? item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if let file = item.fileItem {
                    Button {
                        scanner.toggleSelection(file)
                    } label: {
                        Label(
                            scanner.isSelected(file) ? "Marcado" : "Marcar para borrar",
                            systemImage: scanner.isSelected(file) ? "checkmark.square.fill" : "square"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        scanner.revealInFinder(file)
                    } label: {
                        Label("Finder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        scanner.openFile(file)
                    } label: {
                        Label("Abrir", systemImage: "eye")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if let folder = item.folderNode {
                    Text("Haz clic para entrar en la carpeta o clic derecho para opciones")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        scanner.revealURLInFinder(folder.url)
                    } label: {
                        Label("Finder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                Image(systemName: "hand.point.up.left.fill")
                    .foregroundStyle(.secondary)
                Text("Pasa el cursor sobre cualquier bloque para ver su tamaño y ruta. Haz clic en una carpeta para explorar su interior o clic derecho en un archivo para enviarlo a la Papelera.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

struct TreemapTileView: View {
    let placed: PlacedTreemapRect
    let isHovered: Bool
    let isSelected: Bool
    let isMarkedForTrash: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            placed.item.category.color.opacity(isHovered ? 0.95 : 0.80),
                            placed.item.category.color.opacity(isHovered ? 0.82 : 0.62)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if isMarkedForTrash {
                Rectangle()
                    .fill(Color.red.opacity(0.35))
            }

            Rectangle()
                .stroke(
                    isHovered || isSelected ? Color.white : Color.black.opacity(0.35),
                    lineWidth: isHovered || isSelected ? 2.0 : 1.0
                )

            if placed.rect.width > 55 && placed.rect.height > 28 {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if isMarkedForTrash {
                            Image(systemName: "trash.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.white)
                        }
                        Text(placed.item.title)
                            .font(.system(size: placed.rect.width > 120 ? 12 : 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.45), radius: 1, x: 0, y: 1)
                    }

                    if placed.rect.height > 44 {
                        Text(ByteFormatting.string(fromByteCount: placed.item.size))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.45), radius: 1, x: 0, y: 1)
                    }
                }
                .padding(5)
            }
        }
    }
}
