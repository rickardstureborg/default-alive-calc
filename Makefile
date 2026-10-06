APP_NAME  := Default Alive Calculator
BUNDLE_ID := local.DefaultAliveCalculator
EXEC      := DefaultAliveCalculator
BUILT_APP := build/$(APP_NAME).app
INSTALLED := $(HOME)/Applications/$(APP_NAME).app

PORT      := 8765
PREVIEW   := http://127.0.0.1:$(PORT)/design/

.PHONY: all app test bundle snapshot install selftest preview preview-serve preview-shot preview-stop uninstall clean

# The whole loop: test, build, refresh the snapshot, swap the installed app, relaunch it.
all: test app

# Same minus tests, for pure UI tweaks.
app: bundle snapshot install

# The node half checks design/model.js (the browser preview's math) against the same
# presets spec as the Swift tests, so the preview can't drift from the app.
test:
	swift test
	node --test design/model.test.mjs

# SwiftPM builds the binary; the .app wrapper is just a folder with the binary and
# Info.plist, so assembling it by hand avoids needing an Xcode project.
bundle:
	swift build -c release --product $(EXEC)
	rm -rf "$(BUILT_APP)"
	mkdir -p "$(BUILT_APP)/Contents/MacOS"
	cp "$$(swift build -c release --show-bin-path)/$(EXEC)" "$(BUILT_APP)/Contents/MacOS/"
	cp Resources/Info.plist "$(BUILT_APP)/Contents/"
	codesign --force --sign - "$(BUILT_APP)"

# Every preset in design/presets.json through the real SwiftUI view, light | dark, into
# build/snapshot.png: the "app" columns of the preview gallery. Doesn't launch the app or
# touch saved input.
snapshot: bundle
	"$(BUILT_APP)/Contents/MacOS/$(EXEC)" --snapshot design/presets.json build/snapshot.png

# Inputs are written to UserDefaults on every keystroke, so killing the running copy loses nothing.
install:
	@pkill -x $(EXEC) || true
	@while pgrep -x $(EXEC) >/dev/null; do sleep 0.1; done
	mkdir -p "$(HOME)/Applications"
	rm -rf "$(INSTALLED)"
	cp -R "$(BUILT_APP)" "$(INSTALLED)"
	open "$(INSTALLED)"

# Browser mock of the app; the page reloads itself when design/ or the snapshot changes,
# so the server only needs starting once. Served (not file://) because ES modules and
# fetch() don't work from file URLs; served from the repo root so the page can reach
# build/snapshot.png. Bound to 127.0.0.1 only.
preview: preview-serve
	open "$(PREVIEW)"

preview-serve:
	@if ! lsof -ti tcp:$(PORT) -sTCP:LISTEN >/dev/null; then \
		nohup uv run --no-project --managed-python python -m http.server $(PORT) \
			--bind 127.0.0.1 --directory . >/dev/null 2>&1 & \
		while ! curl -s -o /dev/null $(PREVIEW); do sleep 0.1; done; \
	fi
	@echo "→ $(PREVIEW)"

# Headless screenshots of the preview: build/preview.png (whole page) and
# build/preview-live.png (just the live window), so Claude can look at a
# design without driving your browser. Light appearance; the gallery shows dark anyway.
preview-shot: preview-serve
	@mkdir -p build
	@node design/shot.mjs "$(PREVIEW)" build/preview.png
	@node design/shot.mjs "$(PREVIEW)" build/preview-live.png "#live-window"

preview-stop:
	@lsof -ti tcp:$(PORT) -sTCP:LISTEN | xargs kill 2>/dev/null || true

# Real key events through the app's own event queue (Tab/Return order + selection,
# Esc/C/⌘⌫ clearing) → build/selftest.txt. Opens a second, storage-free copy of the app
# for a couple of seconds; the installed one and its saved input are untouched.
selftest: bundle
	@rm -f build/selftest.txt
	@open -W -n "$(BUILT_APP)" --args --selftest "$(CURDIR)/build/selftest.txt"
	@cat build/selftest.txt
	@grep -q '^ALL PASS' build/selftest.txt

uninstall:
	@pkill -x $(EXEC) || true
	rm -rf "$(INSTALLED)"
	-defaults delete $(BUNDLE_ID)
	rm -rf "$(HOME)/Library/Saved Application State/$(BUNDLE_ID).savedState"

clean:
	rm -rf .build build
