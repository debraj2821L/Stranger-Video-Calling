
package com.cloudwebrtc.webrtc.record;

import androidx.annotation.Nullable;

import android.util.Log;

import com.cloudwebrtc.webrtc.utils.EglUtils;

import org.webrtc.VideoTrack;

import java.io.File;
import java.io.IOException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class MediaRecorderImpl {

    private static final String TAG = "MediaRecorderImpl";

    private final Integer id;
    private final VideoTrack videoTrack;
    private final VideoTrack secondVideoTrack;
    private final AudioSamplesInterceptor audioInterceptor;

    private VideoFileRenderer videoFileRenderer;
    private DualVideoFileRenderer dualVideoFileRenderer;
    private AudioFileRenderer audioFileRenderer;

    private boolean isRunning = false;
    private boolean isStopped = false;
    private File recordFile;

    private final ExecutorService releaseExecutor =
            Executors.newSingleThreadExecutor();

    /**
     * Backward-compatible constructor for existing plugin callers.
     */
    public MediaRecorderImpl(
            Integer id,
            @Nullable VideoTrack videoTrack,
            @Nullable AudioSamplesInterceptor audioInterceptor) {
        this(id, videoTrack, null, audioInterceptor);
    }

    /**
     * Constructor supporting local and remote video tracks.
     */
    public MediaRecorderImpl(
            Integer id,
            @Nullable VideoTrack videoTrack,
            @Nullable VideoTrack secondVideoTrack,
            @Nullable AudioSamplesInterceptor audioInterceptor) {
        this.id = id;
        this.videoTrack = videoTrack;
        this.secondVideoTrack = secondVideoTrack;
        this.audioInterceptor = audioInterceptor;
    }

    public synchronized void startRecording(File file) throws Exception {
        if (isRunning) {
            return;
        }

        if (isStopped) {
            throw new IllegalStateException(
                    "This recorder has already been stopped. Create a new recorder.");
        }

        File parent = file.getParentFile();

        if (parent != null && !parent.exists() && !parent.mkdirs()) {
            throw new IOException(
                    "Could not create recording directory: " + parent);
        }

        recordFile = file;

        try {
            if (videoTrack != null && secondVideoTrack != null) {
                // Compose local and remote video into one output.
                dualVideoFileRenderer = new DualVideoFileRenderer(
                        file.getAbsolutePath(),
                        EglUtils.getRootEglBaseContext(),
                        audioInterceptor != null);

                videoTrack.addSink(dualVideoFileRenderer.localVideoSink);

                try {
                    secondVideoTrack.addSink(
                            dualVideoFileRenderer.remoteVideoSink);
                } catch (Exception e) {
                    videoTrack.removeSink(
                            dualVideoFileRenderer.localVideoSink);
                    dualVideoFileRenderer.release();
                    dualVideoFileRenderer = null;
                    throw e;
                }

                if (audioInterceptor != null) {
                    audioInterceptor.attachCallback(
                            id, dualVideoFileRenderer);
                }

                Log.i(TAG, "Started dual-video recording");
            } else if (videoTrack != null) {
                // Preserve the existing single-video recording path.
                videoFileRenderer = new VideoFileRenderer(
                        file.getAbsolutePath(),
                        EglUtils.getRootEglBaseContext(),
                        audioInterceptor != null);

                videoTrack.addSink(videoFileRenderer);

                if (audioInterceptor != null) {
                    audioInterceptor.attachCallback(
                            id, videoFileRenderer);
                }

                Log.i(TAG, "Started single-video recording");
            } else if (audioInterceptor != null) {
                // Preserve the existing audio-only recording path.
                audioFileRenderer =
                        new AudioFileRenderer(file.getAbsolutePath());

                audioInterceptor.attachCallback(
                        id, audioFileRenderer);

                Log.i(TAG, "Started audio-only recording");
            } else {
                throw new Exception(
                        "No video track or audio source was provided.");
            }

            isRunning = true;
        } catch (Exception e) {
            if (audioInterceptor != null) {
                audioInterceptor.detachCallback(id);
            }

            Log.e(TAG, "Failed to start recording", e);
            throw e;
        }
    }

    public File getRecordFile() {
        return recordFile;
    }

    public synchronized void stopRecording(
            @Nullable Runnable onStopped) {
        if (!isRunning) {
            if (onStopped != null) {
                onStopped.run();
            }
            return;
        }

        isRunning = false;
        isStopped = true;

        if (audioInterceptor != null) {
            audioInterceptor.detachCallback(id);
        }

        final DualVideoFileRenderer dualRenderer =
                dualVideoFileRenderer;
        final VideoFileRenderer singleRenderer =
                videoFileRenderer;
        final AudioFileRenderer audioRenderer =
                audioFileRenderer;

        dualVideoFileRenderer = null;
        videoFileRenderer = null;
        audioFileRenderer = null;

        if (dualRenderer != null) {
            if (videoTrack != null) {
                videoTrack.removeSink(dualRenderer.localVideoSink);
            }

            if (secondVideoTrack != null) {
                secondVideoTrack.removeSink(
                        dualRenderer.remoteVideoSink);
            }
        } else if (singleRenderer != null && videoTrack != null) {
            videoTrack.removeSink(singleRenderer);
        }

        releaseExecutor.submit(() -> {
            try {
                if (dualRenderer != null) {
                    dualRenderer.release();
                }

                if (singleRenderer != null) {
                    singleRenderer.release();
                }

                if (audioRenderer != null) {
                    audioRenderer.release();
                }
            } catch (Exception e) {
                Log.e(TAG, "Failed to release recording resources", e);
            } finally {
                try {
                    if (onStopped != null) {
                        onStopped.run();
                    }
                } finally {
                    releaseExecutor.shutdown();
                }
            }
        });
    }
}
