#!/bin/sh
#--------------------------------Config--------------------------------#

# Server's name
SERVER="Server name"

# Backup directory
BACKDIR=/home/server/backups

# Temp directory
TEMPDIR=/home/server/backups/temp

# Date format filename's
#DATENAME=`date +'%y-%m-%d__%H-%M-%S__%N'`
DATENAME=`date +'%d'`

# Date format log's
DATELOG=`date +'%Y-%m-%d %H:%M:%S'`

# Date format log file's, spilit by this format
DATELOG_FILES=`date +'%Y_%m_%d'`

# MySQL server
HOST=localhost

# MySQL username
USER=username

# MySQL password
PASS=password


# List all of the MySQL databases that you want to backup, separated by a space
# set to 'ALL' if you want to backup all your databases
DBS="database1 database2 database3"



# SCP
SCP_SERVER="188.72.235.249"

#SCP username
SCP_USER="user_scp"

#SCP password
#SCP_PASS="pass_scp"

#SCP location
SCP_LOC="/home/server/backups/daily"
#======================================================================#


echo "========================================================="
echo $SERVER" | Daily"
echo "Date:   "$DATELOG
echo "---------------------------------------------------------"

# check of the backup directory exists
# if not, create it
if  [ ! -d $BACKDIR ]; then
        echo "\n[$(date "+"%H:%M:%S"")] Creating $BACKDIR: "
        mkdir -p $BACKDIR
        echo "\n[$(date "+"%H:%M:%S"")] Done"
fi

# check of the temp directory exists
# if not, create it
if  [ ! -d $TEMPDIR ]; then
        echo "\n\n[$(date "+"%H:%M:%S"")] Creating $TEMPDIR: "
        mkdir -p $TEMPDIR
        echo "\n[$(date "+"%H:%M:%S"")] Done"
fi




if  [ $DBS = "ALL" ]; then
        echo "\n\n[$(date "+"%H:%M:%S"")] Creating list of all your databases: "
        DBS=`mysql -h $HOST --user=$USER --password=$PASS -Bse "show databases;"`
        echo "\n[$(date "+"%H:%M:%S"")] Done"
fi



echo "\n\n[$(date "+"%H:%M:%S"")] Backing up MySQL databases... "
for database in $DBS
do
        echo "\n[$(date "+"%H:%M:%S"")] Database $database: "
        mysqldump -h $HOST -u$USER -p$PASS --opt $database > $TEMPDIR/$database.sql
        echo "\n[$(date "+"%H:%M:%S"")] Done"
done

echo "\n\n[$(date "+"%H:%M:%S"")] Make tar: "
cd $TEMPDIR
tar -cvf $BACKDIR/$DATENAME.tar *.sql /var/www/ /var/vmail/
#tar -cvf $BACKDIR/$DATENAME.tar *.sql
echo "\n[$(date "+"%H:%M:%S"")] Successfully store backup"

echo "\n\n[$(date "+"%H:%M:%S"")] SCP: "
scp $BACKDIR/$DATENAME.tar $SCP_USER@$SCP_SERVER:$SCP_LOC/$DATENAME.tar
#echo $BACKDIR/$DATENAME.tar $SCP_USER@$SCP_SERVER:$SCP_LOC/$DATENAME.tar

echo "\n[$(date "+"%H:%M:%S"")] Done"

rm $TEMPDIR/*.sql

echo "\n\n[$(date "+"%H:%M:%S"")] Backup successful";
echo "\n"



