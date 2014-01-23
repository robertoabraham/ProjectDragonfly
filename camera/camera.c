#include <glob.h>
#include <regex.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <fitsio.h>
#include <fcntl.h>
#include <time.h>

#include "camera.h"

/* Define global variables */
static OpenDeviceParams                odp;
static GetErrorStringParams            gesp;
static GetErrorStringResults           gesr;
static EstablishLinkParams             elp;
static EstablishLinkResults            elr;
static GetCCDInfoParams                gip;
static GetCCDInfoResults0              info_results_main;
static GetCCDInfoResults2              info_results_extended;
static QueryUSBResults                 qur;
static QueryCommandStatusParams        qcsp;
static QueryCommandStatusResults       qcsr;
static QueryTemperatureStatusParams    qtsp;
static QueryTemperatureStatusResults   qtsr;
static QueryTemperatureStatusResults2  qtsr2;
static SetTemperatureRegulationParams  strp;
static SetTemperatureRegulationParams2 strp2;
static CFWParams                       cfwp; 
static CFWResults                      cfwr;
static AOTipTiltParams                 attp;
static ActivateRelayParams             arp;
static StartExposureParams             sep;
static StartExposureParams2            sep2;
static EndExposureParams               eep;
static StartReadoutParams              srp;
static MiscellaneousControlParams      mcp;
static ReadoutLineParams               rlp;
static EndReadoutParams                erp;
static GetDriverInfoParams             gdip;
static GetDriverInfoResults0           gdir;
static SetDriverHandleParams           sdhp;
static GetDriverHandleResults          gdhr;

static int active_camera; // Index of currently active camera
static int verbosity = 0; // Print debug information?
static int err;
static struct flock fl;
static int fd;
static char camlockfile[] = "/var/tmp/sbig.lock";

char  *ccd_image_name;
char  *ccd_serial_number;
int    ccd_image_width;
int    ccd_image_height;
double ccd_image_gain;   
int    ccd_image_status;
int    ccd_phase;
CAMERA_TYPE ccd_camera_type;
int    ccd_type;
int    ccd_ncam;

t_camerainfo ccd_camera_info[4];
unsigned short *ccd_image_data[4];

static t_keyval imagetypelookuptable[] = {
        { "DARK", DARK },   { "dark", DARK },   { "Dark", DARK }, 
        { "LIGHT", LIGHT }, { "light", LIGHT }, { "Light", LIGHT }, 
        { "BIAS", BIAS },   { "bias", BIAS },   { "Bias", BIAS }, 
        { "FLAT", FLAT },   { "flat", FLAT },   { "Flat", FLAT } 
};
#define NIMAGETYPEKEYS (sizeof(imagetypelookuptable)/sizeof(t_keyval))

static t_keyval filternamelookuptable[] = {
        { "r", CFWP_1 },   { "R", CFWP_1 },   { "red",   CFWP_1 }, { "1",  CFWP_1 }, 
        { "g", CFWP_2 },   { "G", CFWP_2 },   { "green", CFWP_2 }, { "2",  CFWP_2 },
        { "b", CFWP_3 },   { "B", CFWP_3 },   { "blue",  CFWP_3 }, { "3",  CFWP_3 },
        { "c", CFWP_4},    { "C", CFWP_4 },   { "clear", CFWP_4 }, { "4",  CFWP_4 }
};
#define NFILTERNAMEKEYS (sizeof(filternamelookuptable)/sizeof(t_keyval))





/* Define functions */

