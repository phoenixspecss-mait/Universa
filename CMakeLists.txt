cmake_minimum_required(VERSION 3.16)
project(DVRForensicRecovery LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

list(PREPEND CMAKE_PREFIX_PATH "/opt/homebrew/opt/opencv@4" "/opt/homebrew/opt/opencv" "/opt/homebrew" "/usr/local/opt/opencv@4" "/usr/local/opt/opencv" "/usr/local")

find_package(Threads REQUIRED)
find_package(OpenSSL REQUIRED)

find_package(PkgConfig QUIET)
if (PKG_CONFIG_FOUND)
    pkg_check_modules(AVCODEC libavcodec)
    pkg_check_modules(AVFORMAT libavformat)
    pkg_check_modules(AVUTIL libavutil)
    pkg_check_modules(LIBHPDF libhpdf)
endif()

if (LIBHPDF_FOUND)
    add_compile_definitions(HAVE_LIBHPDF)
    message(STATUS "Found libhpdf: linking against external PDF library.")
else()
    message(STATUS "libhpdf not found via pkg-config; proceeding with built-in minimal PDF writer fallback.")
endif()

option(ENABLE_AI_DETECTION "Enable OpenCV DNN AI Detection" ON)
set(OPENCV_EXTRA_LIBS "")
set(OPENCV_EXTRA_INCLUDES "")

if (ENABLE_AI_DETECTION)
    find_package(OpenCV QUIET HINTS /opt/homebrew/opt/opencv@4 /opt/homebrew/opt/opencv /usr/local/opt/opencv@4 /usr/local/opt/opencv)
    if (OpenCV_FOUND)
        message(STATUS "Found OpenCV ${OpenCV_VERSION}: enabling AI detection module.")
        add_compile_definitions(ENABLE_AI_DETECTION)
        set(OPENCV_EXTRA_LIBS ${OpenCV_LIBS})
        set(OPENCV_EXTRA_INCLUDES ${OpenCV_INCLUDE_DIRS})
    else()
        message(WARNING "OpenCV not found; AI detection module will compile with graceful no-op fallback.")
    endif()
else()
    message(STATUS "AI detection explicitly disabled via ENABLE_AI_DETECTION=OFF.")
endif()

link_directories(
    /opt/homebrew/lib
    /opt/homebrew/opt/ffmpeg/lib
    /opt/homebrew/opt/openssl/lib
    /opt/homebrew/opt/opencv@4/lib
    /usr/local/lib
    ${AVFORMAT_LIBRARY_DIRS}
    ${AVCODEC_LIBRARY_DIRS}
    ${AVUTIL_LIBRARY_DIRS}
)

if (NOT AVCODEC_FOUND)
    find_path(AVCODEC_INCLUDE_DIRS libavcodec/avcodec.h
        HINTS /opt/homebrew/include /opt/homebrew/opt/ffmpeg/include /usr/local/include /usr/include)
    find_library(AVCODEC_LIBRARIES NAMES avcodec
        HINTS /opt/homebrew/lib /opt/homebrew/opt/ffmpeg/lib /usr/local/lib /usr/lib /usr/lib/x86_64-linux-gnu)
endif()

if (NOT AVFORMAT_FOUND)
    find_path(AVFORMAT_INCLUDE_DIRS libavformat/avformat.h
        HINTS /opt/homebrew/include /opt/homebrew/opt/ffmpeg/include /usr/local/include /usr/include)
    find_library(AVFORMAT_LIBRARIES NAMES avformat
        HINTS /opt/homebrew/lib /opt/homebrew/opt/ffmpeg/lib /usr/local/lib /usr/lib /usr/lib/x86_64-linux-gnu)
endif()

if (NOT AVUTIL_FOUND)
    find_path(AVUTIL_INCLUDE_DIRS libavutil/avutil.h
        HINTS /opt/homebrew/include /opt/homebrew/opt/ffmpeg/include /usr/local/include /usr/include)
    find_library(AVUTIL_LIBRARIES NAMES avutil
        HINTS /opt/homebrew/lib /opt/homebrew/opt/ffmpeg/lib /usr/local/lib /usr/lib /usr/lib/x86_64-linux-gnu)
endif()

include(FetchContent)
FetchContent_Declare(
    httplib
    GIT_REPOSITORY https://github.com/yhirose/cpp-httplib.git
    GIT_TAG v0.15.3
)
if (NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/backend/api/httplib.h")
    FetchContent_MakeAvailable(httplib)
endif()

set(COMMON_SOURCES
    backend/file_carver.cpp
    backend/clip_validator.cpp
    backend/custody_log.cpp
    backend/timeline_normalizer.cpp
    backend/report_generator.cpp
    backend/ai_detector.cpp
)

add_executable(dvr_recovery
    backend/detect.c++
    ${COMMON_SOURCES}
)

target_include_directories(dvr_recovery PRIVATE
    backend
    backend/api
    ${OPENSSL_INCLUDE_DIR}
    ${AVCODEC_INCLUDE_DIRS}
    ${AVFORMAT_INCLUDE_DIRS}
    ${AVUTIL_INCLUDE_DIRS}
    ${OPENCV_EXTRA_INCLUDES}
)

target_link_libraries(dvr_recovery PRIVATE
    OpenSSL::Crypto
    OpenSSL::SSL
    ${AVFORMAT_LIBRARIES}
    ${AVCODEC_LIBRARIES}
    ${AVUTIL_LIBRARIES}
    Threads::Threads
    ${OPENCV_EXTRA_LIBS}
)
if (LIBHPDF_FOUND)
    target_link_libraries(dvr_recovery PRIVATE ${LIBHPDF_LIBRARIES})
endif()

add_executable(dvr_api_server
    backend/api/api_server.cpp
    ${COMMON_SOURCES}
)

target_include_directories(dvr_api_server PRIVATE
    backend
    backend/api
    ${OPENSSL_INCLUDE_DIR}
    ${AVCODEC_INCLUDE_DIRS}
    ${AVFORMAT_INCLUDE_DIRS}
    ${AVUTIL_INCLUDE_DIRS}
    ${OPENCV_EXTRA_INCLUDES}
)

target_link_libraries(dvr_api_server PRIVATE
    OpenSSL::Crypto
    OpenSSL::SSL
    ${AVFORMAT_LIBRARIES}
    ${AVCODEC_LIBRARIES}
    ${AVUTIL_LIBRARIES}
    Threads::Threads
    ${OPENCV_EXTRA_LIBS}
)
if (LIBHPDF_FOUND)
    target_link_libraries(dvr_api_server PRIVATE ${LIBHPDF_LIBRARIES})
endif()

add_executable(synthetic_image_builder
    backend/synthetic_image_builder.cpp
)

target_include_directories(synthetic_image_builder PRIVATE
    backend
)
