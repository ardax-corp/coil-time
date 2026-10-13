# coil-time — pure Coil package (HostInvoke clocks from coil-lang).
#
#   make test  — coil harness (needs `coil` on PATH, archive 4.4+)
#   make clean

.PHONY: test coil-test clean

COIL ?= coil
# Extra module roots for `make test` (CI passes the coil-stdlib checkout).
COIL_ROOTS ?=

test:
	$(COIL) test $(COIL_ROOTS)

coil-test: test

clean:
	rm -f *.hyc
