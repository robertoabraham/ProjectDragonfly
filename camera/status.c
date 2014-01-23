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
    double setpoint;

    get_nondestructive_lock();

    CountCameras();
    if (ccd_ncam < 1){
        return(0);
    }

    InitializeAllCameras();
    for (int i = 0; i<ccd_ncam; i++)
    {
        SetActiveCamera(i);
        GetCameraTemperature();
        fprintf(stdout,"%d: T=%.1fC S=%.1fC A=%.1f [%.1f%%]    ",
                ActiveCamera(),
                (double)ccd_camera_info[ActiveCamera()].temperature,
                (double)ccd_camera_info[ActiveCamera()].setpoint,
                (double)ccd_camera_info[ActiveCamera()].ambientTemperature,
                (double)ccd_camera_info[ActiveCamera()].power);
    }
    DisconnectAllCameras();
    fprintf(stdout,"\n");

    release_lock();

    fflush(stdout);

    return(0);

}

