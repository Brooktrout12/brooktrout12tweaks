ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:17.0
THEOS_PACKAGE_SCHEME = rootless
FINALPACKAGE = 1
DEBUG = 0
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BlurSleep
BlurSleep_FILES = Tweak.m BSAnimationState.c BSAnimationEffects.m
BlurSleep_CFLAGS = -fobjc-arc -Wall -Wextra -Werror
BlurSleep_FRAMEWORKS = Foundation UIKit QuartzCore
BlurSleep_LIBRARIES = substrate
BlurSleep_CODESIGN_FLAGS = -S -Cadhoc -Icom.brooktrout12.blursleep

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
