cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "scrcpy_video_plugin.cc"
  "${CMAKE_SOURCE_DIR}/../native/scrcpy_video_decoder.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# The shared scrcpy H.264 decoder (native/) needs FFmpeg's libavcodec/libavutil.
# Prefer the minimal, glibc-only FFmpeg staged by scripts/build_linux_ffmpeg.sh
# (.ffmpeg-dev/linux) so the build links — and the .deb bundles (see
# linux/CMakeLists.txt) — a self-contained FFmpeg instead of the distro one,
# whose soname would pin the package to a single Ubuntu release. CI forwards the
# same location via FFMPEG_LIB_DIR. Falls back to the system FFmpeg
# (sudo apt install libavcodec-dev libavutil-dev) only when neither is present.
set(_bundled_ffmpeg "${CMAKE_SOURCE_DIR}/../.ffmpeg-dev/linux")
if(DEFINED ENV{FFMPEG_LIB_DIR} AND EXISTS "$ENV{FFMPEG_LIB_DIR}/pkgconfig")
  set(ENV{PKG_CONFIG_PATH} "$ENV{FFMPEG_LIB_DIR}/pkgconfig:$ENV{PKG_CONFIG_PATH}")
elseif(EXISTS "${_bundled_ffmpeg}/lib/pkgconfig")
  set(ENV{PKG_CONFIG_PATH} "${_bundled_ffmpeg}/lib/pkgconfig:$ENV{PKG_CONFIG_PATH}")
endif()
pkg_check_modules(FFMPEG REQUIRED IMPORTED_TARGET libavcodec libavutil)

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::FFMPEG)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}/../native")
