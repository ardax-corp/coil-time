# coil-time — pure Coil package (HostInvoke clocks from coil-lang).
#
#   make test  — coil harness (needs `coil` on PATH, archive 4.4+)
#   make clean

.PHONY: test coil-test clean

COIL ?= coil

test:
	$(COIL) test

coil-test: test

clean:
	rm -f *.hyc
