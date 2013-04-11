#!/bin/bash

# TO DO
#    1. Correct output in bk_ssh when password is provided
#    2. Get Log files as argument

# Set config variables
set SERVER
set BACKDIR
set TEMPDIR
set LOG_FILE
set TAR_LOG_FILE
set GZIP_LOG_FILE
set DATENAME
set DATELOG
set DATELOG_FILES
set HOST
set USER
set PASS
set DBS
set ARCHIVE_FILES
set SCP_SERVER
set SCP_USER
set SCP_LOC
set MAX_SCP_RETRY
set FAILURE_EMAIL_SEND
set FAILURE_EMAIL_SUBJECT
set FAILURE_EMAIL_TO
set FAILURE_EMAIL_BODY_FILENAME
set DEBUG_MODE

# Including config file
source $(dirname $0)/config.sh

SSH_PASS_IS_SET=1
if [ -z "$SCP_PASS" ]; then
    SSH_PASS_IS_SET=0
fi

#--------------------------------Functionz--------------------------------#

bk_debug(){
  if [ $DEBUG_MODE -eq 1 ]; then
    echo $1
  fi
}

bk_getResult(){
  # Echo after substring 'return:'
  local str="$1"
  echo ${str:7}
}

bk_getTime(){
  echo "[$(date "+"%H:%M:%S"")]"
}

bk_notify(){
  echo "[$(bk_getTime)] $1"
}

bk_log(){
  bk_notify "$1" >> $LOG_FILE
}

bk_log_separator(){
  bk_log "      ~~~---------------------------------------~~~"
}

bk_mkdirIfNotExists(){
  # Arguments:
  #   1: Directory Path

  if  [ ! -d $1 ]; then
    bk_log "Creating $1:"
    mkdir -p $1
    bk_log "Done"
  fi
}

bk_backupMySQL(){
  # Arguments:
  #   1: Databases' names
  #   2: MySQL Server
  #   3: MySQL Username
  #   4: MySQL Password
  #   5: Output directory

  local sqlFiles=""
  bk_log "MySQL dump beginning:"
  for database in $1
  do
    bk_log "Backing up $database:"
    nice -n 19 mysqldump -h "$2" -u$3 -p$4 --opt "$database" > $5/$database.sql
    sqlFiles="$sqlFiles $database.sql"
    bk_log "Done"
  done

  echo $sqlFiles
}

bk_compress(){
  # Arguments:
  #   1: Files and directories separated by space
  #   2: Output .tar path

  cd $TEMPDIR

  bk_log "Tar is gonna begin:"
  nice -n 19 tar -cvf $2 $1 >> $TAR_LOG_FILE
  local tarOutput=$?
  bk_log "Tar returned: "$tarOutput

  return $tarOutput
}

bk_gzip(){
  # Arguments:
  #   1: Tar file path to gzip

  bk_log "Gzipping is gonna begin:"
  nice -n 19 gzip -f -v --fast $1 >> $GZIP_LOG_FILE
  local gzipOutput=$?
  bk_log "Gzip returned: "$gzipOutput

  return $gzipOutput
}

