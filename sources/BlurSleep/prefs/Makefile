include $(THEOS)/makefiles/common.mk
BUNDLE_NAME = BlurSleepPrefs
BlurSleepPrefs_FILES = BSRootListController.m ../BSAnimationState.c
BlurSleepPrefs_CFLAGS = -fobjc-arc -Wall -Wextra -Werror
BlurSleepPrefs_FRAMEWORKS = UIKit Foundation
BlurSleepPrefs_PRIVATE_FRAMEWORKS = Preferences
BlurSleepPrefs_INSTALL_PATH = /Library/PreferenceBundles
BlurSleepPrefs_CODESIGN_FLAGS = -S -Cadhoc -Icom.brooktrout12.blursleep.prefs
include $(THEOS_MAKE_PATH)/bundle.mk
