package app.muwa.nasheeds

import android.net.Uri
import android.content.Context
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.*
import org.json.JSONObject
import java.io.File
import java.time.Instant
import java.util.UUID

@Composable fun PublicationScreen(model: MuwaModel) {
    val context=LocalContext.current;val scope=rememberCoroutineScope()
    val prefs=remember {context.getSharedPreferences("muwa.publication",Context.MODE_PRIVATE)}
    var title by rememberSaveableState(prefs.getString("title","") ?: "")
    var artist by rememberSaveableState(prefs.getString("artist","") ?: "")
    var language by rememberSaveableState(prefs.getString("language","ar") ?: "ar")
    var audio by remember {mutableStateOf(prefs.getString("audio",null)?.let(Uri::parse))}
    var cover by remember {mutableStateOf(prefs.getString("cover",null)?.let(Uri::parse))}
    var sending by remember {mutableStateOf(false)};var status by remember {mutableStateOf(prefs.getString("status",null))}
    fun save() {prefs.edit().putString("title",title).putString("artist",artist).putString("language",language).putString("audio",audio?.toString()).putString("cover",cover?.toString()).putString("status",status).apply()}
    val audioPicker=rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) {uri -> if(uri!=null) {runCatching {context.contentResolver.takePersistableUriPermission(uri,android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)};audio=uri;save()} }
    val coverPicker=rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) {uri -> if(uri!=null) {runCatching {context.contentResolver.takePersistableUriPermission(uri,android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)};cover=uri;save()} }
    Column(Modifier.padding(24.dp).verticalScroll(rememberScrollState()),verticalArrangement=Arrangement.spacedBy(12.dp)) {
        Text("Отправить нашид на модерацию",style=MaterialTheme.typography.headlineSmall)
        Text("Аудио и обложка загружаются первыми. Публикация отправляется только после успешной загрузки файлов.")
        OutlinedTextField(title,{title=it;save()},label={Text("Название")},enabled=!sending)
        OutlinedTextField(artist,{artist=it;save()},label={Text("Исполнитель")},enabled=!sending)
        OutlinedTextField(language,{language=it;save()},label={Text("Язык · ar / ru / en")},enabled=!sending)
        Button(onClick={audioPicker.launch(arrayOf("audio/*"))},enabled=!sending) {Text(if(audio==null) "Выбрать MP3" else "Аудио выбрано · заменить")}
        Button(onClick={coverPicker.launch(arrayOf("image/*"))},enabled=!sending) {Text(if(cover==null) "Выбрать обложку" else "Обложка выбрана · заменить")}
        Button(onClick={save();status="Черновик сохранён"},enabled=!sending) {Text("Сохранить черновик")}
        Button(onClick={
            sending=true;status="Загружаем файлы…"
            scope.launch {
                try {
                    check(model.user!=null) {"Для отправки войдите в Muwa в Профиле."}
                    val id=UUID.randomUUID().toString();val temp=File(context.cacheDir,"publication-$id").apply {mkdirs()}
                    try {
                        suspend fun upload(uri: Uri,part: String): String {
                            val local=withContext(Dispatchers.IO) {copyPart(context,uri,File(temp,part))}
                            val mime=context.contentResolver.getType(uri) ?: if(part=="audio") "audio/mpeg" else "image/jpeg"
                            val value=AppGraph.backend.request("publicationUpload",JSONObject().put("draftId",id).put("part",part).put("originalName",if(part=="audio") "audio.mp3" else "cover.jpg").put("contentType",mime).put("sizeBytes",local.length()),true)
                            AppGraph.backend.put(value.getString("presignedUrl"),local,mime);return value.getString("storageKey")
                        }
                        val audioKey=upload(audio!!,"audio");val coverKey=cover?.let {upload(it,"cover")}
                        val document=JSONObject().put("id",id).put("title",title.trim()).put("artist",artist.trim()).put("language",language.trim()).put("audioStorageKey",audioKey).put("coverStorageKey",coverKey ?: JSONObject.NULL).put("submittedAt",Instant.now().toString()).put("client","Muwa Native Android")
                        val file=withContext(Dispatchers.IO) {File(temp,"submission.json").apply {writeText(document.toString())}}
                        val meta=AppGraph.backend.request("publicationUpload",JSONObject().put("draftId",id).put("part","submission").put("originalName","submission.json").put("contentType","application/json").put("sizeBytes",file.length()),true)
                        AppGraph.backend.put(meta.getString("presignedUrl"),file,"application/json")
                        status="Отправлено на модерацию";save()
                    } finally {withContext(Dispatchers.IO) {temp.deleteRecursively()}}
                } catch(e: CancellationException) {throw e} catch(e: Throwable) {Diagnostics.record("publication",e);model.error=e.message;status="Не удалось отправить. Черновик сохранён.";save()}
                finally {sending=false}
            }
        },enabled=!sending&&audio!=null&&title.isNotBlank()&&artist.isNotBlank()) {Text(if(sending) "Отправляем…" else "Отправить")}
        status?.let {Text(it)}
    }
}
private fun copyPart(context: Context,uri: Uri,to: File): File {
    context.contentResolver.openInputStream(uri).use {input -> requireNotNull(input);to.outputStream().use {out -> val bytes=ByteArray(64*1024);var size=0L;while(true) {val count=input.read(bytes);if(count<0) break;size+=count;check(size<=100*1024*1024) {"Файл должен быть меньше 100 МБ."};out.write(bytes,0,count)};check(size>0) {"Файл пуст."}} }
    return to
}
