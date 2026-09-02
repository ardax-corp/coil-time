# Build libtime for coil-time FFI (Rust cdylib).

UNAME_S := $(shell uname -s 2>/dev/null)

ifdef MSYSTEM
  LIB := libtime.dll
else ifeq ($(OS),Windows_NT)
  LIB := time.dll
else ifeq ($(UNAME_S),Darwin)
  LIB := libtime.dylib
else
  LIB := libtime.so
endif

CARGO_TARGET := target/release/$(LIB)
CARGO_TARGET_ALT := target/release/time.dll

.PHONY: all artifact test clean print-artifact

all: artifact

artifact:
	cargo build --release
	@if [ -f "$(CARGO_TARGET)" ]; then cp "$(CARGO_TARGET)" "$(LIB)"; \
	elif [ -f "$(CARGO_TARGET_ALT)" ]; then cp "$(CARGO_TARGET_ALT)" "$(LIB)"; \
	else ls target/release/; exit 1; fi

test:
	cargo test

print-artifact:
	@echo $(CURDIR)/$(LIB)

clean:
	cargo clean
	rm -f libtime.so libtime.dylib libtime.dll time.dll
