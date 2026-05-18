import AVFoundation
import Foundation
import AivisMobileCore

private enum AppViewModelError: LocalizedError {
    case runtimeUnavailable

    var errorDescription: String? {
        switch self {
        case .runtimeUnavailable:
            return "音声合成ランタイムが接続されていません。"
        }
    }
}

@MainActor
final class AppViewModel: NSObject, ObservableObject {
    private static let playbackTimeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter
    }()

    @Published var selectedTab: AppTab = .talk
    @Published var talkEditor: TalkEditorViewModel
    @Published var modelManager: ModelManagerViewModel
    @Published var presetManager: PresetManagerViewModel
    @Published var dictionaryManager: DictionaryManagerViewModel
    @Published var settingsViewModel: SettingsViewModel
    @Published var helpViewModel: HelpViewModel
    @Published var talkActionStatusMessage: String?
    @Published var lastExportedWAVURL: URL?
    @Published var lastExportedWAVByteCount: Int
    @Published var isTalkActionRunning: Bool
    @Published var isPreviewPlaying: Bool
    @Published var playbackCurrentTime: TimeInterval
    @Published var playbackDuration: TimeInterval
    private let modelRepository: (any ModelRepository)?
    private let speechEngine: (any SpeechEngine)?
    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?
    private var automaticQueryRefreshTask: Task<Void, Never>?

    init(
        selectedTab: AppTab = .talk,
        talkEditor: TalkEditorViewModel,
        modelManager: ModelManagerViewModel,
        presetManager: PresetManagerViewModel,
        dictionaryManager: DictionaryManagerViewModel,
        settingsViewModel: SettingsViewModel,
        helpViewModel: HelpViewModel,
        modelRepository: (any ModelRepository)? = nil,
        speechEngine: (any SpeechEngine)? = nil
    ) {
        self.selectedTab = selectedTab
        self.talkEditor = talkEditor
        self.modelManager = modelManager
        self.presetManager = presetManager
        self.dictionaryManager = dictionaryManager
        self.settingsViewModel = settingsViewModel
        self.helpViewModel = helpViewModel
        self.talkActionStatusMessage = nil
        self.lastExportedWAVURL = nil
        self.lastExportedWAVByteCount = 0
        self.isTalkActionRunning = false
        self.isPreviewPlaying = false
        self.playbackCurrentTime = 0
        self.playbackDuration = 0
        self.modelRepository = modelRepository
        self.speechEngine = speechEngine
        super.init()
        self.dictionaryManager.onDictionaryDidChange = { [weak self] in
            self?.handleDictionaryDidChange()
        }
    }

    deinit {
        automaticQueryRefreshTask?.cancel()
    }

    static func bootstrap(
        runtimeStatus: EngineRuntimeStatus = .preview,
        modelRepository: (any ModelRepository)? = nil,
        supportedDevices: SupportedDevices? = nil,
        installedModels: [InstalledModel]? = nil,
        speechEngine: (any SpeechEngine)? = nil
    ) -> AppViewModel {
        let firstVoice = VoiceReference(
            engineID: "1b4a5014-d9fd-11ee-b97d-83c170a68ed3",
            speakerID: "2d8f6f95-3369-4af7-b0bd-a6310c5d5230",
            styleID: 0
        )
        let project = emptyTalkProjectDocument(voice: firstVoice)
        let presetCatalog = (try? FixtureBootstrap.loadPresetCatalog())
            ?? PresetCatalog(items: [:], keys: [])
        let defaultStyles = (try? FixtureBootstrap.loadDefaultStyles())
            ?? [
                DefaultStyleID(
                    engineID: firstVoice.engineID,
                    speakerUUID: firstVoice.speakerID,
                    defaultStyleID: firstVoice.styleID
                )
            ]

        let talkEditor = TalkEditorViewModel(project: project)
        let modelManager = ModelManagerViewModel(
            installedModels: installedModels ?? previewInstalledModels(),
            supportedDevices: supportedDevices ?? SupportedDevices(
                cpu: true,
                gpu: runtimeStatus.coreMLAvailable,
                neuralEnginePreferred: runtimeStatus.coreMLAvailable,
                coreML: runtimeStatus.coreMLAvailable
            ),
            modelRepository: modelRepository,
            runtimeStatus: runtimeStatus
        )
        let presetManager = PresetManagerViewModel(
            catalog: presetCatalog,
            defaultStyles: defaultStyles
        )
        let dictionaryManager = DictionaryManagerViewModel(
            dictionary: SharedUserDictionaryStorage.load()
                ?? (try? FixtureBootstrap.loadDictionary())
                ?? UserDictionary(entries: [])
        )
        let settingsViewModel = SettingsViewModel(
            summary: "端末上のランタイム初期化は有効です。既定では端末内のネイティブ Style-Bert-VITS2 経路だけを使います。Mac の AivisSpeech Engine は開発用の比較確認として明示的に有効化した場合だけ使います。",
            runtimeStatus: runtimeStatus
        )
        let helpViewModel = HelpViewModel(
            summary: "読み上げを中心にしたモバイルシェルです。iOS と将来の Android 互換に向けてランタイム層を分離し、ネイティブ Style-Bert-VITS2 の入口を接続しています。"
        )

        if let firstPresetKey = presetCatalog.keys.first,
           let preset = presetCatalog.items[firstPresetKey] {
            talkEditor.applyPreset(preset, key: firstPresetKey)
            presetManager.selectPresetKey(firstPresetKey)
        }

        return AppViewModel(
            talkEditor: talkEditor,
            modelManager: modelManager,
            presetManager: presetManager,
            dictionaryManager: dictionaryManager,
            settingsViewModel: settingsViewModel,
            helpViewModel: helpViewModel,
            modelRepository: modelRepository,
            speechEngine: speechEngine
        )
    }

    func prepareRuntimeState() async {
        guard modelRepository != nil else {
            return
        }
        await modelManager.refreshFromRepository()
    }

    var exportedWAVByteCountLabel: String? {
        guard lastExportedWAVByteCount > 0 else {
            return nil
        }
        return ByteCountFormatter.string(fromByteCount: Int64(lastExportedWAVByteCount), countStyle: .file)
    }

    var playbackCurrentTimeLabel: String {
        Self.playbackTimeFormatter.string(from: playbackCurrentTime) ?? "0:00"
    }

    var playbackDurationLabel: String {
        Self.playbackTimeFormatter.string(from: playbackDuration) ?? "0:00"
    }

    var talkStyleOptions: [SpeechStyleOption] {
        let selectedVoice = talkEditor.selectedAudioItem?.voice
        let fallbackSpeakerID = selectedVoice?.speakerID ?? ""

        let manifestOptions = modelManager.activeModel?.manifest?.speakers.flatMap { speaker in
            speaker.styles.map { style in
                SpeechStyleOption(
                    speakerID: speaker.uuid.uuidString,
                    speakerName: speaker.name,
                    styleID: style.localID,
                    styleName: style.name,
                    modelName: modelManager.activeModel?.name
                )
            }
        } ?? []

        let descriptorOptions = modelManager.activeModel?.manifest?.runtimeDescriptor?.styleProfiles.map { style in
            SpeechStyleOption(
                speakerID: fallbackSpeakerID,
                speakerName: modelManager.activeModel?.manifest?.speakers.first?.name ?? "選択中の話者",
                styleID: style.localID,
                styleName: style.name,
                modelName: modelManager.activeModel?.name
            )
        } ?? []

        let options = manifestOptions.isEmpty ? descriptorOptions : manifestOptions
        guard let selectedVoice else { return options }

        if options.contains(where: { $0.speakerID == selectedVoice.speakerID && $0.styleID == selectedVoice.styleID })
            || options.contains(where: { $0.styleID == selectedVoice.styleID }) {
            return options
        }

        return [
            SpeechStyleOption(
                speakerID: selectedVoice.speakerID,
                speakerName: "現在の話者",
                styleID: selectedVoice.styleID,
                styleName: selectedVoice.styleID == 0 ? "Normal" : "Style ID \(selectedVoice.styleID)",
                modelName: nil
            ),
        ] + options
    }

    func selectTalkStyle(_ option: SpeechStyleOption) {
        talkEditor.updateStyle(option)
        clearPreviewArtifact()
        talkActionStatusMessage = "\(option.styleName) に切り替えました。"
    }

    func updateTalkText(_ value: String) {
        let selectedText = talkEditor.updateText(value)
        clearPreviewArtifact()
        talkActionStatusMessage = nil
        scheduleAutomaticQueryRefresh(for: selectedText)
    }

    func updateTalkPhraseAccent(phraseIndex: Int, accent: Int) {
        talkEditor.updatePhraseAccent(phraseIndex: phraseIndex, accent: accent)
        clearPreviewArtifact()
        talkActionStatusMessage = nil
    }

    func moveTalkPhraseAccent(phraseIndex: Int, delta: Int) {
        talkEditor.movePhraseAccent(phraseIndex: phraseIndex, delta: delta)
        clearPreviewArtifact()
        talkActionStatusMessage = nil
    }

    func splitTalkPhraseAfter(phraseIndex: Int, moraIndex: Int) {
        talkEditor.splitPhraseAfter(phraseIndex: phraseIndex, moraIndex: moraIndex)
        clearPreviewArtifact()
        talkActionStatusMessage = nil
    }

    func mergeTalkPhraseWithPrevious(phraseIndex: Int) {
        talkEditor.mergePhraseWithPrevious(phraseIndex: phraseIndex)
        clearPreviewArtifact()
        talkActionStatusMessage = nil
    }

    private func handleDictionaryDidChange() {
        talkEditor.invalidateAllQueries()
        clearPreviewArtifact()
        talkActionStatusMessage = "辞書を更新しました。必要な行は再生成されます。"
    }

    func regenerateTalkQuery() async {
        guard !isTalkActionRunning else { return }
        automaticQueryRefreshTask?.cancel()
        let trimmedText = talkEditor.currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            talkActionStatusMessage = "クエリを更新する前にテキストを入力してください。"
            return
        }

        isTalkActionRunning = true
        defer { isTalkActionRunning = false }

        do {
            let query: AudioQuery
            if let speechEngine, let styleID = talkEditor.selectedAudioItem?.voice.styleID {
                query = try await speechEngine.makeAudioQuery(text: trimmedText, styleID: styleID)
            } else {
                query = talkEditor.regenerateSelectedQuery(using: presetManager.selectedPreset)
            }

            talkEditor.replaceSelectedQuery(query, presetKey: presetManager.selectedPresetKey)
            clearPreviewArtifact()
            talkActionStatusMessage = "AudioQuery を現在のテキストで更新しました。"
        } catch {
            talkActionStatusMessage = error.localizedDescription
        }
    }

    private func scheduleAutomaticQueryRefresh(for text: String) {
        automaticQueryRefreshTask?.cancel()

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, speechEngine != nil else {
            return
        }

        automaticQueryRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 550_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            await self?.refreshTalkQueryAutomatically(expectedText: trimmedText)
        }
    }

    private func refreshTalkQueryAutomatically(expectedText: String) async {
        guard !isTalkActionRunning else {
            return
        }
        guard talkEditor.currentText.trimmingCharacters(in: .whitespacesAndNewlines) == expectedText else {
            return
        }
        guard let selectedItem = talkEditor.selectedAudioItem else {
            return
        }
        if let query = selectedItem.query,
           query.kana?.trimmingCharacters(in: .whitespacesAndNewlines) == expectedText,
           !query.accentPhrases.isEmpty {
            return
        }

        isTalkActionRunning = true
        defer { isTalkActionRunning = false }

        do {
            guard let speechEngine else { return }
            let regenerated = try await speechEngine.makeAudioQuery(text: expectedText, styleID: selectedItem.voice.styleID)

            guard talkEditor.currentText.trimmingCharacters(in: .whitespacesAndNewlines) == expectedText else {
                return
            }

            let previous = talkEditor.selectedAudioItem?.query
            let merged = Self.queryByPreservingControls(from: regenerated, previous: previous)
            talkEditor.replaceSelectedQuery(merged, presetKey: presetManager.selectedPresetKey)
            clearPreviewArtifact()
            talkActionStatusMessage = "AudioQuery を自動更新しました。"
        } catch {
            guard talkEditor.currentText.trimmingCharacters(in: .whitespacesAndNewlines) == expectedText else {
                return
            }
            talkActionStatusMessage = error.localizedDescription
        }
    }

    func testSynthesis() async {
        await exportCurrentTalkWAV(named: "preview", autoplay: true)
    }

    func exportTalkWAV() async {
        await exportCurrentTalkWAV(named: "export")
    }

    func exportAllTalkWAV() async {
        await exportAllTalkWAV(named: "all")
    }

    func togglePreviewPlayback() {
        if isPreviewPlaying {
            stopPreviewPlayback()
            talkActionStatusMessage = "プレビュー再生を停止しました。"
            return
        }

        startPreviewPlayback()
    }

    private func startPreviewPlayback() {
        guard let lastExportedWAVURL else {
            talkActionStatusMessage = "先にWAVプレビューを生成してください。"
            return
        }

        do {
            try configurePlaybackSession()
            let player = try AVAudioPlayer(contentsOf: lastExportedWAVURL)
            player.delegate = self
            player.prepareToPlay()
            playbackDuration = player.duration
            playbackCurrentTime = player.currentTime
            if player.play() {
                audioPlayer = player
                isPreviewPlaying = true
                startPlaybackTimer()
                talkActionStatusMessage = "プレビュー再生を開始しました。"
            } else {
                talkActionStatusMessage = "プレビュー再生を開始できませんでした。"
            }
        } catch {
            talkActionStatusMessage = error.localizedDescription
        }
    }

    private func exportCurrentTalkWAV(named prefix: String, autoplay: Bool = false) async {
        guard !isTalkActionRunning else { return }
        guard let selectedItem = talkEditor.selectedAudioItem else {
            talkActionStatusMessage = "先に読み上げ項目を選択してください。"
            return
        }
        guard !selectedItem.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            talkActionStatusMessage = "合成するテキストを入力してください。"
            return
        }

        isTalkActionRunning = true
        defer { isTalkActionRunning = false }

        do {
            let query = try await ensuredSelectedQuery(for: selectedItem)
            let wavData = try await synthesizeWAVData(query: query, styleID: selectedItem.voice.styleID)
            let exportDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("AivisSpeechMobileExports", isDirectory: true)
            try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

            let fileName = "\(prefix)-\(talkEditor.selectedAudioKey ?? "selected")-\(UUID().uuidString.prefix(8)).wav"
            let outputURL = exportDirectory.appendingPathComponent(fileName)
            try wavData.write(to: outputURL, options: .atomic)

            stopPreviewPlayback()
            lastExportedWAVURL = outputURL
            lastExportedWAVByteCount = wavData.count
            refreshPlaybackMetadata(for: outputURL)
            talkActionStatusMessage = "WAVを生成しました: \(outputURL.lastPathComponent)"
            if autoplay {
                startPreviewPlayback()
            }
        } catch {
            talkActionStatusMessage = error.localizedDescription
        }
    }

    private func exportAllTalkWAV(named prefix: String) async {
        guard !isTalkActionRunning else { return }

        let exportRows = talkEditor.availableAudioKeys.compactMap { key -> (key: String, item: AudioItem)? in
            guard let item = talkEditor.project.talk.audioItems[key],
                  !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return (key, item)
        }

        guard !exportRows.isEmpty else {
            talkActionStatusMessage = "書き出すテキスト行がありません。"
            return
        }

        isTalkActionRunning = true
        defer { isTalkActionRunning = false }

        do {
            var wavs: [Data] = []
            wavs.reserveCapacity(exportRows.count)

            for row in exportRows {
                let query = try await ensuredTalkQuery(for: row.key, item: row.item)
                let currentItem = talkEditor.project.talk.audioItems[row.key] ?? row.item
                let wavData = try await synthesizeWAVData(query: query, styleID: currentItem.voice.styleID)
                wavs.append(wavData)
            }

            let wavData = try WAVDataConcatenator.concatenate(wavs)
            let exportDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("AivisSpeechMobileExports", isDirectory: true)
            try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

            let fileName = "\(prefix)-talk-\(UUID().uuidString.prefix(8)).wav"
            let outputURL = exportDirectory.appendingPathComponent(fileName)
            try wavData.write(to: outputURL, options: .atomic)

            stopPreviewPlayback()
            lastExportedWAVURL = outputURL
            lastExportedWAVByteCount = wavData.count
            refreshPlaybackMetadata(for: outputURL)
            talkActionStatusMessage = "全行WAVを生成しました: \(outputURL.lastPathComponent)"
        } catch {
            talkActionStatusMessage = error.localizedDescription
        }
    }

    private func ensuredSelectedQuery(for item: AudioItem) async throws -> AudioQuery {
        if let key = talkEditor.selectedAudioKey {
            return try await ensuredTalkQuery(for: key, item: item)
        }

        return try await makeCurrentQuery(for: item)
    }

    private func ensuredTalkQuery(for key: String, item: AudioItem) async throws -> AudioQuery {
        if let query = item.query,
           query.kana?.trimmingCharacters(in: .whitespacesAndNewlines) == item.text.trimmingCharacters(in: .whitespacesAndNewlines),
           !query.accentPhrases.isEmpty {
            return query
        }

        let query = try await makeCurrentQuery(for: item)
        talkEditor.replaceQuery(query, presetKey: item.presetKey, for: key)
        return query
    }

    private func makeCurrentQuery(for item: AudioItem) async throws -> AudioQuery {
        let regenerated: AudioQuery
        if let speechEngine {
            regenerated = try await speechEngine.makeAudioQuery(text: item.text, styleID: item.voice.styleID)
        } else {
            regenerated = TalkEditorViewModel.fallbackQuery(text: item.text)
        }

        let merged = Self.queryByPreservingControls(from: regenerated, previous: item.query)
        return merged
    }

    private func synthesizeWAVData(query: AudioQuery, styleID: Int) async throws -> Data {
        if let speechEngine {
            return try await speechEngine.synthesize(query: query, styleID: styleID)
        }
        throw AppViewModelError.runtimeUnavailable
    }

    private static func queryByPreservingControls(from regenerated: AudioQuery, previous: AudioQuery?) -> AudioQuery {
        guard let previous else {
            return regenerated
        }

        var query = regenerated
        query.speedScale = previous.speedScale
        query.intonationScale = previous.intonationScale
        query.tempoDynamicsScale = previous.tempoDynamicsScale
        query.pitchScale = previous.pitchScale
        query.volumeScale = previous.volumeScale
        query.pauseLengthScale = previous.pauseLengthScale
        query.prePhonemeLength = previous.prePhonemeLength
        query.postPhonemeLength = previous.postPhonemeLength
        query.outputSamplingRate = previous.outputSamplingRate
        query.outputStereo = previous.outputStereo
        return query
    }

    private func clearPreviewArtifact() {
        stopPreviewPlayback()
        lastExportedWAVURL = nil
        lastExportedWAVByteCount = 0
        playbackCurrentTime = 0
        playbackDuration = 0
    }

    func seekPreview(to time: TimeInterval) {
        let clamped = min(max(time, 0), max(playbackDuration, 0))
        playbackCurrentTime = clamped
        audioPlayer?.currentTime = clamped
    }

    private func stopPreviewPlayback(resetPosition: Bool = false) {
        audioPlayer?.stop()
        audioPlayer = nil
        isPreviewPlaying = false
        stopPlaybackTimer()
        if resetPosition {
            playbackCurrentTime = 0
        }
    }

    private func configurePlaybackSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [])
        try session.setActive(true)
        #endif
    }

    private func refreshPlaybackMetadata(for url: URL) {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            playbackDuration = player.duration
            playbackCurrentTime = 0
        } catch {
            playbackDuration = 0
            playbackCurrentTime = 0
        }
    }

    private func startPlaybackTimer() {
        stopPlaybackTimer()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.audioPlayer else { return }
                self.playbackCurrentTime = player.currentTime
                self.playbackDuration = player.duration
            }
        }
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private static func previewInstalledModels() -> [InstalledModel] {
        let fixtureManifest = try? FixtureBootstrap.loadAIVMXMetadataEnvelope().manifest
        let speakerUUID = fixtureManifest?.speakers.first?.uuid
            ?? UUID(uuidString: "2d8f6f95-3369-4af7-b0bd-a6310c5d5230")
            ?? UUID()
        let styles = fixtureManifest?.speakers.first?.styles.map {
            ModelStyle(localID: $0.localId, name: $0.name)
        } ?? [ModelStyle(localID: 0, name: "Normal")]
        let speakers = [
            ModelSpeaker(uuid: speakerUUID, name: fixtureManifest?.speakers.first?.name ?? "Sample Speaker", styles: styles)
        ]
        let primaryManifest = ModelManifest(
            uuid: fixtureManifest?.uuid ?? UUID(uuidString: "4c9ca6f3-7d9f-4093-a8dd-f87f0d7c2724") ?? UUID(),
            name: fixtureManifest?.name ?? "Sample Voice Model",
            version: fixtureManifest?.version ?? "1.0.0",
            modelArchitecture: fixtureManifest?.modelArchitecture.rawValue ?? "Style-Bert-VITS2",
            modelFormat: fixtureManifest?.modelFormat.rawValue ?? "AIVMX",
            speakers: speakers
        )
        let secondaryManifest = ModelManifest(
            uuid: UUID(uuidString: "6ad4f1d8-024a-4dc7-b0d8-24bce9822489") ?? UUID(),
            name: "Misty Narrator",
            version: "0.9.2",
            modelArchitecture: primaryManifest.modelArchitecture,
            modelFormat: primaryManifest.modelFormat,
            speakers: speakers
        )

        return [
            InstalledModel(
                id: primaryManifest.uuid,
                name: primaryManifest.name,
                version: primaryManifest.version,
                sourceURL: URL(string: "https://example.com/\(primaryManifest.name).aivmx"),
                loadState: .active,
                manifest: primaryManifest
            ),
            InstalledModel(
                id: secondaryManifest.uuid,
                name: secondaryManifest.name,
                version: secondaryManifest.version,
                sourceURL: URL(string: "https://example.com/\(secondaryManifest.name).aivmx"),
                loadState: .loaded,
                manifest: secondaryManifest
            ),
        ]
    }

    private static func emptyTalkProjectDocument(voice: VoiceReference) -> AISPProjectDocument {
        let item = AudioItem(text: "", voice: voice, query: nil, presetKey: "default-normal")
        return AISPProjectDocument(
            appVersion: "1.1.0-dev",
            talk: TalkProject(audioKeys: ["audio-1"], audioItems: ["audio-1": item]),
            song: .empty
        )
    }
}