int InitializeCamera(int camnum){

    int info_mode = 0;
    SBIG_DEVICE_TYPE usb;

    switch (camnum) {
	case 0:
	    usb = DEV_USB1;
	    break;
	case 1:
	    usb = DEV_USB2;
	    break;
	case 2:
	    usb = DEV_USB3;
	    break;
	case 3:
	    usb = DEV_USB4;
	    break;
	default:
	    fprintf(stderr,"Cannot assign camera.");
	    return(1);
	    break;
    }


    if (verbosity)
	fprintf(stdout,"Initializing camera %d\n",camnum);

    // Load driver
    err = SBIGUnivDrvCommand(CC_OPEN_DRIVER, NULL, NULL);
    check_sbig_error(err,"Error opening camera driver\n");

    // Open the device
    odp.deviceType = usb;
    err = SBIGUnivDrvCommand(CC_OPEN_DEVICE, &odp, NULL);
    check_sbig_error(err,"Error opening device\n");

    // Connect to the device
    elp.sbigUseOnly = 0;
    err = SBIGUnivDrvCommand(CC_ESTABLISH_LINK, &elp, &elr);
    check_sbig_error(err,"Link to camera could not be established\n");

    // Get handle for the device
    err = SBIGUnivDrvCommand(CC_GET_DRIVER_HANDLE, NULL, &gdhr);
    check_sbig_error(err,"Could not get driver handle\n");

    // Get camera information
    gip.request = CCD_INFO_IMAGING;
    err = SBIGUnivDrvCommand(CC_GET_CCD_INFO, &gip, &info_results_main);
    check_sbig_error(err,"Camera information could not be determined\n");

    // Get camera serial number
    gip.request = CCD_INFO_EXTENDED;
    err = SBIGUnivDrvCommand(CC_GET_CCD_INFO, &gip, &info_results_extended);
    check_sbig_error(err,"Extended camera information could not be determined\n");

    // Store camera info
    strcpy(ccd_camera_info[camnum].name,info_results_main.name);
    strcpy(ccd_camera_info[camnum].serial_number,info_results_extended.serialNumber);
    ccd_camera_info[camnum].camera_type = info_results_main.cameraType;
    ccd_camera_info[camnum].width = info_results_main.readoutInfo[info_mode].width;
    ccd_camera_info[camnum].height = info_results_main.readoutInfo[info_mode].height;
    ccd_camera_info[camnum].gain = info_results_main.readoutInfo[info_mode].gain;
    ccd_camera_info[camnum].handle  = gdhr.handle;

    // Get camera status
    err=GetCameraStatus(&ccd_image_status);
    check_sbig_error(err,"Unable to get camera status\n");
 
    switch (ccd_image_status) {
	case IDLE:
	    if (verbosity) printf("Camera %d is idle.\n",camnum);
	    break;
	case INTEGRATING:
	    if (verbosity) printf("Camera %d is integrating.\n",camnum);
	    break;
	case COMPLETE:
	    if (verbosity) printf("Exposure %d is complete.\n",camnum);
	    break;
	default:
	    fprintf(stderr,"Camera status is indeterminate.\n");
	    return(1); 
	    break;
    }

    // Free the handle. This allows access to other cameras. If we're
    // on the last camera don't free the handle, as no new handle can
    // be assigned... we're at the limit of 4 cameras. Here is how
    // the procedure is explained in the SBIG Universal Driver documentation: 
    //
    // "Each time you call Set Driver Handle with INVALID_HANDLE_VALUE 
    // you are allowing access to an additional camera up to a maximum 
    // of four cameras."

    if (camnum < 3) {
        sdhp.handle = INVALID_HANDLE_VALUE;
        err = SBIGUnivDrvCommand(CC_SET_DRIVER_HANDLE,&sdhp, NULL);

        char errstring[128];
        sprintf(errstring,"Unable to free handle after accessing camera %d\n",camnum);
        check_sbig_error(err,errstring);
    }

    return(0);

}


int CountCameras()
{
    // Load driver
    err = SBIGUnivDrvCommand(CC_OPEN_DRIVER, NULL, NULL);
    if (err != CE_NO_ERROR)
    {
        fprintf(stderr,"Error opening camera driver\n");
        return(1);
    }

    // Query the USB bus to figure out how many cameras are hooked up.
    err = SBIGUnivDrvCommand(CC_QUERY_USB, NULL, &qur);
    if (err != CE_NO_ERROR)
    {
        fprintf(stderr,"Error querying USB bus\n");
        return(1);
    }

    // Close driver
    err = SBIGUnivDrvCommand(CC_CLOSE_DRIVER, NULL, NULL);
    if ( err != CE_NO_ERROR ) 
    {
        fprintf (stderr, "SBIG close driver error\n");
        return(1);
    }

    ccd_ncam = qur.camerasFound;

    return(0);

}


