#! /bin/bash
#===== README ====
# MOR installation must be upgraded to the most recent version
# This script upgrades mor GUI only with a command specified by GUI_UPGRADE_CMD  variable
# selenium-server must be running
# start selenium server with command:
# 		./mor_test_run.sh -s
#
#==============
#	v3.15	2014-02-05	bundle update before tests to support gem changes
#       v3.14   2013-08-26      Report all FAILED tests for better debugging
#       v3.13   2013-08-05      Cleaned out addons from env.rb and this script - they are controlled from db now
#	v3.12	2013-06-26	More aggressive memory cleaning with debug info to log file, also clean memory after each failed test, wait 30s for apache init
#	v3.11	2013-06-22	Do not reload apache after each test, should save 15s on each test
#       v3.10   2013-06-21      Added function recompile_assets_if_needed which detects command in test_first to recompile assets
#       v3.9    2013-03-18      Added Asterisk 1.8 DB upgrade: /usr/src/mor/sh_scripts/asterisk/db/import_changes.sh
#	v3.9	2013-03-03	Temporary cleaning for huge mess done by this $%^& test: /last_calls_stats/export_last_calls.case
#       v3.8    2012-11-06      Added option to log into file TOP and fee -m output. Enabled and disabled with variable:  ENABLE_PERFORMANCE_LOGGING
#	v3.7	2012-10-31	Speedup fresh db for 12.126 and 12
#	v3.6	2012-10-17	Run all tests 3x. Only sm and all amount of testst are failing from time to time
#	v3.5	2012-09-22	Run all tests only once during the sprint to save time
#	v3.4	2012-09-06	Leave Asterisk alive
#	v3.3	2012-09-05	Kill unecessary services, debug option for SLOW starting selenium.jar file
#       v3.2    2012-08-24      MOR 12 requires addition permissions for assets
#       v3.1    2012-08-16      Clean failed_tests file to do not allow accumulate for failed tests and test only failed tests from last revision
#       v3.0    2012-08-15      Test each test till first OK or up to 3 times (almost solves selenium-ajax issues)


. /usr/local/mor/test_environment/mor_test.cfg

. /usr/src/mor/test/framework/bash_functions.sh

SELENIUM_SERVER_VERSION="2.35.0"

ENABLE_PERFORMANCE_LOGGING=0 # { 0 - disabled, 1 - enabled}

if [ "$MODE" == "0" ]; then
	E_MAIL_RECIPIENTS="$TESTER_EMAIL" #separate each address with a space
elif [ "$MODE" == "1" ]; then
	E_MAIL_RECIPIENTS="serveriu.pranesimai@gmail.com aisteaisteb@gmail.com" #separate each address with a space
#	E_MAIL_RECIPIENTS="mkezys@gmail.com" #separate each address with a space
else
	echo "Unknown error when selecting MODE"
fi


special_test_cases()
{
    # About:    There are cases when it's very hard to write a good test which behaves accoring to specific day it's run. For example first day of the month when calculations are totally different.
    #
    # This function reads test header and does some actions according to it. Available actions documentation:
    #   mor_condition;day;1;alternative_test_path
    #   mor_condition;day;1;/home/mor/selenium/exceptions/services_daily_first_day.case
    local tst=$1
    
    if [ `grep mor_condition $tst | wc -l` -gt "0" ]; then
        local condition=`grep mor_condition $tst | awk -F";" '{print $2}'`
        local argument=`grep mor_condition $tst | awk -F";" '{print $3}'`
        local alternative_test=`grep mor_condition $tst | awk -F";" '{print $4}'`
            
        if [ "$condition" = "day" ]; then
            local DAY_OF_MONTH=`date +%-d`
            if [ "$argument" == "$DAY_OF_MONTH" ]; then
                testas="$alternative_test"
            fi
        fi
    fi
}

#=======OPTIONS========
: ${dbg:="1"}	# dbg= {0 - off, 1 - on }  for debuging purposes
#============FUNCTIONS====================

another_java_instance()
{
    if [ `ps aux | grep java | grep -v grep  | wc -l` != "0" ]; then
        echo "There is another java instance running! "
        exit 0
    fi

}

log_performance_metrics()
{
    #   Abou:   Gathers various statistics (ram, top, etc. ) about system performance at a given time. Will print output to /var/log/mor/n
    
    if [ "$1" != "" ]; then
        report "\n\n[ PERFORMANCE LOG] $1\n\n" 3  
    fi
    
    top -n 1 >> /var/log/mor/n
    free -m >> /var/log/mor/n
}


clean_ram(){
        echo "Cleaning memory, free RAM:"`free -m | grep cache | awk '{ print \$4}' | tail -n 1`
        /etc/init.d/httpd stop
        killall -9 httpd
        killall -9 dispatch.fcgi
        killall -9 ruby
        killall -9 java
        killall -9 firefox
        ipcs -s | grep apache | perl -e 'while (<STDIN>) { @a=split(/\s+/); print `ipcrm sem $a[1]`}'
	sync; echo 3 > /proc/sys/vm/drop_caches
        
        # and now swap...
        sysctl -w vm.swappiness=0
        echo 0 >/proc/sys/vm/swappiness
 
        /etc/init.d/mysqld restart
        /etc/init.d/httpd start
        echo "RAM cleaning finished, free RAM:"`free -m | grep cache | awk '{ print \$4}' | tail -n 1`
}

restart_services_if_not_enough_ram()
{
    # 150 changed to 500 because free -m shows crap, when it shows < 500, top shows that all ram is used and tests began to timeout, so 150 is useless
    if [ `free -m | grep cache | awk '{ print \$4}' | tail -n 1` -lt "500" ]; then
	clean_ram
    else
	echo "RAM OK, free: "`free -m | grep cache | awk '{ print \$4}' | tail -n 1`
	#echo "Apache reload"
        #service httpd reload #what happens without reload? #will try... #ram is wasted, added new operations to cleanup procedure
    fi
}

