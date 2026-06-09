cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "scrcpy_video_plugin.cpp"
  "${CMAKE_SOURCE_DIR}/../native/scrcpy_video_decoder.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Shared scrcpy H.264 decoder (native/) needs FFmpeg's libavcodec/libavutil.
# The runtime DLLs (avcodec-62/avutil-60/avformat-62) already ship in
# platform-tools/windows; build-time headers + import libs come from FFmpeg dev
# (e.g. `vcpkg install ffmpeg`). Prefer pkg-config; otherwise set
# FFMPEG_INCLUDE_DIR / FFMPEG_LIB_DIR, either as -D defines or environment
# variables (CI uses the env vars since `flutter build windows` can't forward
# -D defines).
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}/../native")
find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
  pkg_check_modules(FFMPEG IMPORTED_TARGET libavcodec libavutil)
endif()
if(TARGET PkgConfig::FFMPEG)
  target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::FFMPEG)
else()
  if(NOT DEFINED FFMPEG_INCLUDE_DIR AND DEFINED ENV{FFMPEG_INCLUDE_DIR})
    set(FFMPEG_INCLUDE_DIR "$ENV{FFMPEG_INCLUDE_DIR}")
  endif()
  if(NOT DEFINED FFMPEG_LIB_DIR AND DEFINED ENV{FFMPEG_LIB_DIR})
    set(FFMPEG_LIB_DIR "$ENV{FFMPEG_LIB_DIR}")
  endif()
  if(NOT DEFINED FFMPEG_INCLUDE_DIR OR NOT DEFINED FFMPEG_LIB_DIR)
    message(FATAL_ERROR
      "FFmpeg not found via pkg-config. Install FFmpeg dev (e.g. vcpkg install ffmpeg) "
      "or set FFMPEG_INCLUDE_DIR / FFMPEG_LIB_DIR (-D define or environment variable).")
  endif()
  target_include_directories(${BINARY_NAME} PRIVATE "${FFMPEG_INCLUDE_DIR}")
  target_link_directories(${BINARY_NAME} PRIVATE "${FFMPEG_LIB_DIR}")
  target_link_libraries(${BINARY_NAME} PRIVATE avcodec avutil)
endif()

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
