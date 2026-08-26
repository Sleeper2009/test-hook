include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Notification26
Notification26_FILES = Tweak.x
Notification26_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += notification26prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
