ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:17.0
THEOS_PACKAGE_SCHEME = rootless
FINALPACKAGE = 1
DEBUG = 0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BadgeClear18
BadgeClear18_FILES = Tweak.m
BadgeClear18_CFLAGS = -fobjc-arc -Wall -Wextra -Werror -fvisibility=hidden
BadgeClear18_FRAMEWORKS = UIKit Foundation
BadgeClear18_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

# For Linux compilers emitting the old arm64e ABI only. On a current Apple
# toolchain leave ALLEMANDE unset. Always clean before packaging again.
ifneq ($(strip $(ALLEMANDE)),)
before-package::
	"$(ALLEMANDE)" "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/BadgeClear18.dylib"
	$(TARGET_CODESIGN) -S "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/BadgeClear18.dylib"
endif
