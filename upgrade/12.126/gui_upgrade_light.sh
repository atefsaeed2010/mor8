#!/bin/sh
#==== Includes=====================================
    . /usr/src/mor/sh_scripts/install_configs.sh
    . /usr/src/mor/sh_scripts/mor_install_functions.sh
    . /usr/src/mor/test/framework/bash_functions.sh
#==================================================

do_not_allow_to_downgrade_if_current_gui_higher_than 120

#make backup of previous gui
_mor_time; #get the system time
tar czf /usr/local/mor/backups/GUI/mor_gui_backup.$mor_time.tar.gz /home/mor/app /home/mor/config /home/mor/doc /home/mor/lang /home/mor/lib /home/mor/public/stylesheets /home/mor/vendor 

get_last_stable_mor_revision 12.126
svn co -r $LAST_STABLE_GUI http://svn.kolmisoft.com/mor/gui/branches/12.126 /home/mor
#apache_restart;

chmod -R 777 /home/mor/public/images/logo  /home/mor/public/images/cards

/etc/init.d/httpd restart

log_revision 'mor' 'gui' 'Update was made using gui_upgrade_light.sh'
