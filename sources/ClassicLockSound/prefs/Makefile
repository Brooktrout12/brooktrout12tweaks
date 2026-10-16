include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = ClassicLockSoundPrefs
ClassicLockSoundPrefs_FILES = BTLockSoundPrefsController.m ../BTVolume.c
ClassicLockSoundPrefs_CFLAGS = -fobjc-arc -Wall -Wextra -Werror
ClassicLockSoundPrefs_FRAMEWORKS = UIKit Foundation
ClassicLockSoundPrefs_PRIVATE_FRAMEWORKS = Preferences
ClassicLockSoundPrefs_INSTALL_PATH = /Library/PreferenceBundles
ClassicLockSoundPrefs_CODESIGN_FLAGS = -S -Cadhoc -Icom.brooktrout12.classiclocksound.prefs

include $(THEOS_MAKE_PATH)/bundle.mk
