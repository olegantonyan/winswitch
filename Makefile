APP_NAME    = WinSwitch
BUNDLE_ID   = local.winswitch
CONFIG      = release
APP         = build/$(APP_NAME).app
ICON        = build/AppIcon.icns
INSTALL_DIR = /Applications
# A stable signing identity keeps the Accessibility permission across rebuilds
# (ad-hoc signing would change the signature every build and silently drop it).
SIGN_ID    ?= Apple Development
# Empty = native arch only. "arm64 x86_64" = universal binary (used by CI).
ARCHS      ?=
ARCH_FLAGS  = $(foreach a,$(ARCHS),--arch $(a))
# Empty = keep the version from Info.plist. CI sets it from the git tag.
VERSION    ?=
DMG         = build/$(APP_NAME)$(if $(VERSION),-$(VERSION)).dmg

.PHONY: build bundle dmg run install uninstall clean

# Compile the executable.
build:
	swift build -c $(CONFIG) $(ARCH_FLAGS)

$(ICON): Scripts/make-icon.swift
	rm -rf build/AppIcon.iconset
	swift Scripts/make-icon.swift build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o $(ICON)

# Wrap the binary into a signed .app bundle.
bundle: build $(ICON)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp "$$(swift build -c $(CONFIG) $(ARCH_FLAGS) --show-bin-path)/$(APP_NAME)" $(APP)/Contents/MacOS/$(APP_NAME)
	cp Info.plist $(APP)/Contents/Info.plist
ifneq ($(VERSION),)
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" \
		-c "Set :CFBundleVersion $(VERSION)" $(APP)/Contents/Info.plist
endif
	cp $(ICON) $(APP)/Contents/Resources/AppIcon.icns
	codesign --force --timestamp=none --sign "$(SIGN_ID)" $(APP)
	@echo "Built $(APP)"

# Disk image with the app and an Applications link to drag it to.
# hdiutil sometimes fails with "Resource busy" on CI runners, so retry.
dmg: bundle
	rm -rf build/dmg $(DMG)
	mkdir -p build/dmg
	ditto $(APP) build/dmg/$(APP_NAME).app
	ln -s /Applications build/dmg/Applications
	for i in 1 2 3; do \
		hdiutil create -volname $(APP_NAME) -srcfolder build/dmg -fs HFS+ -format UDZO -ov $(DMG) && exit 0; \
		sleep 5; \
	done; exit 1
	@echo "Built $(DMG)"

# Foreground debug run, logs print here. Ctrl-C to quit.
# Note: started from a terminal, macOS checks the terminal's Accessibility permission.
run: bundle
	./$(APP)/Contents/MacOS/$(APP_NAME)

# Replace the copy in /Applications and start it.
install: bundle
	-pkill -x $(APP_NAME); sleep 1
	rm -rf $(INSTALL_DIR)/$(APP_NAME).app
	ditto $(APP) $(INSTALL_DIR)/$(APP_NAME).app
	open $(INSTALL_DIR)/$(APP_NAME).app

# Untick "Start at login" in Settings before this, or remove it later in
# System Settings → General → Login Items.
uninstall:
	-pkill -x $(APP_NAME)
	rm -rf $(INSTALL_DIR)/$(APP_NAME).app
	-tccutil reset Accessibility $(BUNDLE_ID)
	-defaults delete $(BUNDLE_ID)

clean:
	rm -rf .build build
