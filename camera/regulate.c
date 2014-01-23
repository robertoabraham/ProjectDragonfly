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

    int err;
    int sbig_type = NO_CAMERA;
    int info_mode = 0;
    int portnum;
    float exptime;
    int arg = 1;
    float setpoint;

    get_nondestructive_lock();

    if (argc < 2){
        error_exit("Usage: regulate setpoint\n");
    };
    sscanf(argv[arg++],"%f",&setpoint);

    CountCameras();
    if (ccd_ncam < 1){
	fprintf(stderr,"Found 0 cameras\n");
        return(1);
    }

    InitializeAllCameras();
    for (int i = 0; i < ccd_ncam; i++){
        err = SetActiveCamera(i);
        err = RegulateTemperature(setpoint);
    }
    DisconnectAllCameras();

    release_lock();

    return(0);

}

