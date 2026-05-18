import SwiftUI
import AivisMobileCore
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

#if os(iOS)

struct TalkEditorView: View {
    @State private var prosodyDetailMode: ProsodyDetailMode = .accent
    @State private var isSpeechControlsExpanded = false
    @State private var isPauseControlsExpanded = false
    @State private var isProsodyControlsExpanded = false
    @ObservedObject var viewModel: TalkEditorViewModel
    @ObservedObject var presetManager: PresetManagerViewModel
    let runtimeStatus: EngineRuntimeStatus
    let styleOptions: [SpeechStyleOption]
    let actionStatusMessage: String?
    let exportedWAVURL: URL?
    let exportedWAVByteCountLabel: String?
    let isActionRunning: Bool
    let isPreviewPlaying: Bool
    let playbackCurrentTime: TimeInterval
    let playbackDuration: TimeInterval
    let playbackCurrentTimeLabel: String
    let playbackDurationLabel: String
    let onUpdateText: (String) -> Void
    let onSelectStyle: (SpeechStyleOption) -> Void
    let onUpdatePhraseAccent: (Int, Int) -> Void
    let onMovePhraseAccent: (Int, Int) -> Void
    let onSplitPhraseAfter: (Int, Int) -> Void
    let onMergePhraseWithPrevious: (Int) -> Void
    let onRegenerateQuery: () -> Void
    let onTestSynthesis: () -> Void
    let onExportWAV: () -> Void
    let onExportAllWAV: () -> Void
    let onTogglePreviewPlayback: () -> Void
    let onSeekPreview: (TimeInterval) -> Void