extension AppViewModel: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let duration = player.duration
        Task { @MainActor [weak self, duration] in
            self?.stopPlaybackTimer()
            self?.playbackCurrentTime = duration
            self?.playbackDuration = duration
            self?.isPreviewPlaying = false
            self?.audioPlayer = nil
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor [weak self] in
            self?.stopPlaybackTimer()
            self?.isPreviewPlaying = false
            self?.audioPlayer = nil
            if let error {
                self?.talkActionStatusMessage = error.localizedDescription
            }
        }
    }
}

private extension EngineRuntimeStatus {
    static let preview = EngineRuntimeStatus(
        providerName: "ONNX Runtime Mobile",
        availability: .unavailable,
        preferredExecutionProvider: "CoreML planned",
        linkedVersion: nil,
        coreMLAvailable: true,
        notes: ["ランタイム注入なしのプレビューブートストラップです"]
    )
}

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case talk
    case models
    case presets
    case dictionary
    case settings
    case help

    var id: String { rawValue }

    var title: String {
        switch self {
        case .talk:
            return "読み上げ"
        case .models:
            return "モデル"
        case .presets:
            return "プリセット"
        case .dictionary:
            return "辞書"
        case .settings:
            return "設定"
        case .help:
            return "ヘルプ"
        }
    }

    var systemImage: String {
        switch self {
        case .talk:
            return "waveform"
        case .models:
            return "cube.box.fill"
        case .presets:
            return "slider.horizontal.below.square.filled.and.square"
        case .dictionary:
            return "text.book.closed.fill"
        case .settings:
            return "gearshape.fill"
        case .help:
            return "questionmark.circle.fill"
        }
    }
}

