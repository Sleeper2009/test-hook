THEOS_PACKAGE_SCHEME = rootless

TARGET := iphone:clang:latest:15.0
ARCHS := arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CloseGestureProbe

CloseGestureProbe_FILES = Tweak.x
CloseGestureProbe_CFLAGS = -fobjc-arc
CloseGestureProbe_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
