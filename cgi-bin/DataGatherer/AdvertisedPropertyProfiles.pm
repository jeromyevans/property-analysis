#!/usr/bin/perl
# Written by Jeromy Evans
# Started 13 March 2004
# 
# WBS: A.01.03.01 Developed On-line Database
# Version 0.1  
#
# Description:
#   Module that encapsulate the AdvertisedxProfiles database tables
# 
# History:
#   18 May 2004 - fixed bug in addRecord that failed to properly quote every
#     variable (it addded quotes, but didn't call use the sqlclient quote method
#     to escape quotes contained inside the value.
#
#   9 July 2004 - Merged with LogTable to record encounter information (date last encountered, url, checksum)
#  to support searches like get records 'still advertised'
#   25 July 2004 - added support for instance ID and transactionNo
#   22 August 2004 - added support for State column
#                  - renamed suburbIdentifier to suburbIndex
#   12 September 2004 - added support to specify the DateEntered field instead of using the current time.  This
#     is necessary to support the database recovery function (which uses the time it was logged instead of
#     now)
#   27 November 2004 - added the createdBy field to the table which is a foreign key back to the 
#     OriginatingHTML recordadded function changeRecord() and modified table format to support tracking of changes
#     to records.  Impacts the createTable function, and created createChangeTable
#   29 November 2004 - added support for the WorkingView table - table is created with the main one and
#     updated to the aggregation of changes whenever changeRecord is used
#   30 November 2004 - added support for the CacheView table - table is created with the main one and 
#     updated whenever a record is added to the main, but contains only a subset of fields to improve access time
#     for the cache comparisons
#                    - changed checkIfTupleExists to operate on the CacheView for query speed improvement
#   5 December 2004 - adapted to support both sales and rentals instead of two separete files with duplicated code
#   2 April 2005 - updated all insert functions to use $sqlClient->lastInsertID(); to get the identifier of the
#    last record inserted instead of performing a select function to find out.  This is MUCH faster.
#   8 May 2005 - major change to database structure to include unit number, agentindex, rename some fields and
#     remove unused fields, AND combine sale and rental advertisements into one table
#              - removed cacheview
#              - added checkIfProfileExists - that uses a hash instead of individual parameters
#              - completely removed concept of whether its a sale or rental table - always up to the individual 
#     methods to specify what data they're handling (when appropriate)
#  23 May 2005 - another significant change - modified the table so that the parsers don't need to perform processing
#     of address or price strings - instead the advertisedpropertyprofiles table contains the original unprocessed
#     data.  Later, the working view will include the processed derived data (like decomposed address, indexes etc)
#  26 May 2005 - modified addRecord so it creates the OriginatingHTML record (specify url and htmlsyntaxtree)
#              - modified handling of localtime so it uses localtime(time) instead of the mysql in-built function
#     localtime().  Improved support for overriding the time, and added support for the exact same timestamp
#     to be used in the changetable and originating html
#   5 June 2005 - important change - when checking if a tuple already exists, the dateentered field of the 
#    existing profile is compared against the current timestamp (which may be overridden) to confirm that the 
#    existing profile is actually OLDER than the new one.  This is necessary when processing log files, which
#    can be encountered out of time order.  Without it, the dateentered and lastencountered fields could
#    be corrupted (last encountered older than date entered), aslo impacting the estimates of how long a property
#    was advertised if the dateentered is the wrong field.  NOW, a record is always added if it is deemed 
#    older than the existing record - this may arise in duplicates in the database (except date) but these
#    are fixed later in the batch processing/association functions.
#
# CONVENTIONS
# _ indicates a private variable or method
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
package AdvertisedPropertyProfiles;
require Exporter;

use DBI;
use SQLClient;
use OriginatingHTML;
use Time::Local;

@ISA = qw(Exporter);

#@EXPORT = qw(&parseContent);

# -------------------------------------------------------------------------------------------------
# PUBLIC enumerations
#
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

