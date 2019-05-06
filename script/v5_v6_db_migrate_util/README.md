PopHealth version 5 to version 6 MongoDB migration utility

Please note that the migration utility does not work yet for patient records that were imported using the C-CDA file format.  Those records are missing the hqmfoid that is required to tranform the "records" collection to the version 6 CQL based "qdm_patients" collection.

Here are the steps:
1.	Install version 6.  This will result in using the MongoDB v3.4.5 with a virgin patient database
2.	From the version 5 installation, perform a MongoDB dump of the “pophealth-production” database.  This will create a database backup file called pophealth-production

    `$ mongodump --db pophealth-production`
    
3.	On the version 6 system, retrieve the version 5 database base file and restore the database to a new database named “popHealth-5-1-production”.
  
    `$ mongorestore -d pophealth51-production pophealth-production`
    
4.	Run ./patient_importer.sh.  Specify “popHealth-5-1-production” when prompt for the database name.
