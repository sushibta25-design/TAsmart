ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = CarPlay

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = A510MiniBridge
A510MiniBridge_FILES = A510MiniBridge.xm
A510MiniBridge_FRAMEWORKS = UIKit Foundation
A510MiniBridge_CFLAGS = -fobjc-arc
A510MiniBridge_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
