package app.muwa.nasheeds

import android.content.Intent
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.graphics.Color
import androidx.core.content.FileProvider
import org.json.JSONObject

@Composable fun AuthScreen(model: MuwaModel) {
    var email by rememberSaveableState(""); var password by rememberSaveableState(""); var name by rememberSaveableState(""); var register by rememberSaveableState(false)
    Column(Modifier.padding(24.dp).verticalScroll(rememberScrollState()),verticalArrangement=Arrangement.spacedBy(16.dp)) {
        Text(if(register) "Создать аккаунт Muwa" else "Войти в Muwa",style=MaterialTheme.typography.headlineSmall)
        if(register) OutlinedTextField(name,{name=it},label={Text("Имя")},modifier=Modifier.fillMaxWidth())
        OutlinedTextField(email,{email=it},label={Text("Почта")},singleLine=true,modifier=Modifier.fillMaxWidth())
        OutlinedTextField(password,{password=it},label={Text("Пароль")},visualTransformation=PasswordVisualTransformation(),singleLine=true,modifier=Modifier.fillMaxWidth())
        Button(onClick={model.login(email,password,if(register) name else null)},enabled=!model.busy&&email.isNotBlank()&&password.length>=8,modifier=Modifier.fillMaxWidth()) {Text(if(model.busy) "Подождите…" else if(register) "Создать аккаунт" else "Войти")}
        TextButton(onClick={register=!register}) {Text(if(register) "Уже есть аккаунт" else "Создать аккаунт")}
        model.message?.let {Text(it)}
    }
}
@Composable fun PremiumScreen(model: MuwaModel,promo: ()->Unit,login: ()->Unit) {
    LazyColumn(Modifier.padding(24.dp),verticalArrangement=Arrangement.spacedBy(18.dp)) {
        item {Text(if(model.premium?.optBoolean("isPremium")==true) "Ваш Muwa Premium" else "Больше свободы\nс Muwa Premium",style=MaterialTheme.typography.headlineLarge)}
        item {Text("Все функции доступны для проверки",style=MaterialTheme.typography.titleMedium);Text("Офлайн, фоновое прослушивание и управление с экрана блокировки сейчас работают без покупки. Premium-статус аккаунта сохраняется отдельно.",color=Color.Gray)}
        item {Card {Column(Modifier.padding(20.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {Text("Офлайн-прослушивание");Text("Фоновое воспроизведение");Text("Системное управление аудио");Text("Субтитры доступны бесплатно")}}}
        item {
            if(model.premium?.optBoolean("isPremium")==true) {Text("Premium активен",color=Color(0xFF91DCA0));Text(model.premium?.optString("expiresAt")?.takeUnless {it=="null"||it.isEmpty()}?.let {"Доступ по аккаунту до $it"} ?: "Бессрочный доступ по аккаунту Muwa")}
            else Text("Подписки Google Play пока не настроены. Подарочный Premium работает через ваш аккаунт Muwa.",color=Color.Gray)
        }
        item {Button(onClick=promo,modifier=Modifier.fillMaxWidth()) {Text("Активировать промокод")}}
        if(model.user==null) item {TextButton(onClick=login) {Text("Войти в Muwa")}}
        else item {TextButton(onClick={model.premiumAction(JSONObject().put("action","status"))},enabled=!model.busy) {Text("Обновить доступ")}}
        model.message?.let {item {Text(it)}}
    }
}
@Composable fun PromoScreen(model: MuwaModel,login: ()->Unit) {
    var code by rememberSaveableState(""); var label by rememberSaveableState(""); var days by rememberSaveableState("30"); var uses by rememberSaveableState("1"); var validity by rememberSaveableState("30")
    var discard by remember {mutableStateOf(false)}; var disabling by remember {mutableStateOf<String?>(null)}
    val context=LocalContext.current
    androidx.activity.compose.BackHandler(model.createdCode!=null) {discard=true}
    LazyColumn(Modifier.padding(24.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
        item {Text("Подарочный доступ Muwa",style=MaterialTheme.typography.headlineSmall)}
        if(model.user==null) item {Button(onClick=login) {Text("Войти в Muwa")}}
        else item {
            OutlinedTextField(code,{code=it},label={Text("MUWA-…")},singleLine=true,modifier=Modifier.fillMaxWidth())
            Button(onClick={model.premiumAction(JSONObject().put("action","redeem").put("code",code.trim()))},enabled=!model.busy&&code.isNotBlank()) {Text("Активировать")}
        }
        if(model.premium?.optBoolean("canManageCodes")==true) {
            item {
                Text("Создать подарочный код",style=MaterialTheme.typography.titleLarge)
                OutlinedTextField(label,{label=it},label={Text("Название")},enabled=!model.busy&&model.createdCode==null)
                OutlinedTextField(days,{days=it},label={Text("Дни Premium · 1–365")})
                OutlinedTextField(uses,{uses=it},label={Text("Активации · 1–1000")})
                OutlinedTextField(validity,{validity=it},label={Text("Дни для активации · 1–365")})
                Button(onClick={model.premiumAction(JSONObject().put("action","create").put("label",label.trim()).put("durationDays",days.toInt()).put("maxUses",uses.toInt()).put("validDays",validity.toInt()))},enabled=!model.busy&&model.createdCode==null&&label.isNotBlank()&&(days.toIntOrNull() ?: 0) in 1..365&&(uses.toIntOrNull() ?: 0) in 1..1000&&(validity.toIntOrNull() ?: 0) in 1..365) {Text("Создать код")}
            }
            if(model.createdCode!=null) item {
                Text("Сохраните код перед закрытием",style=MaterialTheme.typography.titleMedium)
                androidx.compose.foundation.text.selection.SelectionContainer {Text(model.createdCode!!)}
                Text("Полный код показывается только сейчас.",color=Color.Gray)
                TextButton(onClick={context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT,model.createdCode),"Подарочный код Muwa"))}) {Text("Поделиться")}
                TextButton(onClick=model::savedCode) {Text("Код сохранён")}
            }
            item {TextButton(onClick={model.premiumAction(JSONObject().put("action","list"))},enabled=!model.busy) {Text("Обновить список кодов")}}
            items(model.codes,key={it.getString("id")}) { item ->
                Card {Column(Modifier.padding(16.dp)) {Text(item.optString("label"));Text("${item.optInt("durationDays")} дней · ${item.optInt("uses")} из ${item.optInt("maxUses")}");if(item.optBoolean("disabled")) Text("Отключён") else TextButton(onClick={disabling=item.getString("id")}) {Text("Отключить новые активации")}}}
            }
        }
        model.message?.let {item {Text(it)}}
    }
    if(discard) AlertDialog(onDismissRequest={discard=false},title={Text("Полный код больше не будет показан")},text={Text("Сохраните код или подтвердите закрытие.")},confirmButton={TextButton(onClick={model.savedCode();discard=false}) {Text("Закрыть без сохранения")}},dismissButton={TextButton(onClick={discard=false}) {Text("Вернуться")}})
    if(disabling!=null) AlertDialog(onDismissRequest={disabling=null},title={Text("Отключить код?")},text={Text("Уже выданный Premium сохранится.")},confirmButton={TextButton(onClick={model.premiumAction(JSONObject().put("action","disable").put("id",disabling));disabling=null}) {Text("Отключить")}},dismissButton={TextButton(onClick={disabling=null}) {Text("Отмена")}})
}
@Composable fun SettingsScreen(model: MuwaModel) {
    val context=LocalContext.current
    var errors by remember {mutableIntStateOf(Diagnostics.count())}
    var remoteEnabled by remember {mutableStateOf(Diagnostics.remoteEnabled)}
    LaunchedEffect(Unit) { Diagnostics.flush() }
    Column(Modifier.padding(24.dp).verticalScroll(rememberScrollState()),verticalArrangement=Arrangement.spacedBy(16.dp)) {
        Text("Скачано: ${model.downloads.downloaded.size}")
        Text("Занято: ${android.text.format.Formatter.formatFileSize(context,model.downloads.bytes())}")
        Text("Диагностика",style=MaterialTheme.typography.headlineSmall);Text("Ошибок: $errors")
        Text("Отчёты сохраняются на устройстве. Пароли, промокоды и содержимое запросов не записываются.",color=Color.Gray)
        Row(verticalAlignment=androidx.compose.ui.Alignment.CenterVertically) { Switch(remoteEnabled,{remoteEnabled=it;Diagnostics.remoteEnabled=it}); Text("Отправлять категории ошибок в Muwa") }
        Text("После входа передаются только категория, код ошибки и версия приложения. Хранение на сервере — 14 дней.",color=Color.Gray)
        Button(onClick={runCatching {
            val file=Diagnostics.export(context); val uri=FileProvider.getUriForFile(context,"${context.packageName}.files",file)
            context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("application/json").putExtra(Intent.EXTRA_STREAM,uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),"Диагностика Muwa"))
        }.onFailure {model.error=it.message}}) {Text("Поделиться отчётом")}
        TextButton(onClick={Diagnostics.clear();errors=0}) {Text("Очистить диагностику")}
        Text("Системный размер текста и уменьшение анимаций учитываются автоматически.",color=Color.Gray)
    }
}
@Composable fun SubtitleScreen(model: MuwaModel) {
    var language by rememberSaveableState("ar"); var follow by rememberSaveableState(true)
    val listState=androidx.compose.foundation.lazy.rememberLazyListState()
    val active=model.subtitles.indexOfFirst {model.position / 1000.0 >= it.optDouble("start") && model.position / 1000.0 < it.optDouble("end")}
    LaunchedEffect(active,follow) {if(follow&&active>=0) listState.animateScrollToItem(active)}
    Column(Modifier.padding(16.dp)) {
        Row {listOf("ar","ru","en").forEach { lang -> TextButton(onClick={language=lang}) {Text(lang.uppercase())}};Switch(follow,{follow=it});Text("Следить",Modifier.padding(top=12.dp))}
        Text(model.subtitleStatus,color=Color.Gray)
        TextButton(onClick=model::loadSubtitles,enabled=!model.subtitleLoading) {Text(if(model.subtitleLoading) "Загрузка…" else "Обновить текст")}
        if(model.subtitleLoading) LinearProgressIndicator(Modifier.fillMaxWidth())
        LazyColumn(state=listState,modifier=Modifier.pointerInput(Unit) {
            awaitPointerEventScope { while (true) { val event = awaitPointerEvent(); if (event.changes.any { it.pressed && it.position != it.previousPosition }) follow=false } }
        }) {items(model.subtitles.size) {index -> val item=model.subtitles[index]
            Column(Modifier.fillMaxWidth().clickable {follow=false;model.seek((item.optDouble("start")*1000).toLong())}.padding(vertical=16.dp)) {
                Text(item.optString("ar"),style=MaterialTheme.typography.titleLarge,color=if(index==active) MaterialTheme.colorScheme.primary else Color.Gray)
                if(language!="ar") Text(item.optString(language),color=if(index==active) Color.White else Color.Gray)
            }
        }}
    }
}
