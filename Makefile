APP := build/Cheet with Both Hands.app
DIST := build/Cheet-with-Both-Hands.zip

# Command Line Tools (without Xcode) ship Swift Testing, but SwiftPM leaves it off the framework
# and runtime search paths. Xcode toolchains don't have this directory, so they get no extra flags.
CLT_DEV := $(shell xcode-select -p)/Library/Developer
ifneq ($(wildcard $(CLT_DEV)/Frameworks/Testing.framework),)
TEST_FLAGS := -Xswiftc -F -Xswiftc $(CLT_DEV)/Frameworks \
              -Xlinker -rpath -Xlinker $(CLT_DEV)/Frameworks \
              -Xlinker -rpath -Xlinker $(CLT_DEV)/usr/lib
endif

.PHONY: app run test install dist clean

app:
	@scripts/build-app.sh

run: app
	@pkill -x CheetWithBothHands 2>/dev/null || true
	@open "$(APP)"

test:
	@swift test $(TEST_FLAGS) $(if $(FILTER),--filter $(FILTER))

install: app
	@rm -rf "/Applications/Cheet with Both Hands.app"
	@cp -R "$(APP)" /Applications/
	@echo "✓ Installed to /Applications"

# Universal (Apple silicon + Intel) build, zipped with ditto so the bundle's permissions and
# signature survive. This is what CI publishes.
dist:
	@UNIVERSAL=1 scripts/build-app.sh
	@rm -f "$(DIST)"
	@ditto -c -k --keepParent "$(APP)" "$(DIST)"
	@echo "✓ Packaged $(DIST)"

clean:
	@rm -rf .build build
