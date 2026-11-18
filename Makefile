APP_NAME    = WinSwitch
BUNDLE_ID   = local.winswitch
CONFIG      = release
BIN         = .build/$(CONFIG)/$(APP_NAME)
APP         = build/$(APP_NAME).app
ICON        = build/AppIcon.icns
INSTALL_DIR = /Applications
# A stable signing identity keeps the Accessibility permission across rebuilds
# (ad-hoc signing would change the signature every build and silently drop it).
SIGN_ID    ?= Apple Development

.PHONY: build bundle run install uninstall clean

# Compile the executable.
build:
	swift build -c $(CONFIG)

$(ICON): Scripts/make-icon.swift
	rm -rf build/AppIcon.iconset
	swift Scripts/make-icon.swift build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o $(ICON)

# Wrap the binary into a signed .app bundle.
bundle: build $(ICON)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN) $(APP)/Contents/MacOS/$(APP_NAME)
	cp Info.plist $(APP)/Contents/Info.plist
	cp $(ICON) $(APP)/Contents/Resources/AppIcon.icns
	codesign --force --timestamp=none --sign "$(SIGN_ID)" $(APP)
	@echo "Built $(APP)"

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
