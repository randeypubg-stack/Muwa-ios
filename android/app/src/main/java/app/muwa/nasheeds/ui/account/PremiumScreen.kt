package app.muwa.nasheeds.ui.account

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import app.muwa.nasheeds.*
import app.muwa.nasheeds.ui.design.*
import org.json.JSONObject

@Composable
fun PremiumScreen(model: MuwaModel, promo: () -> Unit, login: () -> Unit) {
    LazyColumn(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        item {
            Icon(MuwaSymbols.Crown, null, Modifier.size(32.dp), tint = MuwaColors.Ice)
            Spacer(Modifier.height(16.dp))
            Text(
                if (model.premium?.optBoolean("isPremium") == true) "Ваш Muwa Premium"
                else "Больше свободы\nс Muwa Premium",
                style = MaterialTheme.typography.headlineLarge,
            )
        }
        item {
            Text("Все функции доступны для проверки", style = MaterialTheme.typography.titleMedium)
            Text(
                "Офлайн, фоновое прослушивание и управление с экрана блокировки сейчас работают без покупки. Premium-статус аккаунта сохраняется отдельно.",
                color = MuwaColors.Secondary,
            )
        }
        item {
            Column(
                Modifier.fillMaxWidth().glassPanel(24.dp).padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                listOf(
                        listOf(
                            "Слушайте в фоне" to Icons.Default.Headphones,
                            "Сохраняйте офлайн" to Icons.Default.DownloadForOffline,
                        ),
                        listOf(
                            "Выбирайте аудиовыход" to MuwaSymbols.AudioOutput,
                            "Управляйте с экрана блокировки" to Icons.Default.Smartphone,
                        ),
                    )
                    .forEach { row ->
                        Row(horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                            row.forEach { (title, icon) ->
                                Column(
                                    Modifier.weight(1f).heightIn(min = 72.dp),
                                    verticalArrangement = Arrangement.spacedBy(10.dp),
                                ) {
                                    Icon(icon, null, Modifier.size(24.dp), tint = MuwaColors.Ice)
                                    Text(title, style = MaterialTheme.typography.bodyMedium)
                                }
                            }
                        }
                    }
            }
        }
        item {
            if (model.premium?.optBoolean("isPremium") == true) {
                Text("Premium активен", color = Color(0xFF91DCA0))
                Text(
                    model.premium
                        ?.optString("expiresAt")
                        ?.takeUnless { it == "null" || it.isEmpty() }
                        ?.let { "Доступ по аккаунту до $it" }
                        ?: "Бессрочный доступ по аккаунту Muwa"
                )
            } else
                Text(
                    "Подписки Google Play пока не настроены. Подарочный Premium работает через ваш аккаунт Muwa.",
                    color = MuwaColors.Secondary,
                )
        }
        item {
            Button(onClick = promo, modifier = Modifier.fillMaxWidth()) {
                Text("Активировать промокод")
            }
        }
        if (model.user == null) item { TextButton(onClick = login) { Text("Войти в Muwa") } }
        else
            item {
                TextButton(
                    onClick = { model.premiumAction(JSONObject().put("action", "status")) },
                    enabled = !model.busy,
                ) {
                    Text("Обновить доступ")
                }
            }
        model.message?.let { item { Text(it) } }
    }
}
