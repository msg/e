
CPPFLAGS=-Wall -Wextra -O3
CXX=g++

e: e.cc e.h stringfuncs.h path.h
	$(CXX) $(CPPFLAGS) e.cc -o e

install:
	install -D -m0755 e $(DESTDIR)/usr/bin/e
	install -D -m0755 e.sh $(DESTDIR)/etc/profile.d/e.sh

clean:
	rm e
