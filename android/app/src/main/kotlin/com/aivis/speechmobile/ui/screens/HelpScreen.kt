package com.aivis.speechmobile.ui.screens

import androidx.compose.runtime.Composable
import com.aivis.speechmobile.ui.HelpViewModel
import com.aivis.speechmobile.ui.components.AivisDivider
import com.aivis.speechmobile.ui.components.AivisKeyValueRow
import com.aivis.speechmobile.ui.components.AivisNotice
import com.aivis.speechmobile.ui.components.AivisOverview
import com.aivis.speechmobile.ui.components.AivisScrollableScreen
import com.aivis.speechmobile.ui.components.AivisSection

@Composable
fun HelpScreen(viewModel: HelpViewModel) {
    AivisScrollableScreen(title = "ヘルプ") {
        AivisOverview(
            title = "AivisSpeech Mobile",
            body = viewModel.summary,
        )
        AivisSection(title = "マイルストーン") {
            AivisKeyValueRow(label = "v0.1.0", value = "Android UI 層 初期リリース")
            AivisDivider()
            AivisKeyValueRow(label = "v0.2.0", value = "ONNX ランタイム統合")
            AivisDivider()
            AivisKeyValueRow(label = "v0.3.0", value = "モデル管理 UI 拡充")
            AivisDivider()
            AivisKeyValueRow(label = "v1.0.0", value = "iOS 機能パリティ完成")
        }
        AivisSection(title = "ライセンス・リンク") {
            AivisKeyValueRow(label = "GitHub", value = "aivis-project/AivisSpeech")
            AivisDivider()
            AivisKeyValueRow(label = "ライセンス", value = "LGPL-3.0")
            AivisDivider()
            AivisKeyValueRow(label = "モデル形式", value = "AIVMX (Style-Bert-VITS2)")
        }
        AivisNotice(body = "本アプリは AivisSpeech デスクトップ版と互換の .aisp プロジェクト形式をサポートします。iOS 版および Android 版で同一プロジェクトファイルを共有できます。")
    }
}
