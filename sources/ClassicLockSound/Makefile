ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:17.0
THEOS_PACKAGE_SCHEME = rootless
FINALPACKAGE = 1
DEBUG = 0
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ClassicLockSound
ClassicLockSound_FILES = Tweak.m BTVolume.c
ClassicLockSound_CFLAGS = -fno-objc-arc -Wall -Wextra -Werror
ClassicLockSound_FRAMEWORKS = Foundation
ClassicLockSound_PRIVATE_FRAMEWORKS = SpringBoardUI
ClassicLockSound_LIBRARIES = substrate
ClassicLockSound_CODESIGN_FLAGS = -S -Cadhoc -Icom.brooktrout12.classiclocksound

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