struct SpeechStyleOption: Identifiable, Equatable, Hashable {
    var id: String { "\(speakerID):\(styleID)" }
    let speakerID: String
    let speakerName: String
    let styleID: Int
    let styleName: String
    let modelName: String?
}

struct AccentMoraEditorItem: Identifiable, Equatable, Hashable {
    var id: String { "\(phraseIndex)-\(moraIndex)" }
    let phraseIndex: Int
    let moraIndex: Int
    let text: String
    let isHighTone: Bool
    let pitch: Double
    let consonantLength: Double?
    let vowelLength: Double
}

struct AccentPhraseEditorItem: Identifiable, Equatable, Hashable {
    var id: Int { phraseIndex }
    let phraseIndex: Int
    let text: String
    let accent: Int
    let moraCount: Int
    let hasPause: Bool
    let pauseLength: Double?
    let moras: [AccentMoraEditorItem]
}

struct TalkAudioRow: Identifiable, Equatable, Hashable {
    var id: String { key }
    let key: String
    let lineNumber: Int
    let text: String
    let styleID: Int
    let presetKey: String?
}

@MainActor
final class TalkEditorViewModel: ObservableObject {
    @Published var project: AISPProjectDocument
    @Published var selectedAudioKey: String?

    init(project: AISPProjectDocument, selectedAudioKey: String? = nil) {
        self.project = project
        self.selectedAudioKey = selectedAudioKey ?? project.talk.audioKeys.first
    }

