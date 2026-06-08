#ifndef EAGLY_NATIVE_SCRCPY_VIDEO_DECODER_H_
#define EAGLY_NATIVE_SCRCPY_VIDEO_DECODER_H_

#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <functional>
#include <mutex>
#include <thread>
#include <vector>

struct AVCodecContext;
struct AVPacket;
struct AVFrame;

// Decodes scrcpy's H.264 Annex-B access units to tightly-packed RGBA frames on
// a background thread, using FFmpeg (libavcodec). Shared by the Windows and
// Linux runners, each of which wraps it with that platform's Flutter texture
// API. macOS uses VideoToolbox instead (see ScrcpyVideoPlugin.swift).
//
// Wire contract matches the Dart side (lib/services/scrcpy_video_channel.dart):
// each Feed() call is one access unit — a config packet (SPS/PPS) or a coded
// slice. SPS/PPS are carried in-band, so they configure the decoder
// automatically; no extradata setup is required.
class ScrcpyVideoDecoder {
 public:
  // Invoked on the decode thread whenever a new frame becomes available. The
  // platform glue should mark its texture frame available (marshalling to the
  // platform thread if required).
  using FrameAvailableCallback = std::function<void()>;

  explicit ScrcpyVideoDecoder(FrameAvailableCallback on_frame_available);
  ~ScrcpyVideoDecoder();

  ScrcpyVideoDecoder(const ScrcpyVideoDecoder&) = delete;
  ScrcpyVideoDecoder& operator=(const ScrcpyVideoDecoder&) = delete;

  // Enqueues one Annex-B access unit (thread-safe, non-blocking). Old frames
  // are dropped if the decoder falls behind, to stay near the live edge.
  void Feed(const uint8_t* data, size_t size);

  // Copies the most recent decoded frame into |out| as RGBA8888 (4 bytes per
  // pixel, no row padding). Returns false if nothing has been decoded yet.
  bool CopyLatestFrame(std::vector<uint8_t>* out, int* width, int* height);

 private:
  void ThreadMain();
  bool EnsureCodec();
  void DecodePacket(const std::vector<uint8_t>& access_unit);
  void ConvertFrame(const AVFrame* frame);

  FrameAvailableCallback on_frame_available_;

  std::thread thread_;
  std::mutex queue_mutex_;
  std::condition_variable queue_cv_;
  std::deque<std::vector<uint8_t>> queue_;
  bool stop_ = false;

  // FFmpeg state — only touched on the decode thread.
  AVCodecContext* codec_ctx_ = nullptr;
  AVPacket* packet_ = nullptr;
  AVFrame* frame_ = nullptr;

  // Latest decoded frame, guarded by frame_mutex_.
  std::mutex frame_mutex_;
  std::vector<uint8_t> rgba_;
  int width_ = 0;
  int height_ = 0;
  bool has_frame_ = false;
};

#endif  // EAGLY_NATIVE_SCRCPY_VIDEO_DECODER_H_
