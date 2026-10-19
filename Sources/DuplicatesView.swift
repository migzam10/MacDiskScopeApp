import SwiftUI

// MARK: - SECCIÓN 1 de analyze_dupes.py: Duplicados Exactos por Contenido (Mismo Hash MD5)
struct ExactDuplicatesView: View {
    @ObservedObject var scanner: DiskScanner
    @State private var searchText: String = ""
    @State private var selectedCategory: FileCategory? = nil
    @State private var selectedStrategy: AutoSelectStrategy = .keepNewest
    @State private var displayLimit: Int = 60

    private var filteredGroups: [DuplicateGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if selectedCategory == nil && query.isEmpty {
            return scanner.duplicateGroups
        }
        return scanner.duplicateGroups.filter { group in
            if let cat = selectedCategory, group.files.first?.category != cat {
                return false
            }
            if !query.isEmpty {
                if group.hash.lowercased().contains(query) { return true }
                return group.files.contains {
                    $0.name.lowercased().contains(query) || $0.path.lowercased().contains(query)
                }
            }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Cabecera de Resumen y Auto-Selección Inteligente
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.gradient))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("DUPLICADOS POR CONTENIDO (Mismo contenido = Mismo Hash MD5)")
                                .font(.headline)
                            Text("\(scanner.duplicateGroups.count.formatted()) grupos de duplicados • \(scanner.totalDuplicateFilesCount.formatted()) copias extra • **\(ByteFormatting.string(fromByteCount: scanner.totalWastedDuplicateBytes)) recuperables**")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Controles de Auto-Selección Inteligente
                    HStack(spacing: 8) {
                        Picker("Regla de auto-selección:", selection: $selectedStrategy) {
                            ForEach(AutoSelectStrategy.allCases) { strategy in
                                Text(strategy.rawValue).tag(strategy)
                            }
                        }
                        .frame(width: 340)

                        Button {
                            scanner.applyAutoSelectToAllDuplicateGroups(strategy: selectedStrategy)
                        } label: {
                            Label("Auto-Marcar Duplicados", systemImage: "wand.and.stars")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(scanner.duplicateGroups.isEmpty || scanner.isHashingDuplicates)
                    }
                }

