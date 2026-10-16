ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:17.0
THEOS_PACKAGE_SCHEME = rootless
FINALPACKAGE = 1
DEBUG = 0
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Dawn18Apps Dawn18SpringBoard
Dawn18Apps_FILES = Appearance.m Preferences.m Rules.c
Dawn18Apps_CFLAGS = -fobjc-arc -Wall -Wextra -Werror -fvisibility=hidden -DD18_APPLICATIONS=1
Dawn18Apps_FRAMEWORKS = UIKit Foundation CoreFoundation
Dawn18Apps_LIBRARIES = substrate
Dawn18SpringBoard_FILES = Appearance.m Preferences.m Rules.c Preview.m ClassicMenu.m
Dawn18SpringBoard_CFLAGS = -fobjc-arc -Wall -Wextra -Werror -fvisibility=hidden -DD18_APPLICATIONS=0
Dawn18SpringBoard_FRAMEWORKS = UIKit Foundation CoreFoundation
Dawn18SpringBoard_LIBRARIES = substrate

BUNDLE_NAME = Dawn18Prefs
Dawn18Prefs_FILES = Settings.m Preferences.m Rules.c
Dawn18Prefs_CFLAGS = -fobjc-arc -Wall -Wextra -Werror -fvisibility=hidden
Dawn18Prefs_FRAMEWORKS = UIKit Foundation CoreFoundation
Dawn18Prefs_PRIVATE_FRAMEWORKS = Preferences
Dawn18Prefs_INSTALL_PATH = /Library/PreferenceBundles
Dawn18Prefs_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk

# Only for Linux Clang toolchains that emit the old arm64e ABI. On a current
# Apple toolchain, leave ALLEMANDE unset. Convert the staged files and re-sign.
ifneq ($(strip $(ALLEMANDE)),)
before-package::
	"$(ALLEMANDE)" "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/Dawn18Apps.dylib"
	$(TARGET_CODESIGN) -S "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/Dawn18Apps.dylib"
	"$(ALLEMANDE)" "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/Dawn18SpringBoard.dylib"
	$(TARGET_CODESIGN) -S "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/Dawn18SpringBoard.dylib"
	"$(ALLEMANDE)" "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/Dawn18Prefs.bundle/Dawn18Prefs"
	$(TARGET_CODESIGN) -S "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/Dawn18Prefs.bundle/Dawn18Prefs"
endif
