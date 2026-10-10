package app.muwa.nasheeds

import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject

// Data belongs to the debug target only. Release begins with an empty catalog.
fun installReviewCatalog() {
    val instrumentation = InstrumentationRegistry.getInstrumentation()
    val rows = JSONArray(instrumentation.targetContext.assets.open("review-catalog.json").bufferedReader().use { it.readText() })
    instrumentation.runOnMainSync { AppGraph.library.updateCatalog(JSONObject().put("version",1).put("tracks",rows)) }
}
