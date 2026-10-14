package app.muwa.nasheeds.ui.account

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import app.muwa.nasheeds.*
import app.muwa.nasheeds.ui.state.rememberSaveableState

@Composable
fun AuthScreen(model: MuwaModel) {
    var email by rememberSaveableState("")
    var password by rememberSaveableState("")
    var name by rememberSaveableState("")
    var register by rememberSaveableState(false)
    Column(
        Modifier.padding(24.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            if (register) "Создать аккаунт Muwa" else "Войти в Muwa",
            style = MaterialTheme.typography.headlineSmall,
        )
        if (register)
            OutlinedTextField(
                name,
                { name = it },
                label = { Text("Имя") },
                modifier = Modifier.fillMaxWidth(),
            )
        OutlinedTextField(
            email,
            { email = it },
            label = { Text("Почта") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            password,
            { password = it },
            label = { Text("Пароль") },
            visualTransformation = PasswordVisualTransformation(),
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        Button(
            onClick = { model.login(email, password, if (register) name else null) },
            enabled = !model.busy && email.isNotBlank() && password.length >= 8,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(if (model.busy) "Подождите…" else if (register) "Создать аккаунт" else "Войти")
        }
        TextButton(onClick = { register = !register }) {
            Text(if (register) "Уже есть аккаунт" else "Создать аккаунт")
        }
        model.message?.let { Text(it) }
    }
}
