# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(eagly LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "eagly")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Keep std::mutex's pre-VS-17.10 (non-constexpr) constructor. Since MSVC STL
# 17.10 (_MSVC_STL_UPDATE 202402) std::mutex is constexpr-constructed and only
# works with msvcp140.dll 14.40+; loaded against an older one (a Windows 10
# image whose VC++ Redistributable was never updated) the first lock
# null-derefs or aborts inside msvcp140!mtx_do_lock — FLUTTER-M2/M7, from the
# runner's scrcpy plugin/decoder mutexes. The app-local runtime installed below
# is the real fix; this keeps our own code safe even if an old msvcp140.dll
# still wins (e.g. one already loaded into the process by injected software).
# Directory scope, before any add_subdirectory, so the runner, the plugins and
# the sentry-native/crashpad sources built in-tree all get it.
# https://github.com/microsoft/STL/issues/4730
# https://github.com/microsoft/STL/wiki/Changelog (VS 2022 17.10, "constexpr mutex")
add_compile_definitions(_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)

# Copy bundled mobile tools into the app bundle.
set(MOBILE_TOOLS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../platform-tools/windows")
if(EXISTS "${MOBILE_TOOLS_DIR}")
  install(DIRECTORY "${MOBILE_TOOLS_DIR}/" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
    COMPONENT Runtime)
else()
  message(WARNING "Bundled mobile tools were not found at ${MOBILE_TOOLS_DIR}. Run scripts/download_platform_tools.sh first.")
endif()

# The runner imports FFmpeg (scrcpy H.264 decoder) at load time, so the runtime
# DLLs must sit NEXT TO the executable — Windows does not search data/ when
# resolving an exe's import table, and the app fails at startup with
# "avcodec-XX.dll was not found" otherwise. swresample is libavcodec's own
# load-time dependency. The glob keeps this version-agnostic, but the bundled
# runtime (from the scrcpy release zip) must stay at the same FFmpeg major
# version as the import libs used at build time (avcodec-62/avutil-60 ⇔
# FFmpeg 8.x — see .github/workflows/release.yml and native/README.md).
if(EXISTS "${MOBILE_TOOLS_DIR}")
  file(GLOB FFMPEG_RUNTIME_DLLS
    "${MOBILE_TOOLS_DIR}/avcodec-*.dll"
    "${MOBILE_TOOLS_DIR}/avutil-*.dll"
    "${MOBILE_TOOLS_DIR}/avformat-*.dll"
    "${MOBILE_TOOLS_DIR}/swresample-*.dll"
    "${MOBILE_TOOLS_DIR}/swscale-*.dll")
  if(FFMPEG_RUNTIME_DLLS)
    install(FILES ${FFMPEG_RUNTIME_DLLS}
      DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
      COMPONENT Runtime)
  else()
    message(WARNING "No FFmpeg runtime DLLs (avcodec/avutil/swresample) found in ${MOBILE_TOOLS_DIR}; ${BINARY_NAME}.exe will not start without them. Run scripts/download_platform_tools.sh windows.")
  endif()
endif()

# Ship the Visual C++ runtime app-local, next to eagly.exe. The binaries are
# built with the CI image's newest toolset (VS 2026 on windows-2025-vs2026)
# and need an msvcp140.dll at least that new; Windows does not provide one and
# the installer does not run vc_redist, so without these the exe picks up
# whatever C:\Windows\System32 has — on an un-updated Windows 10 that is a pre-
# 14.40 copy and the app crashes in msvcp140!mtx_do_lock (FLUTTER-M2/M7). The
# application directory is searched before System32 (msvcp140/vcruntime140 are
# not KnownDLLs), so these copies win for eagly.exe and every plugin DLL.
# The whole Microsoft.VC<nnn>.CRT folder is the unit Microsoft documents for
# app-local deployment, and the same set the msix tool packs into the .msix:
# https://learn.microsoft.com/cpp/windows/deployment-in-visual-cpp#local-deployment
# Taken from the redist of the VS install whose compiler built us (newest
# version folder), so it is never older than the headers we compiled against.
# Release/Profile only: Debug links the non-redistributable debug CRT.
# The UCRT (ucrtbase.dll) is part of Windows 10+ and is not bundled.
# .github/workflows/release.yml checks the installer and .msix contain them.
if(MSVC)
  string(TOLOWER "${CMAKE_CXX_COMPILER_ARCHITECTURE_ID}" _vc_arch)
  if(DEFINED ENV{VCToolsRedistDir})
    # Set inside a VS developer prompt; points at one Redist/MSVC/<ver> folder.
    file(TO_CMAKE_PATH "$ENV{VCToolsRedistDir}" _vc_redist_root)
    string(REGEX REPLACE "/+$" "" _vc_redist_root "${_vc_redist_root}")
  else()
    # flutter build runs cmake outside a developer prompt, so derive it from
    # the compiler: <VS>/VC/Tools/MSVC/<ver>/bin/Host<arch>/<arch>/cl.exe ->
    # <VS>/VC/Redist/MSVC/<redist ver> (the two versions usually differ).
    string(REGEX REPLACE "/Tools/MSVC/[^/]+/bin/.*$" "" _vc_dir "${CMAKE_CXX_COMPILER}")
    set(_vc_redist_root "${_vc_dir}/Redist/MSVC/14.*")
  endif()
  file(GLOB _vc_crt_dirs LIST_DIRECTORIES true
    "${_vc_redist_root}/${_vc_arch}/Microsoft.VC*.CRT")
  set(VC_RUNTIME_DLLS "")
  if(_vc_crt_dirs)
    # Newest redist version first (the version is the first varying component).
    list(SORT _vc_crt_dirs COMPARE NATURAL ORDER DESCENDING)
    list(GET _vc_crt_dirs 0 _vc_crt_dir)
    file(GLOB VC_RUNTIME_DLLS "${_vc_crt_dir}/*.dll")
  endif()
  if(VC_RUNTIME_DLLS MATCHES "msvcp140\\.dll" AND VC_RUNTIME_DLLS MATCHES "vcruntime140\\.dll")
    message(STATUS "Bundling the VC++ runtime app-local from ${_vc_crt_dir}")
    install(FILES ${VC_RUNTIME_DLLS}
      DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
      CONFIGURATIONS Profile;Release
      COMPONENT Runtime)
  else()
    message(WARNING "VC++ runtime redist not found (looked in '${_vc_redist_root}/${_vc_arch}'); ${BINARY_NAME}.exe will depend on the system's msvcp140.dll and can crash on PCs with an old VC++ Redistributable. Install the 'MSVC v14x - VS C++ x64/x86 build tools' component, or set VCToolsRedistDir.")
  endif()
endif()
