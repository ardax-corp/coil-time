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
# Hash the file under native/ that `--ffi-search-path native` will load.
coil-test: native
	@lib=native/libtime.so; \
	  if [ -f native/libtime.dylib ]; then lib=native/libtime.dylib; fi; \
	  if [ -f native/libtime.dll ]; then lib=native/libtime.dll; fi; \
	  if command -v sha256sum >/dev/null 2>&1; then hash=$$(sha256sum "$$lib" | awk '{print $$1}'); \
	  else hash=$$(shasum -a 256 "$$lib" | awk '{print $$1}'); fi; \
	  printf '%s\n' '[[package]]' "name = 'time'" '[[package.native]]' "sha256 = '$$hash'" > coil.lock
	$(COIL) test --allow-dload time --ffi-search-path native

clean:
	$(MAKE) -C native clean
