package dev.omni.omni

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "dev.omni/media"
    }

    /** Remuxing is file I/O; doing it on the platform thread would jank. */
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "remux" -> {
                        val video = call.argument<String>("videoPath")
                        val audio = call.argument<String>("audioPath")
                        val output = call.argument<String>("outputPath")

                        if (video == null || audio == null || output == null) {
                            result.error(
                                "bad_args",
                                "remux needs videoPath, audioPath and outputPath",
                                null,
                            )
                            return@setMethodCallHandler
                        }

                        worker.execute {
                            try {
                                MediaRemuxer.remux(video, audio, output)
                                main.post { result.success(true) }
                            } catch (e: Throwable) {
                                main.post {
                                    result.error(
                                        "remux_failed",
                                        e.message ?: e::class.java.simpleName,
                                        null,
                                    )
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        worker.shutdown()
        super.onDestroy()
    }
}
