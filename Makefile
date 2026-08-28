# coil-time — native cdylib + package layout.
#
#   make / make native  — native/libtime.{so,dylib,dll}
#   make test           — cargo test in native/
#   make clean

.PHONY: all native test clean

all: native

native:
	$(MAKE) -C native artifact

test:
	$(MAKE) -C native test

clean:
	$(MAKE) -C native clean
