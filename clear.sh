#!/bin/sh
#--------------------------------Config--------------------------------#

# Backup directory
BACKDIR=/home/server/backups

# Clear count
CLEARCOUNT=10

#======================================================================#
DATECLEAR=`date -d $CLEARCOUNT' day ago' +'%d'`
rm $BACKDIR/$DATECLEAR.tar
