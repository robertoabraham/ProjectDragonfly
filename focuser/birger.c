/* 
 * BIRGER - Program to manipulate a Birger Canon EF focus controller.
 *
 * The commands in this source file are documented in the "Canon EF-232
 * Library User Manual 1.3", a PDF of which is available on the Birger
 * website. For debugging purposes it is useful to remember that you can 
 * access the focuser serial port interactively using the "screen" command 
 * from the terminal. For example:
 *
 * screen /dev/tty.KeySerial1 115200
 *
 * Type some serial commands and see what happens. To quit, type ctrl-a ctrl-\
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <ctype.h>

#define DEBUG
#undef DEBUG

#define MAX_STRING 256

#define BADKEY                    -1
#define FOCUSER_CURRENT_POSITION   0
#define FOCUSER_STATUS             1
#define FOCUSER_GOTO               2
#define FOCUSER_MOVE               3
#define FOCUSER_INIT               4
#define FOCUSER_RAW                5


/* Declarations */

/* Lexical parsing */
int value_from_focus_command_key(char *key);

/* Serial port maintenance */
int open_focuser_port(char *portname);

/* Focuser routines */
int FocuserSetVerboseMode(int fd);
int FocuserSendRawCommand(int fd, char command[16]);
int FocuserInit(int fd);
int FocuserGoTo(int fd, int position);
int FocuserMove(int fd, int position);
int FocuserPrintCurrentPosition(int fd);
int FocuserPrintStatus(int fd);
int GetCurrentFocuserPosition(int fd);


/* The structure and lookup table below are used to parse
 * input commands */
typedef struct {
    char *key; 
    int val;
} t_keyval;


static t_keyval focus_command_lookup_table[] = {
        {"status",  FOCUSER_STATUS},   {"s", FOCUSER_STATUS},
        {"goto",    FOCUSER_GOTO},     {"g", FOCUSER_GOTO},
        {"move",    FOCUSER_MOVE},     {"m", FOCUSER_MOVE},
        {"init",    FOCUSER_INIT},     {"i", FOCUSER_INIT}, 
        {"raw",     FOCUSER_RAW},      {"r", FOCUSER_RAW} 
};
#define NFOCUSCOMMANDKEYS (sizeof(focus_command_lookup_table)/sizeof(t_keyval))


/* Return an integer value corresponding to a command key.
 * This is a poor person's lexical parser */
int value_from_focus_command_key(char *key)
{
    int i;
    for (i=0; i < NFOCUSCOMMANDKEYS; i++) {
	t_keyval *sym = focus_command_lookup_table + i;
	if (strcmp(sym->key, key) == 0)
	    return sym->val;
    }
    return BADKEY;
}


/* Global variable help string (structured like a man page) */
char   *help[] = {
    "NAME",
    "    birger --- manipulate an electronic focuser/lens mount for Canon EF lenses",
    "",
    "SYNOPSIS",
    "    birger [options]",
    "    birger [options] command",
    "    birger [options] command value",
    "",
    "COMMANDS",
    "    <none>          - display the focuser's current position",
    "    init            - initialize focuser to 0 and calibrates focus range",
    "    goto <position> - move to an absolute position",
    "    move <delta>    - move delta steps from current position (positive or negative)",
    "    status          - display current position, maximum position, and other information",
    "    raw <command>   - send a raw command to the focuser. See the focuser manual for",
    "                      a list of known commands.",
    "",
    "OPTIONS",
    "    -p portname     - set serial port to portname (default is /dev/cu.KeySerial1)",
    "    -v              - verbose mode",
    "    -h              - print help information",
    "",
    "EXAMPLES",
    "    birger init",
    "    birger",
    "    birger goto 700",
    "    birger move -20",
    "    birger status",
    "",
    "AUTHOR",
    "    Roberto Abraham:  abraham@astro.utoronto.ca",
    "",
    "DESCRIPTION",
    "    The program is designed to operate a Canon EF lens mount/controller made by",
    "    Birger Engineering, Inc. (See http://www.birger.com for more information).",
    "",
    "NOTES",
    "    1. If the serial port is not specified using the -p flag then the program",
    "    attempts to use the environment variable $BIRGER_SERIAL_PORT to identify the",
    "    correct serial port to use. If this environment variable is not defined then",
    "    the program attempts to open /dev/cu.KeySerial1.",
    "",
    "    2. The first command after power-up should be to execute the init command which",
    "    determines the focus range, sets the lens at closest focus, and defines this to",
    "    be the zero position.",
    "",
    "      % birger init",
    "",
    "    3. Raw commands from the library/bootloader can be sent to accomplish all tasks,", 
    "    including those tasks for which this program provides high-level commands. If you",
    "    send the controller raw commands that respond with useful information you probably want",
    "    to do so in verbose mode so you can see the results. For example, here is how you",
    "    can use raw commands to initialize the lens position so that setpoint 0 corresponds",
    "    to closest focus (a task more easily accomplished with 'birger init'):",
    "",
    "      % birger raw mz           (drives focuser to zero position)",
    "      % birger raw sf0          (sets offset so that current position is 0)",
    "",
    "    Confirm this has worked:",
    "",
    "      % birger -v raw pf        (prints current focus position; note use of verbose mode)",
    "",
    "LAST UPDATE",
    "    August 2012",
    "",
    0
};


