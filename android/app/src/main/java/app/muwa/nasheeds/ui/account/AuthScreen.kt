package app.muwa.nasheeds.ui.account

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.*
import androidx.compose.ui.unit.dp
import app.muwa.nasheeds.MuwaModel
import app.muwa.nasheeds.ui.design.*
import app.muwa.nasheeds.ui.state.rememberSaveableState

@Composable
fun AuthScreen(model: MuwaModel, onComplete: () -> Unit) {
    var email by rememberSaveableState("")
    var password by remember { mutableStateOf("") }
    var confirmation by remember { mutableStateOf("") }
    var name by rememberSaveableState("")
    var register by rememberSaveableState(false)
    var revealPassword by remember { mutableStateOf(false) }
    var revealConfirmation by remember { mutableStateOf(false) }
    LaunchedEffect(model.user) { if (model.user != null) onComplete() }
    val fieldColors =
        TextFieldDefaults.colors(
            focusedContainerColor = Color.White.copy(alpha = .055f),
            unfocusedContainerColor = Color.White.copy(alpha = .055f),
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
        )
    Box(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).imePadding().padding(20.dp),
        contentAlignment = Alignment.TopCenter,
    ) {
        Column(
            Modifier.widthIn(max = 460.dp).fillMaxWidth().glassPanel(30.dp).padding(22.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Text(
                if (register) "Создайте аккаунт Muwa" else "Добро пожаловать обратно",
                style = MaterialTheme.typography.headlineSmall,
            )
            Text(
                if (register) "Сохраните любимые нашиды в своём аккаунте"
                else "Войдите в свой аккаунт, чтобы продолжить",
                style = MaterialTheme.typography.bodyMedium,
                color = MuwaColors.Secondary,
            )
            if (register)
                TextField(
                    name,
                    { name = it },
                    placeholder = { Text("Ваше имя") },
                    singleLine = true,
                    leadingIcon = { Icon(Icons.Default.PersonOutline, null) },
                    shape = RoundedCornerShape(17.dp),
                    colors = fieldColors,
                    modifier = Modifier.fillMaxWidth().testTag("auth.name"),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
                )
            TextField(
                email,
                { email = it },
                placeholder = { Text("Email") },
                singleLine = true,
                leadingIcon = { Icon(Icons.Default.MailOutline, null) },
                shape = RoundedCornerShape(17.dp),
                colors = fieldColors,
                modifier = Modifier.fillMaxWidth().testTag("auth.email"),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
            )
            TextField(
                password,
                { password = it },
                placeholder = { Text(if (register) "Пароль — минимум 8 символов" else "Пароль") },
                singleLine = true,
                visualTransformation =
                    if (revealPassword) VisualTransformation.None
                    else PasswordVisualTransformation(),
                leadingIcon = { Icon(Icons.Default.Lock, null) },
                trailingIcon = {
                    IconButton(onClick = { revealPassword = !revealPassword }) {
                        Icon(
                            if (revealPassword) Icons.Default.VisibilityOff
                            else Icons.Default.Visibility,
                            if (revealPassword) "Скрыть пароль" else "Показать пароль",
                        )
                    }
                },
                shape = RoundedCornerShape(17.dp),
                colors = fieldColors,
                modifier = Modifier.fillMaxWidth().testTag("auth.password"),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            )
            if (register)
                TextField(
                    confirmation,
                    { confirmation = it },
                    placeholder = { Text("Повторите пароль") },
                    singleLine = true,
                    visualTransformation =
                        if (revealConfirmation) VisualTransformation.None
                        else PasswordVisualTransformation(),
                    leadingIcon = { Icon(Icons.Default.Lock, null) },
                    trailingIcon = {
                        IconButton(onClick = { revealConfirmation = !revealConfirmation }) {
                            Icon(
                                if (revealConfirmation) Icons.Default.VisibilityOff
                                else Icons.Default.Visibility,
                                "Видимость подтверждения пароля",
                            )
                        }
                    },
                    shape = RoundedCornerShape(17.dp),
                    colors = fieldColors,
                    modifier = Modifier.fillMaxWidth().testTag("auth.confirmation"),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                )
            Button(
                onClick = {
                    model.login(email.trim(), password, if (register) name.trim() else null)
                },
                enabled =
                    !model.busy &&
                        android.util.Patterns.EMAIL_ADDRESS.matcher(email.trim()).matches() &&
                        password.isNotEmpty() &&
                        (!register ||
                            (name.isNotBlank() &&
                                password.length >= 8 &&
                                password == confirmation)),
                modifier = Modifier.fillMaxWidth().height(54.dp).testTag("auth.submit"),
                shape = RoundedCornerShape(18.dp),
                colors =
                    ButtonDefaults.buttonColors(
                        containerColor = Color.White,
                        contentColor = Color.Black,
                        disabledContainerColor = Color.White.copy(alpha = .45f),
                        disabledContentColor = Color.Black,
                    ),
            ) {
                Text(
                    if (model.busy) "Подождите…"
                    else if (register) "Зарегистрироваться" else "Войти"
                )
            }
            TextButton(
                onClick = {
                    register = !register
                    confirmation = ""
                },
                modifier = Modifier.fillMaxWidth().testTag("auth.register-switch"),
            ) {
                Text(
                    if (register) "Уже есть аккаунт? Войти" else "Нет аккаунта? Зарегистрироваться"
                )
            }
            model.message?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MuwaColors.Secondary)
            }
        }
    }
}
