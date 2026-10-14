package app.muwa.nasheeds.ui.account

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import app.muwa.nasheeds.*
import org.json.JSONObject

@Composable
fun PremiumScreen(model: MuwaModel, promo: () -> Unit, login: () -> Unit) {
    LazyColumn(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        item {
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
                color = Color.Gray,
            )
        }
        item {
            Card {
                Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("Офлайн-прослушивание")
                    Text("Фоновое воспроизведение")
                    Text("Системное управление аудио")
                    Text("Субтитры доступны бесплатно")
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
                    color = Color.Gray,
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
