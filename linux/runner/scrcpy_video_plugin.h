#ifndef RUNNER_SCRCPY_VIDEO_PLUGIN_H_
#define RUNNER_SCRCPY_VIDEO_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

// Registers the scrcpy video texture plugin (method channel + binary feed +
// FlPixelBufferTexture) on the given view. Call once after the view is
// realized. See native/scrcpy_video_decoder.h for the decode pipeline.
void scrcpy_video_plugin_register(FlView* view);

G_END_DECLS

#endif  // RUNNER_SCRCPY_VIDEO_PLUGIN_H_
