#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include "fitsio.h"
#include "camera.h"

#define error_exit(a)   fprintf(stderr, (a)); return(1)
#define MAX_STRING 256

#define usage "\n\
NAME\n\
expose --- obtain images from an SBIG camera array \n\
\n\
SYNOPSIS\n\
expose [options...] imageType exposureTime\n\
\n\
DESCRIPTION\n\
\"expose\" operates an array of SBIG CCD cameras. Up to four cameras can be controlled per computer.\n\
\n\
PARAMETERS\n\
imageType       - must be one of \"bias\", \"dark\", \"flat\" or \"light\".\n\
exposureTime    - integration time in seconds \n\
\n\
OPTIONS\n\
-v          # verbose mode \n\
-n Name      \n\
-r RA        \n\
-d Dec       \n\
-a Alt       \n\
-z Az        \n\
\n\
EXAMPLES\n\
expose flat 15 \n\
expose light 120 \n\
expose dark 10 \n\
\n\
BUGS\n\
None known\n\
\n\
FEATURES\n\
A lockfile is used to make sure we don't confuse the cameras by trying to start new integrations in the\n\
middle of active integrations, and to act as a simple IPC mechanism to share information between daemons\n\
that communicate with the cameras, such as temperature monitors, in a way that will work even as we\n\
take data with the cameras.\n\
\n\
If another program can set a write lock on the lockfile then the camera routine is not currently running.\n\
If another instance of the camera routine is started it will block until the first instance finishes.\n\
It should always be possible for other programs to read data from the lockfile. They should request write\n\
access to the lockfile even though they don't write data. This is because this will block if the camera\n\
program happens to be writing to the file at that exact moment, but then things will continue. The\n\
lockfile contains useful information about the current integration request.\n\
\n\
AUTHOR\n\
Bob Abraham:  abraham@astro.utoronto.ca\n\
\n\
LAST UPDATE\n\
April 2012\n\
"


void InterruptHandler(int sig)
{
    int phase=2;
    fprintf(stdout,"Integration terminated by user.\n");
    for (int cam_num = 0; cam_num <ccd_ncam; cam_num++)
    {
        CaptureImage(&phase,ccd_image_data[cam_num],ccd_type,0,FALSE,0,0,0,0);
        SBIGUnivDrvCommand(CC_CLOSE_DEVICE, NULL, NULL);
        SBIGUnivDrvCommand(CC_CLOSE_DRIVER, NULL, NULL);
    }
    release_lock();
    exit(EXIT_FAILURE);
}


