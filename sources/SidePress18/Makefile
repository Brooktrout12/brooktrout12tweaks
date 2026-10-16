ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:17.0
THEOS_PACKAGE_SCHEME = rootless
FINALPACKAGE = 1
DEBUG = 0
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SidePress18 SidePress18Settings
SidePress18_FILES = Tweak.m Actions.m UnlockFlow.m SecureAppLaunch.m ClickSpeedRuntime.m
SidePress18_CFLAGS = -fobjc-arc -Wall -Wextra -Werror
SidePress18_FRAMEWORKS = Foundation UIKit
SidePress18Settings_FILES = ClickSpeedSettings.m
SidePress18Settings_CFLAGS = -fobjc-arc -Wall -Wextra -Werror
SidePress18Settings_FRAMEWORKS = Foundation UIKit LocalAuthentication
SidePress18Settings_PRIVATE_FRAMEWORKS = Preferences
include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk

# Only for Linux's older arm64e ABI toolchain. Omit with current Apple Xcode.
ifneq ($(strip $(ALLEMANDE)),)
SP18_LDID ?= ldid
after-stage::
	"$(ALLEMANDE)" "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/SidePress18.dylib"
	"$(SP18_LDID)" -s "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/SidePress18.dylib"
	"$(SP18_LDID)" -S -Cadhoc "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/SidePress18.dylib"
	"$(ALLEMANDE)" "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/SidePress18Settings.dylib"
	"$(SP18_LDID)" -s "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/SidePress18Settings.dylib"
	"$(SP18_LDID)" -S -Cadhoc "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/SidePress18Settings.dylib"
	"$(ALLEMANDE)" "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/SidePress18Prefs.bundle/SidePress18Prefs"
	"$(SP18_LDID)" -s "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/SidePress18Prefs.bundle/SidePress18Prefs"
	"$(SP18_LDID)" -S -Cadhoc "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/SidePress18Prefs.bundle/SidePress18Prefs"
endif
