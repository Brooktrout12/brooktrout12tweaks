ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:18.0
THEOS_PACKAGE_SCHEME = rootless
FINALPACKAGE = 1
DEBUG = 0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CC17Shapes
CC17Shapes_FILES = Tweak.m
CC17Shapes_CFLAGS = -fobjc-arc -Wall -Wextra -Werror
CC17Shapes_FRAMEWORKS = UIKit Foundation QuartzCore
CC17Shapes_LIBRARIES = substrate
CC17Shapes_CODESIGN_FLAGS = -S -Cadhoc -Icom.brooktrout12.cc17shapes

include $(THEOS_MAKE_PATH)/tweak.mk
