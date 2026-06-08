#include "scrcpy_video_decoder.h"

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavutil/frame.h>
#include <libavutil/pixfmt.h>
}

#include <cstring>
#include <utility>

namespace {

inline uint8_t Clip255(int v) {
  return static_cast<uint8_t>(v < 0 ? 0 : (v > 255 ? 255 : v));
}

// Keep at most this many access units queued; beyond that we drop the oldest so
// a slow consumer doesn't accumulate latency.
constexpr size_t kMaxQueue = 8;

}  // namespace

ScrcpyVideoDecoder::ScrcpyVideoDecoder(FrameAvailableCallback on_frame_available)
    : on_frame_available_(std::move(on_frame_available)) {
  thread_ = std::thread(&ScrcpyVideoDecoder::ThreadMain, this);
}

ScrcpyVideoDecoder::~ScrcpyVideoDecoder() {
  {
    std::lock_guard<std::mutex> lock(queue_mutex_);
    stop_ = true;
  }
  queue_cv_.notify_all();
  if (thread_.joinable()) {
    thread_.join();
  }
  if (frame_) av_frame_free(&frame_);
  if (packet_) av_packet_free(&packet_);
  if (codec_ctx_) avcodec_free_context(&codec_ctx_);
}

void ScrcpyVideoDecoder::Feed(const uint8_t* data, size_t size) {
  if (data == nullptr || size == 0) return;
  {
    std::lock_guard<std::mutex> lock(queue_mutex_);
    if (stop_) return;
    queue_.emplace_back(data, data + size);
    while (queue_.size() > kMaxQueue) {
      queue_.pop_front();
    }
  }
  queue_cv_.notify_one();
}

bool ScrcpyVideoDecoder::CopyLatestFrame(std::vector<uint8_t>* out, int* width,
                                         int* height) {
  std::lock_guard<std::mutex> lock(frame_mutex_);
  if (!has_frame_) return false;
  out->assign(rgba_.begin(), rgba_.end());
  *width = width_;
  *height = height_;
  return true;
}

bool ScrcpyVideoDecoder::EnsureCodec() {
  if (codec_ctx_) return true;
  const AVCodec* codec = avcodec_find_decoder(AV_CODEC_ID_H264);
  if (!codec) return false;
  codec_ctx_ = avcodec_alloc_context3(codec);
  if (!codec_ctx_) return false;
  // Favour latency over throughput: emit frames as soon as they decode and
  // avoid the extra delay that frame-level threading introduces.
  codec_ctx_->flags |= AV_CODEC_FLAG_LOW_DELAY;
  codec_ctx_->thread_count = 1;
  if (avcodec_open2(codec_ctx_, codec, nullptr) < 0) {
    avcodec_free_context(&codec_ctx_);
    codec_ctx_ = nullptr;
    return false;
  }
  packet_ = av_packet_alloc();
  frame_ = av_frame_alloc();
  return packet_ != nullptr && frame_ != nullptr;
}

void ScrcpyVideoDecoder::ThreadMain() {
  for (;;) {
    std::vector<uint8_t> access_unit;
    {
      std::unique_lock<std::mutex> lock(queue_mutex_);
      queue_cv_.wait(lock, [this] { return stop_ || !queue_.empty(); });
      if (stop_ && queue_.empty()) return;
      access_unit = std::move(queue_.front());
      queue_.pop_front();
    }
    if (!EnsureCodec()) continue;
    DecodePacket(access_unit);
  }
}

void ScrcpyVideoDecoder::DecodePacket(const std::vector<uint8_t>& access_unit) {
  if (av_new_packet(packet_, static_cast<int>(access_unit.size())) < 0) return;
  std::memcpy(packet_->data, access_unit.data(), access_unit.size());
  const int ret = avcodec_send_packet(codec_ctx_, packet_);
  av_packet_unref(packet_);
  if (ret < 0) return;
  while (avcodec_receive_frame(codec_ctx_, frame_) == 0) {
    ConvertFrame(frame_);
    av_frame_unref(frame_);
  }
}

void ScrcpyVideoDecoder::ConvertFrame(const AVFrame* frame) {
  const int w = frame->width;
  const int h = frame->height;
  if (w <= 0 || h <= 0) return;

  const uint8_t* yp = frame->data[0];
  const uint8_t* up = frame->data[1];
  const uint8_t* vp = frame->data[2];
  if (yp == nullptr || up == nullptr || vp == nullptr) return;  // expect planar YUV
  const int ys = frame->linesize[0];
  const int us = frame->linesize[1];
  const int vs = frame->linesize[2];

  // Software H.264 decode produces planar 4:2:0 (YUV420P / YUVJ420P). Convert
  // to RGBA with full-range BT.601 coefficients — good enough for a live mirror.
  std::vector<uint8_t> rgba(static_cast<size_t>(w) * static_cast<size_t>(h) * 4);
  for (int y = 0; y < h; ++y) {
    const uint8_t* yrow = yp + static_cast<size_t>(y) * ys;
    const uint8_t* urow = up + static_cast<size_t>(y / 2) * us;
    const uint8_t* vrow = vp + static_cast<size_t>(y / 2) * vs;
    uint8_t* out = rgba.data() + static_cast<size_t>(y) * w * 4;
    for (int x = 0; x < w; ++x) {
      const int Y = yrow[x];
      const int U = urow[x / 2] - 128;
      const int V = vrow[x / 2] - 128;
      out[0] = Clip255(Y + ((91881 * V) >> 16));               // R
      out[1] = Clip255(Y - ((22554 * U + 46802 * V) >> 16));   // G
      out[2] = Clip255(Y + ((116130 * U) >> 16));              // B
      out[3] = 255;                                            // A
      out += 4;
    }
  }

  {
    std::lock_guard<std::mutex> lock(frame_mutex_);
    rgba_.swap(rgba);
    width_ = w;
    height_ = h;
    has_frame_ = true;
  }
  if (on_frame_available_) on_frame_available_();
}