    var availableAudioKeys: [String] {
        project.talk.audioKeys
    }

    var activeAudioItems: [AudioItem] {
        project.talk.audioKeys.compactMap { project.talk.audioItems[$0] }
    }

    var audioRows: [TalkAudioRow] {
        project.talk.audioKeys.enumerated().compactMap { offset, key in
            guard let item = project.talk.audioItems[key] else { return nil }
            return TalkAudioRow(
                key: key,
                lineNumber: offset + 1,
                text: item.text,
                styleID: item.voice.styleID,
                presetKey: item.presetKey
            )
        }
    }

    var selectedAudioItem: AudioItem? {
        guard let selectedAudioKey else { return nil }
        return project.talk.audioItems[selectedAudioKey]
    }

    var selectedQuery: AudioQuery? {
        selectedAudioItem?.query
    }

    var currentText: String {
        selectedAudioItem?.text ?? ""
    }

    var currentVoiceLabel: String {
        guard let voice = selectedAudioItem?.voice else {
            return "音声未選択"
        }
        return "Style ID \(voice.styleID)"
    }

    var currentStyleID: Int? {
        selectedAudioItem?.voice.styleID
    }

    var currentPresetKey: String {
        presetLabel(for: selectedAudioItem?.presetKey)
    }

    func presetLabel(for key: String?) -> String {
        guard let key else {
            return "手動"
        }
        if key == "manual" {
            return "手動"
        }
        if key == "default-normal" {
            return "Normal"
        }
        return key
    }

    var kanaPreview: String {
        selectedQuery?.kana ?? currentText
    }

    var moraCount: Int {
        selectedQuery?.accentPhrases.reduce(0) { $0 + $1.moras.count } ?? 0
    }

    var accentPreview: [String] {
        selectedQuery?.accentPhrases.map { phrase in
            let text = phrase.moras.map(\.text).joined()
            return "\(text) / アクセント \(phrase.accent)"
        } ?? []
    }

    var accentEditorItems: [AccentPhraseEditorItem] {
        guard let phrases = selectedQuery?.accentPhrases else {
            return []
        }
        return phrases.enumerated().map { phraseIndex, phrase in
            AccentPhraseEditorItem(
                phraseIndex: phraseIndex,
                text: phrase.moras.map(\.text).joined(),
                accent: phrase.accent,
                moraCount: phrase.moras.count,
                hasPause: phrase.pauseMora != nil,
                pauseLength: phrase.pauseMora?.vowelLength,
                moras: phrase.moras.enumerated().map { moraIndex, mora in
                    AccentMoraEditorItem(
                        phraseIndex: phraseIndex,
                        moraIndex: moraIndex,
                        text: mora.text,
                        isHighTone: Self.isHighTone(moraIndex: moraIndex, accent: phrase.accent),
                        pitch: mora.pitch,
                        consonantLength: mora.consonantLength,
                        vowelLength: mora.vowelLength
                    )
                }
            )
        }
    }

