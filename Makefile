APP := build/Cheet with Both Hands.app

.PHONY: app run test install clean

app:
	@scripts/build-app.sh

run: app
	@pkill -x CheetWithBothHands 2>/dev/null || true
	@open "$(APP)"

test:
	@swift test

install: app
	@rm -rf "/Applications/Cheet with Both Hands.app"
	@cp -R "$(APP)" /Applications/
	@echo "✓ Installed to /Applications"

clean:
	@rm -rf .build build
