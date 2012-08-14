
CPPFLAGS=-Wall -g -O3

e: e.cc e.h stringfuncs.h path.h
	g++ $(CPPFLAGS) e.cc -o e

