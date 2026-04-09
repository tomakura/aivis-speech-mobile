import Foundation
import Testing
@testable import AivisSpeechiOS
import AivisMobileCore

struct SmokeTests {
    @Test
    @MainActor
    func bootstrapContainsSixTabsAndEmptyTalkLine() {
        let previousStoredValue = UserDefaults.standard.object(forKey: AppUserDictionaryStorage.userDefaultsKey)
        defer {
            if let previousStoredValue {
                UserDefaults.standard.set(previousStoredValue, forKey: AppUserDictionaryStorage.userDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppUserDictionaryStorage.userDefaultsKey)
            }
        }
        AppUserDictionaryStorage.clear()

        let viewModel = AppViewModel.bootstrap()

        #expect(AppTab.allCases.count == 6)
        #expect(viewModel.talkEditor.activeAudioItems.count == 1)
        #expect(viewModel.talkEditor.currentText.isEmpty)
        #expect(viewModel.talkEditor.currentStyleID == 0)
        #expect(viewModel.talkEditor.currentPresetKey == "Normal")
        #expect(viewModel.talkStyleOptions.first?.styleName == "Normal")
        #expect(viewModel.talkEditor.selectedQuery?.accentPhrases.isEmpty ?? true)
        #expect(viewModel.modelManager.installedModels.count == 2)
        #expect(viewModel.presetManager.catalog.keys == ["default-normal"])
        #expect(viewModel.dictionaryManager.dictionary.entries.count == 1)
    }

    @Test
    @MainActor
    func talkActionsRegenerateAndExportWAV() async throws {
        let viewModel = AppViewModel.bootstrap(speechEngine: MockSpeechEngine())

        viewModel.updateTalkText("変更後の読み上げ")
        await viewModel.regenerateTalkQuery()
        #expect(viewModel.talkEditor.selectedQuery?.accentPhrases.isEmpty == false)
        #expect(viewModel.talkActionStatusMessage == "AudioQuery を現在のテキストで更新しました。")

        #expect(viewModel.lastExportedWAVURL == nil)
        viewModel.talkEditor.updateSpeedScale(1.25)

        await viewModel.exportTalkWAV()

        let exportedURL = try #require(viewModel.lastExportedWAVURL)
        let data = try Data(contentsOf: exportedURL)
        #expect(data.count > 44)
        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
        #expect(viewModel.lastExportedWAVByteCount == data.count)
        #expect(viewModel.exportedWAVByteCountLabel != nil)
        #expect(viewModel.playbackDuration > 0)
        #expect(viewModel.playbackDurationLabel != "0:00")
        #expect(viewModel.talkEditor.selectedQuery?.kana == "変更後の読み上げ")
        #expect(viewModel.talkEditor.selectedQuery?.accentPhrases.first?.moras.first?.text == "変更後の読み上げ")
        #expect(viewModel.talkEditor.selectedQuery?.speedScale == 1.25)
    }

