package com.aivis.speechmobile.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aivis.speechmobile.core.EngineRuntimeStatus
import com.aivis.speechmobile.core.InstalledModel
import com.aivis.speechmobile.ui.ModelManagerViewModel
import com.aivis.speechmobile.ui.components.AivisDivider
import com.aivis.speechmobile.ui.components.AivisKeyValueRow
import com.aivis.speechmobile.ui.components.AivisNotice
import com.aivis.speechmobile.ui.components.AivisOverview
import com.aivis.speechmobile.ui.components.AivisScrollableScreen
import com.aivis.speechmobile.ui.components.AivisSection
import com.aivis.speechmobile.ui.theme.LocalAivisColors
import java.util.UUID

@Composable
fun ModelsScreen(viewModel: ModelManagerViewModel) {
    val installedModels by viewModel.installedModels.collectAsStateWithLifecycle()
    val busyModelID by viewModel.busyModelID.collectAsStateWithLifecycle()
    val statusMessage by viewModel.statusMessage.collectAsStateWithLifecycle()
    val colors = LocalAivisColors.current
    val status = viewModel.runtimeStatus

    AivisScrollableScreen(title = "モデル") {
        AivisOverview(
            title = status.providerName,
            body = if (status.availability == EngineRuntimeStatus.Availability.LINKED)
                "ランタイムが接続されています。モデルを選択して読み上げを開始できます。"
            else
                "ランタイムはまだ注入されていません。プレビューモードで動作しています。",
        )

        if (statusMessage != null) {
            AivisNotice(body = statusMessage!!)
        }

        AivisSection(title = "インストール済みモデル (${installedModels.size})") {
            if (installedModels.isEmpty()) {
                Text(
                    text = "インストール済みのモデルはありません。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = colors.mutedText,
                    modifier = Modifier.padding(16.dp),
                )
            } else {
                installedModels.forEachIndexed { i, model ->
                    if (i > 0) AivisDivider()
                    ModelListItem(
                        model = model,
                        isBusy = busyModelID == model.id,
                        onActivate = { viewModel.activateModel(model.id) },
                        onLoad = { viewModel.loadModel(model.id) },
                        onUnload = { viewModel.unloadModel(model.id) },
                    )
                }
            }
        }

        AivisSection(title = "エンジン情報") {
            AivisKeyValueRow(label = "実行プロバイダー", value = status.preferredExecutionProvider)
            status.linkedVersion?.let { ver ->
                AivisDivider()
                AivisKeyValueRow(label = "ONNX バージョン", value = ver)
            }
            AivisDivider()
            AivisKeyValueRow(
                label = "NNAPI",
                value = if (status.nnApiAvailable) "利用可能" else "利用不可",
            )
            AivisDivider()
            AivisKeyValueRow(
                label = "ロード中モデル数",
                value = "${viewModel.loadedModelCount}",
            )
        }

        AivisNotice(body = viewModel.seededRepositoryNotice)
    }
}

@Composable
private fun ModelListItem(
    model: InstalledModel,
    isBusy: Boolean,
    onActivate: () -> Unit,
    onLoad: () -> Unit,
    onUnload: () -> Unit,
) {
    val colors = LocalAivisColors.current
    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = model.name,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Text(
                    text = "v${model.version}",
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.mutedText,
                )
            }
            if (isBusy) {
                CircularProgressIndicator(
                    modifier = Modifier.size(20.dp),
                    color = colors.accent,
                    strokeWidth = 2.dp,
                )
            } else {
                LoadStateBadge(loadState = model.loadState)
            }
        }

        model.manifest?.let { mf ->
            Spacer(Modifier.height(4.dp))
            Text(
                text = "${mf.modelArchitecture} · ${mf.speakers.size}話者 · ${mf.speakers.sumOf { it.styles.size }}スタイル",
                style = MaterialTheme.typography.bodySmall,
                color = colors.mutedText,
            )
        }

        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            when (model.loadState) {
                InstalledModel.LoadState.INSTALLED -> {
                    OutlinedButton(
                        onClick = onLoad,
                        enabled = !isBusy,
                        modifier = Modifier.height(32.dp),
                    ) {
                        Text("ロード", style = MaterialTheme.typography.labelSmall)
                    }
                }
                InstalledModel.LoadState.LOADED -> {
                    Button(
                        onClick = onActivate,
                        enabled = !isBusy,
                        modifier = Modifier.height(32.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = colors.accent),
                    ) {
                        Text("アクティブにする", style = MaterialTheme.typography.labelSmall)
                    }
                    Spacer(Modifier.width(4.dp))
                    OutlinedButton(
                        onClick = onUnload,
                        enabled = !isBusy,
                        modifier = Modifier.height(32.dp),
                    ) {
                        Text("アンロード", style = MaterialTheme.typography.labelSmall)
                    }
                }
                InstalledModel.LoadState.ACTIVE -> {
                    OutlinedButton(
                        onClick = onUnload,
                        enabled = !isBusy,
                        modifier = Modifier.height(32.dp),
                    ) {
                        Text("アンロード", style = MaterialTheme.typography.labelSmall)
                    }
                }
            }
        }
    }
}

@Composable
private fun LoadStateBadge(loadState: InstalledModel.LoadState) {
    val colors = LocalAivisColors.current
    val (label, color) = when (loadState) {
        InstalledModel.LoadState.ACTIVE -> "使用中" to colors.accent
        InstalledModel.LoadState.LOADED -> "ロード済み" to colors.success
        InstalledModel.LoadState.INSTALLED -> "インストール済み" to colors.mutedText
    }
    Surface(
        shape = RoundedCornerShape(4.dp),
        color = color.copy(alpha = 0.15f),
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = color,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
        )
    }
}
