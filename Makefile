CXX ?= clang++
CXXFLAGS ?= -std=c++17 -O2 -Wall -Wextra -Ibackend -Ibackend/api

UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
    HOMEBREW_PREFIX ?= /opt/homebrew
    CXXFLAGS += -I$(HOMEBREW_PREFIX)/opt/ffmpeg/include -I$(HOMEBREW_PREFIX)/opt/openssl/include
    LDFLAGS += -L$(HOMEBREW_PREFIX)/opt/ffmpeg/lib -L$(HOMEBREW_PREFIX)/opt/openssl/lib
    ifneq ($(wildcard $(HOMEBREW_PREFIX)/opt/opencv@4/include/opencv4),)
        OPENCV_DIR = $(HOMEBREW_PREFIX)/opt/opencv@4
        CXXFLAGS += -I$(OPENCV_DIR)/include/opencv4 -DENABLE_AI_DETECTION
        LDFLAGS += -L$(OPENCV_DIR)/lib
        LIBS_OPENCV = -lopencv_core -lopencv_dnn -lopencv_videoio -lopencv_imgproc
    else ifneq ($(wildcard $(HOMEBREW_PREFIX)/opt/opencv/include/opencv4),)
        OPENCV_DIR = $(HOMEBREW_PREFIX)/opt/opencv
        CXXFLAGS += -I$(OPENCV_DIR)/include/opencv4 -DENABLE_AI_DETECTION
        LDFLAGS += -L$(OPENCV_DIR)/lib
        LIBS_OPENCV = -lopencv_core -lopencv_dnn -lopencv_videoio -lopencv_imgproc
    endif
else
    OPENCV_PKG := $(shell pkg-config --exists opencv4 && echo 1 || echo 0)
    ifeq ($(OPENCV_PKG),1)
        CXXFLAGS += $(shell pkg-config --cflags opencv4) -DENABLE_AI_DETECTION
        LIBS_OPENCV = $(shell pkg-config --libs opencv4)
    endif
endif

LIBS_RECOVERY = -lavformat -lavcodec -lavutil -lcrypto -lssl -lpthread $(LIBS_OPENCV)

COMMON_OBJS = backend/file_carver.o backend/clip_validator.o backend/custody_log.o backend/timeline_normalizer.o backend/report_generator.o backend/ai_detector.o

all: dvr_recovery dvr_api_server synthetic_image_builder

%.o: %.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

dvr_recovery: backend/detect.c++ $(COMMON_OBJS)
	$(CXX) $(CXXFLAGS) $^ -o $@ $(LDFLAGS) $(LIBS_RECOVERY)

dvr_api_server: backend/api/api_server.cpp $(COMMON_OBJS)
	$(CXX) $(CXXFLAGS) $^ -o $@ $(LDFLAGS) $(LIBS_RECOVERY)

synthetic_image_builder: backend/synthetic_image_builder.cpp
	$(CXX) $(CXXFLAGS) $^ -o $@ $(LDFLAGS)

clean:
	rm -rf dvr_recovery dvr_api_server synthetic_image_builder *.o backend/*.o backend/api/*.o *.dSYM carved_output output cases synthetic_disk.img /tmp/syn_tmp_*.mp4 build test_build

.PHONY: all clean
