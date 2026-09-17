ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = CarPlay

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TAsmart
TAsmart_FILES = TAsmart.xm
TAsmart_FRAMEWORKS = UIKit Foundation
TAsmart_CFLAGS = -fobjc-arc
TAsmart_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
