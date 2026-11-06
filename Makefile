TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard

# Bỏ dấu # ở dòng dưới nếu máy bạn jailbreak kiểu rootless (có thư mục /var/jb).
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = RecordUnhide

RecordUnhide_FILES = Tweak.x
RecordUnhide_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
