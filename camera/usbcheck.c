#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <signal.h>
#include "camera.h"

#define error_exit(a)   fprintf(stderr, (a)); return(1)
#define MAX_STRING 256

int main(int argc, char *argv[]) {

    get_nondestructive_lock();
    PrintUSBNetworkInformation();
    release_lock();
    fflush(stdout);

    return(0);

}