    @Test
    @MainActor
    func exportAllTalkWAVCombinesRowsInAudioKeyOrder() async throws {
        let viewModel = AppViewModel.bootstrap(speechEngine: MockSpeechEngine())
        viewModel.talkEditor = TalkEditorViewModel(project: Self.projectWithTwoLines())

        await viewModel.exportAllTalkWAV()

        let exportedURL = try #require(viewModel.lastExportedWAVURL)
        let data = try Data(contentsOf: exportedURL)
        let firstRowData = try DiagnosticWAVWriter.makeWAVData(from: Self.query(text: "一行目"), text: "一行目")

        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: data[8..<12], as: UTF8.self) == "WAVE")
        #expect(data.count > firstRowData.count)
        #expect(viewModel.lastExportedWAVByteCount == data.count)
        #expect(viewModel.playbackDuration > 0)
        #expect(viewModel.talkActionStatusMessage?.hasPrefix("全行WAVを生成しました:") == true)
    }

    @Test
    @MainActor
    func talkTextUpdatesQueryAutomatically() async throws {
        let viewModel = AppViewModel.bootstrap(speechEngine: MockSpeechEngine())

        viewModel.updateTalkText("自動更新テスト。")
        try await Task.sleep(nanoseconds: 750_000_000)

        #expect(viewModel.talkEditor.selectedQuery?.kana == "自動更新テスト。")
        #expect(viewModel.talkEditor.selectedQuery?.accentPhrases.isEmpty == false)
        #expect(viewModel.talkActionStatusMessage == "AudioQuery を自動更新しました。")
    }

    @Test
    @MainActor
    func emptyTalkProjectCreatesEditableItemAndUpdatesStyleParameters() {
        let viewModel = TalkEditorViewModel(
            project: AISPProjectDocument(
                appVersion: "1.1.0-dev",
                talk: TalkProject(audioKeys: [], audioItems: [:]),
                song: .empty
            )
        )

        viewModel.updateText("実機入力テスト")
        viewModel.updateStyle(
            SpeechStyleOption(
                speakerID: "speaker-a",
                speakerName: "Speaker A",
                styleID: 7,
                styleName: "Happy",
                modelName: "Test Model"
            )
        )
        viewModel.updateIntonationScale(1.4)
        viewModel.updateTempoDynamicsScale(1.2)

        #expect(viewModel.availableAudioKeys.count == 1)
        #expect(viewModel.currentText == "実機入力テスト")
        #expect(viewModel.selectedAudioItem?.voice.speakerID == "speaker-a")
        #expect(viewModel.selectedAudioItem?.voice.styleID == 7)
        #expect(viewModel.selectedQuery?.intonationScale == 1.4)
        #expect(viewModel.selectedQuery?.tempoDynamicsScale == 1.2)
    }

    @Test
    @MainActor
    func multilineTextUsesDesktopPasteSplitting() {
        let viewModel = TalkEditorViewModel(project: Self.emptyProject())

        viewModel.updateText("一行目。\n\n二行目\r\n 三行目 ")

        #expect(viewModel.availableAudioKeys == ["audio-1", "audio-2", "audio-3"])
        #expect(viewModel.project.talk.audioItems["audio-1"]?.text == "一行目。")
        #expect(viewModel.project.talk.audioItems["audio-2"]?.text == "二行目")
        #expect(viewModel.project.talk.audioItems["audio-3"]?.text == "三行目")
        #expect(viewModel.selectedAudioKey == "audio-3")
    }

    @Test
    @MainActor
    func typingAfterJapanesePeriodDoesNotSplitLine() {
        let viewModel = TalkEditorViewModel(project: Self.emptyProject())

        viewModel.updateText("こんにちは。")
        viewModel.updateText("こんにちは。続き")

        #expect(viewModel.availableAudioKeys == ["audio-1"])
        #expect(viewModel.currentText == "こんにちは。続き")
        #expect(viewModel.selectedQuery?.accentPhrases.isEmpty == true)
    }

    @Test
    @MainActor
    func fallbackQueryDoesNotInventGreetingAccent() {
        let viewModel = TalkEditorViewModel(project: Self.emptyProject())

        viewModel.updateText("こんにちは")
        let query = viewModel.regenerateSelectedQuery()

        #expect(query.kana == "こんにちは")
        #expect(query.accentPhrases.isEmpty)
    }

    @Test
    @MainActor
    func newAndDuplicatedLinesInheritDesktopAudioItemFields() {
        let viewModel = TalkEditorViewModel(project: Self.projectWithTwoLines())

        viewModel.selectAudioKey("audio-1")
        viewModel.updateSpeedScale(1.35)
        viewModel.updatePauseLengthScale(1.25)
        viewModel.addAudioItemAfterSelection()

        let added = viewModel.selectedAudioKey.flatMap { viewModel.project.talk.audioItems[$0] }
        #expect(added?.text == "")
        #expect(added?.voice.speakerID == "speaker-a")
        #expect(added?.voice.styleID == 1)
        #expect(added?.presetKey == "preset-a")
        #expect(added?.query?.speedScale == 1.35)
        #expect(added?.query?.pauseLengthScale == 1.25)

        viewModel.duplicateSelectedAudioItem()
        let duplicated = viewModel.selectedAudioKey.flatMap { viewModel.project.talk.audioItems[$0] }
        #expect(duplicated == added)
    }

    @Test
    @MainActor
    func lineSpecificControlsDoNotLeakToOtherRows() {
        let viewModel = TalkEditorViewModel(project: Self.projectWithTwoLines())

        viewModel.selectAudioKey("audio-1")
        viewModel.updateStyle(
            SpeechStyleOption(
                speakerID: "speaker-z",
                speakerName: "Speaker Z",
                styleID: 9,
                styleName: "Whisper",
                modelName: nil
            )
        )
        viewModel.updatePauseLengthScale(1.6)
        viewModel.updatePrePhonemeLength(0.35)
        viewModel.updatePostPhonemeLength(0.45)
        viewModel.useLongerPauseForSelectedLine()
        viewModel.updateMoraPitch(phraseIndex: 0, moraIndex: 0, pitch: 4.2)
        viewModel.updateMoraVowelLength(phraseIndex: 0, moraIndex: 0, length: 0.22)

        #expect(viewModel.project.talk.audioItems["audio-1"]?.voice.styleID == 9)
        #expect(viewModel.project.talk.audioItems["audio-1"]?.query?.pauseLengthScale == 1.25)
        #expect(viewModel.project.talk.audioItems["audio-1"]?.query?.prePhonemeLength == 0.15)
        #expect(viewModel.project.talk.audioItems["audio-1"]?.query?.postPhonemeLength == 0.35)
        #expect(viewModel.project.talk.audioItems["audio-1"]?.query?.accentPhrases.first?.moras.first?.pitch == 4.2)
        #expect(viewModel.project.talk.audioItems["audio-1"]?.query?.accentPhrases.first?.moras.first?.vowelLength == 0.22)

        #expect(viewModel.project.talk.audioItems["audio-2"]?.voice.styleID == 2)
        #expect(viewModel.project.talk.audioItems["audio-2"]?.query?.pauseLengthScale == 1.0)
        #expect(viewModel.project.talk.audioItems["audio-2"]?.query?.prePhonemeLength == 0.1)
        #expect(viewModel.project.talk.audioItems["audio-2"]?.query?.postPhonemeLength == 0.1)
        #expect(viewModel.project.talk.audioItems["audio-2"]?.query?.accentPhrases.first?.moras.first?.pitch == 1.0)
    }

    @Test
    @MainActor
    func talkEditorEditsAccentPhraseBoundariesAndAccent() {
        let viewModel = TalkEditorViewModel(
            project: AISPProjectDocument(
                appVersion: "1.1.0-dev",
                talk: TalkProject(audioKeys: ["audio-1"], audioItems: [
                    "audio-1": AudioItem(
                        text: "テスト",
                        voice: VoiceReference(engineID: "", speakerID: "", styleID: 0),
                        query: AudioQuery(
                            accentPhrases: [
                                AccentPhrase(
                                    moras: [
                                        Mora(text: "テ", consonant: "t", consonantLength: 0.04, vowel: "e", vowelLength: 0.12, pitch: 1.0),
                                        Mora(text: "ス", consonant: "s", consonantLength: 0.04, vowel: "u", vowelLength: 0.12, pitch: 0.8),
                                        Mora(text: "ト", consonant: "t", consonantLength: 0.04, vowel: "o", vowelLength: 0.12, pitch: 0.6),
                                    ],
                                    accent: 2
                                )
                            ],
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
                            kana: "テスト"
                        ),
                        presetKey: "manual"
                    )
                ]),
                song: .empty
            )
        )

        viewModel.updatePhraseAccent(phraseIndex: 0, accent: 3)
        viewModel.splitPhraseAfter(phraseIndex: 0, moraIndex: 0)
        viewModel.mergePhraseWithPrevious(phraseIndex: 1)

        #expect(viewModel.selectedQuery?.accentPhrases.count == 1)
        #expect(viewModel.selectedQuery?.accentPhrases.first?.accent == 1)
        #expect(viewModel.accentEditorItems.first?.moras.count == 3)
    }

    @Test
    @MainActor
    func dictionaryManagerAddsEntryAndPersistsIt() {
        var persistedDictionary: UserDictionary?
        let viewModel = DictionaryManagerViewModel(
            dictionary: UserDictionary(entries: []),
            persist: { persistedDictionary = $0 }
        )
        var didChange = false
        viewModel.onDictionaryDidChange = {
            didChange = true
        }

        viewModel.editorSurface = "結月"
        viewModel.editorPronunciation = "ゆづき"
        viewModel.editorAccentType = 2
        viewModel.editorWordType = .properNoun
        viewModel.editorPriority = 9
        viewModel.saveEditingEntry()

        let savedEntry = viewModel.dictionary.entries.first
        #expect(savedEntry?.surface == "結月")
        #expect(savedEntry?.pronunciation == "ユヅキ")
        #expect(savedEntry?.accentType == 2)
        #expect(savedEntry?.priority == 9)
        #expect(didChange)
        #expect(persistedDictionary?.entries.first?.surface == "結月")
    }

    @Test
    @MainActor
    func dictionaryAccentPreviewUsesGraphMorasAndClampsAccent() {
        let viewModel = DictionaryManagerViewModel(
            dictionary: UserDictionary(entries: []),
            persist: { _ in }
        )

        viewModel.editorPronunciation = "きゃらめる"
        viewModel.editorAccentType = 9

        let preview = viewModel.editorAccentPreviewItem
        #expect(preview?.moras.map(\.text) == ["キャ", "ラ", "メ", "ル"])
        #expect(preview?.accent == 4)

        viewModel.updateEditorAccentType(2)
        #expect(viewModel.editorAccentType == 2)
        #expect(viewModel.editorAccentPreviewItem?.accent == 2)
    }

    @Test
    @MainActor
    func dictionaryUpdateInvalidatesExistingTalkQueries() {
        let talkEditor = TalkEditorViewModel(project: Self.emptyProject())
        let dictionaryManager = DictionaryManagerViewModel(
            dictionary: UserDictionary(entries: []),
            persist: { _ in }
        )
        let runtimeStatus = EngineRuntimeStatus(
            providerName: "Preview",
            availability: .linked,
            preferredExecutionProvider: "CoreML planned",
            coreMLAvailable: false,
            notes: []
        )
        let appViewModel = AppViewModel(
            talkEditor: talkEditor,
            modelManager: ModelManagerViewModel(
                installedModels: [],
                supportedDevices: SupportedDevices(cpu: true, gpu: false, neuralEnginePreferred: false, coreML: false),
                runtimeStatus: runtimeStatus
            ),
            presetManager: PresetManagerViewModel(
                catalog: PresetCatalog(items: [:], keys: []),
                defaultStyles: []
            ),
            dictionaryManager: dictionaryManager,
            settingsViewModel: SettingsViewModel(summary: "", runtimeStatus: runtimeStatus),
            helpViewModel: HelpViewModel(summary: "")
        )
        appViewModel.updateTalkText("辞書更新テスト")
        appViewModel.talkEditor.replaceSelectedQuery(
            AudioQuery(
                accentPhrases: [
                    AccentPhrase(
                        moras: [Mora(text: "辞書更新テスト", vowel: "a", vowelLength: 0.1, pitch: 1.0)],
                        accent: 1
                    )
                ],
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
                kana: "辞書更新テスト"
            ),
            presetKey: "manual"
        )

        appViewModel.dictionaryManager.editorSurface = "辞書更新テスト"
        appViewModel.dictionaryManager.editorPronunciation = "じしょこうしんてすと"
        appViewModel.dictionaryManager.saveEditingEntry()

        #expect(appViewModel.talkEditor.selectedQuery?.accentPhrases.isEmpty == true)
        #expect(appViewModel.talkActionStatusMessage == "辞書を更新しました。必要な行は再生成されます。")
    }

    private static func emptyProject() -> AISPProjectDocument {
        AISPProjectDocument(
            appVersion: "1.1.0-dev",
            talk: TalkProject(audioKeys: [], audioItems: [:]),
            song: .empty
        )
    }

    private static func projectWithTwoLines() -> AISPProjectDocument {
        AISPProjectDocument(
            appVersion: "1.1.0-dev",
            talk: TalkProject(audioKeys: ["audio-1", "audio-2"], audioItems: [
                "audio-1": AudioItem(
                    text: "一行目",
                    voice: VoiceReference(engineID: "engine", speakerID: "speaker-a", styleID: 1),
                    query: Self.query(text: "一行目"),
                    presetKey: "preset-a"
                ),
                "audio-2": AudioItem(
                    text: "二行目",
                    voice: VoiceReference(engineID: "engine", speakerID: "speaker-b", styleID: 2),
                    query: Self.query(text: "二行目"),
                    presetKey: "preset-b"
                ),
            ]),
            song: .empty
        )
    }

    private static func query(text: String) -> AudioQuery {
        AudioQuery(
            accentPhrases: [
                AccentPhrase(
                    moras: [Mora(text: text, vowel: "a", vowelLength: 0.18, pitch: 1.0)],
                    accent: 1
                )
            ],
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
    }
}

private struct MockSpeechEngine: SpeechEngine {
    func supportedDevices() async throws -> SupportedDevices {
        SupportedDevices(cpu: true, gpu: false, neuralEnginePreferred: false, coreML: false)
    }

    func makeAudioQuery(text: String, styleID: Int) async throws -> AudioQuery {
        AudioQuery(
            accentPhrases: [
                AccentPhrase(
                    moras: [Mora(text: text, vowel: "a", vowelLength: 0.18, pitch: 1.0)],
                    accent: 1
                )
            ],
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
    }

    func synthesize(query: AudioQuery, styleID: Int) async throws -> Data {
        try DiagnosticWAVWriter.makeWAVData(from: query, text: query.kana)
    }
}
