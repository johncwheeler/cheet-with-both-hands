APP := build/Cheet with Both Hands.app

# Command Line Tools (without Xcode) ship Swift Testing, but SwiftPM leaves it off the framework
# and runtime search paths. Xcode toolchains don't have this directory, so they get no extra flags.
CLT_DEV := $(shell xcode-select -p)/Library/Developer
ifneq ($(wildcard $(CLT_DEV)/Frameworks/Testing.framework),)
TEST_FLAGS := -Xswiftc -F -Xswiftc $(CLT_DEV)/Frameworks \
              -Xlinker -rpath -Xlinker $(CLT_DEV)/Frameworks \
              -Xlinker -rpath -Xlinker $(CLT_DEV)/usr/lib
endif

.PHONY: app run test install clean

app:
	@scripts/build-app.sh

run: app
	@pkill -x CheetWithBothHands 2>/dev/null || true
	@open "$(APP)"

test:
	@swift test $(TEST_FLAGS)

install: app
	@rm -rf "/Applications/Cheet with Both Hands.app"
	@cp -R "$(APP)" /Applications/
	@echo "✓ Installed to /Applications"

clean:
	@rm -rf .build build