# Contructor for the AdvertisedPropertyProfiles - returns an instance of this object
# PUBLIC
sub new
{   
   my $sqlClient = shift;

   $tableName = 'AdvertisedPropertyProfiles';
   $originatingHTML = OriginatingHTML::new($sqlClient);
   
   my $advertisedPropertyProfiles = { 
      sqlClient => $sqlClient,
      tableName => $tableName,
      useDifferentTime => 0,
      dateEntered => undef,
      originatingHTML => $originatingHTML
   }; 
      
   bless $advertisedPropertyProfiles;     
   
   return $advertisedPropertyProfiles;   # return this
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# createTable
# attempts to create the advertisedSaleProfiles table in the database if it doesn't already exist
# 
# Purpose:
#  Initialising a new database
#
# Parameters:
#  nil
#
# Constraints:
#  nil
#
# Uses:
#  sqlClient
#
# Updates:
#  nil
#
# Returns:
#   TRUE (1) if successful, 0 otherwise
#

my $SQL_CREATE_TABLE_BODY = 
   "Identifier INTEGER ZEROFILL PRIMARY KEY AUTO_INCREMENT, ".    
   "DateEntered DATETIME NOT NULL, ".
   "LastEncountered DATETIME, ".
   "SaleOrRentalFlag INTEGER,".                   
   "SourceName TEXT, ".
   "SourceID VARCHAR(20), ".
   "TitleString TEXT, ".
   "Checksum INTEGER, ".
   "State VARCHAR(3), ".   
   "SuburbName TEXT, ".
   "Type VARCHAR(10), ".
   "Bedrooms INTEGER, ".
   "Bathrooms INTEGER, ".
   "LandArea TEXT, ".   
   "BuildingArea TEXT, ".
   "YearBuilt VARCHAR(5), ".
   "AdvertisedPriceString TEXT, ".
   "StreetAddress TEXT, ".
   "Description TEXT, ".    
   "Features TEXT,".
   "OriginatingHTML INTEGER ZEROFILL,".       
   "AgencySourceID TEXT, ".
   "AgencyName TEXT, ".
   "AgencyAddress TEXT, ".   
   "SalesPhone TEXT, ".
   "RentalsPhone TEXT, ".
   "Fax TEXT, ".
   "ContactName TEXT, ".
   "MobilePhone TEXT, ".
   "Website TEXT";
   
sub createTable

{
   my $this = shift;
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $tableName = $this->{'tableName'};
   
   my $SQL_CREATE_TABLE_PREFIX = "CREATE TABLE IF NOT EXISTS $tableName (";
   my $SQL_CREATE_TABLE_SUFFIX = ", INDEX (SaleOrRentalFlag, SourceName(5), SourceID(10), TitleString(15), Checksum))";  # extended now that cacheview is dropped
   
   if ($sqlClient)
   {
      # append table prefix, original table body and table suffix
      $sqlStatement = $SQL_CREATE_TABLE_PREFIX.$SQL_CREATE_TABLE_BODY.$SQL_CREATE_TABLE_SUFFIX;
     
      $statement = $sqlClient->prepareStatement($sqlStatement);
      
      if ($sqlClient->executeStatement($statement))
      {
         $success = 1;
         
         # 27Nov04: create the corresponding change table
         $this->_createChangeTable();
         # 29Nov04: create the corresponding working view
         $this->_createWorkingViewTable();
         
         # create the originatingHTML table
         $originatingHTML = $this->{'originatingHTML'};
         $originatingHTML->createTable();
      }
     
   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------
# overrideDateEntered
# sets the dateEntered field to use for the next add (instead of the current time)
# use when adding old data back into a database
#
# Purpose:
#  Storing information in the database
#
# Parameters:
#  timestamp to use (in SQL DATETIME format YYYY-MM-DD HH:MM:SS)
#
# Constraints:
#  nil
#
# Uses:
#  sqlClient
#
# Updates:
#  nil
#
# Returns:
#   TRUE (1) if successful, 0 otherwise
#        
sub overrideDateEntered

{
   my $this = shift;
   my $timestamp = shift;
   
   $this->{'dateEntered'} = $timestamp;
   $this->{'useDifferentTime'} = 1;
}

# -------------------------------------------------------------------------------------------------
# getDateEnteredEpoch
# gets the current dateEntered field (used for the next add if set with overrideDateEntered)
# as an epoch value (seconds since 1970
#
# Purpose:
#  Storing information in the database
#
# Parameters:
#  timestamp to use (in SQL DATETIME format)
#
# Constraints:
#  nil
#
# Uses:
#  sqlClient
#
# Updates:
#  nil
#
# Returns:
#   TRUE (1) if successful, 0 otherwise
#        
sub getDateEnteredEpoch

{
   my $this = shift;
   
   if ($this->{'useDifferentTime'})
   {
      $timestamp = $this->{'dateEntered'};
      ($year, $mon, $mday, $hour, $min, $sec) = split(/-|\s|:/, $timestamp);
      $epoch = timelocal($sec, $min, $hour, $mday, $mon-1, $year-1900);
   }
   else
   {
      $epoch = -1;
   }
      
   return $epoch;
}

# -------------------------------------------------------------------------------------------------
# addRecord
# adds a record of data to the AdvertisedPropertyProfiles table
# OPERATES ON ALL VIEWS (working view is updated)
#
# Purpose:
#  Storing information in the database
#
# Parameters:
#  reference to a hash containing the values to insert
#  string sourceURL
#  htmlsyntaxtree - used to generating originatingHTML record
#
# Constraints:
#  nil
#
# Uses:
#  sqlClient
#
# Updates:
#  nil
#
# Returns:
#   TRUE (1) if successful, 0 otherwise
#        
sub addRecord

{
   my $this = shift;
   my $parametersRef = shift;
   my $url = shift;
   my $htmlSyntaxTree = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   my $tableName = $this->{'tableName'};
   my $localTime;
   my $originatingHTML = $this->{'originatingHTML'};
   my $identifier = -1;
   
   if ($sqlClient)
   {
      $statementText = "INSERT INTO $tableName (DateEntered, ";
      
      @columnNames = keys %$parametersRef;
      
      # modify the statement to specify each column value to set 
      $appendString = join ',', @columnNames;
      
      $statementText = $statementText.$appendString . ") VALUES (";
      
      # modify the statement to specify each column value to set 
      @columnValues = values %$parametersRef;
      $index = 0;
      
      if (!$this->{'useDifferentTime'})
      {
         # determine the current time
         ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
         $this->{'dateEntered'} = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec);
         $localTime = $sqlClient->quote($this->{'dateEntered'});
      }
      else
      {
         # use the specified date instead of the current time
         $localTime = $sqlClient->quote($this->{'dateEntered'});
         $this->{'useDifferentTime'} = 0;  # reset the flag
      }      
      
      $appendString = "$localTime, ";
      $index = 0;
      foreach (@columnValues)
      {
         if ($index != 0)
         {
            $appendString = $appendString.", ";
         }
        
         $appendString = $appendString.$sqlClient->quote($_);
         $index++;
      }
      $statementText = $statementText.$appendString . ")";
      
      #print "statement = ", $statementText, "\n";
      $statement = $sqlClient->prepareStatement($statementText);
      
      if ($sqlClient->executeStatement($statement))
      {
         $success = 1;
         
         # 2 April 2005 - use lastInsertID to get the primary key identifier of the record just inserted
         $identifier = $sqlClient->lastInsertID();
                  
         # --- add the new record to the cache and working view ---
         if ($identifier)
         {
            # NOTE: WORKING VIEW IS CURRENTLY DISABLED 27May05
            #$this->_workingView_addRecord($identifier);
            
            # 27Nov04: save the HTML file entry that created this record
            $originatingHTML->addRecord($this->{'dateEntered'}, $identifier, $url, $htmlSyntaxTree, $tableName);
         }
      }
   }
   
   return $identifier;   
}

# -------------------------------------------------------------------------------------------------
# dropTable
# attempts to drop the AdvertisedxProfiles table 
# 
# Purpose:
#  Initialising a new database
#
# Parameters:
#  nil
#
# Constraints:
#  nil
#
# Uses:
#  sqlClient
#
# Updates:
#  nil
#
# Returns:
#   TRUE (1) if successful, 0 otherwise
#
        
sub dropTable

{
   my $this = shift;
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $tableName = $this->{'tableName'};
   
   if ($sqlClient)
   {
      $statementText = "DROP TABLE $tableName";
      $statement = $sqlClient->prepareStatement($statementText);
      
      if ($sqlClient->executeStatement($statement))
      {
         $success = 1;
         #$statementText = "DROP TABLE CacheView_$tableName";
         #$statement = $sqlClient->prepareStatement($statementText);
         
         #if ($sqlClient->executeStatement($statement))
         #{

            $statementText = "DROP TABLE ChangeTable_$tableName";
            $statement = $sqlClient->prepareStatement($statementText);
            
            if ($sqlClient->executeStatement($statement))
            { 
               
               $statementText = "DROP TABLE WorkingView_$tableName";
               $statement = $sqlClient->prepareStatement($statementText);
               
               if ($sqlClient->executeStatement($statement))
               {       
            
                  $success = 1;
                  
                  # create the originatingHTML table
                  $originatingHTML = $this->{'originatingHTML'};
                  $originatingHTML->dropTable();
               }
            }
         #}
      }
   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# countEntries
# returns the number of advertisements in the database
#
# Purpose:
#  status information
#
# Parameters:
#  nil
#
# Constraints:
#  nil
#
# Updates:
#  Nil
#
# Returns:
#   nil
sub countEntries
{   
   my $this = shift;      
   my $statement;
   my $found = 0;
   my $noOfEntries = 0;
   
   my $sqlClient = $this->{'sqlClient'};
   my $tableName = $this->{'tableName'};
   
   if ($sqlClient)
   {       
      $quotedUrl = $sqlClient->quote($url);      
      my $statementText = "SELECT count(DateEntered) FROM $tableName";
   
      $statement = $sqlClient->prepareStatement($statementText);
      
      if ($sqlClient->executeStatement($statement))
      {
         # get the array of rows from the table
         @selectResult = $sqlClient->fetchResults();
                           
         foreach (@selectResult)
         {        
            # $_ is a reference to a hash
            $noOfEntries = $$_{'count(DateEntered)'};
            last;            
         }                 
      }                    
   }   
   return $noOfEntries;   
}  


# -------------------------------------------------------------------------------------------------


# -------------------------------------------------------------------------------------------------
# checkIfResultExists
# checks whether the specified tuple exists in the table (part of this check uses a checksum)
#
# Purpose:
#  tracking data parsed by the agent
#
# Parameters:
#  saleOrRentalFlag
#  string sourceName
#  string sourceID
#  string titleString (the title of the record in the search results - if it changes, a new record is added) 

# Constraints:
#  nil
#
# Updates:
#  Nil
#
# Returns:
#   nil
sub checkIfResultExists
{   
   my $this = shift;
   my $saleOrRentalFlag = shift;
   my $sourceName = shift;      
   my $sourceID = shift;
   my $titleString = shift;
   my $statement;
   my $found = 0;
   my $statementText;
      
   my $sqlClient = $this->{'sqlClient'};
   my $tableName = $this->{'tableName'};
   
   if ($sqlClient)
   {       
      $quotedSource = $sqlClient->quote($sourceName);
      $quotedSourceID = $sqlClient->quote($sourceID);
      $quotedTitleString = $sqlClient->quote($titleString);

      $statementText = "SELECT unix_timestamp(dateEntered) as unixTimestamp, sourceName, sourceID, titleString FROM $tableName WHERE SaleOrRentalFlag = $saleOrRentalFlag AND sourceName = $quotedSource AND sourceID = $quotedSourceID AND titleString = $quotedTitleString";
      $statement = $sqlClient->prepareStatement($statementText);
      if ($sqlClient->executeStatement($statement))
      {
         # get the array of rows from the table
         @resultList = $sqlClient->fetchResults();
                           
         foreach (@resultList)
         {
#            DebugTools::printHash("result", $_);
            # only check advertisedpricelower if it's undef (if caller hasn't set it because info wasn't available then don't check that field.           
            
            # $_ is a reference to a hash               
            if (($$_{'sourceName'} == $sourceName) && ($$_{'sourceID'} == $sourceID) && ($$_{'titleString'} == $titleString))            
            {
               # found a match
               # 5 June 2005 - BUT, make sure the dateEntered for the existing record is OLDER than the record being added
               # if it's not, added the new record  (only matters if useDifferentTime is SET)
               $dateEntered = $this->getDateEnteredEpoch();
               if (($$_{'unixTimestamp'} <= $dateEntered) || (!$this->{'useDifferentTime'}))
               { 
                  $found = 1;
                  last;
               }
            }
         }                 
      }              
   }   
   return $found;   
}  



# -------------------------------------------------------------------------------------------------
# checkIfTupleExists
# checks whether the specified tuple exists in the table (part of this check uses a checksum)
#
# Purpose:
#  tracking data parsed by the agent
#
# Parameters:
#  saleOrRentalFlag
#  string sourceName
#  string sourceID
#  string checksum (ignored if undef)
#  string priceString (ignored if undef)

# Constraints:
#  nil
#
# Updates:
#  Nil
#
# Returns:
#   nil
sub checkIfTupleExists
{   
   my $this = shift;
   my $saleOrRentalFlag = shift;
   my $sourceName = shift;      
   my $sourceID = shift;
   my $checksum = shift;
   my $advertisedPriceString = shift;
   my $statement;
   my $found = 0;
   my $statementText;
      
   my $sqlClient = $this->{'sqlClient'};
   my $tableName = $this->{'tableName'};
   
   if ($sqlClient)
   {       
      $quotedSource = $sqlClient->quote($sourceName);
      $quotedSourceID = $sqlClient->quote($sourceID);
      
      if (defined $checksum)
      {
         if ($advertisedPriceLower)
         {
            $statementText = "SELECT unix_timestamp(dateEntered) as unixTimestamp, sourceName, sourceID, checksum, advertisedPriceString FROM $tableName WHERE SaleOrRentalFlag = $saleOrRentalFlag AND sourceName = $quotedSource and sourceID = $quotedSourceID and checksum = $checksum and advertisedPriceString = $advertisedPriceString";
         }
         else
         {
            $statementText = "SELECT unix_timestamp(dateEntered) as unixTimestamp, sourceName, sourceID, checksum FROM $tableName WHERE SaleOrRentalFlag = $saleOrRentalFlag AND sourceName = $quotedSource and sourceID = $quotedSourceID and checksum = $checksum";
         }
      }
      else
      {
         #print "   checkIfTupleExists:noChecksum\n";
         if ($advertisedPriceLower)
         {
            #print "   checkIfTupleExists:apl=$advertisedPriceLower\n";

            $statementText = "SELECT unix_timestamp(dateEntered) as unixTimestamp, sourceName, sourceID, advertisedPriceString FROM $tableName WHERE SaleOrRentalFlag = $saleOrRentalFlag AND sourceName = $quotedSource and sourceID = $quotedSourceID and advertisedPriceString = $advertisedPriceString";
         }
         else
         {
            #print "   checkIfTupleExists:no apl\n";

            $statementText = "SELECT unix_timestamp(dateEntered) as unixTimestamp, sourceName, sourceID FROM $tableName WHERE SaleOrRentalFlag = $saleOrRentalFlag AND sourceName = $quotedSource and sourceID = $quotedSourceID";
         }
      }
      
      #print "   checkIfTupleExistsSales: $statementText\n";      
      $statement = $sqlClient->prepareStatement($statementText);
      if ($sqlClient->executeStatement($statement))
      {
         # get the array of rows from the table
         @checksumList = $sqlClient->fetchResults();
         #DebugTools::printList("checksum", \@checksumList);                  
         foreach (@checksumList)
         {
            #DebugTools::printHash("result", $_);
            # only check advertisedpricelower if it's undef (if caller hasn't set it because info wasn't available then don't check that field.           
            if ($advertisedPriceLower)
            {
               # $_ is a reference to a hash
               
               if (($$_{'checksum'} == $checksum) && ($$_{'sourceName'} == $sourceName) && ($$_{'sourceID'} == $sourceID) && ($$_{'advertisedPriceString'} == $advertisedPriceString))            
               {
                  # found a match
                  # 5 June 2005 - BUT, make sure the dateEntered for the existing record is OLDER than the record being added
                  # if it's not, added the new record  (only matters if useDifferentTime is SET)
                  $dateEntered = $this->getDateEnteredEpoch();
                  if (($$_{'unixTimestamp'} <= $dateEntered) || (!$this->{'useDifferentTime'}))
                  { 
                     $found = 1;
                     last;
                  }
               }
            }
            else
            {
               # $_ is a reference to a hash
               if (($$_{'checksum'} == $checksum) && ($$_{'sourceName'} == $sourceName) && ($$_{'sourceID'} == $sourceID))            
               {
                  # found a match
                  # 5 June 2005 - BUT, make sure the dateEntered for the existing record is OLDER than the record being added
                  # if it's not, added the new record  (only matters if useDifferentTime is SET)
                  $dateEntered = $this->getDateEnteredEpoch();
                  if (($$_{'unixTimestamp'} <= $dateEntered) || (!$this->{'useDifferentTime'}))
                  { 
                     $found = 1;
                     last;
                  }
               }
            }
         }                 
      }              
   }   
   return $found;   
}  


# -------------------------------------------------------------------------------------------------
# checkIfProfileExists
# checks whether the specified profile already exists in the table (part of this check uses a checksum)
#
# Purpose:
#  tracking changed data parsed by the agent
#
# Parameters:
#  reference to the profile hash
#
# Constraints:
#  nil
#
# Updates:
#  Nil
#
# Returns:
#   true if found
#
sub checkIfProfileExists
{   
   my $this = shift;
   my $propertyProfile = shift;
   
   $found = $this->checkIfTupleExists($$propertyProfile{'SaleOrRentalFlag'}, $$propertyProfile{'SourceName'}, $$propertyProfile{'SourceID'}, $$propertyProfile{'Checksum'}, $$propertyProfile{'AdvertisedPriceString'});

   return $found;   
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# addEncounterRecord
# records in the table that a unique tuple with has been encountered again
# (used for tracking how often unchanged data is encountered, parsed and rejected)
# 
# Purpose:
#  Logging information in the database
#
# Parameters: 
#  string sourceName
#  string sourceID
#  integer checksum  (ignored if undef)
#
# Constraints:
#  nil
#
# Uses:
#  sqlClient
#
# Updates:
#  nil
#
# Returns:
#   TRUE (1) if successful, 0 otherwise
#        
sub addEncounterRecord

{
   my $this = shift;
   my $saleOrRentalFlag = shift;
   my $sourceName = shift;
   my $sourceID = shift;
   my $checksum = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};  
   my $tableName = $this->{'tableName'};
   my $statementText;
   my $localTime;
   
   if ($sqlClient)
   {
      $quotedSource = $sqlClient->quote($sourceName);
      $quotedSourceID = $sqlClient->quote($sourceID);
      $quotedUrl = $sqlClient->quote($url);
  
      if (!$this->{'useDifferentTime'})
      {
         # determine the current time
         ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
         $this->{'dateEntered'} = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec);
         $localTime = $sqlClient->quote($this->{'dateEntered'});
      }
      else
      {
         # use the specified date instead of the current time
         $localTime = $sqlClient->quote($this->{'dateEntered'});
         $this->{'useDifferentTime'} = 0;  # reset the flag
      }
  
      if (defined $checksum)
      {
         $statementText = "UPDATE $tableName ".
           "SET LastEncountered = $localTime ".
           "WHERE (SaleOrRentalFlag = $saleOrRentalFlag AND sourceName = $quotedSource AND sourceID = $quotedSourceID AND checksum = $checksum)";
      }
      else
      {
         $statementText = "UPDATE $tableName ".
           "SET LastEncountered = $localTime ".
           "WHERE (SaleOrRentalFlag = $saleOrRentalFlag AND sourceName = $quotedSource AND sourceID = $quotedSourceID)";
      }
      
      #print "addEncounterRecord: $statementText\n";
      $statement = $sqlClient->prepareStatement($statementText);
      
      if ($sqlClient->executeStatement($statement))
      {
         $success = 1;
      }
      #print "addEncounterRecord: finished\n";
   }
   
   return $success;   
}


# -------------------------------------------------------------------------------------------------
# createChangeTable
# attempts to create the advertisedxProfiles table in the database if it doesn't already exist
# 
# Purpose:
#  Initialising a new database
#
# Parameters:
#  nil
#
# Constraints:
#  nil
#
# Uses:
#  sqlClient
#
# Updates:
#  nil
#
# Returns:
#   TRUE (1) if successful, 0 otherwise
#   

sub _createChangeTable

{
   my $this = shift;
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $tableName = $this->{'tableName'};
 
   my $SQL_CREATE_CHANGE_TABLE_PREFIX = "CREATE TABLE IF NOT EXISTS ChangeTable_$tableName (";
   my $SQL_CREATE_CHANGE_TABLE_SUFFIX = ", ".
      "ChangesRecord INTEGER ZEROFILL REFERENCES $tableName(identifier), ".  # foreign key
      "ChangedBy TEXT,".                         # who/what changed it
      "INDEX (SaleOrRentalFlag, sourceName(5), sourceID(10)))";    # 23Jan05 - index!
      
   if ($sqlClient)
   {
      # append change table prefix, original table body and change table suffix
      $sqlStatement = $SQL_CREATE_CHANGE_TABLE_PREFIX.$SQL_CREATE_TABLE_BODY.$SQL_CREATE_CHANGE_TABLE_SUFFIX;
      
      $statement = $sqlClient->prepareStatement($sqlStatement);
      
      if ($sqlClient->executeStatement($statement))
      {
         $success = 1;
      }
   }
   
   return $success;   
}


# -------------------------------------------------------------------------------------------------
# changeRecord
# alters a record of data in the AdvertisedxProfiles table and records the changed
#  data transaction.   Note ONLY the WORKING VIEW is updated, not the original view 
# 
# Purpose:
#  Storing information in the database
#
# Parameters:
#  reference to a hash containing the values to insert
#  string sourceURL
#  integer sourceIdentifier
#  string ChangedBy
#
# Constraints:
#  nil
#
# Uses:
#  sqlClient
#
# Updates:
#  nil
#
# Returns:
#   TRUE (1) if successful, 0 otherwise
#        
sub changeRecord

{
   my $this = shift;
   my $parametersRef = shift;
   my $url = shift;
   my $sourceIdentifier = shift;
   my $changedBy = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   my $localTime;
   my $tableName = $this->{'tableName'};
   
   if ($sqlClient)
   {
      # --- get the last change record for this identifier to ensure this isn't a duplicate ---
      
      $statementText = "SELECT DateEntered, ";
      # note DateEntered isn't used but is obtained for information - confirm it was infact the last entry that
      # was matched (only used in debugging)
      @columnNames = keys %$parametersRef;
      
      $appendString ="";
      $index = 0;
      foreach (@columnNames)
      {
         if ($index != 0)
         {
            $appendString = $appendString.", ";
         }
        
         $appendString = $appendString . $_;
         $index++;
      }      
      
      $statementText = $statementText.$appendString . " FROM ChangeTable_$tableName WHERE "; 
      
      # modify the statement to specify each column value to set 
      @columnValues = values %$parametersRef;
      $index = 0;
      
      $appendString = "ChangesRecord = $sourceIdentifier AND ";
      while(($field, $value) = each(%$parametersRef)) 
      {
         if ($index != 0)
         {
            $appendString = $appendString." AND ";
         }
        
         $appendString = $appendString."$field = ".$sqlClient->quote($value);
         $index++;
      }
      # order by reverse data limit 1 to get the last entry
      $statementText = $statementText.$appendString." ORDER BY DateEntered DESC LIMIT 1";

      @selectResults = $sqlClient->doSQLSelect($statementText);
      $noOfResults = @selectResults;
      if ($noOfResults > 0)
      {
         # that record already exists as the last entry in the table!!!
         #print "That change already exists as the last entry (MATCHED=$noOfResults)\n";
         $success = 0;
      }
      else
      {
         # ------------------------------------
         # --- insert the new change record ---
         # ------------------------------------
         $statementText = "INSERT INTO ChangeTable_$tableName (";
         
         @columnNames = keys %$parametersRef;
         
         # modify the statement to specify each column value to set 
         $appendString = "DateEntered, identifier, ChangesRecord, ChangedBy, ";
         $index = 0;
         foreach (@columnNames)
         {
            if ($index != 0)
            {
               $appendString = $appendString.", ";
            }
           
            $appendString = $appendString . $_;
            $index++;
         }      
         
         $statementText = $statementText.$appendString . ") VALUES (";
         
         # modify the statement to specify each column value to set 
         @columnValues = values %$parametersRef;
         $index = 0;
         $quotedInstance = $sqlClient->quote($instanceID);
         $quotedChangedBy = $sqlClient->quote($changedBy);
   
         if (!$this->{'useDifferentTime'})
         {
            ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
            $this->{'dateEntered'} = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec);
            $localTime = $sqlClient->quote($this->{'dateEntered'});
         }
         else
         {
            # use the specified date instead of the current time
            $localTime = $sqlClient->quote($this->{'dateEntered'});
            $this->{'useDifferentTime'} = 0;  # reset the flag
         }      
         
         $appendString = "$localTime, null, $sourceIdentifier, $quotedChangedBy, ";
         foreach (@columnValues)
         {
            if ($index != 0)
            {
               $appendString = $appendString.", ";
            }
           
            $appendString = $appendString.$sqlClient->quote($_);
            $index++;
         }
         $statementText = $statementText.$appendString . ")";
         
         #print "statement = ", $statementText, "\n";
         
         $statement = $sqlClient->prepareStatement($statementText);
         
         if ($sqlClient->executeStatement($statement))
         {
            $success = 1;
            
            # --- now update the working view ---
            $this->_workingView_changeRecord($parametersRef, $sourceIdentifier); 
         }
      }
   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# _createWorkingViewTable
# attempts to create the WorkingView_AdvertisedSaleProfiles table in the database if it doesn't already exist
# 
# Purpose:
#  Initialising a new database
#
# Parameters:
#  nil
#
# Constraints:
#  nil
#
# Uses:
#  sqlClient
#
# Updates:
#  nil
#
# Returns:
#   TRUE (1) if successful, 0 otherwise
#   

sub _createWorkingViewTable

{
   my $this = shift;
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $tableName = $this->{'tableName'};

   my $SQL_CREATE_WORKINGVIEW_TABLE_PREFIX = "CREATE TABLE IF NOT EXISTS WorkingView_$tableName (";
   my $SQL_CREATE_WORKINGVIEW_TABLE_SUFFIX = ", ".
       "ValidityCode INTEGER DEFAULT 1, ".        # validity code - default 1 means unvalidated
       "OverridenValidity INTEGER DEFAULT 0, ".   # overriddenValidity set by human
       "ComponentOf INTEGER ZEROFILL,".            # foreign key to master property table
       " INDEX (SaleOrRentalFlag, sourceName(5), sourceID(10)))";   # 23Jan05 - index!
    
   
   if ($sqlClient)
   {
      # append change table prefix, original table body and change table suffix
      $sqlStatement = $SQL_CREATE_WORKINGVIEW_TABLE_PREFIX.$SQL_CREATE_TABLE_BODY.$SQL_CREATE_WORKINGVIEW_TABLE_SUFFIX;
      
      $statement = $sqlClient->prepareStatement($sqlStatement);
      
      if ($sqlClient->executeStatement($statement))
      {
         $success = 1;
      }
   }
   
   return $success;   
}



# -------------------------------------------------------------------------------------------------
# copyToWorkingView
# adds a record of data to the WorkingView_AdvertisedxProfiles table direcly from the 
# original table
# 
# Purpose:
#  Storing information in the database
#
# Parameters:
#  integer Identifier - this is the identifier of the original record (foreign key)
#   (the rest of the fields are obtained automatically using select syntax)
#
# Constraints:
#  nil
#
# Uses:
#  sqlClient
#
# Updates:
#  nil
#
# Returns:
#   TRUE (1) if successful, 0 otherwise
#        
sub copyToWorkingView
{
   my $this = shift;
   my $identifier = shift;

   return $this->_workingView_addRecord($identifier);
}


# -------------------------------------------------------------------------------------------------
# _workingView_addRecord
# adds a record of data to the WorkingView_AdvertisedxProfiles table
# 
# Purpose:
#  Storing information in the database
#
# Parameters:
#  integer Identifier - this is the identifier of the original record (foreign key)
#   (the rest of the fields are obtained automatically using select syntax)
#
# Constraints:
#  nil
#
# Uses:
#  sqlClient
#
# Updates:
#  nil
#
# Returns:
#   TRUE (1) if successful, 0 otherwise
#        
sub _workingView_addRecord

{
   my $this = shift;
   my $identifier = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   my $tableName = $this->{'tableName'};
   my $localTime;
   
   if ($sqlClient)
   {
      $quotedIdentifier = $sqlClient->quote($identifier);
      @selectResults = $sqlClient->doSQLSelect("select * from $tableName where Identifier=$quotedIdentifier");
      
      $length = @selectResults;
      # Identifier is a primary key so only one result returned
      $parametersRef = $selectResults[0]; 
      
      if ($parametersRef)
      {
         $statementText = "INSERT INTO WorkingView_$tableName (";
      
         @columnNames = keys %$parametersRef;
         
         # modify the statement to specify each column value to set 
         $appendString = "";
         $index = 0;
         foreach (@columnNames)
         {
            if ($index != 0)
            {
               $appendString = $appendString.", ";
            }
           
            $appendString = $appendString . $_;
            $index++;
         }      
         
         $statementText = $statementText.$appendString . ") VALUES (";
         
         # modify the statement to specify each column value to set 
         @columnValues = values %$parametersRef;
         $index = 0;
         $appendString = "";
         foreach (@columnValues)
         {
            if ($index != 0)
            {
               $appendString = $appendString.", ";
            }
           
            $appendString = $appendString.$sqlClient->quote($_);
            $index++;
         }
         $statementText = $statementText.$appendString . ")";
                  
         $statement = $sqlClient->prepareStatement($statementText);
         
         if ($sqlClient->executeStatement($statement))
         {
            $success = 1;
         }
      }
   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------
# _workingView_changeRecord
# alters a record of data in the WorkingView_AdvertisedxProfiles table and records the changed
#  data transaction
# 
# Purpose:
#  Storing information in the database
#
# Parameters:
#  reference to a hash containing the values to insert
#  integer sourceIdentifier
#
# Constraints:
#  nil
#
# Uses:
#  sqlClient
#
# Updates:
#  nil
#
# Returns:
#   TRUE (1) if successful, 0 otherwise
#        
sub _workingView_changeRecord

{
   my $this = shift;
   my $parametersRef = shift;   
   my $sourceIdentifier = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   my $localTime;
   my $tableName = $this->{'tableName'};
   
   if ($sqlClient)
   {
      $appendString = "UPDATE WorkingView_$tableName SET ";
      # modify the statement to specify each column value to set 
      $index = 0;
      while(($field, $value) = each(%$parametersRef)) 
      {
         if ($index > 0)
         {
            $appendString = $appendString . ", ";
         }
         
         $quotedValue = $sqlClient->quote($value);
         
         $appendString = $appendString . "$field = $quotedValue ";
         $index++;
      }      
      
      $statementText = $appendString." WHERE identifier=$sourceIdentifier";
      
      $statement = $sqlClient->prepareStatement($statementText);
      
      if ($sqlClient->executeStatement($statement))
      {
         $success = 1;
      }
   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------
# workingView_setSpecialField
# updates a record of data in the WorkingView directly bypassing the changeTable.  Use only
# for fields that don't appear in the change table at all (such as validityCode)
# 
# Purpose:
#  Storing information in the database
#
# Parameters:
#  integer sourceIdentifier
#  string fieldName
#  string fieldValue
#
# Constraints:
#  nil
#
# Uses:
#  sqlClient
#
# Updates:
#  nil
#
# Returns:
#   TRUE (1) if successful, 0 otherwise
#        
sub workingView_setSpecialField

{
   my $this = shift;
   my $sourceIdentifier = shift;
   my $fieldName = shift;
   my $fieldValue = shift;
   my %specialHash;
   
   $specialHash{$fieldName} = $fieldValue;
   
   $this->_workingView_changeRecord(\%specialHash, $sourceIdentifier);
}

# -------------------------------------------------------------------------------------------------

