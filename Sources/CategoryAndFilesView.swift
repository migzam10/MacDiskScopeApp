import SwiftUI

// MARK: - Vista de Grupos por Tipo de Archivo y Lista Ordenada por Tamaño
struct CategoryAndFilesView: View {
    @ObservedObject var scanner: DiskScanner
    @State private var selectedCategory: FileCategory? = nil // nil = Todos los tipos
    @State private var selectedExtension: String? = nil
    @State private var searchText: String = ""
    @State private var minSizeBytes: Int64 = 0
    @State private var sortOrder: FileSortOrder = .sizeDesc
    @State private var displayLimit: Int = 300

    enum FileSortOrder: String, CaseIterable, Identifiable {
        case sizeDesc = "Más pesado a más liviano"
        case sizeAsc = "Más liviano a más pesado"
        case dateDesc = "Más reciente primero"
        case dateAsc = "Más antiguo primero"
        case nameAsc = "Nombre (A-Z)"

        var id: String { rawValue }
    }

    private var activeCategorySummary: CategorySummary? {
        guard let cat = selectedCategory else { return nil }
        return scanner.categorySummaries.first { $0.category == cat }
    }

    private var filteredFiles: [FileItem] {
        let baseFiles: [FileItem]
        if let summary = activeCategorySummary {
            baseFiles = summary.files
        } else {
            baseFiles = scanner.allFiles
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Vía rápida O(1) cuando no hay filtros activos y el orden es de más pesado a más liviano
        if minSizeBytes == 0 && selectedExtension == nil && query.isEmpty {
            switch sortOrder {
            case .sizeDesc:
                return baseFiles
            case .sizeAsc:
                return Array(baseFiles.reversed())
            default:
                break
            }
        }

        let filtered = baseFiles.filter { item in
            if item.size < minSizeBytes { return false }
            if let ext = selectedExtension, item.fileExtension != ext { return false }
            if !query.isEmpty {
                return item.name.lowercased().contains(query) || item.path.lowercased().contains(query)
            }
            return true
        }

        switch sortOrder {
        case .sizeDesc:
            return filtered // Ya vienen ordenados de mayor a menor tamaño
        case .sizeAsc:
            return filtered.reversed()
        case .dateDesc:
            return filtered.sorted { $0.modificationDate > $1.modificationDate }
        case .dateAsc:
            return filtered.sorted { $0.modificationDate < $1.modificationDate }
        case .nameAsc:
            return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 1. Barra de Proporción Visual y Tarjetas por Tipo de Archivo
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Distribución por Grupos de Tipo de Archivo (De más pesado a más liviano)")
                        .font(.headline)
                    Spacer()
                    Text("Total analizado: \(ByteFormatting.string(fromByteCount: scanner.scannedBytesTotal)) en \(scanner.allFiles.count.formatted()) archivos")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                }

                // Barra de proporción multicolor estilo macOS Storage
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(scanner.categorySummaries) { summary in
                            let fraction = scanner.scannedBytesTotal > 0
                                ? CGFloat(summary.totalSize) / CGFloat(scanner.scannedBytesTotal)
                                : 0
                            let width = max(4, geo.size.width * fraction)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(summary.category.color)
                                .frame(width: width)
                                .opacity(selectedCategory == nil || selectedCategory == summary.category ? 1.0 : 0.35)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        if selectedCategory == summary.category {
                                            selectedCategory = nil
                                        } else {
                                            selectedCategory = summary.category
                                        }
                                        selectedExtension = nil
                                    }
                                }
                                .help("\(summary.category.rawValue): \(summary.formattedSize) (\(summary.fileCount) archivos)")
                        }
                    }
                }
                .frame(height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Tarjetas de Grupos de Tipo de Archivo
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        // Tarjeta "Todos"
                        CategoryCardButton(
                            title: "Todos los Tipos",
                            subtitle: "\(scanner.allFiles.count.formatted()) archivos",
                            sizeText: ByteFormatting.string(fromByteCount: scanner.scannedBytesTotal),
                            percentage: 1.0,
                            icon: "square.grid.2x2.fill",
                            color: .accentColor,
                            isSelected: selectedCategory == nil
                        ) {
                            selectedCategory = nil
                            selectedExtension = nil
                        }

                        ForEach(scanner.categorySummaries) { summary in
                            let pct = scanner.scannedBytesTotal > 0
                                ? Double(summary.totalSize) / Double(scanner.scannedBytesTotal)
                                : 0
                            CategoryCardButton(
                                title: summary.category.rawValue,
                                subtitle: "\(summary.fileCount.formatted()) archivos",
                                sizeText: summary.formattedSize,
                                percentage: pct,
                                icon: summary.category.icon,
                                color: summary.category.color,
                                isSelected: selectedCategory == summary.category
                            ) {
                                if selectedCategory == summary.category {
                                    selectedCategory = nil
                                } else {
                                    selectedCategory = summary.category
                                }
                                selectedExtension = nil
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                // Sub-desglose por extensión dentro del grupo seleccionado
                if let summary = activeCategorySummary, !summary.extensionBreakdown.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Text("Extensiones en \(summary.category.rawValue):")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            Button {
                                selectedExtension = nil
                            } label: {
                                Text("Todas (\(summary.fileCount))")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule().fill(selectedExtension == nil ? summary.category.color : Color.secondary.opacity(0.15))
                                    )
                                    .foregroundStyle(selectedExtension == nil ? .white : .primary)
                            }
                            .buttonStyle(.plain)

                            ForEach(summary.extensionBreakdown.prefix(20), id: \.ext) { item in
                                let isExtSelected = selectedExtension == item.ext
                                Button {
                                    selectedExtension = isExtSelected ? nil : item.ext
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(".\(item.ext)")
                                            .fontWeight(.semibold)
                                        Text(ByteFormatting.string(fromByteCount: item.size))
                                            .font(.caption2.monospacedDigit())
                                        Text("(\(item.count))")
                                            .font(.caption2)
                                            .opacity(0.8)
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule().fill(isExtSelected ? summary.category.color : Color.secondary.opacity(0.12))
                                    )
                                    .foregroundStyle(isExtSelected ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // 2. Barra de Filtros y Ordenamiento de la Lista de Archivos
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filtrar por nombre o ruta de archivo...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.textBackgroundColor)))
                .frame(maxWidth: 320)

                Picker("Tamaño mín:", selection: $minSizeBytes) {
                    Text("Todos los tamaños").tag(Int64(0))
                    Text("> 1 MB").tag(Int64(1_048_576))
                    Text("> 10 MB").tag(Int64(10 * 1_048_576))
                    Text("> 100 MB").tag(Int64(100 * 1_048_576))
                    Text("> 500 MB").tag(Int64(500 * 1_048_576))
                    Text("> 1 GB").tag(Int64(1024 * 1_048_576))
                }
                .frame(width: 210)

                Picker("Ordenar:", selection: $sortOrder) {
                    ForEach(FileSortOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .frame(width: 255)

                Spacer()

                Text("\(filteredFiles.count.formatted()) archivo(s)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // 3. Lista de Archivos (Ordenados del más pesado al más liviano)
            let filesToShow = filteredFiles
            let maxFileSize = filesToShow.first?.size ?? 1

            if filesToShow.isEmpty {
                ContentUnavailableView(
                    "No hay archivos que coincidan con el filtro",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Prueba cambiando la categoría seleccionada o reduciendo el filtro de tamaño mínimo.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filesToShow.prefix(displayLimit)) { file in
                        FileRowView(
                            file: file,
                            maxReferenceSize: max(1, maxFileSize),
                            isSelected: scanner.isSelected(file),
                            onToggleSelect: { scanner.toggleSelection(file) },
                            onReveal: { scanner.revealInFinder(file) },
                            onOpen: { scanner.openFile(file) },
                            onTrashNow: { scanner.moveSingleFileToTrash(file) }
                        )
                    }

                    if filesToShow.count > displayLimit {
                        HStack {
                            Spacer()
                            Button("Mostrar 300 archivos más (mostrando \(displayLimit) de \(filesToShow.count.formatted()))") {
                                displayLimit += 300
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.vertical, 8)
                            Spacer()
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }
}

// MARK: - Tarjeta de Categoría
struct CategoryCardButton: View {
    let title: String
    let subtitle: String
    let sizeText: String
    let percentage: Double
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 7).fill(color))

                    Spacer()

                    Text(String(format: "%.1f%%", percentage * 100))
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(isSelected ? color : .secondary)
                }

                Text(sizeText)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(title)
                    .font(.caption.bold())
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(width: 168, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? color.opacity(0.14) : Color(NSColor.textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? color : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Fila Individual de Archivo
struct FileRowView: View {
    let file: FileItem
    let maxReferenceSize: Int64
    let isSelected: Bool
    let onToggleSelect: () -> Void
    let onReveal: () -> Void
    let onOpen: () -> Void
    let onTrashNow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleSelect) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? .red : .secondary)
            }
            .buttonStyle(.plain)
            .help("Marcar para enviar a la Papelera")

            Image(systemName: file.category.icon)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(file.category.color))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(file.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Text(file.category.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(file.category.color.opacity(0.15)))
                        .foregroundStyle(file.category.color)
                }

                Text(file.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Barra de peso relativo y tamaño
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Text(file.formattedSize)
                        .font(.system(.subheadline, design: .monospaced).bold())
                    Text("(\(ByteFormatting.exactBytes(file.size)))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 90, alignment: .trailing)
                }

                GeometryReader { geo in
                    let ratio = min(1.0, max(0.03, CGFloat(file.size) / CGFloat(max(1, maxReferenceSize))))
                    ZStack(alignment: .trailing) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.15))
                        Capsule()
                            .fill(file.category.color)
                            .frame(width: geo.size.width * ratio)
                    }
                }
                .frame(width: 140, height: 6)
            }

            Text(file.formattedDate)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 125, alignment: .trailing)

            HStack(spacing: 6) {
                Button(action: onOpen) {
                    Image(systemName: "eye")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Abrir / Vista Previa")

                Button(action: onReveal) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Mostrar en Finder")

                Button(role: .destructive, action: onTrashNow) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Enviar este archivo a la Papelera ahora")
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Pestaña Explorador Jerárquico de Carpetas (Ordenadas de Más Pesada a Más Liviana)
struct FolderExplorerView: View {
    @ObservedObject var scanner: DiskScanner
    @State private var currentFolder: FolderNode?
    @State private var filesLimit: Int = 150
    @State private var foldersLimit: Int = 150

    private var activeFolder: FolderNode? {
        currentFolder ?? scanner.rootFolderNode
    }

    private var breadcrumbs: [FolderNode] {
        var list: [FolderNode] = []
        var cursor = activeFolder
        while let node = cursor {
            list.insert(node, at: 0)
            cursor = node.parent
        }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            // Barra de ruta (Breadcrumb) y botón subir nivel
            HStack(spacing: 10) {
                if let parent = activeFolder?.parent {
                    Button {
                        currentFolder = parent
                        filesLimit = 150
                        foldersLimit = 150
                    } label: {
                        Label("Subir carpeta", systemImage: "arrow.up.left")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(breadcrumbs.enumerated()), id: \.element.id) { idx, node in
                            if idx > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Button {
                                currentFolder = node
                                filesLimit = 150
                                foldersLimit = 150
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(idx == breadcrumbs.count - 1 ? .blue : .secondary)
                                    Text(node.name)
                                        .fontWeight(idx == breadcrumbs.count - 1 ? .bold : .regular)
                                    Text("(\(node.formattedSize))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(idx == breadcrumbs.count - 1 ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer()

                if let folder = activeFolder {
                    Button {
                        scanner.revealURLInFinder(folder.url)
                    } label: {
                        Label("Abrir carpeta en Finder", systemImage: "folder.badge.gearshape")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if let folder = activeFolder {
                let parentTotal = max(1, folder.totalSize)

                List {
                    if !folder.subfolders.isEmpty {
                        Section("Subcarpetas (Ordenadas de más pesada a más liviana • \(folder.subfolders.count))") {
                            ForEach(folder.subfolders.prefix(foldersLimit)) { sub in
                                let pct = Double(sub.totalSize) / Double(parentTotal)
                                HStack(spacing: 12) {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(sub.dominantCategory.color)
                                        .frame(width: 28)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(sub.name)
                                            .font(.subheadline.bold())
                                        Text("\(sub.fileCount.formatted()) archivos • Tipo dominante: \(sub.dominantCategory.rawValue)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Text(sub.formattedSize)
                                                .font(.system(.subheadline, design: .monospaced).bold())
                                            Text(String(format: "%.1f%%", pct * 100))
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                                .frame(width: 48, alignment: .trailing)
                                        }
                                        ProgressView(value: min(1.0, max(0.0, pct)))
                                            .tint(sub.dominantCategory.color)
                                            .frame(width: 140)
                                    }

                                    Button {
                                        currentFolder = sub
                                        filesLimit = 150
                                        foldersLimit = 150
                                    } label: {
                                        Label("Entrar", systemImage: "chevron.right")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)

                                    Button {
                                        scanner.revealURLInFinder(sub.url)
                                    } label: {
                                        Image(systemName: "folder")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help("Mostrar carpeta en Finder")
                                }
                                .padding(.vertical, 3)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    currentFolder = sub
                                    filesLimit = 150
                                    foldersLimit = 150
                                }
                            }

                            if folder.subfolders.count > foldersLimit {
                                Button("Mostrar 150 subcarpetas más (\(folder.subfolders.count - foldersLimit) restantes)") {
                                    foldersLimit += 150
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    if !folder.files.isEmpty {
                        Section("Archivos en esta carpeta (De más pesado a más liviano • \(folder.files.count))") {
                            ForEach(folder.files.prefix(filesLimit)) { file in
                                FileRowView(
                                    file: file,
                                    maxReferenceSize: parentTotal,
                                    isSelected: scanner.isSelected(file),
                                    onToggleSelect: { scanner.toggleSelection(file) },
                                    onReveal: { scanner.revealInFinder(file) },
                                    onOpen: { scanner.openFile(file) },
                                    onTrashNow: { scanner.moveSingleFileToTrash(file) }
                                )
                            }

                            if folder.files.count > filesLimit {
                                Button("Mostrar 150 archivos más (\(folder.files.count - filesLimit) restantes)") {
                                    filesLimit += 150
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            } else {
                ContentUnavailableView(
                    "Sin datos de carpetas",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Inicia un análisis para explorar la jerarquía de carpetas por tamaño.")
                )
            }
        }
        .onChange(of: scanner.rootFolderNode?.id) { _, _ in
            currentFolder = scanner.rootFolderNode
        }
    }
}
