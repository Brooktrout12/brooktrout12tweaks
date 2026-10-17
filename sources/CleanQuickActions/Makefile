ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:17.0
THEOS_PACKAGE_SCHEME = rootless
FINALPACKAGE = 1
DEBUG = 0
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CleanQuickActions
CleanQuickActions_FILES = Tweak.m IOS17Sections.m Preferences.m Rules.c
CleanQuickActions_CFLAGS = -fobjc-arc -Wall -Wextra -Werror -fvisibility=hidden
CleanQuickActions_FRAMEWORKS = UIKit Foundation CoreFoundation
CleanQuickActions_LIBRARIES = substrate
CleanQuickActions_CODESIGN_FLAGS = -S -Cadhoc -Icom.brooktrout12.cleanquickactions

include $(THEOS_MAKE_PATH)/tweak.mk

# For the legacy Linux arm64e toolchain, scripts/build-linux.sh supplies a
# signer that converts the finished binary before signing. Modern Apple
# toolchains use the normal Theos signing path without ABI conversion.
