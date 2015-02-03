#! /bin/bash
#== Do not edit these default settings==
   CENTOS4=-1  #don't touch it

#===========settings====
   ZAPTEL_VER="1.4.11"
   ASTERISK_VER="1.4.42"
   LIBPRI_VER="1.4.14"
   ADDONS_VER="1.4.11"
   SPANDSP_VER="0.0.4pre18"

   KOLMISOFT_IP="www.kolmisoft.com"
   KOLMISOFT_URL="http://www.kolmisoft.com"

#=========other packets=========
   phpSysInfo=phpSysInfo-3.0-RC6.tar.gz

#=======  INSTALL options  ================
   INSTALL_GUI=1;
   INSTALL_APP=1;
   INSTALL_DB=1;
   INSTALL_H323=1;
   INSTALL_AUTO_DIALER=1;
   INSTALL_ZAPTEL=0

   UPGRADE_TO_0_7=1;  #1 to upgrade to v0.7, 0 - to stay with v0.6
   UPGRADE_TO_8=1;  #1 to upgrade to v0.8, 0 - to stay with v0.7   
   
#==================================================

   WITH_STOPS=0;     #1 - with stops, 0 - without stops during install process
   RUN_TESTS_AFTER_INSTALL=0  # if is set to 1 - automatically runs tests after install


#============ INSTALL type =============

   LOCAL_INSTALL=0;  # 1=local; 
                     # 0=internet

#============= DIRS==========================
   DEFAULT_DOWNLOAD_DIR="/usr/src/";  #default download dir for mor packets
   DEFAULT_DOWNLOAD_DIR2="/usr/src/mor";
   MOR_DIR="/usr/src/mor";
   _BACKUP_FOLDER="/usr/local/mor/backups"

#=======LOGS==============================
   DOWNLOAD_LOG="/tmp/mor_failed_downloads"
   PRODUCTION_LOG="/home/mor/log/production.log"
   MOR_DEBUG="/tmp/mor_debug.txt"
   MOR_CRASH_LOG="/tmp/mor_crash.log"
   BACKUP_LOG="/tmp/mor_debug_backup.txt"    #the place where this backup script logs it's errors

#======== LOCAL INSTALL RELATED SETTINGS ==
   TRUNK_DIR_0_6="/usr/src/other/trunk_0_6";
   TRUNK_DIR_0_7="/usr/src/other/trunk_0_7";
#======== DEBUG RELATED SETTINGS =================================
   VERBOSE=1;  # 0 - no additional output; 1 - with additional output 

#=====================MySQL DB SETTINGS=======================================
   DB_HOST="localhost"
   DB_NAME="mor"
   DB_USERNAME="mor"
   DB_PASSWORD="mor"

#====================program paths=========================================
   _M_python=`which python`;

