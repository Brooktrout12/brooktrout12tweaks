ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:17.0
THEOS_PACKAGE_SCHEME = rootless
FINALPACKAGE = 1
DEBUG = 0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = InstantPasscode18
InstantPasscode18_FILES = Tweak.m
InstantPasscode18_CFLAGS = -fobjc-arc -Wall -Wextra -Werror
InstantPasscode18_FRAMEWORKS = Foundation UIKit

include $(THEOS_MAKE_PATH)/tweak.mk

# Optional Linux toolchain support. Run only with an old-ABI arm64e compiler;
# normal builds with current Apple Xcode must omit ALLEMANDE.
ifneq ($(strip $(ALLEMANDE)),)
IP18_LDID ?= ldid
after-stage::
	"$(ALLEMANDE)" "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/InstantPasscode18.dylib" > "$(THEOS_STAGING_DIR)/../allemande.log"
	"$(IP18_LDID)" -s "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/InstantPasscode18.dylib"
	"$(IP18_LDID)" -S -Cadhoc "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/InstantPasscode18.dylib"
endif