int  PrintUSBNetworkInformation()
{
    // Load driver
    err = SBIGUnivDrvCommand(CC_OPEN_DRIVER, NULL, NULL);
    if (err != CE_NO_ERROR)
    {
        fprintf(stderr,"Error opening camera driver\n");
        return(1);
    }

    // Query the USB bus to figure out how many cameras are hooked up.
    err = SBIGUnivDrvCommand(CC_QUERY_USB, NULL, &qur);
    if (err != CE_NO_ERROR)
    {
        fprintf(stderr,"Error querying USB bus\n");
        return(1);
    }

    fprintf(stdout,"Found %d cameras\n",qur.camerasFound);
    for(int i=0; i<qur.camerasFound; i++){
        switch(i)
        {
            case 0:
                fprintf(stdout,"USB1: ");
                break;
            case 1:
                fprintf(stdout,"USB2: ");
                break;
            case 2:
                fprintf(stdout,"USB3: ");
                break;
            case 3:
                fprintf(stdout,"USB4: ");
                break;
            default:
                fprintf(stdout,"Error: More than 4 cameras found.\n");
                return(1);
        }
        fprintf(stdout,"id = %-9s name = %s \n",qur.usbInfo[i].serialNumber,qur.usbInfo[i].name);

    }

    // Close driver
    err = SBIGUnivDrvCommand(CC_CLOSE_DRIVER, NULL, NULL);
    if ( err != CE_NO_ERROR ) 
    {
        fprintf (stderr, "SBIG close driver error\n");
        return(1);
    }

    return(0);

}


int InitializeAllCameras()
{
    for (int i= 0; i < ccd_ncam; i++){
        err = InitializeCamera(i);
        check_sbig_error(err,"Error initializing camera\n");
    }
    return(0);
}


int DisconnectAllCameras()
{
    for (int i=0;i<ccd_ncam;i++)
    {
        err = SetActiveCamera(i);
    
        err = SBIGUnivDrvCommand(CC_CLOSE_DEVICE, NULL, NULL);
        if (err != CE_NO_ERROR )
        {
            fprintf (stderr, "SBIG close device error\n");
        }
       
        err = SBIGUnivDrvCommand(CC_CLOSE_DRIVER, NULL, NULL);
        if ( err != CE_NO_ERROR ) 
        {
            fprintf (stderr, "SBIG close driver error\n");
        } 
    }

    return(0); 
}


int SetActiveCamera(int camnum) {
    active_camera = camnum;
    ccd_image_name = ccd_camera_info[camnum].name;
    ccd_serial_number = ccd_camera_info[camnum].serial_number;
    ccd_camera_type = ccd_camera_info[camnum].camera_type;
    ccd_image_width = ccd_camera_info[camnum].width;
    ccd_image_height = ccd_camera_info[camnum].height;
    ccd_image_gain= ccd_camera_info[camnum].gain;
    sdhp.handle = ccd_camera_info[camnum].handle;

    err = SBIGUnivDrvCommand(CC_SET_DRIVER_HANDLE,&sdhp, NULL);
    if (verbosity)
        fprintf(stderr,"Activating camera with %d x %d format\n",ccd_image_width,ccd_image_height);
    check_sbig_error(err,"Unable to get handle to camera\n");
    return(0);
}

int ActiveCamera()
{
    return (active_camera);
}


int PrintCameraInformation() 
{
    printf("Serial Number: %s\n",ccd_camera_info[active_camera].serial_number);
    printf("Width:         %d\n",ccd_camera_info[active_camera].width);
    printf("Height:        %d\n",ccd_camera_info[active_camera].height);
    printf("Gain BCD:      %g\n",ccd_camera_info[active_camera].gain);
    return(0);
}


int RegulateTemperature(double sp) 
{
    ccd_camera_info[active_camera].setpoint=sp;
    strp2.ccdSetpoint = sp;
    strp2.regulation = 1;
    err = SBIGUnivDrvCommand(CC_SET_TEMPERATURE_REGULATION2,&strp2, NULL);
    check_sbig_error(err,"Unable to regulate camera\n");
    ccd_camera_info[active_camera].setpoint = sp;
    return(0);
}


int DisableTemperatureRegulation() 
{
    strp2.regulation = 0;
    err = SBIGUnivDrvCommand(CC_SET_TEMPERATURE_REGULATION2,&strp2, NULL);
    check_sbig_error(err,"Unable to disable temperature regulation\n");
    return(0);
}


int GetCameraTemperature()
{
    qtsp.request=2;
    err = SBIGUnivDrvCommand(CC_QUERY_TEMPERATURE_STATUS,&qtsp,&qtsr2);
    check_sbig_error(err,"Unable to get temperature information\n");
    ccd_camera_info[active_camera].power = qtsr2.imagingCCDPower;
    ccd_camera_info[active_camera].temperature = qtsr2.imagingCCDTemperature;
    ccd_camera_info[active_camera].ambientTemperature = qtsr2.ambientTemperature;
    ccd_camera_info[active_camera].setpoint = qtsr2.ccdSetpoint;
    return(0);
}


