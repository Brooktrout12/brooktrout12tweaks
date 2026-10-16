include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = BatteryCapacity18Prefs
BatteryCapacity18Prefs_FILES = BC18PrefsController.m
BatteryCapacity18Prefs_CFLAGS = -fobjc-arc -Wall -Wextra -Werror
BatteryCapacity18Prefs_FRAMEWORKS = UIKit Foundation
BatteryCapacity18Prefs_PRIVATE_FRAMEWORKS = Preferences
BatteryCapacity18Prefs_INSTALL_PATH = /Library/PreferenceBundles
BatteryCapacity18Prefs_CODESIGN_FLAGS = -S -Cadhoc -Icom.brooktrout12.batterycapacity18.prefs

include $(THEOS_MAKE_PATH)/bundle.mk
