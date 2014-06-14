
all: test examples

DOCOPTLIB = libdocopt.a

DMDLINK = -Isource -L$(DOCOPTLIB)

DFLAGS = -debug

$(DOCOPTLIB): source/*.d
	dmd -lib -oflibdocopt.a source/*.d

test/test_docopt: $(DOCOPTLIB)
	dmd $(DFLAGS) test/test_docopt.d -oftest/test_docopt $(DMDLINK)

test: test/test_docopt
	dub test
	./test/test_docopt test/testcases.docopt

examples: arguments

arguments: $(DOCOPTLIB) examples/arguments/source/arguments.d
	dmd $(DFLAGS) examples/arguments/source/arguments.d -op $(DMDLINK)

clean:
	@rm -rf test/test_docopt test/test_docopt.o
	@rm -rf lib*a
	@rm -rf __test__library__
	@rm -rf arguments
	@find . -name "*.o" -exec rm {} \;

.PHONY: test
