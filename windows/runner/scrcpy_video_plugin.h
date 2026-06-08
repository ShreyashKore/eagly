#ifndef RUNNER_SCRCPY_VIDEO_PLUGIN_H_
#define RUNNER_SCRCPY_VIDEO_PLUGIN_H_

namespace flutter {
class FlutterEngine;
}

// Registers the scrcpy video texture plugin (method channel + binary feed +
// PixelBufferTexture) with the given engine. Call once after the engine is
// created. See native/scrcpy_video_decoder.h for the decode pipeline.
void RegisterScrcpyVideoPlugin(flutter::FlutterEngine* engine);

#endif  // RUNNER_SCRCPY_VIDEO_PLUGIN_H_
