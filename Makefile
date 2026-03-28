PREFIX ?= /usr/local
BINARY_NAME = alkali
BUILD_DIR = .build/release

.PHONY: build install uninstall clean

build:
	swift build -c release --disable-sandbox

install: build
	@mkdir -p $(PREFIX)/bin
	@cp $(BUILD_DIR)/$(BINARY_NAME) $(PREFIX)/bin/$(BINARY_NAME)
	@echo "Installed $(BINARY_NAME) to $(PREFIX)/bin/$(BINARY_NAME)"

uninstall:
	@rm -f $(PREFIX)/bin/$(BINARY_NAME)
	@echo "Removed $(BINARY_NAME) from $(PREFIX)/bin"

clean:
	swift package clean
	@rm -rf .build
