ARCHS = armv7
TARGET = iphone:clang:latest:6.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Pogoda
Pogoda_FILES = main.m AppDelegate.m RootViewController.m
Pogoda_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore CoreLocation
Pogoda_CFLAGS = -fobjc-arc -fno-optimize-sibling-calls
Pogoda_CFLAGS += -Wno-unused-const-variable -Wno-error

include $(THEOS_MAKE_PATH)/application.mk
