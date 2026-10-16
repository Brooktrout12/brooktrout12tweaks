ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:17.0
THEOS_PACKAGE_SCHEME = rootless
FINALPACKAGE = 1
DEBUG = 0
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CleanQuickActions
CleanQuickActions_FILES = Tweak.m Preferences.m Rules.c
CleanQuickActions_CFLAGS = -fobjc-arc -Wall -Wextra -Werror -fvisibility=hidden
CleanQuickActions_FRAMEWORKS = UIKit Foundation CoreFoundation
CleanQuickActions_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

# Linux Clang toolchains with the old arm64e ABI only. Leave ALLEMANDE unset
# when building with a current Apple toolchain. Always start with make clean.
ifneq ($(strip $(ALLEMANDE)),)
before-package::
	"$(ALLEMANDE)" "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/CleanQuickActions.dylib"
	$(TARGET_CODESIGN) -S "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/CleanQuickActions.dylib"
endif
