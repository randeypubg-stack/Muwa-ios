package app.muwa.nasheeds.ui.profile

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.*
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.muwa.nasheeds.*
import app.muwa.nasheeds.R
import app.muwa.nasheeds.ui.design.*
import coil.compose.AsyncImage
import org.json.JSONObject

@Composable
fun ProfileScreen(model: MuwaModel, onRoute: (String) -> Unit) {
    var about by remember { mutableStateOf(false) }
    val identity: @Composable (Modifier) -> Unit = { modifier ->
        Column(modifier, verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                AsyncImage(
                    model.user?.optString("avatarUrl")?.takeIf { it.startsWith("https://") },
                    "Muwa",
                    Modifier.size(62.dp).clip(CircleShape),
                    placeholder = painterResource(R.drawable.app_mark),
                    error = painterResource(R.drawable.app_mark),
                    contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                )
                Column(
                    Modifier.weight(1f).padding(start = 14.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(
                        model.user?.optString("displayName") ?: "Гость",
                        fontSize = 20.sp,
                        lineHeight = 24.sp,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        model.user?.optString("email") ?: "Войдите, чтобы управлять аккаунтом",
                        fontSize = 12.sp,
                        lineHeight = 16.sp,
                        color = MuwaColors.Secondary,
                    )
                    Text(
                        if (model.premium?.optBoolean("isPremium") == true) "Premium активен"
                        else "Бесплатный доступ",
                        fontSize = 11.sp,
                        lineHeight = 14.sp,
                        color = MuwaColors.Secondary,
                    )
                }
            }
            if (model.user == null)
                ProfileRow(
                    "Войти или создать аккаунт",
                    Icons.Default.PersonAdd,
                    Modifier.glassPanel(18.dp),
                ) {
                    onRoute("auth")
                }
            Row(
                Modifier.fillMaxWidth()
                    .glassPanel()
                    .clickable { onRoute("premium") }
                    .padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(MuwaSymbols.Crown, null, tint = Color(0xFFF0C785))
                Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                    Text("Premium", fontWeight = FontWeight.Bold)
                    Text(
                        if (model.premium?.optBoolean("isPremium") == true) "Управление подпиской"
                        else "Поддержка и управление доступом",
                        fontSize = 12.sp,
                        lineHeight = 16.sp,
                        color = MuwaColors.Secondary,
                    )
                }
                Icon(Icons.Default.ChevronRight, null, tint = MuwaColors.Secondary)
            }
        }
    }
    val settings: @Composable (Modifier) -> Unit = { modifier ->
        Column(modifier.glassPanel(22.dp).padding(horizontal = 4.dp)) {
            ProfileRow("ПРОМОКОД", Icons.Default.CardGiftcard) { onRoute("promo") }
            HorizontalDivider(color = Color.White.copy(alpha = .05f))
            ProfileRow("Настройки приложения", Icons.Default.Settings) { onRoute("settings") }
            HorizontalDivider(color = Color.White.copy(alpha = .05f))
            ProfileRow("Восстановить доступ", Icons.Default.Refresh) {
                if (model.user == null) onRoute("auth")
                else model.premiumAction(JSONObject().put("action", "status"))
            }
            HorizontalDivider(color = Color.White.copy(alpha = .05f))
            ProfileRow("О приложении", Icons.Default.Info) { about = true }
            if (model.user != null) {
                HorizontalDivider(color = Color.White.copy(alpha = .05f))
                ProfileRow(
                    "Выйти из аккаунта",
                    Icons.AutoMirrored.Filled.Logout,
                    destructive = true,
                ) {
                    model.logout()
                }
            }
        }
    }
    val smallestWidth = LocalConfiguration.current.smallestScreenWidthDp
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val layout = MuwaAdaptiveLayout(maxWidth.value, maxHeight.value, smallestWidth)
        val wide = layout.wideTablet
        Column(
            Modifier.widthIn(max = 920.dp)
                .align(Alignment.TopCenter)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = layout.screenPadding.dp, vertical = 18.dp),
            verticalArrangement = Arrangement.spacedBy(22.dp),
        ) {
            if (wide)
                Row(horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                    identity(Modifier.weight(1f))
                    settings(Modifier.weight(1f))
                }
            else {
                identity(Modifier)
                settings(Modifier)
            }
            model.message?.let {
                Text(it, fontSize = 12.sp, lineHeight = 16.sp, color = MuwaColors.Secondary)
            }
            Text(
                "Muwa · Нашиды без музыки",
                Modifier.fillMaxWidth(),
                fontSize = 11.sp,
                lineHeight = 14.sp,
                color = MuwaColors.Secondary.copy(alpha = .6f),
                textAlign = TextAlign.Center,
            )
        }
    }
    if (about)
        AlertDialog(
            onDismissRequest = { about = false },
            icon = { Image(painterResource(R.drawable.app_mark), "Muwa", Modifier.size(72.dp)) },
            title = { Text("Muwa") },
            text = {
                Text(
                    "Нативное приложение для прослушивания нашидов без музыки.\n\nВерсия ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"
                )
            },
            confirmButton = { TextButton(onClick = { about = false }) { Text("Готово") } },
        )
}

@Composable
private fun ProfileRow(
    title: String,
    icon: ImageVector,
    modifier: Modifier = Modifier,
    destructive: Boolean = false,
    click: () -> Unit,
) {
    Row(
        modifier
            .fillMaxWidth()
            .clickable(onClick = click)
            .padding(horizontal = 14.dp, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val color = if (destructive) Color(0xFFFF6868) else MuwaColors.Text
        Icon(icon, null, Modifier.size(24.dp), tint = color)
        Text(
            title,
            Modifier.weight(1f).padding(start = 12.dp),
            fontSize = 15.sp,
            lineHeight = 20.sp,
            color = color,
        )
        if (!destructive)
            Icon(
                Icons.Default.ChevronRight,
                null,
                Modifier.size(18.dp),
                tint = MuwaColors.Secondary,
            )
    }
}