                if scanner.isHashingDuplicates {
                    HStack(spacing: 12) {
                        ProgressView(value: scanner.hashingProgress)
                            .frame(width: 220)
                        Text(scanner.scanPhase)
                            .font(.caption.monospacedDigit().bold())
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Detener cálculo de hashes") {
                            scanner.cancelScan()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
                }

                // Barra de búsqueda y filtro por tipo de archivo
                HStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Buscar por nombre, ruta o Hash MD5...", text: $searchText)
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
                    .frame(maxWidth: 340)

                    Picker("Tipo de archivo:", selection: $selectedCategory) {
                        Text("Todos los tipos").tag(FileCategory?.none)
                        ForEach(FileCategory.allCases) { cat in
                            Text(cat.rawValue).tag(FileCategory?.some(cat))
                        }
                    }
                    .frame(width: 240)

                    Spacer()

                    Text("Mostrando \(min(displayLimit, filteredGroups.count)) de \(filteredGroups.count.formatted()) grupos (ordenados por mayor desperdicio)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            let groups = filteredGroups
            if groups.isEmpty {
                if scanner.isHashingDuplicates {
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Analizando hashes MD5 para detectar duplicados exactos...")
                            .font(.headline)
                        Text(scanner.scanPhase)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        scanner.duplicateGroups.isEmpty
                            ? "¡Excelente! No se encontraron archivos duplicados por contenido"
                            : "Sin coincidencias para el filtro actual",
                        systemImage: "checkmark.seal.fill",
                        description: Text(
                            scanner.duplicateGroups.isEmpty
                                ? "Ningún archivo tiene exactamente el mismo Hash MD5 en las carpetas analizadas."
                                : "Prueba limpiando el texto de búsqueda o cambiando el tipo de archivo."
                        )
                    )
                }
            } else {
                List {
                    let visibleSlice = groups.prefix(displayLimit)
                    ForEach(Array(visibleSlice.enumerated()), id: \.element.id) { index, group in
                        DuplicateGroupCard(
                            index: index + 1,
                            group: group,
                            scanner: scanner
                        )
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    }

                    if groups.count > displayLimit {
                        HStack {
                            Spacer()
                            Button("Mostrar 60 grupos de duplicados más (mostrando \(displayLimit) de \(groups.count.formatted()))") {
                                displayLimit += 60
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.vertical, 10)
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

struct DuplicateGroupCard: View {
    let index: Int
    let group: DuplicateGroup
    @ObservedObject var scanner: DiskScanner
    @State private var showAllFilesInGroup: Bool = false

    private let maxFilesCollapsed = 8

    private var newestDate: Date? {
        group.files.map(\.modificationDate).max()
    }

    private var shortestPathCount: Int? {
        group.files.map { $0.path.count }.min()
    }

    private var visibleFiles: ArraySlice<FileItem> {
        if showAllFilesInGroup || group.files.count <= maxFilesCollapsed {
            return group.files[...]
        } else {
            return group.files.prefix(maxFilesCollapsed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Encabezado del grupo
            HStack(spacing: 10) {
                Text("🔴 DUPLICADO #\(index)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.red)

                if let first = group.files.first {
                    HStack(spacing: 4) {
                        Image(systemName: first.category.icon)
                        Text(first.category.rawValue)
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(first.category.color.opacity(0.15)))
                    .foregroundStyle(first.category.color)
                }

                Text("MD5: \(group.hash)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                Button {
                    scanner.copyToClipboard(group.hash)
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .help("Copiar Hash MD5")

                Spacer()

                Text("Tamaño c/u: \(group.formattedFileSize) • \(group.files.count) copias")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Text("Recuperable: \(group.formattedWastedSpace)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.red.opacity(0.15)))
                    .foregroundStyle(.red)

                Menu {
                    ForEach(AutoSelectStrategy.allCases) { strategy in
                        Button(strategy.rawValue) {
                            scanner.applyAutoSelect(strategy: strategy, in: group)
                        }
                    }
                } label: {
                    Label("Auto-marcar", systemImage: "wand.and.stars")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Divider()

            // Lista de archivos idénticos dentro del grupo (acotada para fluidez)
            ForEach(Array(visibleFiles.enumerated()), id: \.element.id) { fileIdx, file in
                let isSelected = scanner.isSelected(file)
                let isNewest = (file.modificationDate == newestDate)
                let isShortestPath = (file.path.count == shortestPathCount)

                HStack(spacing: 10) {
                    Button {
                        scanner.toggleSelection(file)
                    } label: {
                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                            .font(.system(size: 16))
                            .foregroundStyle(isSelected ? .red : .secondary)
                    }
                    .buttonStyle(.plain)

                    Text("\(fileIdx + 1).")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(file.name)
                                .font(.subheadline.weight(.semibold))
                                .strikethrough(isSelected, color: .red)
                                .lineLimit(1)

                            if !isSelected {
                                Text("CONSERVAR")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.green.opacity(0.2)))
                                    .foregroundStyle(.green)
                            } else {
                                Text("MARCADO PARA PAPELERA")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.red.opacity(0.2)))
                                    .foregroundStyle(.red)
                            }

                            if isNewest {
                                Text("MÁS RECIENTE")
                                    .font(.system(size: 9, weight: .semibold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.blue.opacity(0.15)))
                                    .foregroundStyle(.blue)
                            }

                            if isShortestPath {
                                Text("RUTA CORTA")
                                    .font(.system(size: 9, weight: .semibold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.purple.opacity(0.15)))
                                    .foregroundStyle(.purple)
                            }
                        }

                        Text(file.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    Text(file.formattedDate)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Button {
                        scanner.openFile(file)
                    } label: {
                        Image(systemName: "eye")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Abrir / Vista Previa")

                    Button {
                        scanner.revealInFinder(file)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Mostrar en Finder")

                    Button(role: .destructive) {
                        scanner.moveSingleFileToTrash(file)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Mover esta copia a la Papelera ahora")
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.red.opacity(0.08) : Color.clear)
                )
            }

            if group.files.count > maxFilesCollapsed {
                Button {
                    showAllFilesInGroup.toggle()
                } label: {
                    Text(
                        showAllFilesInGroup
                            ? "Ocultar copias adicionales"
                            : "Ver las \(group.files.count - maxFilesCollapsed) copias adicionales de este archivo..."
                    )
                    .font(.caption.bold())
                }
                .buttonStyle(.link)
                .padding(.leading, 32)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                )
        )
    }
}

// MARK: - SECCIÓN 2 de analyze_dupes.py: Mismo Nombre pero Diferente Contenido
struct SameNameDiffContentView: View {
    @ObservedObject var scanner: DiskScanner
    @State private var searchText: String = ""
    @State private var selectedCategory: FileCategory? = nil
    @State private var displayLimit: Int = 60

    private var filteredGroups: [SameNameGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if selectedCategory == nil && query.isEmpty {
            return scanner.sameNameGroups
        }
        return scanner.sameNameGroups.filter { group in
            if let cat = selectedCategory, group.files.first?.category != cat {
                return false
            }
            if !query.isEmpty {
                if group.fileName.lowercased().contains(query) { return true }
                return group.files.contains { $0.path.lowercased().contains(query) }
            }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Cabecera explicativa de la Sección 2
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.gradient))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("ARCHIVOS CON MISMO NOMBRE PERO DIFERENTE CONTENIDO")
                            .font(.headline)
                        Text("\(scanner.sameNameGroups.count.formatted()) nombres de archivo repetidos en distintas rutas con distinto tamaño o distinto Hash MD5")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                HStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Filtrar por nombre de archivo o ruta...", text: $searchText)
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
                    .frame(maxWidth: 340)

                    Picker("Tipo de archivo:", selection: $selectedCategory) {
                        Text("Todos los tipos").tag(FileCategory?.none)
                        ForEach(FileCategory.allCases) { cat in
                            Text(cat.rawValue).tag(FileCategory?.some(cat))
                        }
                    }
                    .frame(width: 240)

                    Spacer()

                    Text("Mostrando \(min(displayLimit, filteredGroups.count)) de \(filteredGroups.count.formatted()) grupos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            let groups = filteredGroups
            if groups.isEmpty {
                ContentUnavailableView(
                    scanner.sameNameGroups.isEmpty
                        ? "No se encontraron archivos con el mismo nombre y diferente contenido"
                        : "Sin coincidencias para el filtro",
                    systemImage: "doc.badge.gearshape",
                    description: Text("Cuando dos archivos se llamen igual pero tengan distinto contenido o tamaño, aparecerán aquí para que puedas compararlos.")
                )
            } else {
                List {
                    ForEach(groups.prefix(displayLimit)) { group in
                        SameNameGroupCard(group: group, scanner: scanner)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    }

                    if groups.count > displayLimit {
                        HStack {
                            Spacer()
                            Button("Mostrar 60 grupos más (mostrando \(displayLimit) de \(groups.count.formatted()))") {
                                displayLimit += 60
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.vertical, 10)
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

struct SameNameGroupCard: View {
    let group: SameNameGroup
    @ObservedObject var scanner: DiskScanner
    @State private var showAllFilesInGroup: Bool = false

    private let maxFilesCollapsed = 8

    private var newestDate: Date? {
        group.files.map(\.modificationDate).max()
    }

    private var visibleFiles: ArraySlice<FileItem> {
        if showAllFilesInGroup || group.files.count <= maxFilesCollapsed {
            return group.files[...]
        } else {
            return group.files.prefix(maxFilesCollapsed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("⚠️ Nombre: \(group.fileName)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)

                if let first = group.files.first {
                    Text(first.category.rawValue)
                        .font(.caption2.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(first.category.color.opacity(0.15)))
                        .foregroundStyle(first.category.color)
                }

                Text("Encontrado \(group.files.count) veces con diferente contenido (\(group.distinctHashesCount) variantes)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Rango: \(group.sizeRangeText)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Text("Total: \(group.formattedTotalSize)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                    .foregroundStyle(.orange)
            }

            Divider()

            ForEach(visibleFiles) { file in
                let isSelected = scanner.isSelected(file)
                let isLargest = (file.size == group.maxSize && group.minSize != group.maxSize)
                let isNewest = (file.modificationDate == newestDate)

                HStack(spacing: 10) {
                    Button {
                        scanner.toggleSelection(file)
                    } label: {
                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                            .font(.system(size: 16))
                            .foregroundStyle(isSelected ? .red : .secondary)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(file.path)
                                .font(.caption.monospaced().weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.middle)

                            if isLargest {
                                Text("MÁS PESADO")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.orange.opacity(0.2)))
                                    .foregroundStyle(.orange)
                            }

                            if isNewest {
                                Text("MÁS RECIENTE")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.blue.opacity(0.15)))
                                    .foregroundStyle(.blue)
                            }
                        }

                        HStack(spacing: 12) {
                            Text("Hash MD5: \(file.md5Hash ?? "Diferente tamaño")")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)

                            Text("•")
                                .foregroundStyle(.secondary)

                            Text("Tamaño: \(file.formattedSize) (\(ByteFormatting.exactBytes(file.size)))")
                                .font(.caption2.monospacedDigit().bold())
                                .foregroundStyle(.primary)

                            Text("•")
                                .foregroundStyle(.secondary)

                            Text("Modificado: \(file.formattedDate)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        scanner.openFile(file)
                    } label: {
                        Image(systemName: "eye")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Abrir / Vista Previa")

                    Button {
                        scanner.revealInFinder(file)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Mostrar en Finder")

                    Button(role: .destructive) {
                        scanner.moveSingleFileToTrash(file)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Mover esta versión a la Papelera")
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.red.opacity(0.08) : Color.clear)
                )
            }

            if group.files.count > maxFilesCollapsed {
                Button {
                    showAllFilesInGroup.toggle()
                } label: {
                    Text(
                        showAllFilesInGroup
                            ? "Ocultar variantes adicionales"
                            : "Ver las \(group.files.count - maxFilesCollapsed) variantes adicionales de '\(group.fileName)'..."
                    )
                    .font(.caption.bold())
                }
                .buttonStyle(.link)
                .padding(.leading, 26)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                )
        )
    }
}
