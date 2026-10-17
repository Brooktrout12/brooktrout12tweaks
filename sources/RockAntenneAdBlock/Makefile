# App Store apps run arm64, including on A12+ devices. This tweak never injects
# into arm64e system processes; an arm64e slice is unnecessary here.
ARCHS = arm64
TARGET = iphone:clang:16.5:17.0
THEOS_PACKAGE_SCHEME = rootless
FINALPACKAGE = 1
DEBUG = 0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = RockAntenneAdBlock
RockAntenneAdBlock_FILES = Tweak.m Diagnostics.m AdsWizz.m Rules.c SkipGate.c
RockAntenneAdBlock_CFLAGS = -fobjc-arc -Wall -Wextra -Werror -fvisibility=hidden
RockAntenneAdBlock_FRAMEWORKS = Foundation UIKit AVFoundation CoreMedia

include $(THEOS_MAKE_PATH)/tweak.mk


