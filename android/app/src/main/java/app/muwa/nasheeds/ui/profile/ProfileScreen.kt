package app.muwa.nasheeds.ui.profile

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.*
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.muwa.nasheeds.*
import app.muwa.nasheeds.R
import app.muwa.nasheeds.ui.components.*
import app.muwa.nasheeds.ui.design.*

@Composable
fun ProfileScreen(model: MuwaModel, onRoute: (String) -> Unit) {
    LazyColumn(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item {
            Image(
                painterResource(R.drawable.app_mark),
                "Muwa",
                Modifier.size(80.dp).clip(RoundedCornerShape(22.dp)),
            )
            Text(
                model.user?.optString("displayName") ?: "Гость",
                style = MaterialTheme.typography.headlineSmall,
            )
            Text(
                model.user?.optString("email") ?: "Войдите, чтобы управлять аккаунтом",
                color = Color.Gray,
            )
        }
        if (model.user == null)
            item { Button(onClick = { onRoute("auth") }) { Text("Войти или создать аккаунт") } }
        item { ActionCard("Premium", Icons.Default.WorkspacePremium) { onRoute("premium") } }
        item { ActionCard("Промокод", Icons.Default.CardGiftcard) { onRoute("promo") } }
        item {
            ActionCard("Настройки и диагностика", Icons.Default.Settings) { onRoute("settings") }
        }
        if (model.user != null)
            item {
                TextButton(onClick = model::logout, enabled = !model.busy) {
                    Text("Выйти из аккаунта")
                }
            }
        item {
            Text(
                "Muwa · Нашиды без музыки\nВерсия ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
                fontSize = 12.sp,
                color = Color.Gray,
            )
        }
    }
}