/* Inquire about the exposure status of the camera */
/* Note use of shift >> 2 bits to the right  to recover image status */
/* Sets internal ccd_track_status and ccd_image_status */
/* Returns these values to the calling routine */

int GetCameraStatus(int *image_status)
{
    ccd_image_status = IDLE;
    qcsp.command = CC_START_EXPOSURE;
    err = SBIGUnivDrvCommand(CC_QUERY_COMMAND_STATUS, &qcsp, &qcsr);
    check_sbig_error(err,"Unable to determine camera status.\n");

    switch ( qcsr.status&3 )
    {
	case CS_IDLE:
	    ccd_image_status = IDLE;  
	    break;

	case CS_IN_PROGRESS:
	    ccd_image_status = INTEGRATING;
	    break;

	case CS_INTEGRATING:
	    ccd_image_status = INTEGRATING;
	    break;

	case CS_INTEGRATION_COMPLETE:
	    ccd_image_status = COMPLETE;
	    break;
    }

    *image_status = ccd_image_status;
    return(0);
}


/***************************************************************/
/*                                                             */
/* CaptureImage()                                              */
/*                                                             */
/* Acquire an image frame                                      */
/* Image capture functions for external use                    */
/* Returns 1 on success and 0 on failure                       */
/* May send messages to stderr                                 */
/* Images are always saved as a file on disk                   */
/* Most recent image is always available in allocated storage  */
/*                                                             */
/* Reads these  parameters as needed:                          */
/*   phase     0 start exposure                                */
/*             1 readout if ready                              */
/*             2 interrupt and reset                           */
/*   frame     0 dark                                          */
/*             1 light                                         */
/*             2 bias                                          */
/*             3 flat                                          */
/*   exposure  time in seconds                                 */
/*   data      malloc'd image storage                          */
/*   subarea   TRUE or FALSE for subarea extraction            */
/*   x         initial x for subarea                           */
/*   y         initial y for subarea                           */
/*   width     width of subarea                                */
/*   height    height of subarea                               */
/*                                                             */
/*   The return value of phase indicates whether the image     */
/*   was read:                                                 */
/*                                                             */
/*   phase     0 exposure not started                          */
/*             1 exposure in progress                          */
/*             2 exposure complete                             */
/*                                                             */
/* Usage:                                                      */
/*   Make the first call with phase = 0 to start an exposure   */
/*   Make repeated calls with phase = 1 to ask for a readout   */
/*   User may delay asking for phase 1 or poll                 */
/*   Make one call with phase = 2 to interrupt an exposure     */
/*   Return value of phase indicates whether image was read    */
/*   Function will set phase = 2 when the exposure is done     */
/*   A minimum of two calls are required to capture an image   */
/*                                                             */
/***************************************************************/