int main(int argc, char *argv[]) {

    int arg=1;
    int sbig_type = NO_CAMERA;
    int info_mode = 0;
    int verbose = 0;
    char name[MAX_STRING] = "";
    char ra[MAX_STRING] = "";
    char dec[MAX_STRING] = "";
    char alt[MAX_STRING] = "";
    char az[MAX_STRING] = "";
    char imtype[8];
    int phase;
    float exptime;
    int err;

    /* Set an interrupt handler to trap Ctr-C nicely */
    if(signal(SIGINT, SIG_IGN) != SIG_IGN)
		signal(SIGINT, InterruptHandler);

    /*  set lockfile from the outset */
    get_lock();
    store_pid_in_lockfile();


    /* parse args */
    if (argc < 3) {
        error_exit(usage);
    };
    while (arg < argc - 2) 
    {
        switch (argv[arg++][1]) {
            case 'v':
                verbose = 1;
                SetVerbosity(verbose);
                break;
            case 'n':
                sscanf(argv[arg++], "%s", name);
                break;
             case 'r':
                sscanf(argv[arg++], "%s", ra);
                break;
             case 'd':
                sscanf(argv[arg++], "%s", dec);
                break;
             case 'a':
                sscanf(argv[arg++], "%s", alt);
                break;
             case 'z':
                sscanf(argv[arg++], "%s", az);
                break;
             default:
                error_exit(usage);
                break;
        }
    }
    sscanf(argv[arg++],"%s",imtype);
    sscanf(argv[arg++],"%f",&exptime);

    // Determine what kind of image to take 
    switch(value_from_imagetype_key(imtype)) {
        case DARK:   ccd_type=DARK;  if (verbose) printf("Taking dark frame.\n");  break;
        case LIGHT:  ccd_type=LIGHT; if (verbose) printf("Taking light frame.\n"); break;
        case BIAS:   ccd_type=BIAS;  if (verbose) printf("Taking bias frame.\n");  break;
        case FLAT:   ccd_type=FLAT;  if (verbose) printf("Taking flat frame.\n");  break;
        case BADKEY: fprintf(stderr,"Unknown image type %s\n",imtype); return(1); break;
    }
    fflush(stdout);

    CountCameras();
    if (ccd_ncam < 1){
	fprintf(stderr,"Found 0 cameras\n");
        return(1);
    }

    InitializeAllCameras();
    store_timestamped_note_in_lockfile("Started");
    store_directory_in_lockfile();
    char myline[128];
    sprintf(myline,"Exptime: %5.1f\n",exptime);
    store_note_in_lockfile(myline);


    // Start integrations going on each of the cameras one by one.
    for (int cam_num = 0; cam_num <ccd_ncam; cam_num++)
    {
        err = SetActiveCamera(cam_num);
        ccd_image_data[cam_num] = 
            (unsigned short *) malloc(ccd_image_width*ccd_image_height*sizeof(unsigned short));
        phase = 0;
        err = CaptureImage(&phase,ccd_image_data[cam_num],ccd_type,exptime,FALSE,0,0,0,0);
    }

    // Wait until the data is ready. I'm intentionally playing this safe by
    // making sure I wait at least 1s before trying to read out the data.
    // This is something I will have to look into if I ever use this for
    // fast focusing.
    int nsec = (int) exptime + 1;
    int count = 0;
    for (int i=0; i<=nsec;i++)
    {
        if(nsec > 3 && nsec < 10){ 
            load_bar(count++,nsec,3,30);
        }
        else if (nsec >  10 && nsec < 100){
            load_bar(count++,nsec,(int)(nsec/2),30);
        }
        else if (nsec >  100){
            load_bar(count++,nsec,(int)(nsec/3),30);
        }
        sleep(1);
    }

    // The cameras are ready to be read out. We once again cycle over each camera and 
    // save the data.
    
    for (int cam_num = 0; cam_num <ccd_ncam; cam_num++)
    {
        char infoline[128];
        phase = 1;
        err = SetActiveCamera(cam_num); 
        fflush(stderr);
        err = CaptureImage(&phase,ccd_image_data[cam_num],ccd_type,exptime,FALSE,0,0,0,0);

        // Print out some pixel values to let the user check data integrity
        if (verbose)
            printf("Some pixel values: %u %u %d\n",
                    *(ccd_image_data[cam_num] + 10000), 
                    *(ccd_image_data[cam_num] + 15000), 
                    *(ccd_image_data[cam_num]+20000)); 

        // Figure out what to call the new file
        char *newname;
        newname = (char *)malloc(MAX_STRING*sizeof(char));
        new_filename(ccd_serial_number,imtype,newname);    

        // Save as a FITS file
        GetCameraTemperature();
        double temperature = ccd_camera_info[ActiveCamera()].temperature;
        int filterNumber = 0;
        if (IsCameraAnST402ME())
            filterNumber = FilterWheelPosition();
        write_fits(newname, ccd_image_width, ccd_image_height, ccd_image_data[cam_num], 
                   exptime,imtype,temperature,filterNumber,ccd_serial_number, name,
                   ra,dec,alt,az);
        fprintf(stderr,"Saved %s \n",newname);
        sprintf(infoline,"Camera %d wrote: %s\n",cam_num,newname);
        store_note_in_lockfile(infoline);
        free(ccd_image_data[cam_num]);
        free(newname);

    }

    DisconnectAllCameras();
    release_lock();

    store_timestamped_note_in_lockfile("Completed");

    // Release the lock file
    release_lock();

    // Ring bell to wake up the astronomer
    if (verbose)
    	printf("Camera(s) opened and closed successfully.\n");
    putchar('\a'); putchar('\a'); putchar('\a');

    return(0);

}

