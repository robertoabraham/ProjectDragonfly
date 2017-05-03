CC = gcc 
CFLAGS = -std=c99 -g
LFLAGS = -L /usr/lib -l sbigudrv -L /lib/x86_64-linux-gnu -l cfitsio
INCDIR = /usr/include

DEPS = camera.h
OBJ = expose.o regulate.o status.o camera.o setfilter.o usbcheck.o camera_server
PROGRAMS = expose regulate status setfilter usbcheck camera_server

%.o: %.c $(DEPS)
	$(CC) -c $(CFLAGS) -I${INCDIR} -o $@ $< 

all: expose regulate status setfilter camera_server

camera_server: camera_server.o camera.o
	$(CC) -o $@ $^ ${LFLAGS}

expose: expose.o camera.o
	$(CC) -o $@ $^ ${LFLAGS}

regulate: regulate.o camera.o
	$(CC) -o $@ $^ ${LFLAGS}

status: status.o camera.o
	$(CC) -o $@ $^ ${LFLAGS}

setfilter: setfilter.o camera.o
	$(CC) -o $@ $^ ${LFLAGS}

usbcheck: usbcheck.o camera.o
	$(CC) -o $@ $^ ${LFLAGS}

clean:
	rm -f *.o

install: $(PROGRAMS)
	mv $(PROGRAMS) /usr/local/bin