actions_before_new_test()
{
    # About:    This is a place for all house cleaning actions before new test
    #== House cleaning before tests
    #killall -9 dispatch.fcgi    # removing all dispatch processes. As they are hanging up and consuming RAM;           We are using passenger now

    sync; echo 3 > /proc/sys/vm/drop_caches &> /dev/null # clean mem cache
    #=======================LOGS==============================

    rm -rf /tmp/mor_debug.txt /tmp/mor_crash.log /home/mor/log/production.log /var/log/httpd/access_log /var/log/httpd/error_log /var/log/mor/selenium_server.log /tmp/mor_pdf_test.pdf
    touch /tmp/mor_debug.txt /tmp/mor_crash.log /home/mor/log/production.log /var/log/httpd/access_log /var/log/httpd/error_log /var/log/mor/selenium_server.log
    chmod 777 /var/log/httpd/access_log /var/log/httpd/error_log /tmp/mor_debug.txt /tmp/mor_crash.log /home/mor/log/production.log /var/log/mor/selenium_server.log

    # clean uploaded auto dialer files; Hardcoding for now. Please note that this value can also be set in environment.rb. Also please note that the path currently set there is just a symlink
    rm -rf /home/mor/public/ad_sounds/*.wav
    # cleaning test IVR files
    
    
    find /home/mor/public/ivr_voices/* -name "*test*" | xargs rm -rf
    touch  /tmp/mor_crash_email.txt /tmp/mor_debug.txt /tmp/mor_crash.log /tmp/mor_crash.txt /home/mor/log/production.log /var/log/httpd/access_log /var/log/httpd/error_log
    mkdir -p /home/mor/log /var/log/httpd
    chmod -R 777 /tmp/mor_crash_email.txt /tmp/mor_debug.txt /tmp/mor_crash.log /tmp/mor_crash.txt /home/mor/log/production.log /var/log/httpd/access_log /var/log/httpd/error_log /var/log/httpd /home/mor/public/ivr_voices/ /home/mor/public/images
    chmod 777 /home/mor/Gemfile.lock


    rm -rf /home/DB_BACKUP_*
    #=====================================================
}



initialize_ror()
{
    # initiate apache/compile ror

    if [ `curl http://127.0.0.1/billing/callc/login 2> /dev/null | grep "login_username" | wc -l` != "2" ]; then
        echo "MOR GUI is not accessible, will wait 30 seconds"
        sleep 30
        
        # fix cannot load such file -- rack (LoadError) problem
        rm -fr /home/mor/Gemfile
        rm -fr /home/mor/Gemfile.lock
	rm -fr /home/mor/Rakefile
	rm -fr /home/mor/config.ru
	cd /home/mor
	svn update
	/etc/init.d/httpd restart
        
        if [ `curl http://127.0.0.1/billing/callc/login 2> /dev/null | grep "login_username" | wc -l` != "2" ]; then
            echo "Something happened with GUI - it is not accessbile even after giving 30 second for initialization"
            rm -rf /tmp/.mor_test_is_running    # Will try to update GUI and recover
            exit 0
        fi
    fi
}



house_cleaning()
{

    # also kill somebody...
    /etc/init.d/avahi-daemon stop  &> /dev/null
    # it seems asterisk is necessary for tests
    #killall -9 safe_asterisk  &> /dev/null
    #/etc/init.d/asterisk stop  &> /dev/null
    /etc/init.d/cups stop  &> /dev/null
    # kill some nonsense
    killall -9 wnck-applet &> /dev/null

    # and now swap...
    sysctl -w vm.swappiness=0
    echo 0 >/proc/sys/vm/swappiness
    # turning of all swap if any
    swapoff -a

    # clean mem cache
    sync; echo 3 > /proc/sys/vm/drop_caches

}



gather_log_about_machine_state_after_failed_test()
{
    # About:  This function logs all required info to a log which is sent to brain after a failed test.
    echo -e "\n\n============[`date +%0k\:%0M\:%0S`]  Additinional logs gathered after a failed test===================\n\n" >> $TMP_FILE

    echo -e "\n============ Top ===================\n\n" >> $TMP_FILE
    top -n 1 >> $TMP_FILE

    echo -e "\n============RAM===================\n\n" >> $TMP_FILE
    free -m >> $TMP_FILE
    echo -e "\n\n============Full System Process List===================\n\n" >> $TMP_FILE
    ps aux >> $TMP_FILE
    echo -e "\n\n============MySQL Process List===================\n\n" >> $TMP_FILE
    mysql mor -e "show processlist" 2>&1>> $TMP_FILE
}




default_interface_ip()
{
    #This function makes available in your scripts 2 variables: DEFAULT_INTERFACE  - this will be the name of the default interface throw which the traffic will be routed when no other destination adress mathced in kernel routing table. DEFAULT_IP - this is the IP assigned to DEFAULT_INTERFACE
    #How to use this function:
        # write anywhere in your script a call to this function and then you can use those two global variables for that script. Example:
        #       default_interface_ip;
        #       echo $DEFAULT_INTERFACE;
        #       echo $DEFAULT_IP;

    DEFAULT_INTERFACE=`/bin/netstat -nr | (read; cat) | (read; cat) | grep "^0.0.0.0" | awk '{ print $8}' | head -n 1` #Gets kernel routing table, when skips 2 first lines, when grep's the default path and finally prints the interface name
    DEFAULT_IP=`/sbin/ip addr show $DEFAULT_INTERFACE | grep "inet " | awk -F" " '{print $2}' | awk -F"/" '{print $1}'`
    DEFAULT_INTERFACE_MAC=`/sbin/ifconfig | grep eth | awk -F'HWaddr' '{print $2}' | sed 's/ //g'`
}




job_report()
{
    #   About:  This function reports test results after each test

    _mor_time
    if [ ! -f /usr/src/mor/test/cluster1/x5/brain-scripts/reporter.rb ]; then
        echo "[`date +%0k\:%0M\:%0S`] PS ID: $$. /usr/src/mor/test/cluster1/x5/brain-scripts/reporter.rb not found" | tee -a /var/log/mor/test_system
        rm -rf "$TEST_RUNNING_LOCK";
        exit 1;
    fi

    # determine if test is OK or FAILED
    grep -v -F "^warn: Current subframe appears" $TMP_FILE | grep "^error:\|^warn:"   &> /dev/null     # first grep - nasty hack for crm to ignore the message by selenium and report that test as ok
    if [ "$?" == "0" ]; then
        STATUS_v2="FAILED";
        # Saving test state as failed to log - next time it will be launched first
        echo "$testas" >> /var/log/mor/failed_tests
    else
        STATUS_v2="OK";
    fi

    TEST_NODE_ID_FROM_BRAIN="123" #hack to be compatible with brain2
    TEST_PRODUCT="mor"      #porting function here from more advanced scripts

    if [ -f /usr/src/mor/test/cluster1/x5/brain-scripts/reporter.rb ]; then
	echo "[`date +%0k\:%0M\:%0S`] PS ID: $$. Reporting to BRAIN..."
        if [ "$TEST_PRODUCT" == "mor" ]; then
            RELATVE_PATH_TO_TEST=`echo $TEST_TEST | sed 's/\/home\/mor\/selenium\/tests\///'`
        elif [ "$TEST_PRODUCT" == "crm" ]; then
            RELATVE_PATH_TO_TEST=`echo $TEST_TEST | sed 's/\/home\/tickets\/selenium\/tests\///'`
        fi
        local counter=0;
        while [ "$counter" != "5" ]; do
            counter=$(($counter+1))
            local temp=`mktemp`


            if [ "$STATUS_v2" == "OK" ]; then
                if [ "$TEST_PRODUCT" == "mor" ]; then
                    local result=`/usr/local/mor/mor_ruby /usr/src/mor/test/cluster1/x5/brain-scripts/reporter.rb $MOR_VERSION_YOU_ARE_TESTING_FOR_TESTS $CURRENT_REVISION $RELATVE_PATH_TO_TEST $STATUS_v2 "$TEST_NODE_ID_FROM_BRAIN"  "$JOB_RECEIVED_TIMESTAMP" "$SELENIUM_START_TIMESTAMP" "$SELENIUM_FINISH_TIMESTAMP" "test_log $TMP_FILE" | tee -a $temp /tmp/reporter.log`
                    echo "[`date +%0k\:%0M\:%0S`] PS ID: $$. [ $STATUS_v2 ] /usr/local/mor/mor_ruby /usr/src/mor/test/cluster1/x5/brain-scripts/reporter.rb $MOR_VERSION_YOU_ARE_TESTING_FOR_TESTS $CURRENT_REVISION $RELATVE_PATH_TO_TEST $STATUS_v2 $TEST_NODE_ID_FROM_BRAIN  \"$JOB_RECEIVED_TIMESTAMP\" \"$SELENIUM_START_TIMESTAMP\" \"$SELENIUM_FINISH_TIMESTAMP\" \"test_log $TMP_FILE\""
                elif [ "$TEST_PRODUCT" == "crm" ]; then
                    local result=`/usr/local/mor/mor_ruby /usr/src/mor/test/cluster1/x5/brain-scripts/reporter.rb 'tickets' $CURRENT_REVISION $RELATVE_PATH_TO_TEST $STATUS_v2 "$TEST_NODE_ID_FROM_BRAIN" "$JOB_RECEIVED_TIMESTAMP" "$SELENIUM_START_TIMESTAMP" "$SELENIUM_FINISH_TIMESTAMP"  "test_log $TMP_FILE" | tee -a $temp /tmp/reporter.log`
                    echo "[`date +%0k\:%0M\:%0S`] PS ID: $$. [ $STATUS_v2 ] /usr/local/mor/mor_ruby /usr/src/mor/test/cluster1/x5/brain-scripts/reporter.rb tickets $CURRENT_REVISION $RELATVE_PATH_TO_TEST $STATUS_v2 $TEST_NODE_ID_FROM_BRAIN  \"$JOB_RECEIVED_TIMESTAMP\" \"$SELENIUM_START_TIMESTAMP\" \"$SELENIUM_FINISH_TIMESTAMP\" \"test_log $TMP_FILE\""
                fi
            else
                gather_log_about_machine_state_after_failed_test  # the test failed, gathering additional logs

                if [ "$TEST_PRODUCT" == "mor" ]; then
                    local result=`/usr/local/mor/mor_ruby /usr/src/mor/test/cluster1/x5/brain-scripts/reporter.rb $MOR_VERSION_YOU_ARE_TESTING_FOR_TESTS $CURRENT_REVISION $RELATVE_PATH_TO_TEST $STATUS_v2 "$TEST_NODE_ID_FROM_BRAIN"  "$JOB_RECEIVED_TIMESTAMP" "$SELENIUM_START_TIMESTAMP" "$SELENIUM_FINISH_TIMESTAMP" "my_debug /tmp/mor_debug.txt" "crash_log /tmp/mor_crash.log" "production_log /home/mor/log/production.log" "access_log /var/log/httpd/access_log" "error_log  /var/log/httpd/error_log" "selenium_server_log /var/log/mor/selenium_server.log" "test_log $TMP_FILE" | tee -a $temp /tmp/reporter.log`
                    echo "[`date +%0k\:%0M\:%0S`] PS ID: $$. [ $STATUS_v2 ] /usr/local/mor/mor_ruby /usr/src/mor/test/cluster1/x5/brain-scripts/reporter.rb $MOR_VERSION_YOU_ARE_TESTING_FOR_TESTS $CURRENT_REVISION $RELATVE_PATH_TO_TEST $STATUS_v2 \"$TEST_NODE_ID_FROM_BRAIN\"  \"$JOB_RECEIVED_TIMESTAMP\" \"$SELENIUM_START_TIMESTAMP\" \"$SELENIUM_FINISH_TIMESTAMP\" \"my_debug /tmp/mor_debug.txt\" \"crash_log /tmp/mor_crash.log\" \"production_log /home/mor/log/production.log\" \"access_log /var/log/httpd/access_log\" \"error_log  /var/log/httpd/error_log\" \"selenium_server_log /var/log/mor/selenium_server.log\" \"test_log $TMP_FILE\""
                elif [ "$TEST_PRODUCT" == "crm" ]; then
                    local result=`/usr/local/mor/mor_ruby /usr/src/mor/test/cluster1/x5/brain-scripts/reporter.rb 'tickets' $CURRENT_REVISION $RELATVE_PATH_TO_TEST $STATUS_v2 "$TEST_NODE_ID_FROM_BRAIN" "$JOB_RECEIVED_TIMESTAMP" "$SELENIUM_START_TIMESTAMP" "$SELENIUM_FINISH_TIMESTAMP"  "my_debug /tmp/mor_debug.txt" "crash_log /tmp/mor_crash.log" "production_log /home/mor/log/production.log" "access_log /var/log/httpd/access_log" "error_log  /var/log/httpd/error_log" "selenium_server_log /var/log/mor/selenium_server.log" "test_log $TMP_FILE" | tee -a $temp /tmp/reporter.log`
                    echo "[`date +%0k\:%0M\:%0S`] PS ID: $$. [ $STATUS_v2 ] /usr/local/mor/mor_ruby /usr/src/mor/test/cluster1/x5/brain-scripts/reporter.rb tickets $CURRENT_REVISION $RELATVE_PATH_TO_TEST $STATUS_v2 \"$TEST_NODE_ID_FROM_BRAIN\"  \"$JOB_RECEIVED_TIMESTAMP\" \"$SELENIUM_START_TIMESTAMP\" \"$SELENIUM_FINISH_TIMESTAMP\" \"my_debug /tmp/mor_debug.txt\" \"crash_log /tmp/mor_crash.log\" \"production_log /home/mor/log/production.log\" \"access_log /var/log/httpd/access_log\" \"error_log  /var/log/httpd/error_log\" \"selenium_server_log /var/log/mor/selenium_server.log\" \"test_log $TMP_FILE\""
                fi

            fi
            grep "RECEIVED" $temp &> /dev/null
            if [ "$?" == "0" ]; then
                rm -rf /tmp/reporter.log $temp
                echo "[`date +%0k\:%0M\:%0S`] PS ID: $$. Reporting complete! Job WAS RECEIVED BY BRAIN"
                break
            else
                echo -e "\n\n\nThe answer from BRAIN: \n\n\n"
                cat $temp >> /var/log/mor/n
            fi
            rm -rf /tmp/reporter.log $temp
            echo "[`date +%0k\:%0M\:%0S`] PS ID: $$. Still reporting..."
            sleep $((3*$counter))   #will wait incrementally: 0, 3, 6, 12, 15 seconds..
        done
        if [ "$counter" -ge "5" ]; then # if reporting to brain failed
            echo "[`date +%0k\:%0M\:%0S`] PS ID: $$. Test reporting to brain failed: [ $STATUS_v2 ] $MOR_VERSION_YOU_ARE_TESTING_FOR_TESTS $CURRENT_REVISION $RELATVE_PATH_TO_TEST "
        fi
    else
        echo "[`date +%0k\:%0M\:%0S`] The reporter script was not found"
    fi
}





generate_suite_file()
{
    #   About:  This function works as a wrapper for old selenium tests
    #
    # $1  - test to add to suite file

    local TEST_NAME="$1"
    local TEST_TEST="$2"

    echo '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
  <meta content="text/html; charset=UTF-8" http-equiv="content-type" />
  <title>Test Suite</title>
</head>
<body>
<table id="suiteTable" cellpadding="1" cellspacing="1" border="1" class="selenium"><tbody>
<tr><td><b>Test Suite</b></td></tr>
<tr><td><a href="'$TEST_NAME.html'">'$TEST_TEST'</a></td></tr>
</tbody></table>
</body>
</html>' > /tmp/suite.html

}




copy_selenium_to_ram_if_not_present()
{
    #   About:  This function copies Selenium Server to RAM for faster execution
    #
    if [ ! -f /dev/shm/selenium-server-standalone-$SELENIUM_SERVER_VERSION.jar ]; then
        if [ ! -f /usr/src/selenium-server-standalone-$SELENIUM_SERVER_VERSION.jar ]; then
            wget -c http://selenium.googlecode.com/files/selenium-server-standalone-$SELENIUM_SERVER_VERSION.jar -O /usr/src/selenium-server-standalone-$SELENIUM_SERVER_VERSION.jar
            if [ "$?" != "0" ]; then
                report "Failed to download selenium " 3
                exit 0;
            fi
        fi
        rm -rf /dev/shm/selenium-server-standalone* #deleting possible old versions
        cp -fr  /usr/src/selenium-server-standalone-$SELENIUM_SERVER_VERSION.jar /dev/shm/selenium-server-standalone-$SELENIUM_SERVER_VERSION.jar
    fi
}



clean_logs()
{
    rm -rf /tmp/mor_debug.txt /tmp/mor_crash.log /home/mor/log/production.log /var/log/httpd/access_log /var/log/httpd/error_log /var/log/mor/selenium_server.log #/var/log/mor/test_system
    touch /tmp/mor_debug.txt /tmp/mor_crash.log /home/mor/log/production.log /var/log/httpd/access_log /var/log/httpd/error_log /var/log/mor/selenium_server.log #/var/log/mor/test_system
    chmod 777 /tmp/mor_debug.txt /tmp/mor_crash.log /home/mor/log/production.log /var/log/httpd/access_log /var/log/httpd/error_log /var/log/mor/selenium_server.log #/var/log/mor/test_system
}



restart_services()
{
    #selenium
    killall -9 java
    start_selenium_server;
    #-------
}
#--- git-------



git_check_and_install()
{
    #   About:  This func installs git if it is not present
    if [ ! -f /usr/bin/git ]; then
        cd /usr/src/
        wget -c http://download.fedora.redhat.com/pub/epel/5/i386/epel-release-5-4.noarch.rpm
        rpm -Uvh epel-release-*
        yum check-update
        yum -y install git
    fi
}



gem_rest_client_check_and_install()
{
    #   About:  This func installs rest-client gem if it is not present
    gem list | grep rest &> /dev/null
    if [ "$?" != "0" ]; then
        gem install rest-client
        if [ "$?" != "0" ]; then
            echo "FAILED TO INSTALL GEM: rest-client";
            exit 1;
        fi
    fi
}



checkout_brain_script()
{
    #   About:  This func downloads latest Kolmisoft TEST SYSTEM v2 brain scripts from brain git repo
    git_check_and_install
    rm -rf /usr/src/brain-scripts
    cd /usr/src
    git clone git://$GIT_REPO_ADDRESS/brain-scripts.git 
}

#git_check_and_install
#gem_rest_client_check_and_install
#checkout_brain_script


#---- /git-----



#------------------------------------------
prepare_db(){

	# recreate ramdisk
	/usr/src/mor/test/cluster1/rebuild_mysql_ram.sh > /var/log/mor/rebuild_mysql_ram.log 2>&1
        mysql < /usr/src/mor/db/init.sql
        /usr/src/mor/db/0.8/make_new_db.sh nobk
	

        # MySQL FILE permission GRANT
        /usr/src/mor/test/scripts/mysql/mysql_file_grant.sh # Do not delete this!!!
        

        #mysql mor < /home/mor/selenium/mor_0.8_testdb.sql;
        #report "Running /usr/src/mor/db/9/import_changes.sh" 3
        #/usr/src/mor/db/9/import_changes.sh

        mor_gui_current_version 
        mor_version_mapper  $MOR_VERSION_YOU_ARE_TESTING_FOR_TESTS
        
        #if [ "$MOR_MAPPED_VERSION_WEIGHT" -ge "100" ]; then
        #    report "Running /usr/src/mor/db/10/import_changes.sh" 3
        #    /usr/src/mor/db/10/import_changes.sh
        #fi

        #if [ "$MOR_MAPPED_VERSION_WEIGHT" -ge "110" ]; then
        #    report "Running /usr/src/mor/db/11/import_changes.sh" 3
        #    /usr/src/mor/db/11/import_changes.sh
        #fi

        #if [ "$MOR_MAPPED_VERSION_WEIGHT" -ge "123" ]; then
        #    report "Running /usr/src/mor/db/12/import_changes.sh" 3
        #    /usr/src/mor/db/12/import_changes.sh
        #fi

        #if [ "$MOR_MAPPED_VERSION_WEIGHT" -ge "140" ]; then
        #    report "Running /usr/src/mor/upgrade/x4/sipchaning.rb  -v" 3
        #    /usr/local/rvm/bin/ruby-1.9.3-p327@x4  /usr/src/mor/upgrade/x4/sipchaning.rb  -v
        #    
        #    report "Running /usr/src/mor/db/x4/import_changes.sh" 3
        #    /usr/src/mor/db/x4/import_changes.sh "NO_SCREEN"
        #fi
        
        if [ "$MOR_MAPPED_VERSION_WEIGHT" -ge "150" ]; then
            mysql mor < /usr/src/mor/test/node2/db/x4.sql
            report "Running /usr/src/mor/db/x5/import_changes.sh" 3
            /usr/src/mor/db/x5/import_changes.sh "NO_SCREEN"
        fi

        mysql mor < /home/mor/selenium/mor_trunk_testdb.sql
        
        /usr/src/mor/sh_scripts/asterisk/db/import_changes.sh   # For asterisk 1.8

	echo "Exporting prepared db to ramdisk"
	mkdir -p /home/ramdisk
	mysqldump -h localhost -u mor -pmor mor > /home/ramdisk/mor.sql
}

#------------------------------------------
import_db(){
	echo "Importing test mor database from /home/ramdisk/mor.sql";
	mysql mor < /home/ramdisk/mor.sql
}



#------------------------------------------
#------------------------------------------
dir_exists()
{
   if [ -d "$1" ];
			then
					[ $dbg == 1 ] && echo "$1 is dir";
					return 0;
      else return 1;
   fi
}



#-------------------------------------------
_mor_time()
{
	mor_time=`date +%Y\-%0m\-%0d\_%0k\:%0M\:%0S`;
}

svn_update()
{
    #   About:  This method updates from SVN and also ensures that update will be successful, if not - attempts to cleanup the repo
    #
    #   Arguments:
    #       $1 - path to update via SVN
    #
    #   Example:
    #       svn_update /usr/src/mor
    
    local PATH_TO_UPDATE="$1"
    cd $PATH_TO_UPDATE
    svn update $PATH_TO_UPDATE
    if [ "$?" != "0" ]; then
        cd $PATH_TO_UPDATE
        svn cleanup
        svn update
    fi
}


#--------------------------------------------
check_if_there_is_available_new_revision()
{
    #   About:  This function checks if a new revision is available, if yes and and all previously failed tests are already tested - current revision testing is canceled.

    REPO_CURRENT_REVISION=`svn info http://svn.kolmisoft.com/mor/gui/branches/$MOR_VERSION_YOU_ARE_TESTING_FOR_TESTS |  grep "Changed Rev:" | awk '{print \$NF}'`

    if [ "$REPO_CURRENT_REVISION" -gt "$CURRENT_REVISION" ]; then
        echo "Found new revision in repository, killing current revision testing and starting new one"
        echo "New revision found. Aborting current revision: $CURRENT_REVISION. Will start: $REPO_CURRENT_REVISION" >> /var/log/mor/current_test
        rm -rf /tmp/.mor_test_is_running    # cleaning the lock
        exit 0
    fi
}




#   About:  This function prepares the queue by ordering the tests that failed tests would be tested at the beginning

prepare_new_queue()
{


    rm -rf /var/log/mor/queue
    touch /var/log/mor/queue

    # 1. adding first_test tests from svn
    if [ -f /home/mor/selenium/test_first ]; then
        FILE="/home/mor/selenium/test_first"
        exec < $FILE
        while read testas; do
            if [ -f "$testas" ]; then
                echo $testas >> /var/log/mor/queue
            else
                echo "/home/mor/selenium/test_first (maintained by programmers) contains incorrect test names or paths. Path $testas does not exist in file system, skipped adding to queue: /var/log/mor/queue"
            fi
        done
    fi



    # 2. adding failed tests from previous test-run
    if [ -f /var/log/mor/failed_tests ]; then
        cat /var/log/mor/failed_tests >> /var/log/mor/queue
        #deleting failed tests so they do not accumulate, e.g. will test first only tests which failed from last revision
        rm -fr /var/log/mor/failed_tests
    else
        touch /var/log/mor/queue # why we touch this file here??
    fi
    touch /var/log/mor/failed_tests


    # 3. sort random first part of queue to speedup initial tests so nodes would nod do all the same tests at the same time
    for i in `cat /var/log/mor/queue`; do echo "$RANDOM $i"; done | sort | sed -r 's/^[0-9]+ //' > /var/log/mor/queue_random
    rm -fr /var/log/mor/queue
    mv /var/log/mor/queue_random /var/log/mor/queue



    # X. adding recently changed tests in svn
    #    cd /home/mor/selenium
    #    svn diff --summarize -r28160:28168
    #    atmesti tuos, kurie prasideda D (deleted)
    #    imti -10 reviziju
    # todo...

    echo "success" >> /var/log/mor/queue # from this point it is assumed that later tests previously were successful


    # 4. adding remaining tests in random order
    # DISABLED, we will ask BRAIN for test to test

#    TEST_DIR=/home/mor/selenium/tests
#    find $TEST_DIR -name "*.case" > /tmp/tests
#    for i in `cat /tmp/tests`; do echo "$RANDOM $i"; done | sort | sed -r 's/^[0-9]+ //' > /tmp/randomized_tests    # Magic line to randomize lines order in filesssss
#    rm -rf /tmp/tests

#    FILE="/tmp/randomized_tests"
#    exec < $FILE
#    while read testas; do
#        TEST_DIR_LENGTH=${#TEST_DIR}+1
#        TEST_FIRST_LETTER=${testas:$TEST_DIR_LENGTH:1}
#        POSITION_IN_ARRAY=`expr index "$TESTS_STARTS_WITH" $TEST_FIRST_LETTER`

#        if [ "$POSITION_IN_ARRAY" != "0" ]; then
#            if [ `grep "$testas" /var/log/mor/queue | wc -l` == "0" ]; then  #not found in current queue
#                echo "Adding test: $testas to queue /var/log/mor/queue"
#                echo "$testas" >> /var/log/mor/queue
#            else
#                echo "$testas is already in queue with higher priority"
#            fi
#        fi
#    done

    # remove duplicates in whole file but keep same test order
    awk '!x[$0]++' /var/log/mor/queue > /var/log/mor/queue_nodups
    rm -fr /var/log/mor/queue
    mv /var/log/mor/queue_nodups /var/log/mor/queue

}



run_all_rb()
{
        rm -rf /tmp/mor_session.log /tmp/session.log.tar.gz
        mkdir -p  /usr/local/mor/backups/restore /home/mor/tmp
        touch /tmp/mor_session.log 
		chmod -R 777 /tmp/mor_session.log /usr/local/mor/backups/restore /home/mor/tmp

		# in case there were gem changes
		# takes ~24s if there none
                cd /home/mor
                bundle update
		/etc/init.d/httpd restart

		echo -e "REVISION: $CURRENT_REVISION\nLAST AUTHOR: $LAST_AUTHOR">>$report
                echo "Converting files which starts with: $TESTS_STARTS_WITH"

                prepare_new_queue   #preparing new test queue, failed tests are tested first

                check_for_new_rev_on_every_test="0"

                FILE="/var/log/mor/queue"
                exec < $FILE
                while read testas;  do
                    #---- Check if there is available new revision
                    if [ "$testas" == "success" ]; then
                        check_for_new_rev_on_every_test=1
                        continue
                        #break
                    fi

                    if [ "$check_for_new_rev_on_every_test" == "1" ]; then
                        check_if_there_is_available_new_revision
                        echo "OK $testas" >> /var/log/mor/current_test
                    else
                        echo "FAILED $testas" >> /var/log/mor/current_test
                    fi


                    # ----------------------------- Failed test worth testing --------------------

		    original_test="$testas" # saving original test from loop

		    
		    number=$RANDOM
		    let "number %= 3"
		    if [ $number == "0" ]; then
			# 1 out of 3 times check for failed tests to avoid all nodes testing FAILED test at the same time
		    
                	# Checking if test exists in file system
                	if [ ! -f "$testas" ]; then
                    	echo "Test $testas does not exist on file system, skipping"
                	    continue
            	        fi
                        JOB_RECEIVED_TIMESTAMP=`date +%s`
                        JOB_RECEIVED_HUMAN=`date +%Y\-%-m\-%-d\ %-k\:%-M\:%-S`
	                another_java_instance   #check for another java instance - kill this script if found
		        actions_before_new_test
        	        dir_exists testas; #checking whether we have path to dir or file
            		if [ $? == 0 ]; then continue; fi; #let's do another circle, nothing to do with dir..

		        # checking for failed test worth testing
		        get_failed_test_to_retest result $CURRENT_REVISION $DEFAULT_INTERFACE_MAC $DEFAULT_IP $MOR_VERSION_YOU_ARE_TESTING_FOR_TESTS
		        len=${#result}
		        if [ $len != "0" ]; then
		    	echo -e "\e[40m\e[96mFailed test worth testing: $result \e[0m"
		            testas="/home/mor/selenium/tests/$result"
			    test_one_test
		        else
			    echo -e "\e[40m\e[96mNo failed tests worth testing \e[0m"
			fi
	
		    else
			# skipping FAILED test checking
			echo -e "\n\e[40m\e[96mSkipping failed test checking \e[0m"
		    fi


		    # --------------------------------------- Normal test from Queue ------------------------

		    # loop which runs test 3 times, with a hope to get OK
		    # this is done to avoid messing with selenium-ajax issue where test sometimes fails because selenium cannot properly test ajax
                    #for i in 1 2 3 # NEVER EVER CHANGE THIS TO MORE THAN 3 - WASTE OF TIME
                    #do


		    testas="$original_test"

                    # Checking if test exists in file system
                    if [ ! -f "$testas" ]; then
                        echo "Test $testas does not exist on file system, skipping"
                        continue
                    fi
                    JOB_RECEIVED_TIMESTAMP=`date +%s`
                    JOB_RECEIVED_HUMAN=`date +%Y\-%-m\-%-d\ %-k\:%-M\:%-S`
                    another_java_instance   #check for another java instance - kill this script if found
                    actions_before_new_test
                    dir_exists testas; #checking whether we have path to dir or file
                    if [ $? == 0 ]; then continue; fi; #let's do another circle, nothing to do with dir..


			echo
			echo "Starting test: $testas"

			# checking if test is not yet tested OK (or broken on 3+ nodes, so not worth testing anymore), skip if true
			TEST_NAME="${testas:25:${#testas}-1}"
			check_if_test_not_tested result $TEST_NAME $CURRENT_REVISION $MOR_VERSION_YOU_ARE_TESTING_FOR_TESTS
			if [ "$result" == "1" ];then
			    echo -e "\e[40m\e[96mTest is already tested! (or not worth testing anymore): $TEST_NAME\e[0m"
			    #break
			else
			    echo -e "\e[40m\e[96mTest needs to be tested: $TEST_NAME\e[0m"
			    test_one_test
			fi

			

			#clean_ram  #only for FAILED test to be more sure environment is clean with hope retest would help

		    #end for loop which runs test for 3 times till OK
                    #done

                done



		# --------------------------------------- Remaining tests from BRAIN ------------------------

                while true;  do

                    check_if_there_is_available_new_revision

		    # checking for test worth testing
		    get_test_to_test result $CURRENT_REVISION $DEFAULT_INTERFACE_MAC $DEFAULT_IP $MOR_VERSION_YOU_ARE_TESTING_FOR_TESTS

		    len=${#result}
		    if [ $len != "0" ]; then
			echo -e "\e[40m\e[96mTest worth testing: $result \e[0m"
			testas="/home/mor/selenium/tests/$result"
			
            	        # Checking if test exists in file system
                	if [ ! -f "$testas" ]; then
                    	    echo "Test $testas does not exist on file system, skipping"
                    	    continue
                	fi
                	JOB_RECEIVED_TIMESTAMP=`date +%s`
                	JOB_RECEIVED_HUMAN=`date +%Y\-%-m\-%-d\ %-k\:%-M\:%-S`
                	another_java_instance   #check for another java instance - kill this script if found
                	actions_before_new_test
                	dir_exists testas; #checking whether we have path to dir or file
                	if [ $? == 0 ]; then continue; fi; #let's do another circle, nothing to do with dir..
			
			test_one_test
		    else
		        echo -e "\e[40m\e[96mNo more tests worth testing (or BRAIN unreachable) \e[0m"
		        break
		    fi

		done

                mv /var/log/mor/time /var/log/mor/time_previous
                touch /var/log/mor/time

		echo -e "Report was generated...\nReport was saved to $report\n";

		echo -e "\e[40m\e[93mFINISHED ALL TESTS FOR CURRENT REVISION: $CURRENT_REVISION \e[0m\n"


}


test_one_test()
{

                	import_db   # creating thread dropping and importing a fresh database

                	echo "Proceeding test: $testas"
                	TMP_FILE=`mktemp`

                	# cleanup
                	rm -rf /home/mor/public/ad_sounds/*.wav /tmp/rezultatas.html /tmp/mor_pdf_test.pdf 
                	# cleaning test IVR files
                	find /home/mor/public/ivr_voices/* -name "*test*" | xargs rm -rf
                        find /home/mor/public/ivr_voices/* -name "*test*"  >> $TMP_FILE #logging output to log file in order programmers and testers would be able to debug if uploaded ivr sound files were properly deleted
                        #-----
                        ORIGINAL_TEST="$testas"
                        special_test_cases $testas # This function is required for very special cases when it's not possible to write tests for special cases for example for the first day of the month. What this function does - it launches alternative test in such case.
                        #-----
                	
                        TEST_NAME=`echo "$testas" | awk -F "/" '{print $NF}' |  awk -F "." '{print $1}'`
                	TEST_TEST="$testas"

                	generate_suite_file $TEST_NAME $TEST_TEST

                	# Here is is very important part - the script adds here at the beginning of test new command setTimeout which sets timeout for each command in the test. 60000 = 60 seconds

                	sed -e 's/<\/thead><tbody>/<\/thead><tbody>\n<tr>\n<td>setTimeout<\/td>\n<td>10000<\/td>\n<td><\/td>\n<\/tr>/g' $TEST_TEST > /tmp/$TEST_NAME.html

			echo "Waiting for background jobs to complete"
                	wait

                	# "Restarting/reloading apache and warming up the application"
                	restart_services_if_not_enough_ram      #to do: later he add procedures to track tests which eat up all ram
                	initialize_ror

                	echo "Starting Selenium"
                	SELENIUM_START_TIMESTAMP=`date +%s`
                	SELENIUM_START_HUMAN=`date +%Y\-%-m\-%-d\ %-k\:%-M\:%-S`
                	echo "$JOB_RECEIVED_HUMAN - Started to prepare VM for $testas" >> /var/log/mor/time
                	echo "$SELENIUM_START_HUMAN - Selenium start" >> /var/log/mor/time

                	# run the test
                        default_interface_ip    #getting IP each time - because if DHCP changes the IP - the whole revision will fail
                        
                        if [ "$ENABLE_PERFORMANCE_LOGGING" == "1" ]; then
                            log_performance_metrics "Performance metrics before test: $testas"
                        fi

		        # rand fix - removes lag between tests
		        sudo mv /dev/random /dev/random.real
		        sudo ln -s /dev/urandom /dev/random

                	DISPLAY=:0 /usr/local/mor/test_environment/jre1.6.0_13/bin/java -jar /dev/shm/selenium-server-standalone-$SELENIUM_SERVER_VERSION.jar  -userExtensions /usr/src/mor/test/files/selenium/user-extensions.js -timeout 600 -singleWindow -htmlSuite "*firefox" "http://$DEFAULT_IP" "/tmp/suite.html" "/tmp/rezultatas.html"
                        testas="$ORIGINAL_TEST"
                        TEST_TEST="$ORIGINAL_TEST"

                	SELENIUM_FINISH_TIMESTAMP=`date +%s`
                	SELENIUM_FINISH_HUMAN=`date +%Y\-%-m\-%-d\ %-k\:%-M\:%-S`
                	echo "$SELENIUM_FINISH_HUMAN - Selenium end" >> /var/log/mor/time
                	echo "Selenium finished."
                        
                        if [ "$ENABLE_PERFORMANCE_LOGGING" == "1" ]; then
                            log_performance_metrics "Performance metrics after test: $testas"
                        fi
                    

                	if [ ! -f /tmp/rezultatas.html ]; then
                    	    echo "Something went wrong -  /tmp/rezultatas.html does not exist. Cancelling this machine tests"
                    	    clean_ram
                    	    exit 0
                	fi

                	#echo -ne "Time log for all tests in this machine:\n\nhttp://$DEFAULT_IP/time\n\n" >> $TMP_FILE
                	cat /tmp/rezultatas.html >> $TMP_FILE

                	# check if test is OK or FAILED, finish if OK
                	grep -v -F "^warn: Current subframe appears" $TMP_FILE | grep "^error:\|^warn:"   &> /dev/null
                	if [ "$?" == "0" ]; then

                    	    #reporting job to BRAIN
                    	    job_report $testas >> /var/log/mor/n &     #moving job reporting to separate thread

                	    echo "Test Status $i: FAILED..." >> /var/log/mor/time
                	    echo -e "\e[41m\e[97mFAILED $testas\e[0m"
                	    #clean_ram
                            
                	else
                	    echo "Test Status $i: OK!" >> /var/log/mor/time
                	    echo -e "\e[42m\e[97mOK $testas\e[0m"

                    	    #reporting job to BRAIN
                    	    job_report $testas >> /var/log/mor/n &    #moving job reporting to separate thread

                    	    # get out of loop because we have OK!
                    	    #break
                	fi

                        # separate visually test logs
                        echo "" >> /var/log/mor/time

}



#=====================
delete_all_rb()
{
	echo "Deleting stale *.rb files";
		find $TEST_DIR -name "*.rb" | sort | while read testas
		do
			dir_exists testas; #checking whether we have path to dir or file
			if [ $? == 0 ]; then continue; fi; #let's do another circle, nothing to do with dir..'

			rm -rf $testas
		done
		echo "All stale *rb files were deleted";
}



#=====================================================================
last_directory_in_the_path()
{
	last_dir_in_path=`pwd | awk -F\/ '{print $(NF)}'`;
}



#===========================MAIL======================================
send_report_by_email()	{
	if [ -f "$SEND_EMAIL" ]; then

		if [ "$STATUS" == "OK" ]; then
			$SEND_EMAIL -f mor_tests@kolmisoft.com -t $E_MAIL_RECIPIENTS -u "[$STATUS][MOR TESTS $SERVER_NAME $MOR_VERSION_YOU_ARE_TESTING] $CURRENT_REVISION $mor_time" -m "REVISION: $CURRENT_REVISION  LAST AUTHOR: $LAST_AUTHOR  STATUS: $STATUS     `cat $report`" -a /tmp/session.log.tar.gz  $EMAIL_SEND_OPTIONS > /tmp/mor_temp

		elif [ "$STATUS" == "FAILED" ]; then
			$SEND_EMAIL -f mor_tests@kolmisoft.com -t $E_MAIL_RECIPIENTS -u "[$STATUS][MOR TESTS $SERVER_NAME $MOR_VERSION_YOU_ARE_TESTING] $CURRENT_REVISION $mor_time" -m "REVISION: $CURRENT_REVISION  LAST AUTHOR: $LAST_AUTHOR  STATUS: $STATUS `cat $report`" -a  /tmp/session.log.tar.gz -a $MOR_CRASH_LOG $EMAIL_SEND_OPTIONS > /tmp/mor_temp
		fi

		else echo "$SEND_EMAIL NOT FOUND!";
	fi

	if [ $? == 0 ]; then echo "Email was sent"; fi
}



#=====================================================================
skip_failed_test()
{
    #   About: This function checks if this test was converted successfully - if not - forces to skip the test (problem was already reported)

    grep "$testas" /tmp/failed_conversions   &> /dev/null
    if [ "$?" == "0" ]; then
        echo "$testas was not converted successfully, skipping"
        continue;
    fi
}



convert_html_cases_to_rb()
{

	echo "Converting files which starts with: $TESTS_STARTS_WITH"

	find $TEST_DIR -name "*.case" | sort | while read testas
		do

			TEST_DIR_LENGTH=${#TEST_DIR}+1
			TEST_FIRST_LETTER=${testas:$TEST_DIR_LENGTH:1}
			POSITION_IN_ARRAY=`expr index "$TESTS_STARTS_WITH" $TEST_FIRST_LETTER`

			if [ $POSITION_IN_ARRAY != "0" ] ; then

			    dir_exists testas; #checking whether we have path to dir or file
			    if [ $? == 0 ]; then continue; fi; #let's do another cicle, nothing to do with dir..'
			    echo "Converting test: $testas"
                            TEMP=`/bin/mktemp`
			    /usr/local/mor/mor_ruby /home/mor/selenium/converter/converter.rb -h "http://$1" $testas &> /tmp/test_convert_error

                            grep "flunk\|converter.rb\|syntax error" /tmp/test_convert_error &> /dev/null

                            if [ "$?" == "0" ]; then    #error was found!
                                #===report to brain
                                if [ -f /usr/src/mor/test/cluster1/x5/brain-scripts/reporter.rb ]; then
                                    RELATVE_PATH_TO_TEST=`echo $testas | sed 's/\/home\/mor\/selenium\/tests\///'`

                                    local counter=0;
                                    while [ "$counter" != "5" ]; do
                                        counter=$(($counter+1))
                                        local temp=`mktemp`

                                        local result=`/usr/local/mor/mor_ruby /usr/src/mor/test/cluster1/x5/brain-scripts/reporter.rb $MOR_VERSION_YOU_ARE_TESTING $CURRENT_REVISION $RELATVE_PATH_TO_TEST "FAILED" "test_log /tmp/test_convert_error" | tee -a $temp /tmp/reporter.log`

                                        grep "RECEIVED" $temp &> /dev/null
                                        if [ "$?" == "0" ]; then
                                            rm -rf $temp $TMP_FILE
                                            break;
                                        fi

                                        rm -rf $temp
                                        sleep $((3*$counter))   #will wait incrementally: 0, 3, 6, 12, 15 seconds..
                                    done
                                else
                                    echo "The reporter script was not found"
                                fi
                                echo "$testas" >> /tmp/failed_conversions
                            fi
                        #======

                        rm -rf /tmp/test_convert_error    # cleanup
                        #================================
			else
			    echo "Skipping file: $testas"
			fi

		done

}



#====================================================================
is_another_test_still_running()
{
	if [ -f "$TEST_RUNNING_LOCK" ]; then
		echo "$mor_time Another test is already running, exiting";
		exit 0;
	fi
}



check_if_test_not_tested()
{

    local TEST="$2"
    local REVISION="$3"
    local VERSION="$4"

    echo "Checking if test worth testing: $TEST, Revision: $REVISION, Version: $VERSION"

    local work=`/bin/mktemp`
    echo "0" > work
    
    if [ "$TEST" != "" ] && [ "$REVISION" != "" ] && [ "$VERSION" != "" ]; then
	#echo "[`date +%0k\:%0M\:%0S`] PS ID: $$. curl http://brain.kolmisoft.com/api/test_tested_ok?version=$VERSION&revision=$REVISION&test=$TEST"
	curl -s "http://brain.kolmisoft.com/api/test_tested_ok?version=$VERSION&revision=$REVISION&test=$TEST" > work
    fi

    local  __result=$1
    local  myresult=`cat work`
    eval   $__result="'$myresult'"

    rm -rf $work
}



get_failed_test_to_retest()
{

    local REVISION="$2"
    local MAC="$3"
    local IP="$4"
    local VERSION="$5"

    echo
    echo "Checking for failed test worth testing - Revision: $REVISION, MAC: $MAC, IP: $IP, Version: $VERSION"

    local work=`/bin/mktemp`
    echo "0" > work
    
    if [ "$REVISION" != "" ] && [ "$MAC" != "" ] && [ "$IP" != "" ] && [ "$VERSION" != "" ]; then
	#echo "[`date +%0k\:%0M\:%0S`] PS ID: $$. curl http://brain.kolmisoft.com/api/test_failed_to_retest?version=$VERSION&revision=$REVISION&mac=$MAC&ip=$IP"
	curl -s "http://brain.kolmisoft.com/api/test_failed_to_retest?version=$VERSION&revision=$REVISION&mac=$MAC&ip=$IP" > work
    fi

    local  __result=$1
    local  myresult=`cat work`
    eval   $__result="'$myresult'"

    rm -rf $work
}


get_test_to_test()
{

    local REVISION="$2"
    local MAC="$3"
    local IP="$4"
    local VERSION="$5"

    echo
    echo "Checking for test worth testing - Revision: $REVISION, MAC: $MAC, IP: $IP, Version: $VERSION"

    local work=`/bin/mktemp`
    echo "0" > work
    
    if [ "$REVISION" != "" ] && [ "$MAC" != "" ] && [ "$IP" != "" ] && [ "$VERSION" != "" ]; then
	#echo "[`date +%0k\:%0M\:%0S`] PS ID: $$. curl http://brain.kolmisoft.com/api/test_request?version=$VERSION&revision=$REVISION&mac=$MAC&ip=$IP"
	curl -s "http://brain.kolmisoft.com/api/test_request?version=$VERSION&revision=$REVISION&mac=$MAC&ip=$IP" > work
    fi

    local  __result=$1
    local  myresult=`cat work`
    eval   $__result="'$myresult'"

    rm -rf $work
}


#====================================MAIN============================
_mor_time;




if [ -z "$1" ];
	then
		echo -e "\n\n=========MOR TEST ENGINE CONTROLLER=======";
		echo "Arguments:";
		echo -e "\t-a \tUpgrades GUI, resets a database, runs all tests, sends the report by email.";
		echo -e "\t-i \tGives you a fresh database, by importing $PATH_TO_DATABASE_SQL";
		echo -e "\t-d \tNOT USED ANYMORE - Dumps a current database state to $DIR_TO_STORE_DATABASE_DUMPS";
		echo -e "\t-r \tNOT USED ANYMORE - Dumps a current database state to $DIR_TO_STORE_DATABASE_DUMPS and replaces the default database file $PATH_TO_DATABASE_SQL \n";
		echo -e "\t-s \tStart a Selenium RC server\n";
		echo -e "\t-t \tFor testing\n";

	elif [ "$1" == "-t" ]; then  #test mode

		# test random number
#		number=$RANDOM
#		let "number %= 3"
#		echo $number
#		if [ $number == "0" ]; then
#		    echo "lets do some work"
#		else
#		    echo "skipping"
#		fi


                while true;  do
		    echo "break from second while"
		    break

		done


		get_test_to_test result "44778" "00:0C:29:EE:75:B6" "192.168.0.116" "x5"
		echo $result


		# get failed test to retest
#		get_failed_test_to_retest result "44613" "00:0C:29:EE:75:B6" "192.168.0.197" "x5"
#		echo $result

		# test string length
#			len=${#result}
#			echo "len: $len"
#			if [ $len != "0" ]; then
#			    testas="$result"
#			    test_one_test
#			    echo "LETS TEST! $testas"
#			else
#			    echo "length 0"
#			fi


#		echo "============"

		# check if test is worth testing
#		check_if_test_not_tested result "accountant_permissions/accountant_fake_form.case" "44610" "x5"
#		echo $result
#		if [ "$result" == "1" ];then
#		    echo "test is tested!"
#		else
#		    echo "test needs to be tested"
#		fi

#                svn_update /usr/src/mor




		echo "Test finished"

	elif [ "$1" == "-a" ]; then  #do all tasks


		# ----------- clean huge mess in /home/mor after this $%^&* test /last_calls_stats/export_last_calls.case --------
	        # DISABLED because it does not repeat itself and this cleaning procedure messes up Gemfiles
	        
	        # saving necessary files
	        #cd /home/mor
	        #cp gui_upgrade.sh /tmp
	        #cp gui_upgrade_light.sh /tmp
	        #cp config.ru /tmp
	        #cp assets.log /tmp
	        #cp Rakefile /tmp
	        #cp Gemfile /tmp
	        #cp Gemfile.lock /tmp
	        #cp README.rdoc /tmp
		
		# clean #$%^&* mess
		#find /home/mor -type f -maxdepth 1 -delete >> /dev/null
		
	        # move files back
	        #cd /tmp
	        #cp gui_upgrade.sh /home/mor
	        #cp gui_upgrade_light.sh /home/mor
	        #cp config.ru /home/mor
	        #cp assets.log /home/mor
	        #cp Rakefile /home/mor
	        #cp Gemfile /home/mor
	        #cp Gemfile.lock /home/mor
		#cp README.rdoc /home/mor
		#chmod /home/mor/Gemfile.lock
		
		# ---------- end of #$%^&* mess cleaning ------------

		URL="$2" #saving second parameter before it gets overwritten by set command

                # update testing script
                svn_update /usr/src/mor

		is_another_test_still_running #if another instance is running - script will terminate.

                rm -rf /usr/local/mor/backups/db_dump* 
                mor_gui_current_version
		touch "$TEST_RUNNING_LOCK"  #creating the lock

                killall java  &> /dev/null      #ensuring that no other Java instances are running
                copy_selenium_to_ram_if_not_present
                rm -rf /tmp/failed_conversions
                default_interface_ip    #getting this node IP


		chmod +x /usr/bin/mor
    		chmod -R 777 /home/mor/public/ivr_voices

    		#-- Updating backup scripts
    		cp -fr /usr/src/mor/sh_scripts/backup/make_restore.sh /usr/local/mor/make_restore.sh
    		cp -fr /usr/src/mor/sh_scripts/backup/make_backup.sh /usr/local/mor/make_backup.sh

		rm -rf /tmp/mor_crash.log
		echo -e "\n------\n" >> /var/log/mor/selenium_server.log
		touch /tmp/mor_crash.log /tmp/mor_debug_backup.txt
		chmod -R 777 /tmp/mor_crash.log /tmp/mor_debug_backup.txt /usr/local/mor/backups

    		#if [ -d /home/mor/app/assets ]; then
        	#    chmod -R 777 /home/mor/app/assets
    		#fi

		svn status /home/mor | grep "app\|selenium" | awk '{print $2}' | xargs rm -rf      #clean old trash if any

                svn_update /home/mor
                
                touch /tmp/mor_debug.log  /tmp/new_log.txt
                chown -R apache: /home/mor /tmp/mor_debug.log  /tmp/new_log.txt
                
                

		# this file should be empty and readable
                rm -fr /home/mor/Gemfile.lock
                touch /home/mor/Gemfile.lock
                chmod 666 /home/mor/Gemfile.lock

		set $(cd /home/mor/ && svn info | grep "Last Changed Rev") &> /dev/null
		CURRENT_REVISION="$4";  #newest

		set $(cat "$LAST_REVISION_FILE" | tail -n 1 ) &> /dev/null


		LAST_REVISION=$2;

		set $(cd /home/mor/ && svn info | grep "Last Changed Author:");
		LAST_AUTHOR="$4"

		[ $dbg == 1 ] && echo "Current revision: $CURRENT_REVISION";
		[ $dbg == 1 ] && echo "Last revision: $LAST_REVISION";
		[ $dbg == 1 ] && echo "Last author: $LAST_AUTHOR";


            if [ "$CURRENT_REVISION" != "$LAST_REVISION" ] || [ "$MODE" == "0" ]; then
                [ $dbg == 1 ] && echo "Versions didn't matched, running the tests"
                /etc/init.d/httpd stop
                killall -9 httpd #yeah, I don't trust scripts
                /etc/init.d/httpd start
                

                report="$DIR_FOR_LOG_FILES/$LOGFILE_NAME.$mor_time.txt"
                prepare_db;

                echo "House cleaning...."
                # turn off swap and kill some nasty stuff
                house_cleaning 
                echo "Initiating apache/compiling ror..."

                run_all_rb "$URL";

                # house cleaning
                house_cleaning 
                restart_services_if_not_enough_ram

                rm -fr /tmp/CGI* /tmp/file* /tmp/_sox* /tmp/tmp.* /tmp/*.json.part /tmp/*.pdf.part

                finish_time=`date +%Y\-%0m\-%0d\_%0k\:%0M\:%0S`;
                echo "Started: $mor_time      Finished: $finish_time"
                echo "Started:  $mor_time" >> $report
                echo "Finished: $finish_time" >> $report
                echo "Processed tests starting with: $TESTS_STARTS_WITH" >> $report

                #====checking for errors or failures
                grep "Error:" $report
                if [ "$?" == "0" ]; then
                        STATUS="FAILED";
                        else STATUS="OK";
                fi

                grep "Failure:" $report
                if [ "$?" == "0" ]; then STATUS="FAILED"; fi
                #===================================


		# clean /tmp folder
		rm -fr /tmp/*.html
		rm -fr /tmp/*.csv
		rm -fr /tmp/tmp*
		rm -fr /tmp/Rack*
		rm -fr /tmp/Last*
		rm -fr /tmp/import*
		rm -fr /tmp/Country*
		rm -fr /tmp/*tar.gz
		rm -fr /tmp/_sox.txt*
		rm -fr /tmp/file*
		rm -fr /tmp/*,
		rm -fr /tmp/*.part


                #----- put session log to email
                #if [ -f /tmp/mor_session.log ]; then
                #    echo -e "\n\n=========== SESSION LOG ===================" >> $report
                #    tar czf /tmp/session.log.tar.gz /tmp/mor_session.log
                #else
                #    echo -e "\n\n\nSession log /tmp/mor_session.log not found" >> $report
                #fi
                #-----

                #send_report_by_email;
                echo -e "$mor_time\t$CURRENT_REVISION\t\t$LAST_AUTHOR\t$STATUS" >> $LAST_REVISION_FILE
            fi

            rm -rf "$TEST_RUNNING_LOCK";
            if [ "$?" != "0" ]; then echo "$mor_time Failed to delete $TEST_RUNNING_LOCK lock"; fi;

	elif [ "$1" == "-l" ]; then
                #
                # This option is used for development only. It updates MOR GUI, imports clean DB for current GUI version, cleans old uploaded stuff like ivr sound files, cleans logs.
                #
                # Usage /usr/src/mor/test/cluster1/12.126/mor_test_run.sh -l
                

                actions_before_new_test # cleanup

                svn_update /usr/src/mor
                mor_gui_current_version

                svn status /home/mor | grep "app\|selenium" | awk '{print $2}' | xargs rm -rf      #clean old trash if any                mor_gui_current_version
                svn_update /home/mor
		svn co http://svn.kolmisoft.com/mor/gui/branches/$MOR_VERSION_YOU_ARE_TESTING_FOR_TESTS /home/mor

                chmod +x /usr/bin/mor
                chmod -R 777 /home/mor/public/ivr_voices
                rm -rf /tmp/mor_crash.log
                touch /tmp/mor_crash.log
                chmod -R 777 /tmp/mor_crash.log /tmp/mor_debug_backup.txt /usr/local/mor/backups
                #if [ -d /home/mor/app/assets ]; then
                #    chmod -R 777 /home/mor/app/assets
                #fi

                rm -fr /home/mor/Gemfile.lock
                touch /home/mor/Gemfile.lock
                chmod 666 /home/mor/Gemfile.lock
                wait    # we need results of threads here.

		prepare_db;

		/etc/init.d/httpd restart

	elif [ "$1" == "-i" ]; then
         svn co http://svn.kolmisoft.com/mor/install_script/trunk/ /usr/src/mor
	    	import_db; 	#import
	elif [ "$1" == "-b" ]; then   #RUN BETA TESTS
				is_another_test_still_running #if another instance is running - script will terminate.
				touch "$TEST_RUNNING_LOCK"  #creating the lock

				rm -rf "$TEST_RUNNING_LOCK";
				if [ "$?" != "0" ]; then echo "$mor_time Failed to delete $TEST_RUNNING_LOCK lock"; fi;
	elif [ "$1" == "-d" ]; then   # prepare db
		import_db #reimports db
	elif [ "$1" == "-di" ]; then   # import db
				import_db;
	elif [ "$1" == "-s" ]; then
			start_selenium_server;


fi