    var body: some View {
        AivisScreen(
            title: "読み上げ",
            subtitle: "\(viewModel.audioRows.count) 行 / \(currentStyleLabel)"
        ) {
            AivisSection("読み上げ行") {
                if viewModel.audioRows.isEmpty {
                    EmptyState(text: "読み上げ行がありません。")
                } else {
                    VStack(spacing: 8) {
                        ForEach(viewModel.audioRows) { row in
                            TalkLineRow(
                                row: row,
                                isSelected: viewModel.selectedAudioKey == row.key,
                                canDelete: viewModel.audioRows.count > 1,
                                presetLabel: presetDisplayName(for: row.presetKey),
                                styleLabel: styleDisplayName(for: row.styleID),
                                onSelect: { viewModel.selectAudioKey(row.key) },
                                onMoveUp: {
                                    viewModel.selectAudioKey(row.key)
                                    viewModel.moveSelectedAudioItem(offset: -1)
                                },
                                onMoveDown: {
                                    viewModel.selectAudioKey(row.key)
                                    viewModel.moveSelectedAudioItem(offset: 1)
                                },
                                onDuplicate: {
                                    viewModel.selectAudioKey(row.key)
                                    viewModel.duplicateSelectedAudioItem()
                                },
                                onDelete: {
                                    viewModel.selectAudioKey(row.key)
                                    viewModel.deleteSelectedAudioItem()
                                }
                            )
                        }
                    }
                }

                Button {
                    viewModel.addAudioItemAfterSelection()
                } label: {
                    Label("テキスト欄を追加", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            AivisSection("選択行") {
                TextEditor(text: textBinding)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(minHeight: 112)
                    .padding(10)
                    .background(AivisUI.secondarySurface, in: RoundedRectangle(cornerRadius: AivisUI.radius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AivisUI.radius, style: .continuous)
                            .stroke(AivisUI.border, lineWidth: 1)
                    )
                    .accessibilityLabel("読み上げテキスト")

                HStack(spacing: 10) {
                    Menu {
                        if presetManager.catalog.keys.isEmpty {
                            Text("プリセットなし")
                        } else {
                            ForEach(presetManager.catalog.keys, id: \.self) { key in
                                Button(presetDisplayName(for: key)) {
                                    presetManager.selectPresetKey(key)
                                    if let preset = presetManager.catalog.items[key] {
                                        viewModel.applyPreset(preset, key: key)
                                    }
                                }
                            }
                        }
                    } label: {
                        Label(viewModel.currentPresetKey, systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Menu {
                        if styleOptions.isEmpty {
                            Text("スタイルなし")
                        } else {
                            ForEach(styleOptions) { option in
                                Button(option.styleName) {
                                    onSelectStyle(option)
                                }
                            }
                        }
                    } label: {
                        Label(currentStyleLabel, systemImage: "waveform")
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if shouldShowKanaPreview {
                    AivisKeyValueRow(title: "かな", value: viewModel.kanaPreview, imageName: "textformat")
                }
                if viewModel.currentText.count >= 250 {
                    AivisNotice(
                        text: "長い文章はうまく音声合成できないことがあります。句読点の位置で文章を分割することをおすすめします。",
                        tone: .warning
                    )
                }
            }

            AivisSection("生成") {
                VStack(spacing: 10) {
                    Button(action: onTestSynthesis) {
                        Label("合成して再生", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isActionRunning)

                    HStack(spacing: 10) {
                        Button(action: onExportWAV) {
                            Label("選択行", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(isActionRunning)

                        Button(action: onExportAllWAV) {
                            Label("全行", systemImage: "square.stack.3d.down.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(isActionRunning)
                    }
                }

                if exportedWAVURL != nil {
                    PlaybackControl(
                        isPlaying: isPreviewPlaying,
                        isEnabled: !isActionRunning,
                        currentTime: playbackCurrentTime,
                        duration: playbackDuration,
                        currentTimeLabel: playbackCurrentTimeLabel,
                        durationLabel: playbackDurationLabel,
                        onToggle: onTogglePreviewPlayback,
                        onSeek: onSeekPreview
                    )
                }

                if let exportedWAVURL {
                    ShareLink(item: exportedWAVURL) {
                        Label("WAVを共有", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                if isActionRunning {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("音声プレビューを準備しています")
                            .font(.subheadline)
                            .foregroundStyle(AivisUI.mutedText)
                    }
                }

                if let actionStatusMessage {
                    AivisNotice(text: actionStatusMessage)
                }

                if let exportedWAVURL {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("最新のWAV")
                            .font(.subheadline.weight(.semibold))
                        Text(exportedWAVURL.lastPathComponent)
                            .font(.footnote.weight(.semibold))
                            .textSelection(.enabled)
                        if let exportedWAVByteCountLabel {
                            Text(exportedWAVByteCountLabel)
                                .font(.caption)
                                .foregroundStyle(AivisUI.mutedText)
                        }
                        if playbackDuration > 0 {
                            Text("長さ \(playbackDurationLabel)")
                                .font(.caption)
                                .foregroundStyle(AivisUI.mutedText)
                        }
                        Text(exportedWAVURL.path)
                            .font(.caption)
                            .foregroundStyle(AivisUI.mutedText)
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                }
            }

            AivisSection("調整") {
                AccordionDisclosure(
                    title: "話し方",
                    systemImage: "slider.horizontal.3",
                    isExpanded: $isSpeechControlsExpanded
                ) {
                    ParameterPanel {
                        ParameterSlider(
                            title: "話速",
                            value: Binding(
                                get: { viewModel.selectedQuery?.speedScale ?? 1.0 },
                                set: { viewModel.updateSpeedScale($0) }
                            ),
                            range: 0.0...2.0,
                            step: 0.05,
                            isEnabled: viewModel.selectedQuery != nil
                        )
                        ParameterSlider(
                            title: "スタイルの強さ",
                            value: Binding(
                                get: { viewModel.selectedQuery?.intonationScale ?? 1.0 },
                                set: { viewModel.updateIntonationScale($0) }
                            ),
                            range: 0.0...2.0,
                            step: 0.05,
                            isEnabled: viewModel.selectedQuery != nil
                        )
                        ParameterSlider(
                            title: "テンポの緩急",
                            value: Binding(
                                get: { viewModel.selectedQuery?.tempoDynamicsScale ?? 1.0 },
                                set: { viewModel.updateTempoDynamicsScale($0) }
                            ),
                            range: 0.0...2.0,
                            step: 0.05,
                            isEnabled: viewModel.selectedQuery != nil
                        )
                        ParameterSlider(
                            title: "音高",
                            value: Binding(
                                get: { viewModel.selectedQuery?.pitchScale ?? 0.0 },
                                set: { viewModel.updatePitchScale($0) }
                            ),
                            range: -0.5...0.5,
                            step: 0.05,
                            isEnabled: viewModel.selectedQuery != nil
                        )
                        ParameterSlider(
                            title: "音量",
                            value: Binding(
                                get: { viewModel.selectedQuery?.volumeScale ?? 1.0 },
                                set: { viewModel.updateVolumeScale($0) }
                            ),
                            range: 0.0...2.0,
                            step: 0.05,
                            isEnabled: viewModel.selectedQuery != nil
                        )
                    }
                }

                Divider()

                AccordionDisclosure(
                    title: "間",
                    systemImage: "timer",
                    isExpanded: $isPauseControlsExpanded
                ) {
                    HStack(spacing: 10) {
                        Button {
                            viewModel.useStandardPauseForSelectedLine()
                        } label: {
                            Label("標準", systemImage: "timer")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(viewModel.selectedQuery == nil)

                        Button {
                            viewModel.useLongerPauseForSelectedLine()
                        } label: {
                            Label("行末長め", systemImage: "timer.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(viewModel.selectedQuery == nil)
                    }

                    ParameterPanel {
                        ParameterSlider(
                            title: "文内の間",
                            value: Binding(
                                get: { viewModel.selectedQuery?.pauseLengthScale ?? 1.0 },
                                set: { viewModel.updatePauseLengthScale($0) }
                            ),
                            range: 0.0...2.0,
                            step: 0.05,
                            isEnabled: viewModel.selectedQuery != nil
                        )
                        ParameterSlider(
                            title: "行頭の間",
                            value: Binding(
                                get: { viewModel.selectedQuery?.prePhonemeLength ?? 0.1 },
                                set: { viewModel.updatePrePhonemeLength($0) }
                            ),
                            range: 0.0...1.5,
                            step: 0.01,
                            isEnabled: viewModel.selectedQuery != nil
                        )
                        ParameterSlider(
                            title: "行末の間",
                            value: Binding(
                                get: { viewModel.selectedQuery?.postPhonemeLength ?? 0.1 },
                                set: { viewModel.updatePostPhonemeLength($0) }
                            ),
                            range: 0.0...1.5,
                            step: 0.01,
                            isEnabled: viewModel.selectedQuery != nil
                        )
                    }
                }

                Divider()

                AccordionDisclosure(
                    title: "読み・区切り・イントネーション",
                    systemImage: "waveform.path.ecg",
                    isExpanded: $isProsodyControlsExpanded
                ) {
                    if viewModel.accentEditorItems.isEmpty {
                        EmptyState(text: "テキスト入力後に読みと区切りを自動解析します。")
                    } else {
                        Picker("編集項目", selection: $prosodyDetailMode) {
                            ForEach(ProsodyDetailMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        ProsodyGraphEditor(
                            items: viewModel.accentEditorItems,
                            mode: prosodyDetailMode,
                            intonationScale: viewModel.selectedQuery?.intonationScale ?? 1.0,
                            onUpdateAccent: onUpdatePhraseAccent,
                            onMoveAccent: onMovePhraseAccent,
                            onSplitAfter: onSplitPhraseAfter,
                            onMergeWithPrevious: onMergePhraseWithPrevious,
                            onUpdateMoraPitch: { phraseIndex, moraIndex, pitch in
                                viewModel.updateMoraPitch(phraseIndex: phraseIndex, moraIndex: moraIndex, pitch: pitch)
                            },
                            onUpdateMoraVowelLength: { phraseIndex, moraIndex, length in
                                viewModel.updateMoraVowelLength(phraseIndex: phraseIndex, moraIndex: moraIndex, length: length)
                            },
                            onUpdateMoraConsonantLength: { phraseIndex, moraIndex, length in
                                viewModel.updateMoraConsonantLength(phraseIndex: phraseIndex, moraIndex: moraIndex, length: length)
                            },
                            onUpdatePauseLength: { phraseIndex, length in
                                viewModel.updatePauseMoraLength(phraseIndex: phraseIndex, length: length)
                            }
                        )
                    }
                }
            }
        }
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { viewModel.currentText },
            set: { onUpdateText($0) }
        )
    }

    private var stereoBinding: Binding<Bool> {
        Binding(
            get: { viewModel.selectedQuery?.outputStereo ?? false },
            set: { viewModel.updateStereo($0) }
        )
    }

    private var shouldShowKanaPreview: Bool {
        let kana = viewModel.kanaPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = viewModel.currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !kana.isEmpty && kana != text
    }

    private var sampleRateLabel: String {
        switch viewModel.selectedQuery?.outputSamplingRate ?? .explicit(44_100) {
        case .engineDefault:
            return "エンジン既定"
        case let .explicit(value):
            return "\(value.formatted()) Hz"
        }
    }

    private var currentStyleLabel: String {
        guard let styleID = viewModel.currentStyleID else {
            return "未選択"
        }
        if let option = styleOptions.first(where: { $0.styleID == styleID }) {
            return option.styleName
        }
        if styleID == 0 {
            return "Normal"
        }
        return "Style ID \(styleID)"
    }

    private func styleDisplayName(for styleID: Int) -> String {
        if let option = styleOptions.first(where: { $0.styleID == styleID }) {
            return option.styleName
        }
        if styleID == 0 {
            return "Normal"
        }
        return "Style ID \(styleID)"
    }

    private func presetDisplayName(for key: String?) -> String {
        guard let key else {
            return "手動"
        }
        if key == "manual" {
            return "手動"
        }
        return presetManager.catalog.items[key]?.name ?? viewModel.presetLabel(for: key)
    }

    private func isCurrentStyle(_ option: SpeechStyleOption) -> Bool {
        guard let selectedStyleID = viewModel.currentStyleID else {
            return false
        }
        return selectedStyleID == option.styleID
    }
}

struct ModelsView: View {
    @ObservedObject var viewModel: ModelManagerViewModel
    @State private var isImportingModel = false

    var body: some View {
        AivisScreen(
            title: "モデル",
            subtitle: "音声モデルの読み込み、検査、有効化を管理します。"
        ) {
            AivisOverview(
                title: viewModel.runtimeStatus.providerName,
                detail: "端末上の実行経路とモデル状態を確認できます。",
                items: [
                    viewModel.runtimeStatus.preferredExecutionProvider,
                    "\(viewModel.loadedModelCount) 件読み込み済み",
                    viewModel.activeModel?.name ?? "有効な音声なし",
                ]
            )

            if let statusMessage = viewModel.statusMessage {
                AivisNotice(text: statusMessage, tone: .warning)
            }

            AivisNotice(text: viewModel.seededRepositoryNotice)

            AivisSection("デバイス経路") {
                CapabilityRow(title: "CPU", isEnabled: viewModel.supportedDevices.cpu)
                AivisDivider()
                CapabilityRow(title: "Core ML", isEnabled: viewModel.supportedDevices.coreML)
                AivisDivider()
                CapabilityRow(title: "Neural Engine 優先", isEnabled: viewModel.supportedDevices.neuralEnginePreferred)
            }

            AivisSection("インストール済みモデル") {
                Button {
                    isImportingModel = true
                } label: {
                    Label("ローカルモデルを読み込む", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if viewModel.installedModels.isEmpty {
                    EmptyState(text: "モデルがまだありません。")
                } else {
                    VStack(spacing: 0) {
                        ForEach(viewModel.installedModels) { model in
                            ModelRow(
                                model: model,
                                inspection: viewModel.inspectionByModelID[model.id],
                                isBusy: viewModel.busyModelID == model.id,
                                onActivate: {
                                    Task {
                                        await viewModel.activateModel(model.id)
                                    }
                                },
                                onLoad: {
                                    Task {
                                        await viewModel.loadModel(model.id)
                                    }
                                },
                                onUnload: {
                                    Task {
                                        await viewModel.unloadModel(model.id)
                                    }
                                }
                            )
                            if model.id != viewModel.installedModels.last?.id {
                                AivisDivider()
                            }
                        }
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isImportingModel,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else {
                    viewModel.statusMessage = "ファイルが選択されていません。"
                    return
                }
                Task {
                    await viewModel.importModel(from: url)
                }
            case let .failure(error):
                viewModel.statusMessage = error.localizedDescription
            }
        }
    }
}

struct PresetsView: View {
    @ObservedObject var viewModel: PresetManagerViewModel

    var body: some View {
        AivisScreen(
            title: "プリセット",
            subtitle: "よく使う話し方の設定を確認します。"
        ) {
            AivisOverview(
                title: viewModel.selectedPreset?.name ?? "プリセットライブラリ",
                detail: "保存形式を変えずに、モバイルで確認しやすい一覧として表示します。",
                items: [
                    "\(viewModel.catalog.keys.count) 件のプリセット",
                    "\(viewModel.defaultStyles.count) 件の既定スタイル",
                ]
            )

            AivisSection("プリセット一覧") {
                if viewModel.catalog.keys.isEmpty {
                    EmptyState(text: "プリセットがありません。")
                } else {
                    VStack(spacing: 0) {
                        ForEach(viewModel.catalog.keys, id: \.self) { key in
                            Button {
                                viewModel.selectPresetKey(key)
                            } label: {
                                PresetRow(
                                    key: key,
                                    preset: viewModel.catalog.items[key],
                                    isSelected: viewModel.selectedPresetKey == key
                                )
                            }
                            .buttonStyle(.plain)
                            if key != viewModel.catalog.keys.last {
                                AivisDivider()
                            }
                        }
                    }
                }
            }
        }
    }
}

struct DictionaryView: View {
    @ObservedObject var viewModel: DictionaryManagerViewModel

    var body: some View {
        AivisScreen(
            title: "辞書",
            subtitle: "単語の表記、読み、アクセントを管理します。"
        ) {
            AivisOverview(
                title: "ユーザー辞書",
                detail: "保存した単語は次の AudioQuery 生成から使われます。",
                items: [
                    "\(viewModel.dictionary.entries.count) 件",
                    viewModel.searchText.isEmpty ? "全件表示" : "絞り込み中",
                ]
            )

            AivisSection(viewModel.isEditingExistingEntry ? "単語を編集" : "単語を追加") {
                VStack(spacing: 10) {
                    TextField("表記", text: $viewModel.editorSurface)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("読み", text: $viewModel.editorPronunciation)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Picker("品詞", selection: $viewModel.editorWordType) {
                        ForEach(DictionaryWordTypeOption.allCases) { option in
                            Text(option.title).tag(option.wordType)
                        }
                    }
                    .pickerStyle(.menu)

                    HStack(spacing: 12) {
                        Stepper(
                            value: Binding(
                                get: { min(max(viewModel.editorAccentType, viewModel.editorAccentRange.lowerBound), viewModel.editorAccentRange.upperBound) },
                                set: { viewModel.updateEditorAccentType($0) }
                            ),
                            in: viewModel.editorAccentRange
                        ) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("アクセント")
                                    .font(.subheadline.weight(.semibold))
                                Text("\(viewModel.editorAccentPreviewItem?.accent ?? viewModel.editorAccentType)")
                                    .font(.caption)
                                    .foregroundStyle(AivisUI.mutedText)
                            }
                        }

                        Stepper(value: $viewModel.editorPriority, in: 0...10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("優先度")
                                    .font(.subheadline.weight(.semibold))
                                Text("\(viewModel.editorPriority)")
                                    .font(.caption)
                                    .foregroundStyle(AivisUI.mutedText)
                            }
                        }
                    }

                    if let previewItem = viewModel.editorAccentPreviewItem {
                        DictionaryAccentEditor(
                            item: previewItem,
                            onUpdateAccent: { _, accent in
                                viewModel.updateEditorAccentType(accent)
                            }
                        )
                    }

                    HStack(spacing: 10) {
                        Button(action: viewModel.saveEditingEntry) {
                            Label(viewModel.isEditingExistingEntry ? "更新" : "追加", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button(action: viewModel.cancelEditing) {
                            Label("クリア", systemImage: "xmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }

                    if viewModel.isEditingExistingEntry {
                        Button(role: .destructive, action: viewModel.deleteEditingEntry) {
                            Label("削除", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }

                if let statusMessage = viewModel.statusMessage {
                    AivisNotice(text: statusMessage)
                }
            }

            AivisSection("検索") {
                TextField("表記または読みを検索", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("辞書検索")
            }

            AivisSection("単語一覧") {
                if viewModel.filteredEntries.isEmpty {
                    EmptyState(text: "一致する単語はありません。")
                } else {
                    VStack(spacing: 0) {
                        ForEach(viewModel.filteredEntries) { entry in
                            Button {
                                viewModel.beginEditing(entry)
                            } label: {
                                DictionaryRow(
                                    entry: entry,
                                    isSelected: viewModel.editingEntryID == entry.id
                                )
                            }
                            .buttonStyle(.plain)
                            if entry.id != viewModel.filteredEntries.last?.id {
                                AivisDivider()
                            }
                        }
                    }
                }
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        AivisScreen(
            title: "設定",
            subtitle: "実行環境と端末上のランタイム状態を確認します。"
        ) {
            AivisOverview(
                title: viewModel.runtimeStatus.preferredExecutionProvider,
                detail: viewModel.summary,
                items: [
                    viewModel.runtimeStatus.linkedVersion ?? "バージョン未確定",
                    viewModel.runtimeStatus.coreMLAvailable ? "Core ML 利用可" : "CPU フォールバック",
                ]
            )

            AivisSection("ランタイムノート") {
                if viewModel.runtimeStatus.notes.isEmpty {
                    EmptyState(text: "ランタイムノートはありません。")
                } else {
                    VStack(spacing: 0) {
                        ForEach(viewModel.runtimeStatus.notes, id: \.self) { note in
                            TimelineRow(title: "確認済み", detail: note, systemImage: "checkmark.seal.fill")
                            if note != viewModel.runtimeStatus.notes.last {
                                AivisDivider()
                            }
                        }
                    }
                }
            }

            AivisSection("AivisSpeech Engine URL") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("開発用リモートエンジンを使う", isOn: $viewModel.remoteEngineEnabled)
                        .font(.subheadline.weight(.semibold))
                    TextField("http://192.168.1.42:10102", text: $viewModel.remoteEngineURLString)
                        .textInputAutocapitalization(.never)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .disabled(!viewModel.remoteEngineEnabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(AivisUI.secondarySurface, in: RoundedRectangle(cornerRadius: AivisUI.radius, style: .continuous))
                        .opacity(viewModel.remoteEngineEnabled ? 1.0 : 0.45)
                    Text("既定では端末単体のネイティブ経路だけを使います。この項目は別端末の AivisSpeech Engine と比較確認する開発用で、通常の動作には不要です。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct HelpView: View {
    @ObservedObject var viewModel: HelpViewModel

    var body: some View {
        AivisScreen(
            title: "ヘルプ",
            subtitle: "モバイル版の現在地と次の作業を確認します。"
        ) {
            AivisOverview(
                title: "タッチ向けに整理した Aivis Speech",
                detail: viewModel.summary,
                items: ["読み上げ", "モデル", "辞書", "書き出し"]
            )

            AivisSection("開発状況") {
                TimelineRow(title: "日本語フロントエンド", detail: "ネイティブ OpenJTalk による読みと区切りの自動解析を実装済みです。", systemImage: "checkmark.circle.fill")
                AivisDivider()
                TimelineRow(title: "実音声合成", detail: "Style-Bert-VITS2 ONNX エンジンによる端末内音声合成を実装済みです。", systemImage: "checkmark.circle.fill")
                AivisDivider()
                TimelineRow(title: "プロジェクト互換", detail: ".aisp の往復互換を保ちながら、画面構造だけをモバイル向けに整理します。", systemImage: "doc.text")
            }
        }
    }
}

private enum ProsodyDetailMode: String, CaseIterable, Identifiable {
    case accent
    case pitch
    case length

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accent:
            return "アクセント"
        case .pitch:
            return "イントネーション"
        case .length:
            return "長さ"
        }
    }
}

private struct TalkLineRow: View {
    let row: TalkAudioRow
    let isSelected: Bool
    let canDelete: Bool
    let presetLabel: String
    let styleLabel: String
    let onSelect: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(row.lineNumber)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(isSelected ? AivisUI.accent : AivisUI.mutedText)
                    .frame(width: 30, alignment: .trailing)

                VStack(alignment: .leading, spacing: 5) {
                    Text(row.text.isEmpty ? "空のテキスト欄" : row.text)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(presetLabel) / \(styleLabel)")
                        .font(.caption)
                        .foregroundStyle(AivisUI.mutedText)
                }

                Spacer(minLength: 8)

                Menu {
                    Button("上へ移動", action: onMoveUp)
                    Button("下へ移動", action: onMoveDown)
                    Button("複製", action: onDuplicate)
                    Button("削除", role: .destructive, action: onDelete)
                        .disabled(!canDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("\(row.lineNumber)行目の操作")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? AivisUI.accentMuted : AivisUI.secondarySurface,
                in: RoundedRectangle(cornerRadius: AivisUI.radius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AivisUI.radius, style: .continuous)
                    .stroke(isSelected ? AivisUI.accent : AivisUI.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct PresetChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(isSelected ? AivisUI.accent : AivisUI.secondarySurface, in: Capsule())
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .overlay(
                    Capsule()
                        .stroke(isSelected ? AivisUI.accent : AivisUI.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct StyleChip: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.82) : AivisUI.mutedText)
                    .lineLimit(1)
            }
            .frame(minWidth: 132, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? AivisUI.accent : AivisUI.secondarySurface, in: RoundedRectangle(cornerRadius: AivisUI.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AivisUI.radius, style: .continuous)
                    .stroke(isSelected ? AivisUI.accent : AivisUI.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)、\(subtitle)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct PlaybackControl: View {
    let isPlaying: Bool
    let isEnabled: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval
    let currentTimeLabel: String
    let durationLabel: String
    let onToggle: () -> Void
    let onSeek: (TimeInterval) -> Void

    private var sliderRange: ClosedRange<Double> {
        0...max(duration, 0.01)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(action: onToggle) {
                    Label(isPlaying ? "停止" : "再生", systemImage: isPlaying ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!isEnabled)

                Text(duration > 0 ? durationLabel : "0:00")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(AivisUI.mutedText)
                    .frame(minWidth: 52, alignment: .trailing)
                    .accessibilityLabel("長さ \(durationLabel)")
            }

            Slider(
                value: Binding(
                    get: { min(max(currentTime, 0), max(duration, 0)) },
                    set: { onSeek($0) }
                ),
                in: sliderRange
            )
            .tint(AivisUI.accent)
            .disabled(!isEnabled || duration <= 0)
            .accessibilityLabel("再生位置")

            HStack {
                Text(currentTimeLabel)
                Spacer()
                Text(durationLabel)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(AivisUI.mutedText)
        }
        .padding(12)
        .background(AivisUI.secondarySurface, in: RoundedRectangle(cornerRadius: AivisUI.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AivisUI.radius, style: .continuous)
                .stroke(AivisUI.border, lineWidth: 1)
        )
    }
}

private struct ParameterSlider: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let isEnabled: Bool

    private var foreground: Color {
        colorScheme == .dark ? .white : .primary
    }

    private var muted: Color {
        colorScheme == .dark ? Color.white.opacity(0.55) : Color.secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer()
                Text(value.formatted(.number.precision(.fractionLength(2))))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(isEnabled ? foreground : muted)
            }
            Slider(value: $value, in: range, step: step)
                .tint(AivisUI.editorAccent)
                .disabled(!isEnabled)
                .accessibilityLabel(title)
        }
        .foregroundStyle(foreground)
        .opacity(isEnabled ? 1.0 : 0.5)
        .frame(minHeight: 44)
    }
}

private struct AccordionDisclosure<Content: View>: View {
    let title: String
    let systemImage: String
    @Binding var isExpanded: Bool
    let content: Content

    init(
        title: String,
        systemImage: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(.top, 10)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .tint(AivisUI.accent)
        .padding(.vertical, 2)
    }
}

private struct ParameterPanel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var panelBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.18, blue: 0.20)
            : AivisUI.secondarySurface
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            content
        }
        .padding(16)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: AivisUI.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AivisUI.radius, style: .continuous)
                .stroke(AivisUI.border, lineWidth: 1)
        )
    }
}

private struct ProsodyGraphEditor: View {
    let items: [AccentPhraseEditorItem]
    let mode: ProsodyDetailMode
    let intonationScale: Double
    let onUpdateAccent: (Int, Int) -> Void
    let onMoveAccent: (Int, Int) -> Void
    let onSplitAfter: (Int, Int) -> Void
    let onMergeWithPrevious: (Int) -> Void
    let onUpdateMoraPitch: (Int, Int, Double) -> Void
    let onUpdateMoraVowelLength: (Int, Int, Double) -> Void
    let onUpdateMoraConsonantLength: (Int, Int, Double) -> Void
    let onUpdatePauseLength: (Int, Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.title)
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                if mode == .pitch {
                    Text("強さ \(intonationScale.formatted(.number.precision(.fractionLength(2))))")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AivisUI.accentMuted, in: Capsule())
                        .foregroundStyle(AivisUI.accent)
                }
            }

            VStack(spacing: 12) {
                ForEach(items) { item in
                    ProsodyPhraseCard(
                        item: item,
                        mode: mode,
                        canMergeWithPrevious: item.phraseIndex > 0,
                        onUpdateAccent: onUpdateAccent,
                        onMoveAccent: onMoveAccent,
                        onSplitAfter: onSplitAfter,
                        onMergeWithPrevious: onMergeWithPrevious,
                        onUpdateMoraPitch: onUpdateMoraPitch,
                        onUpdateMoraVowelLength: onUpdateMoraVowelLength,
                        onUpdateMoraConsonantLength: onUpdateMoraConsonantLength,
                        onUpdatePauseLength: onUpdatePauseLength
                    )
                }
            }
        }
    }
}

private struct ProsodyPhraseCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: AccentPhraseEditorItem
    let mode: ProsodyDetailMode
    let canMergeWithPrevious: Bool
    let onUpdateAccent: (Int, Int) -> Void
    let onMoveAccent: (Int, Int) -> Void
    let onSplitAfter: (Int, Int) -> Void
    let onMergeWithPrevious: (Int) -> Void
    let onUpdateMoraPitch: (Int, Int, Double) -> Void
    let onUpdateMoraVowelLength: (Int, Int, Double) -> Void
    let onUpdateMoraConsonantLength: (Int, Int, Double) -> Void
    let onUpdatePauseLength: (Int, Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.text.isEmpty ? "アクセント句 \(item.phraseIndex + 1)" : item.text)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(item.moraCount) モーラ\(item.hasPause ? " / 句読点あり" : "")")
                        .font(.caption)
                        .foregroundStyle(AivisUI.mutedText)
                }
                Spacer(minLength: 8)
                Text("山 \(item.accent)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(AivisUI.editorAccent)
                Menu {
                    Button {
                        AivisHaptics.selectionChanged()
                        onMoveAccent(item.phraseIndex, -1)
                    } label: {
                        Label("山を左へ", systemImage: "arrow.left")
                    }
                    .disabled(item.accent <= 1)

                    Button {
                        AivisHaptics.selectionChanged()
                        onMoveAccent(item.phraseIndex, 1)
                    } label: {
                        Label("山を右へ", systemImage: "arrow.right")
                    }
                    .disabled(item.accent >= item.moraCount)

                    Button {
                        AivisHaptics.selectionChanged()
                        onMergeWithPrevious(item.phraseIndex)
                    } label: {
                        Label("前の句と結合", systemImage: "link")
                    }
                    .disabled(!canMergeWithPrevious)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("アクセント句 \(item.phraseIndex + 1) の操作")
            }

            switch mode {
            case .accent:
                ProsodyPhraseTimeline(item: item, onUpdateAccent: onUpdateAccent)

                Stepper(
                    value: Binding(
                        get: { item.accent },
                        set: { onUpdateAccent(item.phraseIndex, $0) }
                    ),
                    in: 1...max(1, item.moraCount)
                ) {
                    Text("山 \(item.accent)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(colorScheme == .dark ? Color.white : Color.primary)
                }
                .tint(AivisUI.editorAccent)

                ProsodyMoraControlStrip(
                    item: item,
                    onUpdateAccent: onUpdateAccent,
                    onSplitAfter: onSplitAfter
                )

            case .pitch:
                ProsodyPitchControls(item: item, onUpdateMoraPitch: onUpdateMoraPitch)

            case .length:
                ProsodyLengthControls(
                    item: item,
                    onUpdateMoraVowelLength: onUpdateMoraVowelLength,
                    onUpdateMoraConsonantLength: onUpdateMoraConsonantLength,
                    onUpdatePauseLength: onUpdatePauseLength
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AivisUI.secondarySurface, in: RoundedRectangle(cornerRadius: AivisUI.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AivisUI.radius, style: .continuous)
                .stroke(AivisUI.border, lineWidth: 1)
        )
        .tint(AivisUI.editorAccent)
    }
}

private struct ProsodyPhraseTimeline: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: AccentPhraseEditorItem
    let onUpdateAccent: (Int, Int) -> Void

    private let topY: CGFloat = 28
    private let lowY: CGFloat = 92
    private let highY: CGFloat = 54

    private var accent: Color {
        AivisUI.editorAccent
    }

    private var lineColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.9) : Color.primary.opacity(0.82)
    }

    private var mutedLine: Color {
        colorScheme == .dark ? Color.white.opacity(0.28) : Color.primary.opacity(0.20)
    }

    private var textColor: Color {
        colorScheme == .dark ? .white : .primary
    }

    var body: some View {
        GeometryReader { proxy in
            let graphWidth = max(1, proxy.size.width)
            ZStack(alignment: .topLeading) {
                Path { path in
                    guard !item.moras.isEmpty else { return }
                    path.move(to: point(for: 0, width: graphWidth))
                    for index in item.moras.indices.dropFirst() {
                        path.addLine(to: point(for: index, width: graphWidth))
                    }
                }
                .stroke(lineColor, lineWidth: 1.5)

                Path { path in
                    path.move(to: CGPoint(x: 0, y: topY))
                    path.addLine(to: CGPoint(x: xPosition(for: max(0, item.accent - 1), width: graphWidth), y: topY))
                }
                .stroke(accent, lineWidth: 4)

                Path { path in
                    path.move(to: CGPoint(x: xPosition(for: max(0, item.accent - 1), width: graphWidth), y: topY))
                    path.addLine(to: CGPoint(x: graphWidth, y: topY))
                }
                .stroke(mutedLine, lineWidth: 4)

                ForEach(Array(item.moras.enumerated()), id: \.element.id) { index, mora in
                    let x = xPosition(for: index, width: graphWidth)
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 44))
                        path.addLine(to: CGPoint(x: x, y: 108))
                    }
                    .stroke(accent.opacity(0.65), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))

                    Text(mora.text)
                        .font(.headline.weight(.regular))
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 56, height: 34)
                        .position(x: x, y: 132)
                }

                let accentX = xPosition(for: max(0, item.accent - 1), width: graphWidth)
                Circle()
                    .fill(accent)
                    .frame(width: 34, height: 34)
                    .position(x: accentX, y: topY)
                Rectangle()
                    .fill(accent)
                    .frame(width: 6, height: 86)
                    .position(x: accentX, y: 70)
            }
            .frame(width: graphWidth, height: 154)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onUpdateAccent(item.phraseIndex, accentIndex(for: value.location.x, width: graphWidth))
                    }
            )
            .accessibilityLabel("アクセントグラフ")
            .accessibilityHint("タップまたはドラッグでアクセントの山を移動します")
        }
        .frame(height: 154)
        .padding(.horizontal, 4)
    }

    private func point(for index: Int, width: CGFloat) -> CGPoint {
        CGPoint(x: xPosition(for: index, width: width), y: item.moras[index].isHighTone ? highY : lowY)
    }

    private func xPosition(for index: Int, width: CGFloat) -> CGFloat {
        guard item.moras.count > 1 else {
            return width / 2
        }
        let inset: CGFloat = 24
        let usableWidth = max(1, width - inset * 2)
        let clampedIndex = min(max(index, 0), item.moras.count - 1)
        return inset + usableWidth * CGFloat(clampedIndex) / CGFloat(item.moras.count - 1)
    }

    private func accentIndex(for x: CGFloat, width: CGFloat) -> Int {
        guard item.moras.count > 1 else {
            return 1
        }
        let inset: CGFloat = 24
        let usableWidth = max(1, width - inset * 2)
        let normalized = min(max((x - inset) / usableWidth, 0), 1)
        let index = Int((normalized * CGFloat(item.moras.count - 1)).rounded())
        return min(max(index + 1, 1), item.moras.count)
    }
}

private struct ProsodyMoraControlStrip: View {
    let item: AccentPhraseEditorItem
    let onUpdateAccent: (Int, Int) -> Void
    var onSplitAfter: ((Int, Int) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: 8) {
                ForEach(Array(item.moras.enumerated()), id: \.element.id) { offset, mora in
                    Menu {
                        Button {
                            AivisHaptics.selectionChanged()
                            onUpdateAccent(item.phraseIndex, mora.moraIndex + 1)
                        } label: {
                            Label("山をここにする", systemImage: "mountain.2.fill")
                        }

                        if offset < item.moras.count - 1, let onSplitAfter {
                            Button {
                                AivisHaptics.selectionChanged()
                                onSplitAfter(item.phraseIndex, mora.moraIndex)
                            } label: {
                                Label("この後で区切る", systemImage: "scissors")
                            }
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(mora.text)
                                .font(.headline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Text(mora.isHighTone ? "高" : "低")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(mora.isHighTone ? AivisUI.editorAccent : AivisUI.mutedText)
                        }
                        .frame(minWidth: 50, minHeight: 50)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .accessibilityLabel("\(mora.text) の操作")
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct DictionaryAccentEditor: View {
    let item: AccentPhraseEditorItem
    let onUpdateAccent: (Int, Int) -> Void

    var body: some View {
        ParameterPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("アクセント")
                            .font(.subheadline.weight(.semibold))
                        Text("読み上げと同じ山グラフで位置を決めます。")
                            .font(.caption)
                            .foregroundStyle(AivisUI.mutedText)
                    }
                    Spacer(minLength: 8)
                    Text("山 \(item.accent)")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(AivisUI.editorAccent)
                }

                ProsodyPhraseTimeline(item: item, onUpdateAccent: onUpdateAccent)

                Stepper(
                    value: Binding(
                        get: { item.accent },
                        set: { onUpdateAccent(item.phraseIndex, $0) }
                    ),
                    in: 1...max(1, item.moraCount)
                ) {
                    Text("山 \(item.accent)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                }
                .tint(AivisUI.editorAccent)

                ProsodyMoraControlStrip(
                    item: item,
                    onUpdateAccent: onUpdateAccent
                )
            }
        }
    }
}

private struct ProsodyPitchControls: View {
    let item: AccentPhraseEditorItem
    let onUpdateMoraPitch: (Int, Int, Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(item.moras) { mora in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(mora.text)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(mora.pitch.formatted(.number.precision(.fractionLength(2))))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AivisUI.mutedText)
                    }
                    Slider(
                        value: Binding(
                            get: { mora.pitch },
                            set: { onUpdateMoraPitch(item.phraseIndex, mora.moraIndex, $0) }
                        ),
                        in: 0.0...6.5,
                        step: 0.01
                    )
                    .tint(AivisUI.editorAccent)
                    .accessibilityLabel("\(mora.text) の音高")
                }
                .padding(10)
                .background(AivisUI.surface, in: RoundedRectangle(cornerRadius: AivisUI.radius, style: .continuous))
            }
        }
    }
}

private struct ProsodyLengthControls: View {
    let item: AccentPhraseEditorItem
    let onUpdateMoraVowelLength: (Int, Int, Double) -> Void
    let onUpdateMoraConsonantLength: (Int, Int, Double) -> Void
    let onUpdatePauseLength: (Int, Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(item.moras) { mora in
                VStack(alignment: .leading, spacing: 8) {
                    Text(mora.text)
                        .font(.subheadline.weight(.semibold))

                    lengthSlider(
                        title: "母音",
                        value: mora.vowelLength,
                        range: 0.0...0.6,
                        onChange: { onUpdateMoraVowelLength(item.phraseIndex, mora.moraIndex, $0) }
                    )

                    if let consonantLength = mora.consonantLength {
                        lengthSlider(
                            title: "子音",
                            value: consonantLength,
                            range: 0.0...0.6,
                            onChange: { onUpdateMoraConsonantLength(item.phraseIndex, mora.moraIndex, $0) }
                        )
                    }
                }
                .padding(10)
                .background(AivisUI.surface, in: RoundedRectangle(cornerRadius: AivisUI.radius, style: .continuous))
            }

            if let pauseLength = item.pauseLength {
                lengthSlider(
                    title: "句読点の無音",
                    value: pauseLength,
                    range: 0.0...1.0,
                    onChange: { onUpdatePauseLength(item.phraseIndex, $0) }
                )
                .padding(10)
                .background(AivisUI.surface, in: RoundedRectangle(cornerRadius: AivisUI.radius, style: .continuous))
            }
        }
    }

    private func lengthSlider(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(value.formatted(.number.precision(.fractionLength(3))))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AivisUI.mutedText)
            }
            Slider(
                value: Binding(
                    get: { value },
                    set: { onChange($0) }
                ),
                in: range,
                step: 0.001
            )
            .tint(AivisUI.editorAccent)
            .accessibilityLabel(title)
        }
    }
}

private enum AivisHaptics {
    static func selectionChanged() {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}

private struct QueueRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? AivisUI.accent : AivisUI.mutedText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AivisUI.mutedText)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct CapabilityRow: View {
    let title: String
    let isEnabled: Bool

    var body: some View {
        AivisKeyValueRow(
            title: title,
            value: isEnabled ? "利用可" : "未対応",
            imageName: isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill",
            tint: isEnabled ? AivisUI.success : AivisUI.mutedText
        )
        .padding(.vertical, 8)
    }
}

private struct ModelRow: View {
    let model: InstalledModel
    let inspection: ModelInspectionSummary?
    let isBusy: Bool
    let onActivate: () -> Void
    let onLoad: () -> Void
    let onUnload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(model.version)
                        .font(.subheadline)
                        .foregroundStyle(AivisUI.mutedText)
                }
                Spacer(minLength: 12)
                Text(label(for: model.loadState))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(color(for: model.loadState).opacity(0.12), in: Capsule())
                    .foregroundStyle(color(for: model.loadState))
            }

            if let manifest = model.manifest {
                VStack(spacing: 8) {
                    AivisKeyValueRow(title: "アーキテクチャ", value: manifest.modelArchitecture)
                    AivisKeyValueRow(title: "話者数", value: "\(manifest.speakers.count)")
                }
            }

            if let inspection {
                VStack(alignment: .leading, spacing: 8) {
                    AivisKeyValueRow(title: "入力", value: "\(inspection.inputNames.count)")
                    AivisKeyValueRow(title: "出力", value: "\(inspection.outputNames.count)")
                    Text("Input: \(inspection.inputNames.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(AivisUI.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Output: \(inspection.outputNames.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(AivisUI.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button(model.loadState == .active ? "有効" : "有効化", action: onActivate)
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy || model.loadState == .active)
                Button(model.loadState == .installed ? "読み込み" : "再検査", action: onLoad)
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
                Button("解除", action: onUnload)
                    .buttonStyle(.bordered)
                    .disabled(isBusy || model.loadState == .installed)
            }
            .controlSize(.regular)

            if isBusy {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("ランタイムセッションを準備しています")
                        .font(.caption)
                        .foregroundStyle(AivisUI.mutedText)
                }
            }
        }
        .padding(.vertical, 14)
    }

    private func label(for state: InstalledModel.LoadState) -> String {
        switch state {
        case .installed:
            return "インストール済み"
        case .loaded:
            return "読み込み済み"
        case .active:
            return "有効"
        }
    }

    private func color(for state: InstalledModel.LoadState) -> Color {
        switch state {
        case .installed:
            return AivisUI.mutedText
        case .loaded:
            return AivisUI.warning
        case .active:
            return AivisUI.success
        }
    }
}

private struct PresetRow: View {
    let key: String
    let preset: Preset?
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? AivisUI.accent : AivisUI.mutedText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(preset?.name ?? key)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(key)
                    .font(.caption)
                    .foregroundStyle(AivisUI.mutedText)
                if let preset {
                    Text("話速 \(preset.speedScale.formatted(.number.precision(.fractionLength(2)))) / イントネーション \(preset.intonationScale.formatted(.number.precision(.fractionLength(2)))) / 緩急 \((preset.tempoDynamicsScale ?? 1.0).formatted(.number.precision(.fractionLength(2))))")
                        .font(.caption)
                        .foregroundStyle(AivisUI.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private enum DictionaryWordTypeOption: String, CaseIterable, Identifiable {
    case properNoun
    case commonNoun
    case verb
    case adjective
    case suffix

    var id: String { rawValue }

    var wordType: UserDictionaryEntry.WordType {
        switch self {
        case .properNoun:
            return .properNoun
        case .commonNoun:
            return .commonNoun
        case .verb:
            return .verb
        case .adjective:
            return .adjective
        case .suffix:
            return .suffix
        }
    }

    var title: String {
        switch self {
        case .properNoun:
            return "固有名詞"
        case .commonNoun:
            return "一般名詞"
        case .verb:
            return "動詞"
        case .adjective:
            return "形容詞"
        case .suffix:
            return "接尾辞"
        }
    }
}

private struct DictionaryRow: View {
    let entry: UserDictionaryEntry
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.surface)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 12)
                Text("アクセント \(entry.accentType)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AivisUI.accent)
            }
            Text(entry.pronunciation)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Text("優先度 \(entry.priority) / \(entry.wordType)")
                .font(.caption)
                .foregroundStyle(AivisUI.mutedText)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            isSelected ? AivisUI.accentMuted : Color.clear,
            in: RoundedRectangle(cornerRadius: AivisUI.radius, style: .continuous)
        )
    }
}

private struct TimelineRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(AivisUI.accent)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(AivisUI.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }
}

private struct EmptyState: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(AivisUI.mutedText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
    }
}

#else

struct TalkEditorView: View {
    @ObservedObject var viewModel: TalkEditorViewModel
    @ObservedObject var presetManager: PresetManagerViewModel
    let runtimeStatus: EngineRuntimeStatus
    let styleOptions: [SpeechStyleOption]
    let actionStatusMessage: String?
    let exportedWAVURL: URL?
    let exportedWAVByteCountLabel: String?
    let isActionRunning: Bool
    let isPreviewPlaying: Bool
    let playbackCurrentTime: TimeInterval
    let playbackDuration: TimeInterval
    let playbackCurrentTimeLabel: String
    let playbackDurationLabel: String
    let onUpdateText: (String) -> Void
    let onSelectStyle: (SpeechStyleOption) -> Void
    let onUpdatePhraseAccent: (Int, Int) -> Void
    let onMovePhraseAccent: (Int, Int) -> Void
    let onSplitPhraseAfter: (Int, Int) -> Void
    let onMergePhraseWithPrevious: (Int) -> Void
    let onRegenerateQuery: () -> Void
    let onTestSynthesis: () -> Void
    let onExportWAV: () -> Void
    let onExportAllWAV: () -> Void
    let onTogglePreviewPlayback: () -> Void
    let onSeekPreview: (TimeInterval) -> Void

    var body: some View {
        Text("iOS専用の読み上げエディタです")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ModelsView: View {
    @ObservedObject var viewModel: ModelManagerViewModel
    var body: some View { Text("iOS専用のモデル画面です") }
}

struct PresetsView: View {
    @ObservedObject var viewModel: PresetManagerViewModel
    var body: some View { Text("iOS専用のプリセット画面です") }
}

struct DictionaryView: View {
    @ObservedObject var viewModel: DictionaryManagerViewModel
    var body: some View { Text("iOS専用の辞書画面です") }
}

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    var body: some View { Text("iOS専用の設定画面です") }
}

struct HelpView: View {
    @ObservedObject var viewModel: HelpViewModel
    var body: some View { Text("iOS専用のヘルプ画面です") }
}

#endif
