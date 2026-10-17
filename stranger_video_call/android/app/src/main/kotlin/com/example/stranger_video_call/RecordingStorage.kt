
package com.example.stranger_video_call

import android.content.Context
import android.util.Base64
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.security.SecureRandom
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.CipherInputStream
import javax.crypto.CipherOutputStream
import javax.crypto.spec.GCMParameterSpec

object RecordingStorage {

    private const val DIRECTORY = "encrypted_recordings"
    private const val CACHE_DIRECTORY = "recording_playback"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val NONCE_SIZE = 12
    private const val TAG_SIZE_BITS = 128
    private const val BUFFER_SIZE = 64 * 1024

    // Eight-byte file signature identifying our recording format.
    private val MAGIC = byteArrayOf(
        0x53, 0x56, 0x52, 0x45, 0x43, 0x30, 0x30, 0x31
    )

    private fun recordingsDir(context: Context): File {
        return File(context.filesDir, DIRECTORY).also {
            if (!it.exists() && !it.mkdirs()) {
                throw IOException("Cannot create recording directory")
            }
        }
    }

    private fun playbackDir(context: Context): File {
        return File(context.cacheDir, CACHE_DIRECTORY).also {
            if (!it.exists() && !it.mkdirs()) {
                throw IOException("Cannot create playback cache")
            }
        }
    }

    /**
     * Encrypts a completed media file into app-private storage.
     * The plaintext source is deleted only after encryption succeeds.
     */
    @Synchronized
    fun encryptRecording(context: Context, source: File): String {
        require(source.isFile) { "Recording source does not exist" }

        val destination = File(
            recordingsDir(context),
            "${UUID.randomUUID()}.svcrec"
        )

        val nonce = ByteArray(NONCE_SIZE).also {
            SecureRandom().nextBytes(it)
        }

        try {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(
                Cipher.ENCRYPT_MODE,
                RecordingKeyManager.getOrCreateKey(),
                GCMParameterSpec(TAG_SIZE_BITS, nonce)
            )

            FileOutputStream(destination).use { fileOutput ->
                BufferedOutputStream(fileOutput).use { output ->
                    output.write(MAGIC)
                    output.write(nonce)

                    CipherOutputStream(output, cipher).use { encrypted ->
                        BufferedInputStream(FileInputStream(source)).use { input ->
                            val buffer = ByteArray(BUFFER_SIZE)
                            while (true) {
                                val count = input.read(buffer)
                                if (count < 0) break
                                encrypted.write(buffer, 0, count)
                            }
                        }
                    }
                }
            }

            if (!source.delete()) {
                // Keep the encrypted result, but report that plaintext cleanup failed.
                throw IOException(
                    "Encrypted recording saved, but plaintext cleanup failed"
                )
            }

            return destination.name
        } catch (e: Exception) {
            destination.delete()
            throw e
        }
    }

    /**
     * Fully decrypts and authenticates a recording into the app's private
     * cache. Return the path only to the in-app player. Delete it afterward.
     */
    @Synchronized
    fun decryptForPlayback(context: Context, fileName: String): String {
        require(fileName.matches(Regex("[a-fA-F0-9-]+\\.svcrec"))) {
            "Invalid recording filename"
        }

        val source = File(recordingsDir(context), fileName)
        require(source.isFile) { "Recording not found" }

        val destination = File(
            playbackDir(context),
            "${UUID.randomUUID()}.mp4"
        )

        try {
            BufferedInputStream(FileInputStream(source)).use { input ->
                val header = ByteArray(MAGIC.size)
                if (input.readFullyOrFalse(header).not() ||
                    !header.contentEquals(MAGIC)
                ) {
                    throw IOException("Invalid recording format")
                }

                val nonce = ByteArray(NONCE_SIZE)
                if (!input.readFullyOrFalse(nonce)) {
                    throw IOException("Recording header is incomplete")
                }

                val cipher = Cipher.getInstance(TRANSFORMATION)
                cipher.init(
                    Cipher.DECRYPT_MODE,
                    RecordingKeyManager.getOrCreateKey(),
                    GCMParameterSpec(TAG_SIZE_BITS, nonce)
                )

                // Reading to EOF is required to validate the GCM authentication tag.
                CipherInputStream(input, cipher).use { decrypted ->
                    BufferedOutputStream(FileOutputStream(destination)).use { output ->
                        val buffer = ByteArray(BUFFER_SIZE)
                        while (true) {
                            val count = decrypted.read(buffer)
                            if (count < 0) break
                            output.write(buffer, 0, count)
                        }
                    }
                }
            }

            return destination.absolutePath
        } catch (e: Exception) {
            destination.delete()
            throw IOException("Cannot decrypt recording", e)
        }
    }

    fun listRecordings(context: Context): List<String> {
        return recordingsDir(context)
            .listFiles()
            ?.filter { it.isFile && it.name.endsWith(".svcrec") }
            ?.sortedByDescending { it.lastModified() }
            ?.map { it.name }
            ?: emptyList()
    }

    fun deleteRecording(context: Context, fileName: String): Boolean {
        require(fileName.matches(Regex("[a-fA-F0-9-]+\\.svcrec"))) {
            "Invalid recording filename"
        }

        val file = File(recordingsDir(context), fileName)
        return !file.exists() || file.delete()
    }

    fun deletePlaybackCache(context: Context) {
        playbackDir(context).listFiles()?.forEach { file ->
            if (file.isFile) file.delete()
        }
    }

    private fun java.io.InputStream.readFullyOrFalse(
        buffer: ByteArray
    ): Boolean {
        var offset = 0
        while (offset < buffer.size) {
            val count = read(buffer, offset, buffer.size - offset)
            if (count < 0) return false
            offset += count
        }
        return true
    }
}
