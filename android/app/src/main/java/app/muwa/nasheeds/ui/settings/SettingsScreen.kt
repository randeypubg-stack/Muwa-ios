package app.muwa.nasheeds.ui.settings

import android.content.Intent
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import app.muwa.nasheeds.*
import app.muwa.nasheeds.ui.design.*

@Composable
fun SettingsScreen(model: MuwaModel) {
    val context = LocalContext.current
    var errors by remember { mutableIntStateOf(Diagnostics.count()) }
    var remoteEnabled by remember { mutableStateOf(Diagnostics.remoteEnabled) }
    var confirmClear by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { Diagnostics.flush() }
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(22.dp),
    ) {
        SettingsGroup("Офлайн") {
            SettingsValue("Скачано нашидов", model.downloads.downloaded.size.toString())
            SettingsValue(
                "Занято на устройстве",
                android.text.format.Formatter.formatFileSize(context, model.downloads.bytes()),
            )
            Text(
                "Загрузки хранятся в приложении. Управлять отдельными файлами можно в Библиотеке → Загрузки.",
                style = MaterialTheme.typography.bodySmall,
                color = MuwaColors.Secondary,
            )
        }
        SettingsGroup("Диагностика") {
            SettingsValue("Ошибки", errors.toString())
            Text(
                "Ошибки сохраняются на устройстве. Пароли, промокоды и содержимое запросов не записываются.",
                style = MaterialTheme.typography.bodySmall,
                color = MuwaColors.Secondary,
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "Отправлять категории ошибок в Muwa",
                    Modifier.weight(1f),
                    style = MaterialTheme.typography.bodyMedium,
                )
                Switch(
                    remoteEnabled,
                    {
                        remoteEnabled = it
                        Diagnostics.remoteEnabled = it
                    },
                    colors =
                        SwitchDefaults.colors(
                            checkedTrackColor = Color(0xFF30D158),
                            checkedThumbColor = Color.White,
                        ),
                )
            }
            Text(
                "После входа передаются только категория, код ошибки и версия приложения. Хранение на сервере — 14 дней.",
                style = MaterialTheme.typography.bodySmall,
                color = MuwaColors.Secondary,
            )
            TextButton(
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
            TextButton(onClick = { confirmClear = true }) {
                Text("Очистить диагностику", color = Color(0xFFFF6868))
            }
        }
        SettingsGroup("Доступность") {
            Text(
                "Системный размер текста и уменьшение анимаций учитываются автоматически.",
                style = MaterialTheme.typography.bodyMedium,
                color = MuwaColors.Secondary,
            )
        }
    }
    if (confirmClear)
        AlertDialog(
            onDismissRequest = { confirmClear = false },
            title = { Text("Очистить сохранённые отчёты?") },
            confirmButton = {
                TextButton(
                    onClick = {
                        Diagnostics.clear()
                        errors = 0
                        confirmClear = false
                    }
                ) {
                    Text("Очистить")
                }
            },
            dismissButton = { TextButton(onClick = { confirmClear = false }) { Text("Отмена") } },
        )
}

@Composable
private fun SettingsGroup(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            title,
            style = MaterialTheme.typography.bodySmall,
            color = MuwaColors.Secondary,
            fontWeight = FontWeight.SemiBold,
        )
        Column(
            Modifier.fillMaxWidth().glassPanel(20.dp).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
            content = content,
        )
    }
}

@Composable
private fun SettingsValue(title: String, value: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
        Text(value, color = MuwaColors.Secondary)
    }
}
