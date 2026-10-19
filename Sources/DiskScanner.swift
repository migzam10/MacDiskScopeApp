import Foundation
import SwiftUI
import AppKit
import CryptoKit

@MainActor
final class DiskScanner: ObservableObject {
    // MARK: - Configuración de Escaneo
    enum ScanScopeMode: String, CaseIterable, Identifiable {
        case customFolders = "Carpetas Seleccionadas"
        case userHome = "Carpeta de Usuario (~)"
        case fullDisk = "Todo el Disco (/)"

        var id: String { rawValue }
    }

    @Published var scopeMode: ScanScopeMode = .customFolders
    @Published var customFolders: [URL] = []
    @Published var skipHiddenFiles: Bool = true
    @Published var skipDevFolders: Bool = true // Ignorar .git, node_modules, DerivedData por defecto para evitar miles de micro-archivos
    @Published var minDuplicateSizeBytes: Int64 = 1024 // Ignorar micro-archivos < 1 KB en duplicados para máxima velocidad

    // MARK: - Estado de Ejecución
    @Published var isScanning: Bool = false
    @Published var isHashingDuplicates: Bool = false
    @Published var scanPhase: String = "Listo para analizar"
    @Published var scannedFilesCount: Int = 0
    @Published var scannedBytesTotal: Int64 = 0
    @Published var hashingProgress: Double = 0.0
    @Published var statusMessage: String = ""
    @Published var lastScanDuration: TimeInterval = 0

    // MARK: - Resultados del Análisis
    @Published var allFiles: [FileItem] = [] // Ordenados de mayor a menor tamaño
    @Published var categorySummaries: [CategorySummary] = [] // Ordenados de mayor a menor tamaño
    @Published var rootFolderNode: FolderNode?
    @Published var duplicateGroups: [DuplicateGroup] = [] // Sección 1: Mismo contenido (Hash MD5)
    @Published var sameNameGroups: [SameNameGroup] = []   // Sección 2: Mismo nombre, diferente contenido

    // Totales precalculados en O(1) para no recalcular en el hilo principal
    @Published private(set) var totalWastedDuplicateBytes: Int64 = 0
    @Published private(set) var totalDuplicateFilesCount: Int = 0
    @Published private(set) var selectedBytesToRecover: Int64 = 0

    // MARK: - Selección para Borrar (Papelera)
    @Published private(set) var selectedFilePaths: Set<String> = []
    private var sizeByPath: [String: Int64] = [:]

    @Published var lastTrashedCount: Int = 0
    @Published var lastTrashedBytes: Int64 = 0
    @Published var errorMessage: String?

    // MARK: - Info del Disco
    @Published var diskSpaceInfo: DiskSpaceInfo = DiskSpaceInfo.current()

    private var scanTask: Task<Void, Never>?

    init() {
        let currentDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        self.customFolders = [currentDir]
        self.diskSpaceInfo = DiskSpaceInfo.current()
    }

    var targetURLsToScan: [URL] {
        switch scopeMode {
        case .fullDisk:
            return [URL(fileURLWithPath: "/")]
        case .userHome:
            return [FileManager.default.homeDirectoryForCurrentUser]
        case .customFolders:
            return customFolders
        }
    }

    // MARK: - Gestión de Carpetas
    func selectFoldersWithPanel(replaceExisting: Bool = false) {
        let panel = NSOpenPanel()
        panel.title = "Selecciona una o varias carpetas para analizar"
        panel.message = "Puedes elegir múltiples carpetas (con Cmd + Clic) o un disco entero"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "Seleccionar"

        if panel.runModal() == .OK {
            scopeMode = .customFolders
            if replaceExisting {
                customFolders = panel.urls
            } else {
                for url in panel.urls where !customFolders.contains(url) {
                    customFolders.append(url)
                }
            }
        }
    }

    func removeCustomFolder(_ url: URL) {
        customFolders.removeAll { $0 == url }
    }

    func setQuickPreset(_ url: URL, mode: ScanScopeMode = .customFolders) {
        self.scopeMode = mode
        if mode == .customFolders {
            self.customFolders = [url]
        }
        startScan()
    }

