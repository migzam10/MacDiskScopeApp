import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case categoriesAndFiles = "Por Tipo y Tamaño"
    case treemap = "Mapa Visual (Treemap)"
    case folderExplorer = "Explorador de Carpetas"
    case exactDuplicates = "Duplicados (Mismo Hash)"
    case sameNameDiffContent = "Mismo Nombre ≠ Contenido"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .categoriesAndFiles: return "chart.bar.xaxis"
        case .treemap: return "square.split.bottomrightquarter.fill"
        case .folderExplorer: return "folder.fill.badge.gearshape"
        case .exactDuplicates: return "doc.on.doc.fill"
        case .sameNameDiffContent: return "exclamationmark.triangle.fill"
        }
    }
}

struct ContentView: View {
    @StateObject private var scanner = DiskScanner()
    @State private var selectedTab: MainTab = .categoriesAndFiles
    @State private var showTrashConfirmation: Bool = false
    @State private var showSelectedSheet: Bool = false

    var body: some View {
        NavigationSplitView {
            sidebarView
                .navigationSplitViewColumnWidth(min: 285, ideal: 310, max: 360)
        } detail: {
            VStack(spacing: 0) {
                // Barra Superior de Resumen Rápido (KPIs)
                topMetricsBar

                Divider()

                // Contenido Principal según Pestaña Activa
                ZStack {
                    switch selectedTab {
                    case .categoriesAndFiles:
                        CategoryAndFilesView(scanner: scanner)
                    case .treemap:
                        TreemapView(scanner: scanner)
                    case .folderExplorer:
                        FolderExplorerView(scanner: scanner)
                    case .exactDuplicates:
                        ExactDuplicatesView(scanner: scanner)
                    case .sameNameDiffContent:
                        SameNameDiffContentView(scanner: scanner)
                    }

                    if scanner.isScanning {
                        scanningOverlay
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Barra Inferior de Papelera / Archivos Seleccionados
                if !scanner.selectedFilePaths.isEmpty || !scanner.statusMessage.isEmpty || scanner.errorMessage != nil {
                    Divider()
                    bottomActionBar
                }
            }
        }
        .confirmationDialog(
            "¿Mover \(scanner.selectedFilePaths.count) archivo(s) a la Papelera de macOS?",
            isPresented: $showTrashConfirmation,
            titleVisibility: .visible
        ) {
            Button("Mover a la Papelera (\(ByteFormatting.string(fromByteCount: scanner.selectedBytesToRecover)))", role: .destructive) {
                scanner.moveSelectedToTrash()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Los archivos seleccionados se enviarán a la Papelera de tu Mac, desde donde podrás restaurarlos si cambias de opinión.")
        }
        .sheet(isPresented: $showSelectedSheet) {
            SelectedFilesReviewSheet(scanner: scanner) {
                showSelectedSheet = false
                showTrashConfirmation = true
            }
        }
        .onAppear {
            if scanner.allFiles.isEmpty && !scanner.isScanning {
                scanner.startScan()
            }
        }
    }

    // MARK: - Sidebar
    private var sidebarView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 1. Tarjeta de Estado del Disco de macOS
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "internaldrive.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(scanner.diskSpaceInfo.volumeName)
                                .font(.subheadline.bold())
                            Text("Almacenamiento del Sistema")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    ProgressView(value: scanner.diskSpaceInfo.usedPercentage)
                        .tint(scanner.diskSpaceInfo.usedPercentage > 0.85 ? .red : .blue)

                    HStack {
                        Text("Usado: \(ByteFormatting.string(fromByteCount: scanner.diskSpaceInfo.usedBytes))")
                            .font(.caption2.monospacedDigit())
                        Spacer()
                        Text("Libre: \(ByteFormatting.string(fromByteCount: scanner.diskSpaceInfo.freeBytes))")
                            .font(.caption2.monospacedDigit().bold())
                            .foregroundStyle(.green)
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.controlBackgroundColor))
                )

                // 2. Navegación de Vistas
                VStack(alignment: .leading, spacing: 6) {
                    Text("VISTAS DE ANÁLISIS")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    ForEach(MainTab.allCases) { tab in
                        let isSelected = (selectedTab == tab)
                        Button {
                            selectedTab = tab
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: tab.icon)
                                    .frame(width: 20)
                                    .foregroundStyle(isSelected ? .white : tabIconColor(tab))
                                Text(tab.rawValue)
                                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? .white : .primary)
                                Spacer()
                                badgeView(for: tab, isSelected: isSelected)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isSelected ? Color.accentColor : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()

                // 3. Selección de Qué Analizar (Todo el Disco o Carpetas Seleccionadas)
                VStack(alignment: .leading, spacing: 10) {
                    Text("QUÉ ANALIZAR")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    Picker("Alcance:", selection: $scanner.scopeMode) {
                        ForEach(DiskScanner.ScanScopeMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.radioGroup)

                    if scanner.scopeMode == .customFolders {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Button {
                                    scanner.selectFoldersWithPanel(replaceExisting: true)
                                } label: {
                                    Label("Elegir Carpeta(s)...", systemImage: "folder.badge.plus")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button {
                                    scanner.selectFoldersWithPanel(replaceExisting: false)
                                } label: {
                                    Image(systemName: "plus")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help("Añadir otra carpeta a la selección para comparar")
                            }

                            ForEach(scanner.customFolders, id: \.path) { url in
                                HStack(spacing: 6) {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(.blue)
                                        .font(.caption)
                                    Text(url.path)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .truncationMode(.head)
                                    Spacer()
                                    if scanner.customFolders.count > 1 {
                                        Button {
                                            scanner.removeCustomFolder(url)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.secondary)
                                                .font(.caption)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
                            }
                        }
                    }

                    // Accesos directos rápidos
                    Text("Accesos Rápidos:")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        QuickPresetButton(title: "Descargas", icon: "arrow.down.circle.fill") {
                            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
                            scanner.setQuickPreset(url)
                        }
                        QuickPresetButton(title: "Documentos", icon: "doc.text.fill") {
                            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
                            scanner.setQuickPreset(url)
                        }
                        QuickPresetButton(title: "Escritorio", icon: "menubar.dock.rectangle") {
                            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
                            scanner.setQuickPreset(url)
                        }
                        QuickPresetButton(title: "Usuario (~)", icon: "person.crop.circle.fill") {
                            scanner.setQuickPreset(FileManager.default.homeDirectoryForCurrentUser, mode: .userHome)
                        }
                        QuickPresetButton(title: "Aplicaciones", icon: "app.badge.fill") {
                            scanner.setQuickPreset(URL(fileURLWithPath: "/Applications"))
                        }
                        QuickPresetButton(title: "Todo el Disco", icon: "internaldrive.fill") {
                            scanner.setQuickPreset(URL(fileURLWithPath: "/"), mode: .fullDisk)
                        }
                    }
                }

                Divider()

                // 4. Opciones de Filtrado de Escaneo
                VStack(alignment: .leading, spacing: 8) {
                    Text("OPCIONES DE ESCANEO")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    Toggle("Ignorar archivos ocultos (.*)", isOn: $scanner.skipHiddenFiles)
                        .font(.caption)

                    Toggle("Ignorar cachés dev (node_modules, .git)", isOn: $scanner.skipDevFolders)
                        .font(.caption)

                    HStack {
                        Text("Duplicados mín:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $scanner.minDuplicateSizeBytes) {
                            Text("Todos (> 0 B)").tag(Int64(1))
                            Text("> 1 KB").tag(Int64(1024))
                            Text("> 100 KB").tag(Int64(100 * 1024))
                            Text("> 1 MB").tag(Int64(1024 * 1024))
                        }
                        .labelsHidden()
                    }
                }

                // 5. Botón Principal de Acción
                if scanner.isScanning || scanner.isHashingDuplicates {
                    Button(role: .destructive) {
                        scanner.cancelScan()
                    } label: {
                        Label(
                            scanner.isScanning ? "Detener Escaneo" : "Detener Cálculo de Duplicados",
                            systemImage: "stop.circle.fill"
                        )
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button {
                        scanner.startScan()
                    } label: {
                        Label("Analizar Ahora", systemImage: "sparkles.magnifyingglass")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
            }
            .padding(14)
        }
    }

    private func tabIconColor(_ tab: MainTab) -> Color {
        switch tab {
        case .categoriesAndFiles: return .blue
        case .treemap: return .purple
        case .folderExplorer: return .cyan
        case .exactDuplicates: return .red
        case .sameNameDiffContent: return .orange
        }
    }

    @ViewBuilder
    private func badgeView(for tab: MainTab, isSelected: Bool) -> some View {
        let text: String? = {
            switch tab {
            case .categoriesAndFiles:
                return scanner.allFiles.isEmpty ? nil : "\(scanner.categorySummaries.count) tipos"
            case .treemap:
                return nil
            case .folderExplorer:
                return nil
            case .exactDuplicates:
                return scanner.duplicateGroups.isEmpty ? nil : "\(scanner.duplicateGroups.count)"
            case .sameNameDiffContent:
                return scanner.sameNameGroups.isEmpty ? nil : "\(scanner.sameNameGroups.count)"
            }
        }()

        if let badge = text {
            Text(badge)
                .font(.caption2.monospacedDigit().bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.white.opacity(0.25) : Color.secondary.opacity(0.15))
                )
                .foregroundStyle(isSelected ? .white : .secondary)
        }
    }

    // MARK: - Top Metrics Bar
    private var topMetricsBar: some View {
        HStack(spacing: 16) {
            MetricPill(
                icon: "doc.on.doc",
                title: "Archivos Analizados",
                value: scanner.scannedFilesCount.formatted(),
                subtitle: scanner.scanPhase,
                color: .blue
            )

            MetricPill(
                icon: "externaldrive.fill.badge.timemachine",
                title: "Tamaño Total Analizado",
                value: ByteFormatting.string(fromByteCount: scanner.scannedBytesTotal),
                subtitle: "\(scanner.categorySummaries.count) categorías de archivos",
                color: .purple
            )

            MetricPill(
                icon: "square.on.square.dashed",
                title: "Duplicados (Mismo Hash)",
                value: ByteFormatting.string(fromByteCount: scanner.totalWastedDuplicateBytes),
                subtitle: "\(scanner.duplicateGroups.count) grupos (\(scanner.totalDuplicateFilesCount) copias extra)",
                color: .red
            )
            .onTapGesture {
                selectedTab = .exactDuplicates
            }

            MetricPill(
                icon: "exclamationmark.triangle",
                title: "Mismo Nombre ≠ Contenido",
                value: "\(scanner.sameNameGroups.count) nombres",
                subtitle: "Archivos con igual nombre y distinto contenido",
                color: .orange
            )
            .onTapGesture {
                selectedTab = .sameNameDiffContent
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Overlay de Escaneo
    private var scanningOverlay: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)

            Text(scanner.scanPhase)
                .font(.headline)

            Text("Procesados \(scanner.scannedFilesCount.formatted()) archivos (\(ByteFormatting.string(fromByteCount: scanner.scannedBytesTotal)))")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)

            if scanner.hashingProgress > 0 && scanner.hashingProgress < 1.0 {
                ProgressView(value: scanner.hashingProgress)
                    .frame(width: 260)
            }

            Button("Cancelar") {
                scanner.cancelScan()
            }
            .buttonStyle(.bordered)
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(radius: 16)
        )
    }

    // MARK: - Barra Inferior de Papelera y Notificaciones
    private var bottomActionBar: some View {
        HStack(spacing: 14) {
            if let error = scanner.errorMessage {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                Button("Cerrar") {
                    scanner.errorMessage = nil
                }
                .buttonStyle(.plain)
                .font(.caption.bold())
            } else if !scanner.statusMessage.isEmpty && scanner.selectedFilePaths.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(scanner.statusMessage)
                    .font(.caption)
                Button("OK") {
                    scanner.statusMessage = ""
                }
                .buttonStyle(.plain)
                .font(.caption.bold())
            }

            Spacer()

            if !scanner.selectedFilePaths.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "trash.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(scanner.selectedFilePaths.count) archivo(s) marcados para borrar")
                            .font(.subheadline.bold())
                        Text("Espacio a recuperar: \(ByteFormatting.string(fromByteCount: scanner.selectedBytesToRecover))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Button("Revisar lista") {
                        showSelectedSheet = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Desmarcar todos") {
                        scanner.clearSelection()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(role: .destructive) {
                        showTrashConfirmation = true
                    } label: {
                        Label("Mover a la Papelera (\(ByteFormatting.string(fromByteCount: scanner.selectedBytesToRecover)))", systemImage: "trash.fill")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Componentes Auxiliares de UI
struct QuickPresetButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct MetricPill: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(color.gradient))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
                )
        )
    }
}

