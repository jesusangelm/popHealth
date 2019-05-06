#!/bin/sh

previousDb=""
a=0
currentDb="pophealth-production"

read -p 'Please enter the popHealth 5.1 Database Name to Migrate the Data : ' previousDb
echo "Verifying "$previousDb

if [ $( mongo localhost:27017 --eval " db.getMongo().getDBNames().indexOf('$previousDb') " --quiet ) -lt $a ]
 then
 echo "The Database doesnt exist"
else
 echo "Starting Records Migration"
 mongodump --collection providers --db $previousDb
 mongodump --collection records --db $previousDb
 mongorestore --db $currentDb dump/$previousDb/
 ruby patient_importer.rb
 rm -r dump/
fi

