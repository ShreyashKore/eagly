#include "scrcpy_video_plugin.h"

#include <cstdint>
#include <cstring>
#include <map>
#include <mutex>
#include <vector>

#include "scrcpy_video_decoder.h"

// ---------------------------------------------------------------------------
// Custom FlPixelBufferTexture that pulls RGBA frames from a ScrcpyVideoDecoder.
// ---------------------------------------------------------------------------

G_DECLARE_FINAL_TYPE(ScrcpyTexture, scrcpy_texture, SCRCPY, TEXTURE,
                     FlPixelBufferTexture)

struct _ScrcpyTexture {
  FlPixelBufferTexture parent_instance;
  ScrcpyVideoDecoder* decoder;   // owned
  std::vector<uint8_t>* pixels;  // persistent buffer handed to the engine
};

G_DEFINE_TYPE(ScrcpyTexture, scrcpy_texture, fl_pixel_buffer_texture_get_type())

static gboolean scrcpy_texture_copy_pixels(FlPixelBufferTexture* texture,
                                           const uint8_t** out_buffer,
                                           uint32_t* width, uint32_t* height,
                                           GError** error) {
  ScrcpyTexture* self = SCRCPY_TEXTURE(texture);
  int w = 0;
  int h = 0;
  if (self->decoder == nullptr ||
      !self->decoder->CopyLatestFrame(self->pixels, &w, &h)) {
    // No frame yet — return a 1x1 transparent pixel so the engine has data.
    static const uint8_t kEmpty[4] = {0, 0, 0, 0};
    *out_buffer = kEmpty;
    *width = 1;
    *height = 1;
    return TRUE;
  }
  *out_buffer = self->pixels->data();
  *width = static_cast<uint32_t>(w);
  *height = static_cast<uint32_t>(h);
  return TRUE;
}

static void scrcpy_texture_dispose(GObject* object) {
  ScrcpyTexture* self = SCRCPY_TEXTURE(object);
  delete self->decoder;
  self->decoder = nullptr;
  delete self->pixels;
  self->pixels = nullptr;
  G_OBJECT_CLASS(scrcpy_texture_parent_class)->dispose(object);
}

static void scrcpy_texture_class_init(ScrcpyTextureClass* klass) {
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels = scrcpy_texture_copy_pixels;
  G_OBJECT_CLASS(klass)->dispose = scrcpy_texture_dispose;
}

static void scrcpy_texture_init(ScrcpyTexture* self) {
  self->decoder = nullptr;
  self->pixels = nullptr;
}

// ---------------------------------------------------------------------------
// Plugin context + channel handlers.
// ---------------------------------------------------------------------------

namespace {

struct PluginContext {
  FlTextureRegistrar* textures = nullptr;
  FlMethodChannel* method_channel = nullptr;
  FlBasicMessageChannel* feed_channel = nullptr;
  std::mutex mutex;
  std::map<int64_t, ScrcpyTexture*> sessions;
};

struct MarkData {
  FlTextureRegistrar* registrar;
  FlTexture* texture;
};

// Marks a frame available on the platform thread (decode happens off-thread).
gboolean MarkFrameIdle(gpointer user_data) {
  auto* data = static_cast<MarkData*>(user_data);
  fl_texture_registrar_mark_texture_frame_available(data->registrar,
                                                    data->texture);
  g_object_unref(data->texture);
  delete data;
  return G_SOURCE_REMOVE;
}

int64_t CreateSession(PluginContext* ctx) {
  ScrcpyTexture* texture =
      SCRCPY_TEXTURE(g_object_new(scrcpy_texture_get_type(), nullptr));
  texture->pixels = new std::vector<uint8_t>();

  fl_texture_registrar_register_texture(ctx->textures, FL_TEXTURE(texture));
  const int64_t id = fl_texture_get_id(FL_TEXTURE(texture));

  FlTextureRegistrar* registrar = ctx->textures;
  texture->decoder = new ScrcpyVideoDecoder([registrar, texture]() {
    // Called on the decode thread; bounce to the GLib main loop, holding a
    // ref so the texture stays alive until the mark runs.
    g_object_ref(texture);
    g_idle_add(MarkFrameIdle, new MarkData{registrar, FL_TEXTURE(texture)});
  });

  {
    std::lock_guard<std::mutex> lock(ctx->mutex);
    ctx->sessions[id] = texture;
  }
  return id;
}

void DisposeSession(PluginContext* ctx, int64_t id) {
  ScrcpyTexture* texture = nullptr;
  {
    std::lock_guard<std::mutex> lock(ctx->mutex);
    auto it = ctx->sessions.find(id);
    if (it == ctx->sessions.end()) return;
    texture = it->second;
    ctx->sessions.erase(it);
  }
  fl_texture_registrar_unregister_texture(ctx->textures, FL_TEXTURE(texture));
  g_object_unref(texture);  // release our ref; pending idle marks hold their own
}

void FeedMessageCb(FlBasicMessageChannel* channel, FlValue* message,
                   FlBasicMessageChannelResponseHandle* response_handle,
                   gpointer user_data) {
  auto* ctx = static_cast<PluginContext*>(user_data);
  if (fl_value_get_type(message) == FL_VALUE_TYPE_UINT8_LIST) {
    const uint8_t* data = fl_value_get_uint8_list(message);
    const size_t len = fl_value_get_length(message);
    if (len > 8) {
      int64_t id = 0;
      std::memcpy(&id, data, sizeof(int64_t));  // Dart little-endian; Linux is LE
      ScrcpyVideoDecoder* decoder = nullptr;
      {
        std::lock_guard<std::mutex> lock(ctx->mutex);
        auto it = ctx->sessions.find(id);
        if (it != ctx->sessions.end()) decoder = it->second->decoder;
      }
      if (decoder) decoder->Feed(data + 8, len - 8);
    }
  }
  fl_basic_message_channel_respond(channel, response_handle, nullptr, nullptr);
}

void MethodCallCb(FlMethodChannel* channel, FlMethodCall* method_call,
                  gpointer user_data) {
  auto* ctx = static_cast<PluginContext*>(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(method, "create") == 0) {
    const int64_t id = CreateSession(ctx);
    g_autoptr(FlValue) result = fl_value_new_int(id);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "dispose") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* texture_id = fl_value_lookup_string(args, "textureId");
      if (texture_id != nullptr &&
          fl_value_get_type(texture_id) == FL_VALUE_TYPE_INT) {
        DisposeSession(ctx, fl_value_get_int(texture_id));
      }
    }
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_null()));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  fl_method_call_respond(method_call, response, &error);
}

}  // namespace

void scrcpy_video_plugin_register(FlView* view) {
  FlEngine* engine = fl_view_get_engine(view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);

  // Intentionally leaked: lives for the lifetime of the application.
  auto* ctx = new PluginContext();
  ctx->textures = fl_engine_get_texture_registrar(engine);

  g_autoptr(FlStandardMethodCodec) method_codec = fl_standard_method_codec_new();
  ctx->method_channel = fl_method_channel_new(
      messenger, "flutter_scrcpy/video", FL_METHOD_CODEC(method_codec));
  fl_method_channel_set_method_call_handler(ctx->method_channel, MethodCallCb,
                                            ctx, nullptr);

  g_autoptr(FlBinaryCodec) binary_codec = fl_binary_codec_new();
  ctx->feed_channel = fl_basic_message_channel_new(
      messenger, "flutter_scrcpy/video/feed", FL_MESSAGE_CODEC(binary_codec));
  fl_basic_message_channel_set_message_handler(ctx->feed_channel, FeedMessageCb,
                                               ctx, nullptr);
}
