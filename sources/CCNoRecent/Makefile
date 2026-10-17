ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:17.0
THEOS_PACKAGE_SCHEME = rootless
FINALPACKAGE = 1
DEBUG = 0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CCNoRecent
CCNoRecent_FILES = Tweak.m
CCNoRecent_CFLAGS = -fobjc-arc -Wall -Wextra -Werror
CCNoRecent_FRAMEWORKS = Foundation UIKit
CCNoRecent_LIBRARIES = substrate
CCNoRecent_CODESIGN_FLAGS = -S -Cadhoc -Icom.brooktrout12.ccnorecent

include $(THEOS_MAKE_PATH)/tweak.mk
