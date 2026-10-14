package app.muwa.nasheeds.ui.settings

import android.content.Intent
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import app.muwa.nasheeds.*

@Composable
fun SettingsScreen(model: MuwaModel) {
    val context = LocalContext.current
    var errors by remember { mutableIntStateOf(Diagnostics.count()) }
    var remoteEnabled by remember { mutableStateOf(Diagnostics.remoteEnabled) }
    LaunchedEffect(Unit) { Diagnostics.flush() }
    Column(
        Modifier.padding(24.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Скачано: ${model.downloads.downloaded.size}")
        Text(
            "Занято: ${android.text.format.Formatter.formatFileSize(context,model.downloads.bytes())}"
        )
        Text("Диагностика", style = MaterialTheme.typography.headlineSmall)
        Text("Ошибок: $errors")
        Text(
            "Отчёты сохраняются на устройстве. Пароли, промокоды и содержимое запросов не записываются.",
            color = Color.Gray,
        )
        Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
            Switch(
                remoteEnabled,
                {
                    remoteEnabled = it
                    Diagnostics.remoteEnabled = it
                },
            )
            Text("Отправлять категории ошибок в Muwa")
        }
        Text(
            "После входа передаются только категория, код ошибки и версия приложения. Хранение на сервере — 14 дней.",
            color = Color.Gray,
        )
        Button(
            onClick = {
                runCatching {
                        val file = Diagnostics.export(context)
                        val uri =
                            FileProvider.getUriForFile(
                                context,
                                "${context.packageName}.files",
                                file,
                            )
                        context.startActivity(
                            Intent.createChooser(
                                Intent(Intent.ACTION_SEND)
                                    .setType("application/json")
                                    .putExtra(Intent.EXTRA_STREAM, uri)
                                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
                                "Диагностика Muwa",
                            )
                        )
                    }
                    .onFailure { model.error = it.message }
            }
        ) {
            Text("Поделиться отчётом")
        }
        TextButton(
            onClick = {
                Diagnostics.clear()
                errors = 0
            }
        ) {
            Text("Очистить диагностику")
        }
        Text(
            "Системный размер текста и уменьшение анимаций учитываются автоматически.",
            color = Color.Gray,
        )
    }
}