int CaptureImage(int *phase,  unsigned short *data,
        int frame, double exposure, int subarea, 
        int x, int y, int width, int height)
{ 
    int i;

    ccd_phase = *phase;

    if ( ccd_phase == 2 )
    {

        /* End an exposure without readout */

        eep.ccd = CCD_IMAGING;
        mcp.fanEnable = TRUE;           /* Fan on */
        mcp.shutterCommand = 2;         /* Shutter closed */
        mcp.ledState = 0;               /* LED off */
        err=SBIGUnivDrvCommand(CC_MISCELLANEOUS_CONTROL, &mcp, NULL);
        err=SBIGUnivDrvCommand(CC_END_EXPOSURE, &eep, NULL);
        ccd_phase = 0;
        *phase = ccd_phase;
        if (err != CE_NO_ERROR)  
        {
            fprintf(stderr,"Error ending image exposure for camera %d\n",active_camera);
            return(1);
        }
        return(0);
    }

    if ( ccd_phase == 0 )
    { 

        /* Send start request to the camera */

        sep2.ccd = CCD_IMAGING;
        sep2.readoutMode = 0;
        sep2.abgState = ABG_LOW7;
        if ( ( frame == LIGHT ) | (frame == FLAT) )
        {  
            /* Shutter open */
            sep2.openShutter =  SC_OPEN_SHUTTER;
        }
        else if ( ( frame == DARK ) | (frame == BIAS ) )
        {
            /* Shutter closed */
            sep2.openShutter =  SC_CLOSE_SHUTTER;
        }
        else
        {
            fprintf(stderr,"Unknown frame type requested in CaptureImage for camera %d\n",active_camera);
            return(1);
        }
        sep2.exposureTime = (int)(100.0*exposure + 0.5);
        sep2.top = 0;
        sep2.left = 0;
        sep2.height = ccd_image_height;
        sep2.width = ccd_image_width;
        if (verbosity) fprintf(stderr,"Calling CC_START_EXPOSURE2\n");
        err=SBIGUnivDrvCommand(CC_START_EXPOSURE2, &sep2, NULL);   
        if (verbosity) fprintf(stderr,"Finished calling CC_START_EXPOSURE2\n");
        check_sbig_error(err,"Request to start camera exposure ignored\n");
        if (verbosity)
            fprintf(stderr,"Exposure started on camera %d\n",active_camera);

        /* Return indicating succesful start and  exposure in progress */

        ccd_phase = 1;
        *phase = ccd_phase;
        return(0);
    }   

    if ( ccd_phase != 1 )
    {
        /* We have already handled all allowed values except 1 */
        /* Reset phase to 0.  This permits recursive calls */
        ccd_phase = 0;
        *phase = ccd_phase;
        return(0) ;
    }

    /* Are we done yet? */
    /* If so, read it, if not reset phase and return */

    GetCameraStatus(&ccd_image_status);

    if ( ccd_image_status != COMPLETE )
    {
        /* The exposure is still underway */
        fprintf(stderr,"Exposure is already in progress on camera %d.\n",active_camera);
        ccd_phase = 1;
        *phase = ccd_phase;
        return(0);
    }  

    /* Test for subarea request */
    /* If not subarea, then default to driver's values for ccd dimensions */
    /* If subarea, then check validity and clamp to allowed bounds */

    if (subarea == FALSE)
    {
        x = 0;
        y = 0;
        width = ccd_image_width;
        height = ccd_image_height;
    }  
    else 
    {
        if (x < 0)
        {
            x = 0;
        }
        if (y < 0)
        {
            y = 0;
        }
        if (x > ccd_image_width  )
        {
            x = ccd_image_width;
        }
        if (y > ccd_image_height )
        {
            y = ccd_image_height;
        }
    }          

    /* Flush the buffers */
    /* This probably isn't necessary.  It's a carryover from earlier versions. */

    fflush(stdout);
    fflush(stderr);
    sync();

    /* End the exposure */

    eep.ccd = CCD_IMAGING;
    srp.ccd = CCD_IMAGING;
    rlp.ccd = CCD_IMAGING;
    erp.ccd = CCD_IMAGING;

    err=SBIGUnivDrvCommand(CC_END_EXPOSURE, &eep, NULL);
    if ( err != CE_NO_ERROR ) 
    {
        return(1);
    } 

    /* Prepare to read the image */

    sync();
    fflush(stdout);

    /* Read it */

    if (verbosity)
        fprintf(stderr,"Reading out camera %d... ",active_camera);
    srp.readoutMode =  0;
    srp.top = y;
    srp.left = x;
    srp.width = width;
    srp.height = height; 

    if (verbosity)
        fprintf(stderr,"Sending CC_START_READOUT to camera %d... ",active_camera);
    err = SBIGUnivDrvCommand(CC_START_READOUT, &srp, NULL);
    check_sbig_error(err,"Error reading out device\n");

    for (i = 0; i < srp.height; ++i) 
    {
        rlp.readoutMode = 0;
        rlp.pixelStart = x;
        rlp.pixelLength = width;
        //if (verbosity)
        //    fprintf(stderr,"Sending CC_READOUT_LINE line %d/%d to camera %d\n",i+1,srp.height,active_camera);
        err = SBIGUnivDrvCommand(CC_READOUT_LINE, &rlp, data + i*width);
        if (err != CE_NO_ERROR) 
        {
            fprintf(stderr,"Unable to read image data from camera %d\n",active_camera);
            ccd_phase = 0;
            *phase = ccd_phase;
            return(1);
        }
    }
    fprintf(stderr,"Readout successful on camera %d\n",active_camera);

    /* Successful readout. Send the End Readout command to the camera. */
    err = SBIGUnivDrvCommand(CC_END_READOUT, &erp, NULL);
    if (err != CE_NO_ERROR) 
    {
        fprintf(stderr,"Unable to end readout from camera %d\n",active_camera);
        ccd_phase = 2;
        *phase = ccd_phase;
        return(1);
    }


    /* Indicate that a new image is available */
    if (verbosity)
        fprintf(stderr,"finished\n");
    ccd_phase = 2;
    *phase = ccd_phase;  
    return(0);
}



