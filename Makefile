# coil-time — native cdylib + package layout.
#
#   make / make native  — native/libtime.{so,dylib,dll}
#   make test           — cargo test in native/
#   make coil-test      — coil harness (needs `coil` on PATH)
#   make clean

.PHONY: all native test coil-test clean

COIL ?= coil

all: native

native:
	$(MAKE) -C native artifact

test:
	$(MAKE) -C native test

# Host grant is CLI-only. Runtime dload still needs a native sha256 pin.
# `trusted` on a dep skips that pin — this package pins the file `make` just built.
coil-test: native
	@set -eu; \
	  lib=; \
	  for f in native/libtime.so native/libtime.dylib native/libtime.dll native/time.dll; do \
	    if [ -f "$$f" ]; then lib=$$f; break; fi; \
	  done; \
	  if [ -z "$$lib" ]; then echo "make coil-test: missing native libtime" >&2; exit 1; fi; \
	  if command -v sha256sum >/dev/null 2>&1; then hash=$$(sha256sum "$$lib" | awk '{print $$1}'); \
	  else hash=$$(shasum -a 256 "$$lib" | awk '{print $$1}'); fi; \
	  printf '%s\n' '[[package]]' "name = 'time'" '[[package.native]]' "stem = 'time'" "sha256 = '$$hash'" > coil.lock; \
	  echo "pinned $$lib sha256=$$hash"; \
	  $(COIL) test --allow-dload time --ffi-search-path native

clean:
	$(MAKE) -C native clean
