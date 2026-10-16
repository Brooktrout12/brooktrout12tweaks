ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:17.0
THEOS_PACKAGE_SCHEME = rootless
FINALPACKAGE = 1
DEBUG = 0
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = InstantClear18
InstantClear18_FILES = Tweak.m
InstantClear18_CFLAGS = -fobjc-arc -Wall -Wextra -Werror
InstantClear18_FRAMEWORKS = Foundation UIKit
include $(THEOS_MAKE_PATH)/tweak.mk
ifneq ($(strip $(ALLEMANDE)),)
SP18_LDID ?= ldid
after-stage::
	"$(ALLEMANDE)" "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/InstantClear18.dylib"
	"$(SP18_LDID)" -s "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/InstantClear18.dylib"
	"$(SP18_LDID)" -S -Cadhoc "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/InstantClear18.dylib"
endif