/* FITS routines                               */
/*                                             */
/* Write a FITS primary array with a 2-D image */
/*   and a header with keywords                */
/*                                             */             

void write_fits(char *filename, int w, int h, unsigned short *data, 
	double obs_duration, 
	char*  obs_type, 
	double obs_temperature,
    int    obs_filterNumber,
    char*  serial_number,
    char*  name,
    char*  ra,
    char*  dec,
    char*  alt,
    char * az
    )
{
    fitsfile *fptr;       /* pointer to the FITS file, defined in fitsio.h */
    int status;
    long  fpixel, nelements;

    /* Initialize FITS image parameters */

    int bitpix   =  USHORT_IMG;       /* 16-bit unsigned short pixel values */
    long naxis    =   2;              /* 2-dimensional image                */    
    long naxes[2] = { 256,256 };      /* default image 256 wide by 256 rows */

    /* Set the actual width and height of the image */

    naxes[0] = w;
    naxes[1] = h;

    /* Delete old FITS file if it already exists */  

    remove(filename); 

    /* Must initialize status before calling fitsio routines */           

    status = 0;  

    /* Create a new FITS file and show error message if one occurs */

    if (fits_create_file(&fptr, filename, &status)) 
	show_cfitsio_error( status );           

    /* Write the required keywords for the primary array image.       */
    /* Since bitpix = USHORT_IMG, this will cause cfitsio to create   */
    /* a FITS image with BITPIX = 16 (signed short integers) with     */
    /* BSCALE = 1.0 and BZERO = 32768.  This is the convention that   */
    /* FITS uses to store unsigned integers.  Note that the BSCALE    */
    /* and BZERO keywords will be automatically written by cfitsio    */
    /* in this case.                                                */

    if ( fits_create_img(fptr,  bitpix, naxis, naxes, &status) )
	show_cfitsio_error( status );          

    fpixel = 1;                               /* first pixel to write      */
    nelements = naxes[0] * naxes[1];          /* number of pixels to write */

    /* Write the array of unsigned integers to the FITS file */

    if ( fits_write_img(fptr, TUSHORT, fpixel, nelements, data, &status) )
	show_cfitsio_error( status );

    /* Write optional keywords to the header */

    if ( fits_update_key_dbl(fptr, "EXPTIME", obs_duration, -3,
		"exposure time (seconds)", &status) )
	show_cfitsio_error( status );

    if ( fits_update_key_dbl(fptr, "TEMPERAT", obs_temperature, -3,
		"temperature (C)", &status) )
	show_cfitsio_error( status );

    if ( fits_update_key_str(fptr, "IMAGETYP", 
		obs_type, "image type", &status) )
	show_cfitsio_error( status );       

    if ( fits_update_key(fptr, TSHORT, "FILTNUM", &obs_filterNumber, NULL, &status))
        show_cfitsio_error( status );       

    if ( fits_write_date(fptr, &status) )
	show_cfitsio_error( status );       

    if ( fits_update_key_str(fptr, "SERIALNO", 
		serial_number, "serial number", &status) )
	show_cfitsio_error( status ); 

    if ( fits_update_key_str(fptr, "TARGET", 
		name, "target name", &status) )
	show_cfitsio_error( status );  

    if ( fits_update_key_str(fptr, "RA", 
		ra, "right ascension", &status) )
	show_cfitsio_error( status );  

    if ( fits_update_key_str(fptr, "DEC", 
		dec, "declination", &status) )
	show_cfitsio_error( status );  

    if ( fits_update_key_str(fptr, "EPOCH", 
		"JNOW", "epoch of coordinates", &status) )
	show_cfitsio_error( status );  

    if ( fits_update_key_str(fptr, "OBJCTRA", 
		ra, "right ascension", &status) )
	show_cfitsio_error( status );  

    if ( fits_update_key_str(fptr, "OBJCTDEC", 
		dec, "declination", &status) )
	show_cfitsio_error( status );  

    if ( fits_update_key_dbl(fptr, "ALTITUDE", atof(alt), -4,
		"Altitude (deg)", &status) )
	show_cfitsio_error( status );

    if ( fits_update_key_dbl(fptr, "AZIMUTH", atof(az), -4,
		"Azimuth (deg)", &status) )
	show_cfitsio_error( status );

    /* Close the file */             

    if ( fits_close_file(fptr, &status) )              
	show_cfitsio_error( status );           

    return;
}


/* Print cfitsio error report */

void show_cfitsio_error(int status)
{
    if (status)
    {
	fits_report_error(stderr, status); 
    }
    return;
}  


