# The classic core's host tests: make test (CC=cc by default).
CC ?= cc
CFLAGS = -std=c89 -pedantic -Wall -Wextra -Werror -O1 -g
CORE = ../core/json.c ../core/http.c ../core/query.c ../core/results.c ../core/config.c ../core/roman.c ../core/notetext.c

test: test_core
	./test_core

test_core: test_core.c vectors.h $(CORE) ../core/*.h
	$(CC) $(CFLAGS) -o $@ test_core.c $(CORE)

clean:
	rm -rf test_core test_core.dSYM

.PHONY: test clean