    // MARK: - Control de Escaneo
    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        isHashingDuplicates = false
        scanPhase = "Análisis detenido por el usuario"
    }

    func startScan() {
        scanTask?.cancel()
        let targets = targetURLsToScan
        guard !targets.isEmpty else {
            errorMessage = "Selecciona al menos una carpeta para analizar."
            return
        }

        isScanning = true
        isHashingDuplicates = false
        errorMessage = nil
        selectedFilePaths.removeAll()
        selectedBytesToRecover = 0
        sizeByPath.removeAll()
        scannedFilesCount = 0
        scannedBytesTotal = 0
        hashingProgress = 0
        scanPhase = "Escaneando estructura de archivos..."
        diskSpaceInfo = DiskSpaceInfo.current(for: targets.first ?? URL(fileURLWithPath: "/"))

        let skipHidden = self.skipHiddenFiles
        let skipDev = self.skipDevFolders
        let minDupSize = self.minDuplicateSizeBytes

        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            let startTime = Date()
            guard let self = self else { return }

            let normalizedTargets = Self.deduplicateRootURLs(targets)

            var discoveredFiles: [FileItem] = []
            discoveredFiles.reserveCapacity(16384)

            let virtualRoot: FolderNode
            if normalizedTargets.count == 1 {
                virtualRoot = FolderNode(url: normalizedTargets[0])
            } else {
                virtualRoot = FolderNode(url: URL(fileURLWithPath: "/"), name: "Carpetas Seleccionadas (\(normalizedTargets.count))")
            }

            var folderMap: [String: FolderNode] = [:]
            if normalizedTargets.count == 1 {
                folderMap[normalizedTargets[0].path] = virtualRoot
            } else {
                for url in normalizedTargets {
                    let node = FolderNode(url: url, parent: virtualRoot)
                    virtualRoot.subfolders.append(node)
                    folderMap[url.path] = node
                }
            }

            let resourceKeys: Set<URLResourceKey> = [
                .isRegularFileKey,
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .isPackageKey,
                .fileSizeKey,
                .totalFileAllocatedSizeKey,
                .contentModificationDateKey,
                .ubiquitousItemDownloadingStatusKey
            ]

            let ignoredDirs: Set<String> = skipDev
                ? ["node_modules", ".git", ".hg", ".svn", ".venv", "venv", "__pycache__", ".build", "DerivedData", "Pods", ".gradle", ".cargo", ".npm"]
                : []

            // Directorios virtuales o firmlinks duplicados de macOS
            let systemSkipPaths: Set<String> = [
                "/System/Volumes/Data",
                "/System/Volumes/Preboot",
                "/System/Volumes/VM",
                "/System/Volumes/Update",
                "/dev",
                "/Volumes",
                "/cores",
                "/private/var/vm"
            ]

            var localCount = 0
            var localBytes: Int64 = 0
            var lastUIUpdate = Date()

            for rootURL in normalizedTargets {
                if Task.isCancelled { return }
                let isScanningRootSlash = (rootURL.path == "/")

                var options: FileManager.DirectoryEnumerationOptions = []
                if skipHidden {
                    options.insert(.skipsHiddenFiles)
                }

                guard let enumerator = FileManager.default.enumerator(
                    at: rootURL,
                    includingPropertiesForKeys: Array(resourceKeys),
                    options: options,
                    errorHandler: { _, _ in true }
                ) else { continue }

                while let fileURL = enumerator.nextObject() as? URL {
                    if Task.isCancelled { return }

                    let fileName = fileURL.lastPathComponent
                    if fileName == ".DS_Store" {
                        continue
                    }

                    let filePath = fileURL.path

                    if isScanningRootSlash && systemSkipPaths.contains(filePath) {
                        enumerator.skipDescendants()
                        continue
                    }

                    guard let values = try? fileURL.resourceValues(forKeys: resourceKeys) else {
                        continue
                    }

                    if values.isSymbolicLink == true {
                        continue
                    }

                    if values.isDirectory == true {
                        if skipDev && ignoredDirs.contains(fileName) {
                            enumerator.skipDescendants()
                            continue
                        }
                        let parentPath = fileURL.deletingLastPathComponent().path
                        if folderMap[filePath] == nil {
                            let parentNode = folderMap[parentPath] ?? virtualRoot
                            let newNode = FolderNode(url: fileURL, parent: parentNode)
                            parentNode.subfolders.append(newNode)
                            folderMap[filePath] = newNode
                        }
                        continue
                    }

                    guard values.isRegularFile == true else { continue }

                    // Ignorar archivos de iCloud que no están descargados localmente para evitar que macOS bloquee el hilo descargándolos
                    if let status = values.ubiquitousItemDownloadingStatus, status != .current {
                        continue
                    }

                    let size = Int64(values.fileSize ?? values.totalFileAllocatedSize ?? 0)
                    let modDate = values.contentModificationDate ?? Date.distantPast
                    let ext = fileURL.pathExtension.lowercased()
                    let category = FileCategory.categorize(extension: ext)
                    let parentPath = fileURL.deletingLastPathComponent().path

                    let item = FileItem(
                        id: filePath,
                        url: fileURL,
                        name: fileName,
                        path: filePath,
                        parentPath: parentPath,
                        fileExtension: ext.isEmpty ? "(sin ext)" : ext,
                        category: category,
                        size: size,
                        modificationDate: modDate,
                        md5Hash: nil
                    )

                    discoveredFiles.append(item)

                    if let folderNode = folderMap[parentPath] {
                        folderNode.files.append(item)
                    } else {
                        let parentNode = Self.ensureFolderNode(
                            for: fileURL.deletingLastPathComponent(),
                            rootURL: rootURL,
                            virtualRoot: virtualRoot,
                            folderMap: &folderMap
                        )
                        parentNode.files.append(item)
                    }

                    localCount += 1
                    localBytes += size

                    // Actualizar la UI como máximo cada 250ms para no saturar el MainActor
                    let now = Date()
                    if now.timeIntervalSince(lastUIUpdate) >= 0.25 {
                        lastUIUpdate = now
                        let countSnapshot = localCount
                        let bytesSnapshot = localBytes
                        await MainActor.run {
                            self.scannedFilesCount = countSnapshot
                            self.scannedBytesTotal = bytesSnapshot
                            self.scanPhase = "Escaneando archivos... (\(countSnapshot.formatted()) encontrados)"
                        }
                    }
                }
            }

            if Task.isCancelled { return }

            // Consolidar tamaños recursivos del árbol de carpetas y ordenar de más pesado a más liviano
            Self.computeFolderSizesRecursively(node: virtualRoot)

            // Ordenar todos los archivos del más pesado al más liviano
            discoveredFiles.sort {
                if $0.size != $1.size { return $0.size > $1.size }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }

            // Construir mapa O(1) de tamaños por ruta
            var localSizeByPath: [String: Int64] = [:]
            localSizeByPath.reserveCapacity(discoveredFiles.count)
            for f in discoveredFiles {
                localSizeByPath[f.path] = f.size
            }

            let initialCategories = Self.buildCategorySummaries(from: discoveredFiles)
            let initialSameNames = Self.buildSameNameGroups(from: discoveredFiles)

            // PUBLICAR FASE 1 INMEDIATAMENTE: El usuario ya puede navegar por Tipo, Tamaño, Treemap y Carpetas sin bloqueo
            let phase1Files = discoveredFiles
            let phase1SizeMap = localSizeByPath
            let countSnapshot = discoveredFiles.count
            let bytesSnapshot = localBytes

            await MainActor.run {
                self.allFiles = phase1Files
                self.sizeByPath = phase1SizeMap
                self.categorySummaries = initialCategories
                self.rootFolderNode = virtualRoot
                self.sameNameGroups = initialSameNames
                self.scannedFilesCount = countSnapshot
                self.scannedBytesTotal = bytesSnapshot
                self.isScanning = false
                self.isHashingDuplicates = true
                self.scanPhase = "Calculando duplicados en segundo plano..."
            }

            // FASE 2 (En segundo plano sin bloquear la interfaz): Análisis de Duplicados por Contenido
            var sizeGroups: [Int64: [Int]] = [:]
            var nameGroups: [String: [Int]] = [:]

            for (index, item) in discoveredFiles.enumerated() {
                if item.size >= max(1, minDupSize) {
                    sizeGroups[item.size, default: []].append(index)
                }
                if item.size >= max(1, minDupSize) {
                    nameGroups[item.name, default: []].append(index)
                }
            }

            var indicesNeedingFastCheck: [Int] = []
            for (_, indices) in sizeGroups where indices.count > 1 {
                indicesNeedingFastCheck.append(contentsOf: indices)
            }

            // Ordenar candidatos de mayor a menor tamaño pero procesar de forma ágil
            var partialHashGroups: [String: [Int]] = [:]
            let totalFastCandidates = indicesNeedingFastCheck.count
            var processedFast = 0

            for idx in indicesNeedingFastCheck {
                if Task.isCancelled { return }
                let item = discoveredFiles[idx]
                if item.size <= 32_768 {
                    partialHashGroups["small_\(item.size)", default: []].append(idx)
                } else if let fastSig = Self.computeFastPartialSignature(url: item.url, size: item.size) {
                    partialHashGroups[fastSig, default: []].append(idx)
                }
                processedFast += 1
                let now = Date()
                if now.timeIntervalSince(lastUIUpdate) >= 0.3 {
                    lastUIUpdate = now
                    let progress = totalFastCandidates > 0 ? Double(processedFast) / Double(totalFastCandidates) * 0.4 : 0.4
                    let fastDoneSnapshot = processedFast
                    await MainActor.run {
                        self.hashingProgress = progress
                        self.scanPhase = "Pre-filtrando candidatos de igual tamaño (\(fastDoneSnapshot)/\(totalFastCandidates))..."
                    }
                }
            }

            var indicesNeedingFullMD5: [Int] = []
            for (key, indices) in partialHashGroups {
                if indices.count > 1 {
                    if key.hasPrefix("small_") {
                        indicesNeedingFullMD5.append(contentsOf: indices)
                    } else {
                        indicesNeedingFullMD5.append(contentsOf: indices)
                    }
                }
            }

            // También para archivos con mismo nombre y mismo tamaño exacto que aún no estén en la lista
            let existingSet = Set(indicesNeedingFullMD5)
            for (_, indices) in nameGroups where indices.count > 1 {
                // Solo necesitamos MD5 si dos archivos con el mismo nombre tienen además el mismo tamaño
                let sizesInNameGroup = Dictionary(grouping: indices, by: { discoveredFiles[$0].size })
                for (_, sameSizeIndices) in sizesInNameGroup where sameSizeIndices.count > 1 {
                    for idx in sameSizeIndices where !existingSet.contains(idx) {
                        if discoveredFiles[idx].size <= 250 * 1024 * 1024 {
                            indicesNeedingFullMD5.append(idx)
                        }
                    }
                }
            }

            let totalToHash = indicesNeedingFullMD5.count
            var hashedSoFar = 0

            for idx in indicesNeedingFullMD5 {
                if Task.isCancelled { return }
                let item = discoveredFiles[idx]
                if let md5 = Self.computeMD5Hex(url: item.url, maxBytesToRead: 512 * 1024 * 1024) {
                    discoveredFiles[idx].md5Hash = md5
                }
                hashedSoFar += 1

                let now = Date()
                if now.timeIntervalSince(lastUIUpdate) >= 0.3 || hashedSoFar == totalToHash {
                    lastUIUpdate = now
                    let progress = totalToHash > 0 ? 0.4 + (Double(hashedSoFar) / Double(totalToHash) * 0.6) : 1.0
                    let currentDone = hashedSoFar
                    await MainActor.run {
                        self.hashingProgress = progress
                        self.scanPhase = "Verificando MD5 de duplicados (\(currentDone)/\(totalToHash))..."
                    }
                }
            }

            if Task.isCancelled { return }

            let dupes = Self.buildDuplicateGroups(from: discoveredFiles)
            let sameNames = Self.buildSameNameGroups(from: discoveredFiles)
            let wastedBytes = dupes.reduce(Int64(0)) { $0 + $1.wastedSpace }
            let extraCopies = dupes.reduce(0) { $0 + max(0, $1.files.count - 1) }
            let elapsed = Date().timeIntervalSince(startTime)

            let finalFiles = discoveredFiles
            await MainActor.run {
                self.allFiles = finalFiles
                self.duplicateGroups = dupes
                self.sameNameGroups = sameNames
                self.totalWastedDuplicateBytes = wastedBytes
                self.totalDuplicateFilesCount = extraCopies
                self.lastScanDuration = elapsed
                self.isScanning = false
                self.isHashingDuplicates = false
                self.hashingProgress = 1.0
                self.scanPhase = "Completado en \(String(format: "%.1f", elapsed)) s"
            }
        }
    }

    // MARK: - Construcción de Agrupaciones
    nonisolated static func buildCategorySummaries(from files: [FileItem]) -> [CategorySummary] {
        var grouped: [FileCategory: [FileItem]] = [:]
        for cat in FileCategory.allCases {
            grouped[cat] = []
        }
        for file in files {
            grouped[file.category, default: []].append(file)
        }

        var summaries: [CategorySummary] = []
        for (cat, catFiles) in grouped where !catFiles.isEmpty {
            let totalSize = catFiles.reduce(Int64(0)) { $0 + $1.size }

            var extMap: [String: (size: Int64, count: Int)] = [:]
            for f in catFiles {
                let current = extMap[f.fileExtension] ?? (0, 0)
                extMap[f.fileExtension] = (current.size + f.size, current.count + 1)
            }
            let extBreakdown = extMap.map { (ext: $0.key, size: $0.value.size, count: $0.value.count) }
                .sorted { $0.size > $1.size }

            summaries.append(
                CategorySummary(
                    category: cat,
                    totalSize: totalSize,
                    fileCount: catFiles.count,
                    files: catFiles,
                    extensionBreakdown: extBreakdown
                )
            )
        }

        summaries.sort { $0.totalSize > $1.totalSize }
        return summaries
    }

    nonisolated static func buildDuplicateGroups(from files: [FileItem]) -> [DuplicateGroup] {
        var byHash: [String: [FileItem]] = [:]
        for file in files {
            guard file.size > 0, let hash = file.md5Hash else { continue }
            byHash[hash, default: []].append(file)
        }

        var groups: [DuplicateGroup] = []
        groups.reserveCapacity(byHash.count)

        for (hash, groupFiles) in byHash where groupFiles.count > 1 {
            let sorted = groupFiles.sorted { $0.path < $1.path }
            groups.append(
                DuplicateGroup(
                    id: hash,
                    hash: hash,
                    fileSize: sorted[0].size,
                    files: sorted
                )
            )
        }

        groups.sort {
            if $0.wastedSpace != $1.wastedSpace {
                return $0.wastedSpace > $1.wastedSpace
            }
            return $0.fileSize > $1.fileSize
        }
        return groups
    }

    nonisolated static func buildSameNameGroups(from files: [FileItem]) -> [SameNameGroup] {
        var byName: [String: [FileItem]] = [:]
        for file in files where file.size > 0 {
            byName[file.name, default: []].append(file)
        }

        var result: [SameNameGroup] = []
        for (name, groupFiles) in byName where groupFiles.count > 1 {
            var contentSignatures = Set<String>()
            for f in groupFiles {
                if let hash = f.md5Hash {
                    contentSignatures.insert("md5:\(hash)")
                } else {
                    contentSignatures.insert("size:\(f.size)")
                }
            }

            if contentSignatures.count > 1 {
                let sorted = groupFiles.sorted {
                    if $0.size != $1.size { return $0.size > $1.size }
                    return $0.path < $1.path
                }
                let sizes = sorted.map(\.size)
                result.append(
                    SameNameGroup(
                        id: name,
                        fileName: name,
                        files: sorted,
                        distinctHashesCount: contentSignatures.count,
                        minSize: sizes.min() ?? 0,
                        maxSize: sizes.max() ?? 0
                    )
                )
            }
        }

        result.sort {
            if $0.totalSize != $1.totalSize {
                return $0.totalSize > $1.totalSize
            }
            return $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
        }
        return result
    }

    // MARK: - Árbol de Carpetas y Utilidades de Hashing
    nonisolated private static func deduplicateRootURLs(_ urls: [URL]) -> [URL] {
        let standardized = urls.map { $0.standardizedFileURL }
        var result: [URL] = []
        for candidate in standardized.sorted(by: { $0.path.count < $1.path.count }) {
            let isInsideExisting = result.contains { existing in
                if existing.path == "/" { return true }
                return candidate.path == existing.path || candidate.path.hasPrefix(existing.path + "/")
            }
            if !isInsideExisting {
                result.append(candidate)
            }
        }
        return result
    }

    nonisolated private static func ensureFolderNode(
        for folderURL: URL,
        rootURL: URL,
        virtualRoot: FolderNode,
        folderMap: inout [String: FolderNode]
    ) -> FolderNode {
        let path = folderURL.path
        if let existing = folderMap[path] {
            return existing
        }
        if path == rootURL.path || path == "/" || path.count <= rootURL.path.count {
            return folderMap[rootURL.path] ?? virtualRoot
        }
        let parentURL = folderURL.deletingLastPathComponent()
        let parentNode = ensureFolderNode(
            for: parentURL,
            rootURL: rootURL,
            virtualRoot: virtualRoot,
            folderMap: &folderMap
        )
        let newNode = FolderNode(url: folderURL, parent: parentNode)
        parentNode.subfolders.append(newNode)
        folderMap[path] = newNode
        return newNode
    }

    nonisolated private static func computeFolderSizesRecursively(node: FolderNode) {
        var total: Int64 = 0
        var count: Int = node.files.count
        var catSizes: [FileCategory: Int64] = [:]

        for file in node.files {
            total += file.size
            catSizes[file.category, default: 0] += file.size
        }

        for sub in node.subfolders {
            computeFolderSizesRecursively(node: sub)
            total += sub.totalSize
            count += sub.fileCount
            for (cat, sz) in sub.categorySizes {
                catSizes[cat, default: 0] += sz
            }
        }

        node.files.sort { $0.size > $1.size }
        node.subfolders.sort { $0.totalSize > $1.totalSize }
        node.totalSize = total
        node.fileCount = count
        node.categorySizes = catSizes
    }

    nonisolated private static func computeFastPartialSignature(url: URL, size: Int64) -> String? {
        let fd = open(url.path, O_RDONLY | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        let chunkSize = 16 * 1024
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        var hasher = Insecure.MD5()

        let headRead = read(fd, &buffer, chunkSize)
        guard headRead > 0 else { return nil }
        hasher.update(data: Data(bytes: buffer, count: headRead))

        if size > Int64(chunkSize * 2) {
            let tailOffset = off_t(size - Int64(chunkSize))
            if lseek(fd, tailOffset, SEEK_SET) == tailOffset {
                let tailRead = read(fd, &buffer, chunkSize)
                if tailRead > 0 {
                    hasher.update(data: Data(bytes: buffer, count: tailRead))
                }
            }
        }

        let digest = hasher.finalize()
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(size)_\(hex)"
    }

    nonisolated static func computeMD5Hex(url: URL, maxBytesToRead: Int64 = 512 * 1024 * 1024) -> String? {
        let fd = open(url.path, O_RDONLY | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var hasher = Insecure.MD5()
        let bufferSize = 256 * 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var totalRead: Int64 = 0

        while totalRead < maxBytesToRead {
            if Task.isCancelled { return nil }
            let bytesRead = read(fd, &buffer, bufferSize)
            if bytesRead <= 0 { break }
            hasher.update(data: Data(bytes: buffer, count: bytesRead))
            totalRead += Int64(bytesRead)
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Selección O(1) y Auto-Selección Instantánea en Lote
    func isSelected(_ item: FileItem) -> Bool {
        selectedFilePaths.contains(item.path)
    }

    func toggleSelection(_ item: FileItem) {
        if selectedFilePaths.contains(item.path) {
            selectedFilePaths.remove(item.path)
            selectedBytesToRecover = max(0, selectedBytesToRecover - item.size)
        } else {
            selectedFilePaths.insert(item.path)
            selectedBytesToRecover += item.size
        }
    }

    func clearSelection() {
        selectedFilePaths.removeAll()
        selectedBytesToRecover = 0
    }

    private func recalculateSelectedBytes(for paths: Set<String>) -> Int64 {
        var total: Int64 = 0
        for path in paths {
            total += sizeByPath[path] ?? 0
        }
        return total
    }

    func applyAutoSelect(strategy: AutoSelectStrategy, in group: DuplicateGroup) {
        guard group.files.count > 1 else { return }
        var updated = selectedFilePaths
        Self.applyStrategy(strategy, to: group, into: &updated)
        selectedFilePaths = updated
        selectedBytesToRecover = recalculateSelectedBytes(for: updated)
    }

    func applyAutoSelectToAllDuplicateGroups(strategy: AutoSelectStrategy) {
        // Modificar en memoria y publicar 1 sola vez para evitar miles de redibujados de SwiftUI
        var updated = selectedFilePaths
        for group in duplicateGroups {
            Self.applyStrategy(strategy, to: group, into: &updated)
        }
        selectedFilePaths = updated
        selectedBytesToRecover = recalculateSelectedBytes(for: updated)
    }

    nonisolated private static func applyStrategy(_ strategy: AutoSelectStrategy, to group: DuplicateGroup, into selection: inout Set<String>) {
        guard group.files.count > 1 else { return }
        for f in group.files {
            selection.remove(f.path)
        }

        let sortedToKeepFirst: [FileItem]
        switch strategy {
        case .keepNewest:
            sortedToKeepFirst = group.files.sorted { $0.modificationDate > $1.modificationDate }
        case .keepOldest:
            sortedToKeepFirst = group.files.sorted { $0.modificationDate < $1.modificationDate }
        case .keepShortestPath:
            sortedToKeepFirst = group.files.sorted { $0.path.count < $1.path.count }
        case .keepLongestPath:
            sortedToKeepFirst = group.files.sorted { $0.path.count > $1.path.count }
        }

        for fileToTrash in sortedToKeepFirst.dropFirst() {
            selection.insert(fileToTrash.path)
        }
    }

    // MARK: - Acciones con Finder y Papelera (Trash)
    func revealInFinder(_ item: FileItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func revealURLInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openFile(_ item: FileItem) {
        NSWorkspace.shared.open(item.url)
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusMessage = "Copiado al portapapeles: \(text)"
    }

    func moveSingleFileToTrash(_ item: FileItem) {
        _ = movePathsToTrash([item.path])
    }

    @discardableResult
    func moveSelectedToTrash() -> (trashedCount: Int, trashedBytes: Int64) {
        let paths = Array(selectedFilePaths)
        return movePathsToTrash(paths)
    }

    private func movePathsToTrash(_ paths: [String]) -> (trashedCount: Int, trashedBytes: Int64) {
        guard !paths.isEmpty else { return (0, 0) }

        var trashedSet = Set<String>()
        var recoveredBytes: Int64 = 0
        var failedFiles: [String] = []

        for path in paths {
            let url = URL(fileURLWithPath: path)
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                trashedSet.insert(path)
                recoveredBytes += sizeByPath[path] ?? 0
                sizeByPath.removeValue(forKey: path)
            } catch {
                failedFiles.append(url.lastPathComponent)
            }
        }

        if !trashedSet.isEmpty {
            allFiles.removeAll { trashedSet.contains($0.path) }
            var remainingSelection = selectedFilePaths
            remainingSelection.subtract(trashedSet)
            selectedFilePaths = remainingSelection
            selectedBytesToRecover = recalculateSelectedBytes(for: remainingSelection)

            scannedFilesCount = allFiles.count
            scannedBytesTotal = max(0, scannedBytesTotal - recoveredBytes)

            categorySummaries = Self.buildCategorySummaries(from: allFiles)
            duplicateGroups = Self.buildDuplicateGroups(from: allFiles)
            sameNameGroups = Self.buildSameNameGroups(from: allFiles)
            totalWastedDuplicateBytes = duplicateGroups.reduce(Int64(0)) { $0 + $1.wastedSpace }
            totalDuplicateFilesCount = duplicateGroups.reduce(0) { $0 + max(0, $1.files.count - 1) }

            if let root = rootFolderNode {
                Self.pruneDeletedFiles(from: root, deletedPaths: trashedSet)
                Self.computeFolderSizesRecursively(node: root)
            }

            lastTrashedCount = trashedSet.count
            lastTrashedBytes = recoveredBytes
            statusMessage = "Se movieron \(trashedSet.count) archivo(s) a la Papelera (\(ByteFormatting.string(fromByteCount: recoveredBytes)) liberados)."
            diskSpaceInfo = DiskSpaceInfo.current()
        }

        if !failedFiles.isEmpty {
            errorMessage = "No se pudieron mover a la Papelera \(failedFiles.count) archivo(s) por permisos: \(failedFiles.prefix(3).joined(separator: ", "))"
        }

        return (trashedSet.count, recoveredBytes)
    }

    nonisolated private static func pruneDeletedFiles(from node: FolderNode, deletedPaths: Set<String>) {
        node.files.removeAll { deletedPaths.contains($0.path) }
        for sub in node.subfolders {
            pruneDeletedFiles(from: sub, deletedPaths: deletedPaths)
        }
        node.subfolders.removeAll { $0.files.isEmpty && $0.subfolders.isEmpty }
    }
}