// MARK: - Hoja de Revisión de Archivos Marcados antes de Enviar a la Papelera
struct SelectedFilesReviewSheet: View {
    @ObservedObject var scanner: DiskScanner
    @Environment(\.dismiss) private var dismiss
    let onConfirmTrash: () -> Void
    @State private var displayLimit: Int = 150

    private var selectedItems: [FileItem] {
        scanner.allFiles.filter { scanner.selectedFilePaths.contains($0.path) }
    }

    var body: some View {
        let items = selectedItems
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Archivos marcados para enviar a la Papelera")
                        .font(.headline)
                    Text("\(scanner.selectedFilePaths.count.formatted()) archivo(s) • Total a liberar: \(ByteFormatting.string(fromByteCount: scanner.selectedBytesToRecover))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cerrar") {
                    dismiss()
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            List {
                ForEach(items.prefix(displayLimit)) { file in
                    HStack(spacing: 10) {
                        Button {
                            scanner.toggleSelection(file)
                        } label: {
                            Image(systemName: "checkmark.square.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name)
                                .font(.subheadline.bold())
                            Text(file.path)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(file.formattedSize)
                            .font(.caption.monospacedDigit().bold())

                        Button {
                            scanner.revealInFinder(file)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if items.count > displayLimit {
                    Button("Mostrar 150 archivos más (\(items.count - displayLimit) restantes)") {
                        displayLimit += 150
                    }
                    .buttonStyle(.bordered)
                }
            }

            Divider()

            HStack {
                Button("Desmarcar todos") {
                    scanner.clearSelection()
                    dismiss()
                }
                Spacer()
                Button(role: .destructive) {
                    onConfirmTrash()
                } label: {
                    Label("Mover todos a la Papelera (\(ByteFormatting.string(fromByteCount: scanner.selectedBytesToRecover)))", systemImage: "trash.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(scanner.selectedFilePaths.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 720, height: 480)
    }
}
