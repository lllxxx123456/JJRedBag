TARGET := iphone:clang:latest:11.0
ARCHS := arm64

INSTALL_TARGET_PROCESSES = WeChat

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = JJRedBag
JJRedBag_FILES = Tweak.xm JJRedBagManager.m JJRedBagSettingsController.m JJRedBagGroupSelectController.m JJRedBagContactSelectController.m JJRedBagMemberSelectController.m JJRedBagReceiveGroupController.m JJRedBagParam.m
JJRedBag_CFLAGS = -fobjc-arc
JJRedBag_FRAMEWORKS = UIKit Foundation AVFoundation CoreLocation UserNotifications ImageIO

include $(THEOS_MAKE_PATH)/tweak.mk