/* Check for error and print error message */
int check_sbig_error(int err, char *msg)
{
    if (err != CE_NO_ERROR)
    {
        fprintf(stderr,"%s",msg);
        return(1);
    }
    return(0);
}


/* Utility routine */
int value_from_imagetype_key(char *key)
{
    int i;
    for (i=0; i < NIMAGETYPEKEYS; i++) {
	t_keyval *sym = imagetypelookuptable + i;
	if (strcmp(sym->key, key) == 0)
	    return sym->val;
    }
    return BADKEY;
}

int value_from_filtername_key(char *key)
{
    int i;
    for (i=0; i < NFILTERNAMEKEYS; i++) {
	t_keyval *sym = filternamelookuptable + i;
	if (strcmp(sym->key, key) == 0)
	    return sym->val;
    }
    return BADKEY;
}

/* Display a progress bar                               */
/* Process has done i out of n rounds,                  */
/* and we want a bar of width w and resolution r.       */
void load_bar(int x, int n, int r, int w)
{
    // Only update r times.
    if ( x % (n/r) != 0 ) return;

    // Calculuate the ratio of complete-to-incomplete.
    float ratio = x/(float)n;
    int   c     = ratio * w;

    // Show the percentage complete.
    printf("%3d%% [", (int)(ratio*100) );

    // Show the load bar.
    for (int x=0; x<c; x++)
	printf("=");

    for (int x=c; x<w; x++)
	printf(" ");

    // ANSI Control codes to go back to the
    // previous line and clear it.
    printf("]\n\033[F\033[J");
}


int new_filename(char *serial_number, char *image_type, char *filename) 
{
    char scratch[256];

    char *gfilename;
    int max_filenumber = 0;
    glob_t glob_results;
    char p[MAX_SUB_EXPR_LEN];             /* For string manipulation                 */

    // Step 1. Glob directory
    //fprintf(stderr,"Globbing directory.\n");
    glob("*.fits", GLOB_NOMAGIC, NULL, &glob_results);
    //fprintf(stderr,"Found %d files.\n", (int)glob_results.gl_pathc);

    // Step 3. Use a regexp to turn each filename into an integer.
    if ( (int)glob_results.gl_pathc > 0) {
	char *aStrRegex;                      // Pointer to the string holding the regex 
	regex_t aCmpRegex;                    // Pointer to our compiled regex       
	char outMsgBuf[MAX_ERR_STR_LEN];      // Holds error messages from regerror()   
	char **aLineToMatch;                  // Holds each line that we wish to match   //
	regmatch_t pMatch[MAX_SUB_EXPR_CNT];  // Hold partial matches.                   //
	int result;                           // Return from regcomp() and regexec() 
        // Define the regexp
	strcat(scratch,"(");
        strcat(scratch,serial_number);
	strcat(scratch,"_)(.*)(_.*fits)+");
	aStrRegex = scratch;
	// Compile the regexp
	if( (result = regcomp(&aCmpRegex, aStrRegex, REG_EXTENDED)) ) {
	    printf("Error compiling regex(%d).\n", result);
	    regerror(result, &aCmpRegex, outMsgBuf, sizeof(outMsgBuf));
	    printf("Error msg: %s\n", outMsgBuf);
	    exit(1);
	};
	// Apply the regexp
	for(aLineToMatch=glob_results.gl_pathv; *aLineToMatch != NULL; aLineToMatch++) {
	    if( !(result = regexec(&aCmpRegex, *aLineToMatch, MAX_SUB_EXPR_CNT, pMatch, 0))) {
		int this_filenumber;
		int fieldnum=2;
		//fprintf(stderr,"Matched! %s...\n",*aLineToMatch);
		strncpy(p, &((*aLineToMatch)[pMatch[fieldnum].rm_so]), pMatch[fieldnum].rm_eo-pMatch[fieldnum].rm_so);
		p[pMatch[fieldnum].rm_eo-pMatch[fieldnum].rm_so] = '\0';
		this_filenumber = atoi(p);
		//fprintf(stderr,"---> %d\n",this_filenumber);
		if (this_filenumber > max_filenumber){
		    max_filenumber = this_filenumber;
		}
	    }
	}
    }

    //fprintf(stderr,"Max filenumber: %d\n",max_filenumber); 
    strcat(filename,serial_number);
    strcat(filename,"_");
    int bufsize=10;
    char buffer[bufsize];
    snprintf(buffer, bufsize, "%d", ++max_filenumber);
    strcat(filename,buffer);
    strcat(filename,"_");
    strcat(filename,image_type);
    strcat(filename,".fits");

    // Clean up
    globfree(&glob_results);

    return(0);

}



