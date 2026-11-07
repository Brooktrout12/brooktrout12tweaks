ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:18.0
THEOS_PACKAGE_SCHEME = rootless
FINALPACKAGE = 1
DEBUG = 0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CCFavorites
CCFavorites_FILES = Tweak.m
CCFavorites_CFLAGS = -fobjc-arc -Wall -Wextra -Werror
CCFavorites_FRAMEWORKS = UIKit Foundation
CCFavorites_LIBRARIES = substrate
CCFavorites_CODESIGN_FLAGS = -S -Cadhoc -Icom.brooktrout12.ccfavorites

include $(THEOS_MAKE_PATH)/tweak.mk