    func selectAudioKey(_ key: String) {
        guard project.talk.audioItems[key] != nil else { return }
        selectedAudioKey = key
    }

    @discardableResult
    func updateText(_ value: String) -> String {
        let texts = Self.splitTextWhenPasteLikeDesktop(value)
        if texts.count >= 2 {
            putSplitTexts(texts)
            return currentText
        }

        mutateSelectedItem { item in
            item.text = value
            item.query?.kana = value
            item.query?.accentPhrases = []
        }
        return value
    }

    func addAudioItemAfterSelection() {
        let key = ensureSelectedAudioKey()
        let base = project.talk.audioItems[key]
        let newKey = nextAudioKey()
        project.talk.audioItems[newKey] = Self.audioItem(
            text: "",
            inheritingFrom: base
        )
        insertAudioKey(newKey, after: key)
        selectedAudioKey = newKey
    }

    func duplicateSelectedAudioItem() {
        guard let key = selectedAudioKey,
              let item = project.talk.audioItems[key] else {
            return
        }
        let newKey = nextAudioKey()
        project.talk.audioItems[newKey] = item
        insertAudioKey(newKey, after: key)
        selectedAudioKey = newKey
    }

    func deleteSelectedAudioItem() {
        guard let key = selectedAudioKey,
              let index = project.talk.audioKeys.firstIndex(of: key),
              project.talk.audioKeys.count > 1 else {
            return
        }

        project.talk.audioItems.removeValue(forKey: key)
        project.talk.audioKeys.remove(at: index)
        let nextIndex = min(index, project.talk.audioKeys.count - 1)
        selectedAudioKey = project.talk.audioKeys[safe: nextIndex]
    }

    func moveSelectedAudioItem(offset: Int) {
        guard let key = selectedAudioKey,
              let index = project.talk.audioKeys.firstIndex(of: key) else {
            return
        }
        let destination = index + offset
        guard project.talk.audioKeys.indices.contains(destination) else {
            return
        }
        project.talk.audioKeys.remove(at: index)
        project.talk.audioKeys.insert(key, at: destination)
    }

    func updateSpeedScale(_ value: Double) {
        mutateSelectedQuery { $0.speedScale = value }
    }

    func updateIntonationScale(_ value: Double) {
        mutateSelectedQuery { $0.intonationScale = value }
    }

    func updatePhraseAccent(phraseIndex: Int, accent: Int) {
        mutateSelectedQuery { query in
            guard query.accentPhrases.indices.contains(phraseIndex) else { return }
            let moraCount = query.accentPhrases[phraseIndex].moras.count
            guard moraCount > 0 else { return }
            query.accentPhrases[phraseIndex].accent = min(max(accent, 1), moraCount)
        }
    }

    func movePhraseAccent(phraseIndex: Int, delta: Int) {
        guard let phrase = selectedQuery?.accentPhrases[safe: phraseIndex] else { return }
        updatePhraseAccent(phraseIndex: phraseIndex, accent: phrase.accent + delta)
    }

    func splitPhraseAfter(phraseIndex: Int, moraIndex: Int) {
        mutateSelectedQuery { query in
            guard query.accentPhrases.indices.contains(phraseIndex) else { return }
            let phrase = query.accentPhrases[phraseIndex]
            guard phrase.moras.indices.contains(moraIndex),
                  moraIndex < phrase.moras.index(before: phrase.moras.endIndex) else {
                return
            }

            let splitIndex = moraIndex + 1
            let firstMoras = Array(phrase.moras[..<splitIndex])
            let secondMoras = Array(phrase.moras[splitIndex...])
            let firstAccent = min(max(phrase.accent, 1), firstMoras.count)
            let secondAccent = phrase.accent > splitIndex
                ? min(max(phrase.accent - splitIndex, 1), secondMoras.count)
                : min(max(1, secondMoras.count / 2), secondMoras.count)
            let first = AccentPhrase(
                moras: firstMoras,
                accent: firstAccent
            )
            let second = AccentPhrase(
                moras: secondMoras,
                accent: secondAccent,
                pauseMora: phrase.pauseMora,
                isInterrogative: phrase.isInterrogative
            )
            query.accentPhrases.replaceSubrange(phraseIndex...phraseIndex, with: [first, second])
        }
    }

    func mergePhraseWithPrevious(phraseIndex: Int) {
        mutateSelectedQuery { query in
            guard query.accentPhrases.indices.contains(phraseIndex),
                  phraseIndex > query.accentPhrases.startIndex else {
                return
            }
            let previousIndex = query.accentPhrases.index(before: phraseIndex)
            let previous = query.accentPhrases[previousIndex]
            let current = query.accentPhrases[phraseIndex]
            let mergedMoras = previous.moras + current.moras
            let mergedAccent = min(max(previous.accent, 1), mergedMoras.count)
            let merged = AccentPhrase(
                moras: mergedMoras,
                accent: mergedAccent,
                pauseMora: current.pauseMora,
                isInterrogative: current.isInterrogative
            )
            query.accentPhrases.replaceSubrange(previousIndex...phraseIndex, with: [merged])
        }
    }

    func updateTempoDynamicsScale(_ value: Double) {
        mutateSelectedQuery { $0.tempoDynamicsScale = value }
    }

    func updatePitchScale(_ value: Double) {
        mutateSelectedQuery { $0.pitchScale = value }
    }

    func updateVolumeScale(_ value: Double) {
        mutateSelectedQuery { $0.volumeScale = value }
    }

    func updatePauseLengthScale(_ value: Double) {
        mutateSelectedQuery { $0.pauseLengthScale = value }
    }

    func updatePrePhonemeLength(_ value: Double) {
        mutateSelectedQuery { $0.prePhonemeLength = value }
    }

    func updatePostPhonemeLength(_ value: Double) {
        mutateSelectedQuery { $0.postPhonemeLength = value }
    }

    func updateMoraPitch(phraseIndex: Int, moraIndex: Int, pitch: Double) {
        mutateMora(phraseIndex: phraseIndex, moraIndex: moraIndex) { mora in
            mora.pitch = pitch
        }
    }

    func updateMoraVowelLength(phraseIndex: Int, moraIndex: Int, length: Double) {
        mutateMora(phraseIndex: phraseIndex, moraIndex: moraIndex) { mora in
            mora.vowelLength = length
        }
    }

    func updateMoraConsonantLength(phraseIndex: Int, moraIndex: Int, length: Double) {
        mutateMora(phraseIndex: phraseIndex, moraIndex: moraIndex) { mora in
            guard mora.consonantLength != nil else { return }
            mora.consonantLength = length
        }
    }

    func updatePauseMoraLength(phraseIndex: Int, length: Double) {
        mutateSelectedQuery { query in
            guard query.accentPhrases.indices.contains(phraseIndex),
                  query.accentPhrases[phraseIndex].pauseMora != nil else {
                return
            }
            query.accentPhrases[phraseIndex].pauseMora?.vowelLength = length
        }
    }

    func useStandardPauseForSelectedLine() {
        mutateSelectedQuery { query in
            query.pauseLengthScale = 1.0
            query.prePhonemeLength = 0.1
            query.postPhonemeLength = 0.1
        }
    }