/* Global variable to control verbosity */
int verbose = 0;


/* Routine to open the serial port and return a handle to it. The black
 * magic (baud speed, parity etc) needed to communicate with the focuser
 * all goes here. */

int open_focuser_port(char *portname)
{
    int fd; 
    struct termios options;
    int max_portname_length=128;

    if (verbose)
        fprintf(stderr,"Attempting to open serial port:%s\n",portname);

    /* fd = open(portname, O_RDWR | O_NOCTTY | O_NDELAY); */
    fd = open(portname, O_RDWR);
    if (fd == -1)
    {
        perror("Error - unable to open serial port.");
    }
    else {
        /* Set the port to use normal (blocking) mode */
        fcntl(fd, F_SETFL, 0);
        /* get the current options */
        tcgetattr(fd, &options);
        /* Baud rate: Erk says to use 115200 baud */
        cfsetispeed(&options, B115200);
        cfsetospeed(&options, B115200);  // new
        /* Parity checking: Erik says communication is 8N1 (no parity) */
        options.c_cflag &= ~PARENB;
        options.c_cflag &= ~CSTOPB;
        options.c_cflag &= ~CSIZE;
        options.c_cflag |= CS8;
        /* Other obscure options */
        options.c_cflag |= (CLOCAL | CREAD); // Enable receive
        /* Local options: set raw input = disable ICANON, ECHO, ECHOE, and ISIG) */
        options.c_lflag     &= ~(ICANON | ECHO | ECHOE | ISIG);
        /* Output options: set raw output = disable post-processing */
         options.c_oflag     &= ~OPOST;
        /* Set read timeout */ 
        options.c_cc[VMIN]  = 0;
        options.c_cc[VTIME] = 20; // In 10ths of a second... so 10 = 1s timeout.
        /* set the options */
        tcsetattr(fd, TCSANOW, &options);
    }

    if (verbose)
        fprintf(stderr," Serial port opened.\n");

    return (fd);
}



/* The information returned by commands in the focuser library depend on the an internal variable
 * which specifies the verbosity. The state of the verbosity variable is burned into an EEPROM
 * so it survives power cycles. I need to do something to make sure that information is given
 * in a format that I can reliably parse. To do this I call the following routine at the 
 * start of the main program, which will set the library to use maximum verbosity. The success
 * of calling this routine also verifies early on that something is attached to the serial
 * port. */

