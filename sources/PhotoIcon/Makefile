ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:17.0
THEOS_PACKAGE_SCHEME = rootless
FINALPACKAGE = 1
DEBUG = 0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PhotoIcon PhotoIconSystem
PhotoIcon_FILES = Tweak.xm PIStore.m PICropViewController.m PIEditorCoordinator.m PIBlockCompatibility.m PISharedPaths.m PIIconPublisher.m PISpringBoardImages.m
PhotoIcon_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter
PhotoIcon_CODESIGN_FLAGS = -S -Cadhoc -Icom.brooktrout12.photoicon
PhotoIcon_FRAMEWORKS = UIKit Foundation QuartzCore PhotosUI UniformTypeIdentifiers ImageIO

PhotoIconSystem_FILES = PISystemIcons.m PISystemIconReader.m PISharedPaths.m
PhotoIconSystem_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter
PhotoIconSystem_CODESIGN_FLAGS = -S -Cadhoc -Icom.brooktrout12.photoicon.system
PhotoIconSystem_FRAMEWORKS = UIKit Foundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk

after-stage::
	install -d -m 0755 "$(THEOS_STAGING_DIR)/var/mobile/Library/Caches/PhotoIcon"
