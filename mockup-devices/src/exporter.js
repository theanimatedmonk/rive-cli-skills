// Frame-perfect video: every frame is rendered on its own and encoded with
// WebCodecs into an H.264 MP4, so a 4K 60 fps export never drops a frame,
// however slow the machine.

import { Muxer, ArrayBufferTarget } from "mp4-muxer";

const CODECS = ["avc1.640034", "avc1.640033", "avc1.640028", "avc1.4d0034", "avc1.42003e"];

export async function pickCodec(width, height, fps, bitrate) {
  if (!("VideoEncoder" in window)) return null;
  for (const codec of CODECS) {
    const config = { codec, width, height, bitrate, framerate: fps };
    try {
      const { supported } = await VideoEncoder.isConfigSupported(config);
      if (supported) return config;
    } catch {
      // Try the next one.
    }
  }
  return null;
}

// drawFrame(t) renders the frame at time t (seconds) into `canvas`.
export async function exportMp4({ canvas, width, height, fps, duration, drawFrame, onProgress, isCancelled, bitrate: wanted }) {
  const bitrate = wanted || Math.min(Math.round(width * height * fps * 0.16), 90_000_000);
  const config = await pickCodec(width, height, fps, bitrate);
  if (!config) throw new Error("This browser can't encode H.264 video (try Chrome, Edge or Safari).");

  const muxer = new Muxer({
    target: new ArrayBufferTarget(),
    video: { codec: "avc", width, height, frameRate: fps },
    fastStart: "in-memory",
  });
  let failure = null;
  const encoder = new VideoEncoder({
    output: (chunk, meta) => muxer.addVideoChunk(chunk, meta),
    error: (e) => (failure = e),
  });
  encoder.configure(config);

  const frames = Math.max(1, Math.round(duration * fps));
  const step = 1_000_000 / fps;
  for (let i = 0; i < frames; i++) {
    if (failure) throw failure;
    if (isCancelled?.()) {
      encoder.close();
      return null;
    }
    await drawFrame(i / fps);
    const frame = new VideoFrame(canvas, { timestamp: Math.round(i * step), duration: Math.round(step) });
    encoder.encode(frame, { keyFrame: i % (fps * 2) === 0 });
    frame.close();
    // Don't run ahead of the encoder.
    while (encoder.encodeQueueSize > 6) await new Promise((r) => setTimeout(r, 1));
    onProgress?.((i + 1) / frames);
  }
  await encoder.flush();
  encoder.close();
  if (failure) throw failure;
  muxer.finalize();
  return new Blob([muxer.target.buffer], { type: "video/mp4" });
}

export function download(blob, name) {
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = name;
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 10_000);
}
