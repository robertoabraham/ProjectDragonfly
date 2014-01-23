CC = clang
CFLAGS = -std=c99 -g
FFLAGS = -framework SBIGUDrv 

MANAGER?=homebrew
ifeq ($(MANAGER),homebrew)
	LFLAGS = -L /usr/local/lib -l cfitsio
	INCDIR = /usr/local/include
else
	LFLAGS = -L /opt/local/lib -l cfitsio
	INCDIR = /opt/local/include
endif

DEPS = camera.h
OBJ = expose.o regulate.o status.o camera.o setfilter.o usbcheck.o camera_server
PROGRAMS = expose regulate status setfilter usbcheck camera_server

%.o: %.c $(DEPS)
	$(CC) -c $(CFLAGS) -I${INCDIR} -o $@ $< 

all: expose regulate status setfilter camera_server

camera_server: camera_server.o camera.o
	$(CC) -o $@ $^ $(FFLAGS) ${LFLAGS}

expose: expose.o camera.o
	$(CC) -o $@ $^ $(FFLAGS) ${LFLAGS}

regulate: regulate.o camera.o
	$(CC) -o $@ $^ $(FFLAGS) ${LFLAGS}

status: status.o camera.o
	$(CC) -o $@ $^ $(FFLAGS) ${LFLAGS}

setfilter: setfilter.o camera.o
	$(CC) -o $@ $^ $(FFLAGS) ${LFLAGS}

usbcheck: usbcheck.o camera.o
	$(CC) -o $@ $^ $(FFLAGS) ${LFLAGS}

clean:
	rm -f *.o

install: $(PROGRAMS)
	mv $(PROGRAMS) /usr/local/bin
