package dev.omni.omni

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import java.nio.ByteBuffer

/**
 * Joins a video-only file and an audio-only file into one playable MP4.
 *
 * Reddit serves adaptive streams, which means the picture and the sound are
 * separate files. This puts them back together — a container rewrite, not a
 * re-encode, so it takes seconds and loses no quality. Both tracks are
 * already H.264 and AAC; nothing is decoded.
 */
object MediaRemuxer {

    /** Roomy enough for a 4K keyframe; sample sizes are read from the file. */
    private const val FALLBACK_BUFFER_BYTES = 2 * 1024 * 1024

    /**
     * Writes [outputPath] from [videoPath] and [audioPath].
     *
     * Throws on anything that would leave a half-written file, and deletes
     * the partial output first, so callers never hand a broken MP4 to the
     * gallery.
     */
    fun remux(videoPath: String, audioPath: String, outputPath: String) {
        var muxer: MediaMuxer? = null
        val video = MediaExtractor()
        val audio = MediaExtractor()

        try {
            video.setDataSource(videoPath)
            audio.setDataSource(audioPath)

            val videoTrack = firstTrackOfType(video, "video/")
                ?: throw IllegalStateException("no video track in $videoPath")
            val audioTrack = firstTrackOfType(audio, "audio/")
                ?: throw IllegalStateException("no audio track in $audioPath")

            video.selectTrack(videoTrack)
            audio.selectTrack(audioTrack)

            val videoFormat = video.getTrackFormat(videoTrack)
            val audioFormat = audio.getTrackFormat(audioTrack)

            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val outVideo = muxer.addTrack(videoFormat)
            val outAudio = muxer.addTrack(audioFormat)
            muxer.start()

            copyTrack(video, muxer, outVideo, bufferSizeFor(videoFormat))
            copyTrack(audio, muxer, outAudio, bufferSizeFor(audioFormat))

            muxer.stop()
        } catch (e: Throwable) {
            // A muxer that never started throws from stop(), which would
            // mask the real failure.
            runCatching { muxer?.stop() }
            File(outputPath).delete()
            throw e
        } finally {
            runCatching { muxer?.release() }
            runCatching { video.release() }
            runCatching { audio.release() }
        }
    }

    private fun firstTrackOfType(extractor: MediaExtractor, prefix: String): Int? {
        for (i in 0 until extractor.trackCount) {
            val mime = extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME)
            if (mime != null && mime.startsWith(prefix)) return i
        }
        return null
    }

    private fun bufferSizeFor(format: MediaFormat): Int =
        if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
            format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)
                .coerceAtLeast(FALLBACK_BUFFER_BYTES)
        } else {
            FALLBACK_BUFFER_BYTES
        }

    private fun copyTrack(
        extractor: MediaExtractor,
        muxer: MediaMuxer,
        outputTrack: Int,
        bufferSize: Int,
    ) {
        val buffer = ByteBuffer.allocate(bufferSize)
        val info = MediaCodec.BufferInfo()

        while (true) {
            val size = extractor.readSampleData(buffer, 0)
            if (size < 0) break

            info.offset = 0
            info.size = size
            info.presentationTimeUs = extractor.sampleTime
            // Carried across rather than assumed: dropping the keyframe flag
            // produces a file that plays but cannot be seeked.
            info.flags = extractor.sampleFlags

            muxer.writeSampleData(outputTrack, buffer, info)
            extractor.advance()
        }
    }
}
