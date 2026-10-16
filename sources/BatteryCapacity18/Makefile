ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:17.0
THEOS_PACKAGE_SCHEME = rootless
FINALPACKAGE = 1
DEBUG = 0
INSTALL_TARGET_PROCESSES = Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BatteryCapacity18
BatteryCapacity18_FILES = Tweak.m BCBatteryReader.m CapacityRules.c AmperageRules.c WarningRules.c
BatteryCapacity18_CFLAGS = -fobjc-arc -Wall -Wextra -Werror -I$(THEOS_PROJECT_DIR)
BatteryCapacity18_FRAMEWORKS = Foundation UIKit IOKit
BatteryCapacity18_PRIVATE_FRAMEWORKS = Preferences
BatteryCapacity18_LIBRARIES = substrate
BatteryCapacity18_CODESIGN_FLAGS = -S -Cadhoc -Icom.brooktrout12.batterycapacity18

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk

# Native modern-ABI builds are left unchanged. Linux clang 11 builds require
# an actual ABI conversion before packaging, followed by a fresh signature.
after-stage::
	python3 scripts/finalize_stage.py "$(THEOS_STAGING_DIR)" --allemande "$(BC18_ALLEMANDE)" --ldid "$(or $(BC18_LDID),$(TARGET_CODESIGN))"
