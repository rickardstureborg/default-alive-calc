APP_NAME  := Default Alive Calculator
BUNDLE_ID := local.DefaultAliveCalculator
EXEC      := DefaultAliveCalculator
BUILT_APP := build/$(APP_NAME).app
INSTALLED := $(HOME)/Applications/$(APP_NAME).app

.PHONY: all app test bundle install snapshot uninstall clean

# The whole loop: test, build, swap the installed app, relaunch it.
all: test app

# Same minus tests, for pure UI tweaks.
app: bundle install

test:
	swift test

# SwiftPM builds the binary; the .app wrapper is just a folder with the binary and
# Info.plist, so assembling it by hand avoids needing an Xcode project.
bundle:
	swift build -c release --product $(EXEC)
	rm -rf "$(BUILT_APP)"
	mkdir -p "$(BUILT_APP)/Contents/MacOS"
	cp "$$(swift build -c release --show-bin-path)/$(EXEC)" "$(BUILT_APP)/Contents/MacOS/"
	cp Resources/Info.plist "$(BUILT_APP)/Contents/"
	codesign --force --sign - "$(BUILT_APP)"

# Inputs are written to UserDefaults on every keystroke, so killing the running copy loses nothing.
install:
	@pkill -x $(EXEC) || true
	@while pgrep -x $(EXEC) >/dev/null; do sleep 0.1; done
	mkdir -p "$(HOME)/Applications"
	rm -rf "$(INSTALLED)"
	cp -R "$(BUILT_APP)" "$(INSTALLED)"
	open "$(INSTALLED)"

# Every preset in design/presets.json through the real SwiftUI view, light | dark,
# into build/snapshot.png. Doesn't launch the app or touch saved input.
snapshot:
	swift build -c release --product $(EXEC)
	mkdir -p build
	"$$(swift build -c release --show-bin-path)/$(EXEC)" --snapshot design/presets.json build/snapshot.png
	@echo "→ build/snapshot.png"

uninstall:
	@pkill -x $(EXEC) || true
	rm -rf "$(INSTALLED)"
	-defaults delete $(BUNDLE_ID)
	rm -rf "$(HOME)/Library/Saved Application State/$(BUNDLE_ID).savedState"

clean:
	rm -rf .build build
