all: ohsc

ohsc: $(wildcard *.vala)
	valac -g --vapidir=. -o $@ --pkg webkit-1.0 --pkg json-glib-1.0 --pkg libsoup-2.4 --pkg posix $^
