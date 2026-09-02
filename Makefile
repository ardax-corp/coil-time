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

# Host grant is CLI-only. `trusted = true` on [dependencies] time skips native sha256.
coil-test: native
	$(COIL) test --allow-dload time --ffi-search-path native

clean:
	$(MAKE) -C native clean
