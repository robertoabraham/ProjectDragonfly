#ifndef CAMERA_H
#define CAMERA_H

#include <sbigudrv.h>

#define MAX_SUB_EXPR_CNT 256
#define MAX_SUB_EXPR_LEN 256
#define MAX_ERR_STR_LEN  256

/* Device status flags */
#define IDLE        0
#define INTEGRATING 1
#define COMPLETE    2

#define FILTER_WHEEL_IDLE CFWS_IDLE

/* Frame definitions */
#define BADKEY          -1
#define DARK             0     
#define LIGHT            1 
#define BIAS             2  
#define FLAT             3  

#ifndef INVALID_HANDLE_VALUE
 #define INVALID_HANDLE_VALUE -1
#endif



/***** TYPES *****/

typedef struct {
    char name[128]; 
    char serial_number[16];
    CAMERA_TYPE camera_type;
    int width;
    int height;
    double gain;
    short handle;
    double setpoint;
    double temperature;
    double ambientTemperature;
    double power;
} t_camerainfo;

typedef struct {
    char *key; 
    int val;
} t_keyval;



/***** GLOBALS *****/

/* Properties of the currently active camera. These are set when
 * the user calls SetActiveCamera(camera_number) */
extern char        *ccd_image_name;        // Camera's long name (supplied by SBIG)
extern char        *ccd_serial_number;     // Camera's serial number (set in firmware)
extern CAMERA_TYPE ccd_camera_type;        // Camera type defined in sbigudrv.h
extern int         ccd_image_width;        // Detector width
extern int         ccd_image_height;       // Detector height
extern double      ccd_image_gain;         // Gain in funny units

/* Variables used for camera control */
extern int ccd_image_status;
extern int ccd_phase;
extern int ccd_type;
extern int ccd_ncam;

/* We support four cameras */
extern t_camerainfo ccd_camera_info[4];
extern unsigned short *ccd_image_data[4];



/***** PROTOTYPES *****/

/* Functions that act on the currently active camera. */
int  SetActiveCamera(int);
int  InitializeCamera(int);
int  RegulateTemperature(double sp);
int  GetCameraTemperature();
int  DisableTemperatureRegulation();
int  PrintCameraInformation(); 
int  PrintUSBNetworkInformation();
int  CaptureImage(int *,  unsigned short *, int, double, int, int, int, int, int);
int  IsCameraAnST402ME();    
int  IsCameraAnSTF8300();    
int  SetFilter(CFW_POSITION pos); // ST-402ME only
int  FilterWheelPosition();       // ST-402ME only 
int  FilterWheelStatus();         // ST-402ME only
int  NumberOfFilters();           // ST-402ME only

/* Functions that act on all cameras */
int  CountCameras();
int  InitializeAllCameras();
int  DisconnectAllCameras();

/* Accessor methods */
int  ActiveCamera();
int  GetCameraStatus(int *);

/* Debug methods */
void SetVerbosity(int);

/* Utilities */
int  value_from_imagetype_key(char *);
int  value_from_filtername_key(char *);
void write_fits(char *, int, int, unsigned short *, double, char*, double,int,char*,char*,char*,char*,char*,char*); 
void show_cfitsio_error(int);
int  check_sbig_error(int err, char *msg);
void load_bar(int, int, int, int);
int  new_filename(char *, char *, char *);
int  get_lock();
int  get_nondestructive_lock();
int  release_lock();
void store_pid_in_lockfile();
void store_note_in_lockfile();
int  store_directory_in_lockfile();
void store_timestamped_note_in_lockfile(char *);

#endif