// Call this and set the verbosity to 1 if you want to see a lot of messages
void SetVerbosity(int v)
{
    verbosity = v;
}


int IsCameraAnST402ME()
{
    if (ccd_camera_type == ST402_CAMERA)
        return(1);
    else
        return(0);
}

int IsCameraAnSTF8300()
{
    if (ccd_camera_type == STF8300_CAMERA)
        return(1);
    else
        return(0);
}

int FilterWheelPosition() 
{
    cfwp.cfwModel = CFWSEL_CFW402;
    cfwp.cfwCommand = CFWC_QUERY;
    err= SBIGUnivDrvCommand(CC_CFW, &cfwp, &cfwr); 
    return (cfwr.cfwPosition);
}


int FilterWheelStatus()
{
    cfwp.cfwModel = CFWSEL_CFW402;
    cfwp.cfwCommand = CFWC_QUERY;
    err= SBIGUnivDrvCommand(CC_CFW, &cfwp, &cfwr); 
    return (cfwr.cfwStatus);
}


int NumberOfFilters() 
{
    cfwp.cfwModel = CFWSEL_CFW402;
    cfwp.cfwCommand = CFWC_GET_INFO;
    err= SBIGUnivDrvCommand(CC_CFW, &cfwp, &cfwr); 
    return((int)cfwr.cfwResult2);
}

int SetFilter(CFW_POSITION pos) 
{
    cfwp.cfwModel = CFWSEL_CFW402;
    cfwp.cfwCommand = CFWC_GOTO;
    cfwp.cfwParam1 = pos;
    // R = CFWP_1, G = CFWP_2, B = CFWP_3, Clear = CFWP_4
    err= SBIGUnivDrvCommand(CC_CFW, &cfwp, &cfwr); 
    return(err);
}

int get_lock()
{
    fl.l_type = F_WRLCK;
    fl.l_whence = SEEK_SET;
    fl.l_start = 0;
    fl.l_len = 0;
    fl.l_pid = getpid();
    if ((fd = open(camlockfile, O_RDWR|O_CREAT|O_TRUNC,0644)) == -1) {
        fprintf(stderr,"Error opening lockfile\n");
        exit(1);
    }
    if (fcntl(fd, F_SETLKW, &fl) == -1) {
        fprintf(stderr,"Error locking the lockfile\n");
        exit(1);
    }
    return(0);
}

int get_nondestructive_lock()
{
    fl.l_type = F_WRLCK;
    fl.l_whence = SEEK_SET;
    fl.l_start = 0;
    fl.l_len = 0;
    fl.l_pid = getpid();
    if ((fd = open(camlockfile, O_RDWR|O_CREAT,0644)) == -1) {
        fprintf(stderr,"Error opening lockfile\n");
        exit(1);
    }
    if (fcntl(fd, F_SETLKW, &fl) == -1) {
        fprintf(stderr,"Error locking the lockfile\n");
        exit(1);
    }
    return(0);
}


int release_lock()
{
    fl.l_type = F_UNLCK;
    if (fcntl(fd, F_SETLK, &fl) == -1) {
        fprintf(stderr,"Error unlocking the lockfile.\n");
        exit(1);
    }
    return(0);
}

void store_pid_in_lockfile()
{
    char lockstring[256]; 
    sprintf(lockstring,"pid: %d\n",fl.l_pid);
    write(fd,lockstring,strlen(lockstring));
}


void store_note_in_lockfile(char *note)
{
    write(fd,note,strlen(note));
}

void store_timestamped_note_in_lockfile(char *note)
{
    char lockstring[256]; 
    time_t curtime;
    struct tm *tlocal;
    curtime = time (NULL);
    tlocal = localtime(&curtime);
    sprintf(lockstring,"%s: %s",note,asctime(tlocal));
    write(fd,lockstring,strlen(lockstring));
}

int store_directory_in_lockfile()
{
    char * cwd;
    char lockstring[512]; 
    cwd = getcwd (0, 0);
    if (! cwd) {
        fprintf (stderr, "getcwd failed: %s\n", strerror (errno));
        return(1);
    } else {
        sprintf(lockstring,"Working directory: %s\n",cwd);
        write(fd,lockstring,strlen(lockstring));
        free (cwd);
    }
    return(0);
}