int FocuserSetVerboseMode(int fd)
{
    char rbuf[128];
    const char set_verbose_response_mode_command[7] = "rm1,1\r";
    int check;
    int count;
    char c;

    /* Make sure we are in verbose mode */
    if (verbose) {
        fprintf(stderr,"<FocuserSetVerboseMode>\n");
        fprintf(stderr,"Sending: %s\n",set_verbose_response_mode_command);
    }

    check = write(fd, set_verbose_response_mode_command, 6);
    if (check != 6){
        fprintf(stderr," Error sending verbose mode command setting to serial port.\n");
        return -1;
    }
    /* First thing sent back is a copy of the command */
    count = 0;
    c = '\0';
    while (c != '\r' && count < 128) {
        check = read(fd, &c, 1);
        if (check != 1){
            fprintf(stderr,"In FocuserSetVerboseMode Position 1: Error reading from serial port.\n");
            return -1;
        }
        *(rbuf + count) = c;
        count++;
    }
    *(rbuf + count) = '\0';
    if (verbose)
        fprintf(stderr," Received: %s\n",rbuf);

    /* After setting verbose mode we expect an 'OK'*/
    count = 0;
    c = '\0';
    while (c != '\r' && count < 128) {
        check = read(fd, &c, 1);
        if (check != 1){
            fprintf(stderr,"In FocuserSetVerboseMode Position 2. Variable check is %d - Error reading from serial port.\n",check);
            return -1;
        }
        *(rbuf + count) = c;
        count++;
    }
    *(rbuf + count) = '\0';
    if (verbose)
        fprintf(stderr," Received: %s\n",rbuf);

    return 0;
}




/* This is the general routine that most other routines call in order to control the
 * focuser. This operates silently unless the program is running in verbose mode.
 * It sends raw serial commands to the focuser. */

int FocuserSendRawCommand(int fd, char command[16]) 
{
    char rbuf[128];
    char command_buffer[9];
    int check;
    int count;
    char c;

    if (verbose) {
        fprintf(stderr,"<FocuserSendRawCommand>\n");
        fprintf(stderr,"Sending: %s\n",command);
    }

    check = write(fd, command, strlen(command));
    if (check != strlen(command) ){
        fprintf(stderr," Error writing body of command to serial port.\n");
        return -1;
    }
    check = write(fd, "\r", 1);
    if (check != 1) {
        fprintf(stderr," Error writing carriage return to serial port.\n");
        return -1;
    }

    /* The first thing sent back (in most cases) is a copy of the command. A
     * couple of commands ("sf0" and "la") appear to send a simple carriage
     * return back though */
    count = 0;
    c = '\0';
    while (c != '\r' && count < 128) {
        check = read(fd, &c, 1);
        if (check != 1) {
            fprintf(stderr," In FocuserSendRawCommand Position 1: Error reading from serial port.\n");
            return -1;
        }
        *(rbuf + count) = c;
        count++;
    }
    *(rbuf + count) = '\0';

    if (verbose)
        fprintf(stderr," Received: %s\n",rbuf);

    /* The next thing sent back (in most cases) is a response from the command.
     * A couple of commands ("sf0" and "la" appear to echo the command here
     * though. And in some cases nothing is returned when something is expected!
     * I think this might be a bug in the firmware. I'll try to code around this
     * by accepting either an echo or nothing, but not gibberish. */
    count = 0;
    c = '\0';
    while (c != '\r' && count < 128) {
        check = read(fd, &c, 1);
        if (check == 0 && count == 0)
            break;
        if (check != 1) {
            fprintf(stderr," In FocuserSendRawCommand Position 2. Variable check has value %d - Error reading from serial port.\n",check);
            return -1;
        }
        *(rbuf + count) = c;
        count++;
    }
    *(rbuf + count) = '\0';

    if (verbose)
        fprintf(stderr," Received: %s\n",rbuf);

    return 0;
}



