#!/bin/bash

MYSQL_LOGIN='-u username --password=password'
 
for db in $(echo "SHOW DATABASES;" | mysql $MYSQL_LOGIN | grep -v -e "Database" -e "information_schema")
do
        TABLES=$(echo "USE $db; SHOW TABLES;" | mysql $MYSQL_LOGIN |  grep -v Tables_in_)
        echo "Switching to database $db"
        for table in $TABLES
        do
                echo -n " * Optimizing table $table ... "
                echo "USE $db; OPTIMIZE TABLE $table" | mysql $MYSQL_LOGIN  >/dev/null
                echo "done."
        done
done
