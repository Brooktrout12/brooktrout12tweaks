ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:17.0
THEOS_PACKAGE_SCHEME = rootless
FINALPACKAGE = 1
DEBUG = 0
INSTALL_TARGET_PROCESSES = Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FaceIDGrace
FaceIDGrace_FILES = Tweak.m
FaceIDGrace_CFLAGS = -fobjc-arc -Wall -Wextra -Werror
FaceIDGrace_FRAMEWORKS = Foundation
FaceIDGrace_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

# Needed only with a Linux toolchain that emits the pre-iOS-14 arm64e ABI.
# Convert the staged binary, then sign it again before packaging.
ifneq ($(strip $(ALLEMANDE)),)
before-package::
	"$(ALLEMANDE)" "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/FaceIDGrace.dylib"
	$(TARGET_CODESIGN) -S "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/FaceIDGrace.dylib"
endif
