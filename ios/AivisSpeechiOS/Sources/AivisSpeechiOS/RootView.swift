import SwiftUI

struct RootView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        TabView(selection: $viewModel.selectedTab) {
            TalkEditorView(
                viewModel: viewModel.talkEditor,
                presetManager: viewModel.presetManager,
                runtimeStatus: viewModel.modelManager.runtimeStatus,
                styleOptions: viewModel.talkStyleOptions,
                actionStatusMessage: viewModel.talkActionStatusMessage,
                exportedWAVURL: viewModel.lastExportedWAVURL,
                exportedWAVByteCountLabel: viewModel.exportedWAVByteCountLabel,
                isActionRunning: viewModel.isTalkActionRunning,
                isPreviewPlaying: viewModel.isPreviewPlaying,
                playbackCurrentTime: viewModel.playbackCurrentTime,
                playbackDuration: viewModel.playbackDuration,
                playbackCurrentTimeLabel: viewModel.playbackCurrentTimeLabel,
                playbackDurationLabel: viewModel.playbackDurationLabel,
                onUpdateText: { text in
                    viewModel.updateTalkText(text)
                },
                onSelectStyle: { option in
                    viewModel.selectTalkStyle(option)
                },
                onUpdatePhraseAccent: { phraseIndex, accent in
                    viewModel.updateTalkPhraseAccent(phraseIndex: phraseIndex, accent: accent)
                },
                onMovePhraseAccent: { phraseIndex, delta in
                    viewModel.moveTalkPhraseAccent(phraseIndex: phraseIndex, delta: delta)
                },
                onSplitPhraseAfter: { phraseIndex, moraIndex in
                    viewModel.splitTalkPhraseAfter(phraseIndex: phraseIndex, moraIndex: moraIndex)
                },
                onMergePhraseWithPrevious: { phraseIndex in
                    viewModel.mergeTalkPhraseWithPrevious(phraseIndex: phraseIndex)
                },
                onRegenerateQuery: {
                    Task {
                        await viewModel.regenerateTalkQuery()
                    }
                },
                onTestSynthesis: {
                    Task {
                        await viewModel.testSynthesis()
                    }
                },
                onExportWAV: {
                    Task {
                        await viewModel.exportTalkWAV()
                    }
                },
                onExportAllWAV: {
                    Task {
                        await viewModel.exportAllTalkWAV()
                    }
                },
                onTogglePreviewPlayback: {
                    viewModel.togglePreviewPlayback()
                },
                onSeekPreview: { time in
                    viewModel.seekPreview(to: time)
                }
            )
            .tabItem {
                Label(AppTab.talk.title, systemImage: AppTab.talk.systemImage)
            }
            .tag(AppTab.talk)

            ModelsView(viewModel: viewModel.modelManager)
                .tabItem {
                    Label(AppTab.models.title, systemImage: AppTab.models.systemImage)
                }
                .tag(AppTab.models)

            PresetsView(viewModel: viewModel.presetManager)
                .tabItem {
                    Label(AppTab.presets.title, systemImage: AppTab.presets.systemImage)
                }
                .tag(AppTab.presets)

            DictionaryView(viewModel: viewModel.dictionaryManager)
                .tabItem {
                    Label(AppTab.dictionary.title, systemImage: AppTab.dictionary.systemImage)
                }
                .tag(AppTab.dictionary)

            SettingsView(viewModel: viewModel.settingsViewModel)
                .tabItem {
                    Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage)
                }
                .tag(AppTab.settings)

            HelpView(viewModel: viewModel.helpViewModel)
                .tabItem {
                    Label(AppTab.help.title, systemImage: AppTab.help.systemImage)
                }
                .tag(AppTab.help)
        }
        .background(AivisUI.background.ignoresSafeArea())
#if os(iOS)
        .toolbarBackground(AivisUI.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
#endif
        .tint(AivisUI.accent)
        .task {
            await viewModel.prepareRuntimeState()
        }
    }
}