    func useLongerPauseForSelectedLine() {
        mutateSelectedQuery { query in
            query.pauseLengthScale = 1.25
            query.prePhonemeLength = 0.15
            query.postPhonemeLength = 0.35
        }
    }

    func updateStyle(_ option: SpeechStyleOption) {
        mutateSelectedItem { item in
            item.voice = VoiceReference(
                engineID: item.voice.engineID,
                speakerID: option.speakerID,
                styleID: option.styleID
            )
        }
    }

    func updateStereo(_ enabled: Bool) {
        mutateSelectedQuery { $0.outputStereo = enabled }
    }

    func applyPreset(_ preset: Preset, key: String) {
        mutateSelectedItem { item in
            var query = item.query ?? AudioQuery(
                accentPhrases: [],
                speedScale: 1.0,
                intonationScale: 1.0,
                tempoDynamicsScale: 1.0,
                pitchScale: 0.0,
                volumeScale: 1.0,
                pauseLengthScale: 1.0,
                prePhonemeLength: 0.1,
                postPhonemeLength: 0.1,
                outputSamplingRate: .explicit(44_100),
                outputStereo: false,
                kana: item.text
            )
            query.speedScale = preset.speedScale
            query.intonationScale = preset.intonationScale
            query.tempoDynamicsScale = preset.tempoDynamicsScale
            query.pitchScale = preset.pitchScale
            query.volumeScale = preset.volumeScale
            query.pauseLengthScale = preset.pauseLengthScale
            query.prePhonemeLength = preset.prePhonemeLength
            query.postPhonemeLength = preset.postPhonemeLength
            item.query = query
            item.presetKey = key
        }
    }

    @discardableResult
    func regenerateSelectedQuery(using preset: Preset? = nil) -> AudioQuery {
        let item = selectedAudioItem ?? AudioItem(
            text: "",
            voice: VoiceReference(engineID: "", speakerID: "", styleID: 0)
        )
        let query = Self.generatedQuery(
            text: item.text,
            existingQuery: item.query,
            preset: preset
        )
        replaceSelectedQuery(query, presetKey: preset != nil ? (selectedAudioItem?.presetKey ?? "manual") : selectedAudioItem?.presetKey)
        return query
    }

    func replaceSelectedQuery(_ query: AudioQuery, presetKey: String?) {
        guard let selectedAudioKey else {
            mutateSelectedItem { item in
                item.query = query
                if let presetKey {
                    item.presetKey = presetKey
                } else if item.presetKey == nil {
                    item.presetKey = "manual"
                }
            }
            return
        }
        replaceQuery(query, presetKey: presetKey, for: selectedAudioKey)
    }

    func replaceQuery(_ query: AudioQuery, presetKey: String?, for key: String) {
        guard var item = project.talk.audioItems[key] else {
            return
        }
        item.query = query
        if let presetKey {
            item.presetKey = presetKey
        } else if item.presetKey == nil {
            item.presetKey = "manual"
        }
        project.talk.audioItems[key] = item
    }

    func invalidateAllQueries() {
        for key in project.talk.audioKeys {
            guard var item = project.talk.audioItems[key],
                  let query = item.query else {
                continue
            }

            item.query = AudioQuery(
                accentPhrases: [],
                speedScale: query.speedScale,
                intonationScale: query.intonationScale,
                tempoDynamicsScale: query.tempoDynamicsScale,
                pitchScale: query.pitchScale,
                volumeScale: query.volumeScale,
                pauseLengthScale: query.pauseLengthScale,
                prePhonemeLength: query.prePhonemeLength,
                postPhonemeLength: query.postPhonemeLength,
                outputSamplingRate: query.outputSamplingRate,
                outputStereo: query.outputStereo,
                kana: item.text
            )
            project.talk.audioItems[key] = item
        }
    }

    private func mutateSelectedItem(_ update: (inout AudioItem) -> Void) {
        let key: String
        if let selectedAudioKey, project.talk.audioItems[selectedAudioKey] != nil {
            key = selectedAudioKey
        } else {
            key = nextAudioKey()
            selectedAudioKey = key
            project.talk.audioKeys.append(key)
            project.talk.audioItems[key] = AudioItem(
                text: "",
                voice: VoiceReference(engineID: "", speakerID: "", styleID: 0),
                query: Self.fallbackQuery(text: ""),
                presetKey: "manual"
            )
        }
        guard var item = project.talk.audioItems[key] else { return }
        update(&item)
        project.talk.audioItems[key] = item
    }

    private func mutateSelectedQuery(_ update: (inout AudioQuery) -> Void) {
        mutateSelectedItem { item in
            guard var query = item.query else { return }
            update(&query)
            item.query = query
        }
    }

    private func mutateMora(phraseIndex: Int, moraIndex: Int, update: (inout Mora) -> Void) {
        mutateSelectedQuery { query in
            guard query.accentPhrases.indices.contains(phraseIndex),
                  query.accentPhrases[phraseIndex].moras.indices.contains(moraIndex) else {
                return
            }
            update(&query.accentPhrases[phraseIndex].moras[moraIndex])
        }
    }

    private func putSplitTexts(_ texts: [String]) {
        guard !texts.isEmpty else { return }

        let selectedKey = ensureSelectedAudioKey()
        let baseItem = project.talk.audioItems[selectedKey]
        var textsToInsert = texts

        if let first = textsToInsert.first {
            mutateSelectedItem { item in
                item.text = first
                item.query = Self.generatedQuery(text: first, existingQuery: item.query, preset: nil)
            }
            textsToInsert.removeFirst()
        }

        var previousKey = selectedKey
        for text in textsToInsert {
            let key = nextAudioKey()
            project.talk.audioItems[key] = Self.audioItem(
                text: text,
                inheritingFrom: baseItem ?? project.talk.audioItems[selectedKey]
            )
            insertAudioKey(key, after: previousKey)
            previousKey = key
        }

        selectedAudioKey = previousKey
    }

    private func ensureSelectedAudioKey() -> String {
        if let selectedAudioKey, project.talk.audioItems[selectedAudioKey] != nil {
            return selectedAudioKey
        }

        let key = nextAudioKey()
        selectedAudioKey = key
        project.talk.audioKeys.append(key)
        project.talk.audioItems[key] = Self.audioItem(text: "", inheritingFrom: nil)
        return key
    }

    private func insertAudioKey(_ key: String, after previousKey: String) {
        let index = project.talk.audioKeys.firstIndex(of: previousKey)
            .map { project.talk.audioKeys.index(after: $0) }
            ?? project.talk.audioKeys.endIndex
        project.talk.audioKeys.insert(key, at: index)
    }

    private static func audioItem(text: String, inheritingFrom baseItem: AudioItem?) -> AudioItem {
        let voice = baseItem?.voice ?? VoiceReference(engineID: "", speakerID: "", styleID: 0)
        let query = generatedQuery(text: text, existingQuery: baseItem?.query, preset: nil)
        return AudioItem(
            text: text,
            voice: voice,
            query: query,
            presetKey: baseItem?.presetKey ?? "manual",
            morphingInfo: baseItem?.morphingInfo
        )
    }

