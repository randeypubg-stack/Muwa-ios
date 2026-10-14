package app.muwa.nasheeds.ui.account

import android.content.Intent
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import app.muwa.nasheeds.*
import app.muwa.nasheeds.ui.state.rememberSaveableState
import org.json.JSONObject

@Composable
fun PromoScreen(model: MuwaModel, login: () -> Unit) {
    var code by rememberSaveableState("")
    var label by rememberSaveableState("")
    var days by rememberSaveableState("30")
    var uses by rememberSaveableState("1")
    var validity by rememberSaveableState("30")
    var discard by remember { mutableStateOf(false) }
    var disabling by remember { mutableStateOf<String?>(null) }
    val context = LocalContext.current
    androidx.activity.compose.BackHandler(model.createdCode != null) { discard = true }
    LazyColumn(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item { Text("Подарочный доступ Muwa", style = MaterialTheme.typography.headlineSmall) }
        if (model.user == null) item { Button(onClick = login) { Text("Войти в Muwa") } }
        else
            item {
                OutlinedTextField(
                    code,
                    { code = it },
                    label = { Text("MUWA-…") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Button(
                    onClick = {
                        model.premiumAction(
                            JSONObject().put("action", "redeem").put("code", code.trim())
                        )
                    },
                    enabled = !model.busy && code.isNotBlank(),
                ) {
                    Text("Активировать")
                }
            }
        if (model.premium?.optBoolean("canManageCodes") == true) {
            item {
                Text("Создать подарочный код", style = MaterialTheme.typography.titleLarge)
                OutlinedTextField(
                    label,
                    { label = it },
                    label = { Text("Название") },
                    enabled = !model.busy && model.createdCode == null,
                )
                OutlinedTextField(days, { days = it }, label = { Text("Дни Premium · 1–365") })
                OutlinedTextField(uses, { uses = it }, label = { Text("Активации · 1–1000") })
                OutlinedTextField(
                    validity,
                    { validity = it },
                    label = { Text("Дни для активации · 1–365") },
                )
                Button(
                    onClick = {
                        model.premiumAction(
                            JSONObject()
                                .put("action", "create")
                                .put("label", label.trim())
                                .put("durationDays", days.toInt())
                                .put("maxUses", uses.toInt())
                                .put("validDays", validity.toInt())
                        )
                    },
                    enabled =
                        !model.busy &&
                            model.createdCode == null &&
                            label.isNotBlank() &&
                            (days.toIntOrNull() ?: 0) in 1..365 &&
                            (uses.toIntOrNull() ?: 0) in 1..1000 &&
                            (validity.toIntOrNull() ?: 0) in 1..365,
                ) {
                    Text("Создать код")
                }
            }
            if (model.createdCode != null)
                item {
                    Text(
                        "Сохраните код перед закрытием",
                        style = MaterialTheme.typography.titleMedium,
                    )
                    androidx.compose.foundation.text.selection.SelectionContainer {
                        Text(model.createdCode!!)
                    }
                    Text("Полный код показывается только сейчас.", color = Color.Gray)
                    TextButton(
                        onClick = {
                            context.startActivity(
                                Intent.createChooser(
                                    Intent(Intent.ACTION_SEND)
                                        .setType("text/plain")
                                        .putExtra(Intent.EXTRA_TEXT, model.createdCode),
                                    "Подарочный код Muwa",
                                )
                            )
                        }
                    ) {
                        Text("Поделиться")
                    }
                    TextButton(onClick = model::savedCode) { Text("Код сохранён") }
                }
            item {
                TextButton(
                    onClick = { model.premiumAction(JSONObject().put("action", "list")) },
                    enabled = !model.busy,
                ) {
                    Text("Обновить список кодов")
                }
            }
            items(model.codes, key = { it.getString("id") }) { item ->
                Card {
                    Column(Modifier.padding(16.dp)) {
                        Text(item.optString("label"))
                        Text(
                            "${item.optInt("durationDays")} дней · ${item.optInt("uses")} из ${item.optInt("maxUses")}"
                        )
                        if (item.optBoolean("disabled")) Text("Отключён")
                        else
                            TextButton(onClick = { disabling = item.getString("id") }) {
                                Text("Отключить новые активации")
                            }
                    }
                }
            }
        }
        model.message?.let { item { Text(it) } }
    }
    if (discard)
        AlertDialog(
            onDismissRequest = { discard = false },
            title = { Text("Полный код больше не будет показан") },
            text = { Text("Сохраните код или подтвердите закрытие.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        model.savedCode()
                        discard = false
                    }
                ) {
                    Text("Закрыть без сохранения")
                }
            },
            dismissButton = { TextButton(onClick = { discard = false }) { Text("Вернуться") } },
        )
    if (disabling != null)
        AlertDialog(
            onDismissRequest = { disabling = null },
            title = { Text("Отключить код?") },
            text = { Text("Уже выданный Premium сохранится.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        model.premiumAction(
                            JSONObject().put("action", "disable").put("id", disabling)
                        )
                        disabling = null
                    }
                ) {
                    Text("Отключить")
                }
            },
            dismissButton = { TextButton(onClick = { disabling = null }) { Text("Отмена") } },
        )
}
