package app.muwa.nasheeds.ui.design

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp

/** App-owned vectors keep the same visual vocabulary without bundling SF Symbols. */
object MuwaSymbols {
    val Library =
        ImageVector.Builder("MuwaLibrary", 24.dp, 24.dp, 24f, 24f)
            .apply {
                path(fill = SolidColor(Color.White), pathFillType = PathFillType.EvenOdd) {
                    moveTo(2f, 5f)
                    lineTo(6f, 5f)
                    lineTo(6f, 21f)
                    lineTo(2f, 21f)
                    close()
                    moveTo(3f, 8f)
                    lineTo(5f, 8f)
                    lineTo(5f, 9f)
                    lineTo(3f, 9f)
                    close()
                    moveTo(8f, 2f)
                    lineTo(13f, 2f)
                    lineTo(13f, 22f)
                    lineTo(8f, 22f)
                    close()
                    moveTo(9f, 6f)
                    lineTo(12f, 6f)
                    lineTo(12f, 7f)
                    lineTo(9f, 7f)
                    close()
                    moveTo(15f, 5f)
                    lineTo(19f, 4f)
                    lineTo(23f, 20f)
                    lineTo(19f, 21f)
                    close()
                }
            }
            .build()
    val Crown =
        ImageVector.Builder("MuwaCrown", 24.dp, 24.dp, 24f, 24f)
            .apply {
                path(fill = SolidColor(Color.White)) {
                    moveTo(3f, 6f)
                    lineTo(8f, 10f)
                    lineTo(12f, 3f)
                    lineTo(16f, 10f)
                    lineTo(21f, 6f)
                    lineTo(19f, 18f)
                    lineTo(5f, 18f)
                    close()
                    moveTo(5f, 20f)
                    lineTo(19f, 20f)
                    lineTo(19f, 22f)
                    lineTo(5f, 22f)
                    close()
                }
            }
            .build()
    val Captions =
        ImageVector.Builder("MuwaCaptions", 24.dp, 24.dp, 24f, 24f)
            .apply {
                path(
                    stroke = SolidColor(Color.White),
                    strokeLineWidth = 1.6f,
                    strokeLineCap = StrokeCap.Round,
                    strokeLineJoin = StrokeJoin.Round,
                ) {
                    moveTo(6f, 3f)
                    lineTo(18f, 3f)
                    quadTo(21f, 3f, 21f, 6f)
                    lineTo(21f, 14f)
                    quadTo(21f, 17f, 18f, 17f)
                    lineTo(11f, 17f)
                    lineTo(6f, 21f)
                    lineTo(6f, 17f)
                    quadTo(3f, 17f, 3f, 14f)
                    lineTo(3f, 6f)
                    quadTo(3f, 3f, 6f, 3f)
                    close()
                    moveTo(6.5f, 8f)
                    lineTo(10.5f, 8f)
                    moveTo(13f, 8f)
                    lineTo(17.5f, 8f)
                    moveTo(6.5f, 12f)
                    lineTo(14.5f, 12f)
                }
            }
            .build()
    val AudioOutput =
        ImageVector.Builder("MuwaAudioOutput", 24.dp, 24.dp, 24f, 24f)
            .apply {
                path(
                    stroke = SolidColor(Color.White),
                    strokeLineWidth = 1.5f,
                    strokeLineCap = StrokeCap.Round,
                ) {
                    moveTo(4.5f, 17f)
                    curveTo(-1f, 10f, 3.5f, 1f, 12f, 1f)
                    curveTo(20.5f, 1f, 25f, 10f, 19.5f, 17f)
                    moveTo(7f, 14.5f)
                    curveTo(3f, 9.5f, 6f, 4.5f, 12f, 4.5f)
                    curveTo(18f, 4.5f, 21f, 9.5f, 17f, 14.5f)
                    moveTo(9.5f, 12.5f)
                    curveTo(7f, 9f, 9f, 8f, 12f, 8f)
                    curveTo(15f, 8f, 17f, 9f, 14.5f, 12.5f)
                }
                path(fill = SolidColor(Color.White)) {
                    moveTo(6.5f, 22f)
                    lineTo(12f, 15f)
                    lineTo(17.5f, 22f)
                    close()
                }
            }
            .build()
}