    private static func generatedQuery(
        text: String,
        existingQuery: AudioQuery?,
        preset: Preset?
    ) -> AudioQuery {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseQuery = existingQuery ?? AudioQuery(
            accentPhrases: [],
            speedScale: 1.0,
            intonationScale: 1.0,
            tempoDynamicsScale: 1.0,
            pitchScale: 0.0,
            volumeScale: 1.0,
            pauseLengthScale: 1.0,
            prePhonemeLength: 0.1,
            postPhonemeLength: 0.1,
            outputSamplingRate: .explicit(44_100),
            outputStereo: false,
            kana: text
        )

        let existingMatchesText = baseQuery.kana?.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedText
        let accentPhrases = trimmedText.isEmpty || !existingMatchesText ? [] : baseQuery.accentPhrases
        let kana = trimmedText.isEmpty ? "" : text

        return AudioQuery(
            accentPhrases: accentPhrases,
            speedScale: preset?.speedScale ?? baseQuery.speedScale,
            intonationScale: preset?.intonationScale ?? baseQuery.intonationScale,
            tempoDynamicsScale: preset?.tempoDynamicsScale ?? baseQuery.tempoDynamicsScale,
            pitchScale: preset?.pitchScale ?? baseQuery.pitchScale,
            volumeScale: preset?.volumeScale ?? baseQuery.volumeScale,
            pauseLengthScale: preset?.pauseLengthScale ?? baseQuery.pauseLengthScale,
            prePhonemeLength: preset?.prePhonemeLength ?? baseQuery.prePhonemeLength,
            postPhonemeLength: preset?.postPhonemeLength ?? baseQuery.postPhonemeLength,
            outputSamplingRate: baseQuery.outputSamplingRate,
            outputStereo: baseQuery.outputStereo,
            kana: kana
        )
    }

    private func nextAudioKey() -> String {
        var index = project.talk.audioKeys.count + 1
        var key = "audio-\(index)"
        while project.talk.audioItems[key] != nil {
            index += 1
            key = "audio-\(index)"
        }
        return key
    }

    static func fallbackQuery(text: String) -> AudioQuery {
        generatedQuery(text: text, existingQuery: nil, preset: nil)
    }

    static func splitTextWhenPasteLikeDesktop(_ text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func isHighTone(moraIndex: Int, accent: Int) -> Bool {
        let accentIndex = max(0, accent - 1)
        if moraIndex == 0 && accentIndex != 0 {
            return false
        }
        return moraIndex <= accentIndex
    }

}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

@MainActor
final class ModelManagerViewModel: ObservableObject {
    @Published var installedModels: [InstalledModel]
    @Published var inspectionByModelID: [UUID: ModelInspectionSummary]
    @Published var busyModelID: UUID?
    @Published var statusMessage: String?
    let supportedDevices: SupportedDevices
    let runtimeStatus: EngineRuntimeStatus
    private let modelRepository: (any ModelRepository)?
    private let inspectableRepository: (any InspectableModelRepository)?

    init(
        installedModels: [InstalledModel],
        supportedDevices: SupportedDevices,
        modelRepository: (any ModelRepository)? = nil,
        runtimeStatus: EngineRuntimeStatus
    ) {
        self.installedModels = installedModels
        self.inspectionByModelID = [:]
        self.busyModelID = nil
        self.supportedDevices = supportedDevices
        self.modelRepository = modelRepository
        self.inspectableRepository = modelRepository as? any InspectableModelRepository
        self.runtimeStatus = runtimeStatus
    }

    var loadedModelCount: Int {
        installedModels.filter { $0.loadState != .installed }.count
    }

    var activeModel: InstalledModel? {
        installedModels.first { $0.loadState == .active }
    }

    func promoteModel(_ id: UUID) async {
        await activateModel(id)
    }

    func activateModel(_ id: UUID) async {
        guard busyModelID == nil else { return }
        busyModelID = id
        defer { busyModelID = nil }

        if let modelRepository {
            do {
                try await modelRepository.activateModel(id: id)
                try await reloadInstalledModels()
                try await refreshInspection(for: id)
                statusMessage = nil
                return
            } catch {
                statusMessage = error.localizedDescription
            }
        }

        installedModels = installedModels.map { model in
            var mutableModel = model
            if model.id == id {
                mutableModel.loadState = .active
            } else if model.loadState == .active {
                mutableModel.loadState = .loaded
            }
            return mutableModel
        }
    }