bk_ssh(){
  # Arguments:
  #   1: Username
  #   2: Server
  #   3: Command
  #   4: Password
  
  USER=$1
  Server=$2
  CMD=$3
  PWD=$4
  
  set local result
  
  if [ -z "$PWD" ]; then
    result=$(ssh $USER@$Server "$CMD")
  else
    result=$(expect -c "
spawn ssh $USER@$Server \"$CMD\"
expect \"*?assword:*\"
send -- \"$PWD\r\"
expect \"\n\"
expect \"\n\"" | tr '\n' ' ')
    
    result=${result#*assword}
  fi
  
  echo $result
}

bk_scp(){
  # Arguments:
  #   1: Source filename
  #   2: Destination filename
  #   3: Password
  
  SRC=$1
  DES=$2
  PWD=$3

  bk_log "Secure copy is gonna begin: $1 -> $2"
  if [ -z "$PWD" ]; then
    scp $SRC $DES >> $LOG_FILE
  else
    /usr/bin/expect <<EOD >> $LOG_FILE
    spawn scp $SRC $DES
    expect "*?assword:*"
    send -- "$PWD\r"
    expect "\n"
    expect "\n"
EOD
  fi
  bk_log "Secure copy finished."
}

bk_md5Check(){
  # Arguments:
  #   1: Local filename
  #   2: Remote filename
  #   3: Remote Username
  #   4: Remote Server
  #   5: Password
  
  localFilename=$1
  remoteFilename=$2
  remoteUsername=$3
  remoteServer=$4
  pass=$5
  
  local localFileMD5=$(md5sum $localFilename)
  localFileMD5=${localFileMD5% *}
  bk_debug "Local MD5: $localFileMD5"
  
  set local remoteFileMD5
  if [ -z "$pass" ]; then
    remoteFileMD5=$(bk_ssh $remoteUsername $remoteServer "md5sum $remoteFilename")
  else
    remoteFileMD5=$(bk_ssh $remoteUsername $remoteServer "md5sum $remoteFilename" "$pass")
  fi
  remoteFileMD5=${remoteFileMD5% *}
  bk_debug "Remote MD5: $remoteFileMD5"
  
  if [ $localFileMD5 = $remoteFileMD5 ]; then
    return 1;
  else
    return 0;
  fi
}

bk_email(){
  # Arguments:
  #   1: Subject
  #   2: Recipient email
  #   3: Body filename
  
  mail -s "$1" "$2" < $3
}

#======================================================================#

bk_log "~~~---------------------------------------------------~~~"
bk_log "        Server: "$SERVER
bk_log "        Date: "$DATELOG
bk_log "        Filename: "$DATENAME
bk_log_separator

SUCCESS=0

# check if the backup and temp directory exists
# if not, create it
bk_mkdirIfNotExists $BACKDIR
bk_mkdirIfNotExists $TEMPDIR

if [ $DBS = "ALL" ]; then
  bk_log "Creating list of all your databases:"
  DBS=`mysql -h $HOST --user=$USER --password=$PASS -Bse "show databases;" | tr '\n' ' '`
  bk_log "Done"
fi

bk_debug "Listing DBs done: $DBS"

ARCHIVE_SQL_FILES=$(bk_backupMySQL "$DBS" $HOST $USER $PASS $TEMPDIR)

bk_debug "Dumped DBS: $ARCHIVE_SQL_FILES"

bk_log_separator

bk_compress "$ARCHIVE_SQL_FILES $ARCHIVE_FILES" "$BACKDIR/$DATENAME.tar"
TAR_OUTPUT=$?

bk_log_separator

case $TAR_OUTPUT in
  "0")
    bk_log "Successfully tarred!"

    bk_gzip "$BACKDIR/$DATENAME.tar"
    GZ_OUTPUT=$?

    case $GZ_OUTPUT in
      "0"|"2")

	if [ $GZ_OUTPUT = "2" ]; then
	  bk_log "gzip finished with some warnings"
	else
          bk_log "Successfully gzipped"
	fi

        scpRetryCount=0
        while [ $SUCCESS -eq 0 ] && [ $scpRetryCount -le $MAX_SCP_RETRY ]
        do
          if [ $SSH_PASS_IS_SET -eq 1 ]; then
            bk_scp "$BACKDIR/$DATENAME.tar.gz" "$SCP_USER@$SCP_SERVER:$SCP_LOC/$DATENAME.tar.gz" "$SCP_PASS"
            bk_md5Check "$BACKDIR/$DATENAME.tar.gz" "$SCP_LOC/$DATENAME.tar.gz" "$SCP_USER" "$SCP_SERVER" "$SCP_PASS"
          else
            bk_scp "$BACKDIR/$DATENAME.tar.gz" "$SCP_USER@$SCP_SERVER:$SCP_LOC/$DATENAME.tar.gz"
            bk_md5Check "$BACKDIR/$DATENAME.tar.gz" "$SCP_LOC/$DATENAME.tar.gz" "$SCP_USER" "$SCP_SERVER"
          fi
	  SUCCESS=$?
          let "scpRetryCount++"
        done
	;;

      "1")
	bk_log "An internal error occured while gzipping"
	;;

      "137")
	bk_log "Gzip killed!"
	;;

      *)
	bk_log "There was an error with Gzip"
	;;
    esac
    ;;

  "137")
    bk_log "Tar Killed!"
    ;;

  *)
    bk_log "There was a problem with tar: "$TAR_OUTPUT
    ;;
esac

if [ $SUCCESS -eq 1 ]; then
  bk_log "Backup successfully finished."
else
  bk_log "Backup finished with failure."
  
  if [ $FAILURE_EMAIL_SEND -eq 1 ]; then
    touch $FAILURE_EMAIL_BODY_FILENAME
    echo "On $(bk_getTime) $DATELOG backup failed" >> $FAILURE_EMAIL_BODY_FILENAME
    lineNumbers=$(wc -l $LOG_FILE)
    lineNumbers=${lineNumbers% *}
    lineNumbers=$((lineNumbers))
    currentLogStartLineNumber=$(echo "$(grep -n "Date: $DATELOG" $LOG_FILE | tail -1)" | cut -d ':' -f 1)
    currentLogStartLineNumber=$((currentLogStartLineNumber-3))
    linesFifference=$((lineNumbers-currentLogStartLineNumber))
    currentLog=$(tail -n $linesFifference $LOG_FILE)
    echo -e "$currentLog" >> $FAILURE_EMAIL_BODY_FILENAME
    
    bk_email "$FAILURE_EMAIL_SUBJECT $(bk_getTime)" $FAILURE_EMAIL_TO $FAILURE_EMAIL_BODY_FILENAME
    
    rm $FAILURE_EMAIL_BODY_FILENAME
  fi
fi

# Remove sql dumps
cd $TEMPDIR
for databaseFilename in $ARCHIVE_SQL_FILES
do
  rm $databaseFilename
done

bk_log_separator
bk_log_separator