/* Get the current focuser position. */
int GetCurrentFocuserPosition(int fd)
{
    char rbuf[128];
    const char print_current_position_command[4] = "pf\r";
    char command_buffer[9];
    int check;
    int count;
    char c;

    if (verbose){
        fprintf(stderr,"<GetCurrentFocuserPosition>\n");
        fprintf(stderr,"Sending %s\n",print_current_position_command);
    }

    check = write(fd, print_current_position_command, strlen(print_current_position_command));
    if (check != strlen(print_current_position_command) ){
        fprintf(stderr," Error writing body of command to serial port.\n");
        return -1;
    }
    /* The first thing sent back is a copy of the command */
    c = '\0';
    while (c != '\r' && count < 128) {
        check = read(fd, &c, 1);
        *(rbuf + count) = c;
        count++;
    }
    *(rbuf + count) = '\0';
    if (verbose) fprintf(stderr," Received: %s\n",rbuf);

    
    /* Now get the part we care about */
    count = 0;
    c = '\0';
    while (c != '\r' && count < 128) {
        check = read(fd, &c, 1);
        *(rbuf + count) = c;
        count++;
    }
    *(rbuf + count) = '\0';
    if (verbose) fprintf(stderr," Received: %s\n",rbuf);

    return atoi(rbuf);
}


/* The first thing the user should do after a power cycle is call the following
 * routine, which initializes the focuser. It sets the focus range and drives the
 * focuser close to zero. It will probably not result in a focuser at exactly zero
 * though because the setpoints vary a bit when a hard stop is reached */

int FocuserInit(int fd)
{
    char drive_to_zero_command[16] = "mz\r";
    char set_zero_position_command[16] = "sf0\r";
    char learn_focus_range_command[16] = "la\r";
    char initialize_aperture_command[16] = "in\r";
    if (verbose) fprintf(stderr,"<FocuserInit>\n");
    FocuserSendRawCommand(fd,drive_to_zero_command);
    FocuserSendRawCommand(fd,set_zero_position_command);
    FocuserSendRawCommand(fd,learn_focus_range_command);
    FocuserSendRawCommand(fd,initialize_aperture_command);
    return 0;
}

/* Drives the focuser to an absolute set point */

int FocuserGoTo(int fd, int position)
{
    char set_focus_command[16];
    if (verbose) fprintf(stderr,"<FocuserGoTo>\n");
    sprintf(set_focus_command,"fa%d\r",(int)position);
    FocuserSendRawCommand(fd,set_focus_command);
    return 0;
}


/* Drives the focuser to a relative set point */

int FocuserMove(int fd, int position)
{
    char set_focus_command[16];
    if (verbose) fprintf(stderr,"<FocuserMove>\n");
    sprintf(set_focus_command,"mf%d\r",(int)position);
    FocuserSendRawCommand(fd,set_focus_command);
    return 0;
}

/* A convenience routine that calls GetCurrentFocuserPosition and
 * prints the result to the screen */

int FocuserPrintCurrentPosition(int fd)
{
    int pos;
    if (verbose) fprintf(stderr,"<FocuserPrintCurrentPosition>\n");
    pos = GetCurrentFocuserPosition(fd);
    fprintf(stdout,"%d\n",pos);
    return 0;
}


/* Lists the current focuser position as well as the focus range. Because
 * the range is specified internally using raw encoder counts that do not have
 * a zero point offset applied, I need to do some fairly elaborate processing
 * to get the needed information. */

