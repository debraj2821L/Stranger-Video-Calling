
package com.example.stranger_video_call

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

class MainActivity : FlutterActivity() {

    private val channelName = "stranger_video_call/recording"

    override fun onCreate(savedInstanceState: Bundle?) {
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "initializeEncryption" -> {
                        RecordingKeyManager.getOrCreateKey()
                        result.success(true)
                    }

                    "isSupported" -> {
                        result.success(true)
                    }

                    "listRecordings" -> {
                        result.success(
                            RecordingStorage.listRecordings(applicationContext)
                        )
                    }

                    "debugRoundTrip" -> {
                        val tempFile = File.createTempFile(
                            "recording_debug_",
                            ".txt",
                            cacheDir
                        )
                        tempFile.writeText(
                            "android-recording-debug-${System.currentTimeMillis()}"
                        )

                        val encryptedName = RecordingStorage.encryptRecording(
                            applicationContext,
                            tempFile
                        )
                        val decryptedPath = RecordingStorage.decryptForPlayback(
                            applicationContext,
                            encryptedName
                        )
                        val decryptedFile = File(decryptedPath)

                        result.success(
                            mapOf(
                                "encryptedFileName" to encryptedName,
                                "decryptedFilePath" to decryptedPath,
                                "decryptedContent" to if (decryptedFile.exists()) {
                                    decryptedFile.readText()
                                } else {
                                    ""
                                },
                                "recordings" to RecordingStorage.listRecordings(
                                    applicationContext
                                )
                            )
                        )
                    }

                    "deleteRecording" -> {
                        val fileName = call.argument<String>("fileName")
                        if (fileName.isNullOrBlank()) {
                            result.error("INVALID_ARGUMENT", "Missing filename", null)
                        } else {
                            result.success(
                                RecordingStorage.deleteRecording(
                                    applicationContext,
                                    fileName
                                )
                            )
                        }
                    }

                    "preparePlayback" -> {
                        val fileName = call.argument<String>("fileName")
                        if (fileName.isNullOrBlank()) {
                            result.error("INVALID_ARGUMENT", "Missing filename", null)
                        } else {
                            result.success(
                                RecordingStorage.decryptForPlayback(
                                    applicationContext,
                                    fileName
                                )
                            )
                        }
                    }

                    "finishPlayback" -> {
                        RecordingStorage.deletePlaybackCache(applicationContext)
                        result.success(true)
                    }

                    "startRecording" -> {
                        val filePath = call.argument<String>("filePath")
                        if (filePath.isNullOrBlank()) {
                            result.error(
                                "INVALID_ARGUMENT",
                                "Missing recording file path",
                                null
                            )
                        } else {
                            val tempFile = File(filePath)
                            val parent = tempFile.parentFile
                            if (parent != null && !parent.exists() && !parent.mkdirs()) {
                                throw IOException("Could not create recording temp directory")
                            }
                            if (tempFile.exists()) {
                                tempFile.delete()
                            }
                            result.success(filePath)
                        }
                    }

                    "stopRecording" -> {
                        val filePath = call.argument<String>("filePath")
                        if (filePath.isNullOrBlank()) {
                            result.error(
                                "INVALID_ARGUMENT",
                                "Missing recording file path",
                                null
                            )
                        } else {
                            val tempFile = File(filePath)
                            if (!tempFile.exists()) {
                                result.success(null)
                                return@setMethodCallHandler
                            }

                            try {
                                val encryptedName = RecordingStorage.encryptRecording(
                                    applicationContext,
                                    tempFile
                                )
                                result.success(encryptedName)
                            } catch (e: Exception) {
                                if (tempFile.exists()) {
                                    tempFile.delete()
                                }
                                throw e
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error(
                    "RECORDING_OPERATION_FAILED",
                    e.message ?: "Recording operation failed",
                    null
                )
            }
        }
    }
}