    func loadModel(_ id: UUID) async {
        guard busyModelID == nil else { return }
        busyModelID = id
        defer { busyModelID = nil }

        guard let modelRepository else { return }
        do {
            try await modelRepository.loadModel(id: id)
            try await reloadInstalledModels()
            try await refreshInspection(for: id)
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func unloadModel(_ id: UUID) async {
        guard busyModelID == nil else { return }
        busyModelID = id
        defer { busyModelID = nil }

        guard let modelRepository else { return }
        do {
            try await modelRepository.unloadModel(id: id)
            inspectionByModelID[id] = nil
            try await reloadInstalledModels()
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func replaceInstalledModels(_ models: [InstalledModel]) {
        installedModels = models
    }

    func refreshFromRepository() async {
        guard modelRepository != nil else {
            return
        }
        do {
            try await reloadInstalledModels()
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    var seededRepositoryNotice: String {
        "同梱シードモデルでリポジトリと ONNX セッションの接続を検証しています。読み上げ出力は必要に応じてプレビュー波形経路を使います。"
    }

    func importModel(from fileURL: URL) async {
        guard busyModelID == nil else { return }
        guard let modelRepository else {
            statusMessage = "モデルリポジトリが接続されていません。"
            return
        }

        let accessedSecurityScope = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScope {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        busyModelID = UUID()
        defer { busyModelID = nil }

        do {
            _ = try await modelRepository.installModel(fromFile: fileURL)
            try await reloadInstalledModels()
            statusMessage = "\(fileURL.lastPathComponent) を読み込みました。"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func reloadInstalledModels() async throws {
        guard let modelRepository else { return }
        installedModels = try await modelRepository.installedModels()
    }

    private func refreshInspection(for id: UUID) async throws {
        guard let inspectableRepository else { return }
        inspectionByModelID[id] = try await inspectableRepository.inspection(for: id)
    }
}

@MainActor
final class PresetManagerViewModel: ObservableObject {
    @Published var catalog: PresetCatalog
    @Published var defaultStyles: [DefaultStyleID]
    @Published var selectedPresetKey: String?

    init(catalog: PresetCatalog, defaultStyles: [DefaultStyleID]) {
        self.catalog = catalog
        self.defaultStyles = defaultStyles
        self.selectedPresetKey = catalog.keys.first
    }

    var selectedPreset: Preset? {
        guard let selectedPresetKey else { return nil }
        return catalog.items[selectedPresetKey]
    }

    func selectPresetKey(_ key: String) {
        selectedPresetKey = key
    }
}

@MainActor
final class DictionaryManagerViewModel: ObservableObject {
    @Published var dictionary: UserDictionary
    @Published var searchText = ""
    @Published var editingEntryID: UUID?
    @Published var editorSurface = ""
    @Published var editorPronunciation = ""
    @Published var editorAccentType = 1
    @Published var editorWordType: UserDictionaryEntry.WordType = .properNoun
    @Published var editorPriority = 5
    @Published var statusMessage: String?
    var onDictionaryDidChange: (() -> Void)?
    private let persist: (UserDictionary) throws -> Void

    init(
        dictionary: UserDictionary,
        persist: @escaping (UserDictionary) throws -> Void = { try SharedUserDictionaryStorage.save($0) }
    ) {
        self.dictionary = dictionary
        self.persist = persist
    }

    var filteredEntries: [UserDictionaryEntry] {
        guard !searchText.isEmpty else { return dictionary.entries }
        return dictionary.entries.filter {
            $0.surface.localizedCaseInsensitiveContains(searchText)
                || $0.pronunciation.localizedCaseInsensitiveContains(searchText)
        }
    }

    var isEditingExistingEntry: Bool {
        editingEntryID != nil
    }

    var editorAccentPreviewItem: AccentPhraseEditorItem? {
        let pronunciation = normalizedPronunciation(editorPronunciation)
        let moraTexts = Self.previewMoraTexts(from: pronunciation)
        guard !moraTexts.isEmpty else {
            return nil
        }
        let accent = clampedAccentType(for: moraTexts.count)
        return AccentPhraseEditorItem(
            phraseIndex: 0,
            text: pronunciation,
            accent: accent,
            moraCount: moraTexts.count,
            hasPause: false,
            pauseLength: nil,
            moras: moraTexts.enumerated().map { index, text in
                AccentMoraEditorItem(
                    phraseIndex: 0,
                    moraIndex: index,
                    text: text,
                    isHighTone: Self.isHighTone(moraIndex: index, accent: accent),
                    pitch: 1.0,
                    consonantLength: nil,
                    vowelLength: 0.12
                )
            }
        )
    }

    var editorAccentRange: ClosedRange<Int> {
        let moraCount = editorAccentPreviewItem?.moraCount ?? 1
        return 1...max(1, moraCount)
    }

    func beginAddingEntry() {
        editingEntryID = nil
        editorSurface = ""
        editorPronunciation = ""
        editorAccentType = 1
        editorWordType = .properNoun
        editorPriority = 5
        statusMessage = nil
    }

    func beginEditing(_ entry: UserDictionaryEntry) {
        editingEntryID = entry.id
        editorSurface = entry.surface
        editorPronunciation = entry.pronunciation
        editorAccentType = entry.accentType
        editorWordType = entry.wordType
        editorPriority = entry.priority
        statusMessage = nil
    }

    func cancelEditing() {
        beginAddingEntry()
    }

    func updateEditorAccentType(_ value: Int) {
        editorAccentType = clampedAccentType(for: editorAccentPreviewItem?.moraCount ?? 1, requested: value)
    }

    func saveEditingEntry() {
        let surface = editorSurface.trimmingCharacters(in: .whitespacesAndNewlines)
        let pronunciation = normalizedPronunciation(editorPronunciation)

        guard !surface.isEmpty else {
            statusMessage = "表記を入力してください。"
            return
        }
        guard !pronunciation.isEmpty else {
            statusMessage = "読みを入力してください。"
            return
        }

        let moraCount = max(1, pronunciationMoraCount(pronunciation))
        let accentType = clampedAccentType(for: moraCount)
        let priority = min(max(editorPriority, 0), 10)

        let entry = UserDictionaryEntry(
            id: editingEntryID ?? UUID(),
            surface: surface,
            pronunciation: pronunciation,
            accentType: accentType,
            wordType: editorWordType,
            priority: priority
        )

        let message: String
        if let index = dictionary.entries.firstIndex(where: { $0.id == entry.id }) {
            dictionary.entries[index] = entry
            message = "辞書を更新しました。"
        } else {
            dictionary.entries.append(entry)
            message = "辞書に追加しました。"
        }

        dictionary.entries.sort {
            if $0.priority == $1.priority {
                return $0.surface.localizedCompare($1.surface) == .orderedAscending
            }
            return $0.priority > $1.priority
        }

        persistDictionary()
        beginEditing(entry)
        statusMessage = message
    }

    func deleteEditingEntry() {
        guard let editingEntryID,
              let index = dictionary.entries.firstIndex(where: { $0.id == editingEntryID }) else {
            statusMessage = "削除する単語を選択してください。"
            return
        }

        dictionary.entries.remove(at: index)
        statusMessage = "辞書から削除しました。"
        persistDictionary()
        beginAddingEntry()
    }

    private func persistDictionary() {
        do {
            try persist(dictionary)
            onDictionaryDidChange?()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func pronunciationMoraCount(_ pronunciation: String) -> Int {
        Self.previewMoraTexts(from: pronunciation).count
    }

    private func normalizedPronunciation(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .applyingTransform(.hiraganaToKatakana, reverse: false)?
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clampedAccentType(for moraCount: Int, requested: Int? = nil) -> Int {
        let count = max(1, moraCount)
        return min(max(requested ?? editorAccentType, 1), count)
    }

    private static func isHighTone(moraIndex: Int, accent: Int) -> Bool {
        let accentIndex = max(0, accent - 1)
        if moraIndex == 0 && accentIndex != 0 {
            return false
        }
        return moraIndex <= accentIndex
    }

    private static func previewMoraTexts(from pronunciation: String) -> [String] {
        let normalized = pronunciation
            .applyingTransform(.hiraganaToKatakana, reverse: false)?
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            ?? pronunciation

        let smallKana = Set(["ャ", "ュ", "ョ", "ァ", "ィ", "ゥ", "ェ", "ォ"])
        let punctuation = Set(["、", "。", "！", "？", ",", ".", "!", "?"])
        let characters = normalized.map(String.init)
        var moras: [String] = []
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || punctuation.contains(character) {
                index += 1
                continue
            }

            if index + 1 < characters.count, smallKana.contains(characters[index + 1]) {
                moras.append(character + characters[index + 1])
                index += 2
                continue
            }

            moras.append(character)
            index += 1
        }

        return moras
    }
}

@MainActor
final class SettingsViewModel: ObservableObject {
    static let remoteEngineURLUserDefaultsKey = "AivisRemoteEngineURLOverride"
    static let remoteEngineURLEnabledUserDefaultsKey = "AivisRemoteEngineURLEnabled"

    @Published var summary: String
    @Published var remoteEngineEnabled: Bool {
        didSet {
            UserDefaults.standard.set(remoteEngineEnabled, forKey: Self.remoteEngineURLEnabledUserDefaultsKey)
        }
    }
    @Published var remoteEngineURLString: String {
        didSet {
            let trimmed = remoteEngineURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: Self.remoteEngineURLUserDefaultsKey)
            } else {
                UserDefaults.standard.set(trimmed, forKey: Self.remoteEngineURLUserDefaultsKey)
            }
        }
    }
    let runtimeStatus: EngineRuntimeStatus

    init(summary: String, runtimeStatus: EngineRuntimeStatus) {
        self.summary = summary
        self.runtimeStatus = runtimeStatus
        self.remoteEngineEnabled = UserDefaults.standard.bool(forKey: Self.remoteEngineURLEnabledUserDefaultsKey)
        let storedRemoteEngineURL = UserDefaults.standard.string(forKey: Self.remoteEngineURLUserDefaultsKey)
        self.remoteEngineURLString = storedRemoteEngineURL ?? ""
    }
}

@MainActor
final class HelpViewModel: ObservableObject {
    @Published var summary: String

    init(summary: String) {
        self.summary = summary
    }
}