int FocuserPrintStatus(int fd)
{
    char command[4], rbuf[128];
    char command_buffer[9];
    int check;
    int count;
    char c;
    int current_position;
    const char delims[]=": ";

    if (verbose) fprintf(stderr,"<FocuserPrintStatus>\n");

    /* Send command to determine range of allowable focus positions */
    sprintf(command,"fp\r");
    if (verbose) fprintf(stderr,"Sending:%s\n",command);
    check = write(fd, command, strlen(command));
    if (check != strlen(command) ){
        fprintf(stderr," Error writing body of command to serial port.\n");
        return -1;
    }

    /* The first thing sent back is a copy of the command */
    count = 0;
    c = '\0';
    while (c != '\r' && count < 128) {
        check = read(fd, &c, 1);
        *(rbuf + count) = c;
        count++;
    }
    *(rbuf + count) = '\0';
    if (verbose) fprintf(stderr," Received: %s\n",rbuf);

    /* Now receive the interesting part */
    count = 0;
    c = '\0';
    while (c != '\r' && count < 128) {
        check = read(fd, &c, 1);
        *(rbuf + count) = c;
        count++;
    }
    *(rbuf + count) = '\0';
    if (verbose) fprintf(stderr," Received: %s\n",rbuf);

    /* Break this into tokens and convert from raw encoder counts to
     * standard counts with the focus counter offset applied. */
    char *fminkey,*fminvalstring,*fmaxkey,*fmaxvalstring,*currentkey,*currentvalstring;
    int fminval,fmaxval,currentval;
    fminkey = strtok(rbuf,delims);
    fminvalstring = strtok(NULL,delims);
    fmaxkey = strtok(NULL,delims);
    fmaxvalstring = strtok(NULL,delims);
    currentkey = strtok(NULL,delims);
    currentvalstring = strtok(NULL,delims);
    fminval = atoi(fminvalstring);
    fmaxval = atoi(fmaxvalstring);
    currentval = atoi(currentvalstring);

    fprintf(stdout,"CurrentValue: %d\n",currentval-fminval);
    fprintf(stdout,"MinimumValue: %d\n",0);
    fprintf(stdout,"MaximumValue: %d\n",fmaxval-fminval);

    return 0;
}



int main(int argc, char *argv[]) {

    int arg = 1;
    char commandstr[8];
    char command_argument[16];
    int action;
    int fd;
    int c, narg;
    char *serial_port;
    int status;
   
    /* Set the default value for the serial port */
    serial_port = getenv("BIRGER_SERIAL_PORT");
    if (serial_port == NULL)
    {  
        serial_port = malloc(256);
        strcpy(serial_port,"/dev/cu.KeySerial1");
    }

    /* parse command-line options */
    opterr = 0;
    while ((c = getopt (argc, argv, "hvp:")) != -1)
        switch (c)
        {               
            case 'h':
                for (int i = 0; help[i] != 0; i++) fprintf (stdout, "%s\n", help[i]);
                return 0;
                break;
            case 'v':
                verbose = 1;
                break;
            case 'p':
                serial_port = optarg;
                break;
            case '?':
                if (optopt == 'c')
                    fprintf(stderr, "Option -%c requires an argument.\n", optopt);
                else if (isprint (optopt))
                    fprintf(stderr, "Unknown option `-%c'.\n", optopt);
                else
                    fprintf(stderr,
                            "Unknown option character `\\x%x'.\n",
                            optopt);
                for (int i = 0; help[i] != 0; i++)
                    fprintf (stdout, "%s\n", help[i]);
                return 1;
            default:
                abort();
        }

    /* Handle non-option arguments */
    narg = argc - optind;
    if (narg == 0)
    {
        action = FOCUSER_CURRENT_POSITION;
    }
    else 
    {
        sscanf (argv[optind++], "%s", commandstr);
        if (narg > 1)
            sscanf (argv[optind++], "%s", command_argument);
        action = value_from_focus_command_key(commandstr);
    }

    if (verbose) fprintf(stderr,"Serial port set to %s\n",serial_port);

    /* Now do the right thing! */
    fd = open_focuser_port(serial_port);
    if (fd<0) 
        return(-1);
    status = FocuserSetVerboseMode(fd);
    if (status == -1) return(1);

    switch(action)
    {
       case FOCUSER_CURRENT_POSITION:
            FocuserPrintCurrentPosition(fd);
            break;
       case FOCUSER_STATUS:
            FocuserPrintStatus(fd);
            break;
       case FOCUSER_GOTO:
            FocuserGoTo(fd,atoi(command_argument));
            break;
       case FOCUSER_MOVE:
            FocuserMove(fd,atoi(command_argument));
            break;
       case FOCUSER_RAW:
            FocuserSendRawCommand(fd,command_argument);
            break;
       case FOCUSER_INIT:
            FocuserInit(fd);
            break;
        default:
            for (int i = 0; help[i] != 0; i++)
                fprintf (stdout, "%s\n", help[i]);
            close(fd);
            return(1);
    }

    close(fd);
    return(0);

}

