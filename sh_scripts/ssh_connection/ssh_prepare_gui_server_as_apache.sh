#! /bin/sh

# this script should be executed on server FROM which will be connecting (e.g. GUI in MOR system)
# authorized_keys should be put into server TO which will be connecting

localip=`ifconfig | awk '/inet addr:/ {print $2}' | awk '{split ($0,a,":"); print a[2]}' | awk '{split ($0,a,"127."); print a[1]}'` 

# do not delete if already generated

if [ -a "/var/www/.ssh/id_rsa" ]; then

    echo "Key exists"

else

    rm /var/www/.ssh/id_rsa
    rm /var/www/.ssh/id_rsa.pub

    # LOGIN AS APACHE!!! su apache

    ssh-keygen -t rsa

    # LOGOUT AS APACHE!!! exit

fi

chmod 700 /var/www/.ssh

cp /var/www/.ssh/id_rsa.pub /var/www/html

echo 
echo 
echo "http://$localip/id_rsa.pub ready" 
echo "DO NOT FORGET TO REMOVE /var/www/html/id_rsa.pub file after you copy it to other server!!!" 

read