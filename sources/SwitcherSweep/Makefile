ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:17.0
THEOS_PACKAGE_SCHEME = rootless
FINALPACKAGE = 1
DEBUG = 0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk
TWEAK_NAME = SwitcherSweep
SwitcherSweep_FILES = Tweak.m
SwitcherSweep_CFLAGS = -fno-objc-arc -Wall -Wextra -Werror
SwitcherSweep_FRAMEWORKS = UIKit Foundation QuartzCore
SwitcherSweep_LIBRARIES = substrate
SwitcherSweep_CODESIGN_FLAGS = -S -Cadhoc -Icom.brooktrout12.switchersweep
include $(THEOS_MAKE_PATH)/tweak.mk
