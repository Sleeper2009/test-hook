ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:14.0

THEOS_DEVICE_IP = 
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Notification26
Notification26_FILES = Tweak.x
Notification26_CFLAGS = -fobjc-arc
Notification26_FRAMEWORKS = UIKit CoreGraphics QuartzCore
Notification26_PRIVATE_FRAMEWORKS =

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += notification26prefs
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 SpringBoard"
