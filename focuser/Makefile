CC = clang
CFLAGS = -std=c99 -g
FFLAGS = 
MANAGER?=homebrew
ifeq ($(MANAGER),homebrew)
        LFLAGS = -L /usr/local/lib -l cfitsio
        INCDIR = /usr/local/include
else
        LFLAGS = -L /opt/local/lib -l cfitsio
        INCDIR = /opt/local/include
endif

DEPS = 
OBJ = robofocus.o
PROGRAMS = robofocus birger

%.o: %.c $(DEPS)
	$(CC) -c $(CFLAGS) -I${INCDIR} -o $@ $< 

all: robofocus birger

robofocus: robofocus.o 
	$(CC) -o $@ $^ $(FFLAGS) ${LFLAGS}

birger: birger.o 
	$(CC) -o $@ $^ $(FFLAGS) ${LFLAGS}

clean:
	rm -f *.o

install: $(PROGRAMS)
	mv $(PROGRAMS) /usr/local/bin
