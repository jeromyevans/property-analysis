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
   my $advertisementType = shift;
   
   if ($advertisementType eq 'Sales')
   {
      $tableName = 'AdvertisedSaleProfiles';
      $tableType = 0;
   }
   else
   {
      if ($advertisementType eq 'Rentals')
      {
         $tableName = 'AdvertisedRentalProfiles';
         $tableType = 1;
      }
      else
      {
         $tableType = -1;
      }
   }
   
   my $advertisedPropertyProfiles = { 
      sqlClient => $sqlClient,
      tableName => $tableName,
      tableType => $tableType,
      useDifferentTime => 0,
      dateEntered => undef
   }; 
      
   bless $advertisedPropertyProfiles;     
   
   return $advertisedPropertyProfiles;   # return this
}

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

my $SQL_CREATE_SALES_TABLE_BODY = 
   "DateEntered DATETIME NOT NULL, ".
   "LastEncountered DATETIME, ".
   "SourceName TEXT, ".
   "SourceURL TEXT, ".
   "SourceID VARCHAR(20), ".
   "Checksum INTEGER, ".
   "InstanceID TEXT, ".
   "TransactionNo INTEGER, ".
   "Identifier INTEGER ZEROFILL PRIMARY KEY AUTO_INCREMENT, ".    
   "SuburbIndex INTEGER UNSIGNED ZEROFILL, ".
   "SuburbName TEXT, ".
   "State TEXT, ".
   "Type VARCHAR(10), ".
   "TypeIndex INTEGER, ".
   "Bedrooms INTEGER, ".
   "Bathrooms INTEGER, ".
   "Land INTEGER, ".
   "YearBuilt VARCHAR(5), ".
   "AdvertisedPriceLower DECIMAL(10,2), ".
   "AdvertisedPriceUpper DECIMAL(10,2), ".
   "Description TEXT, ".    
   "StreetNumber TEXT, ".
   "Street TEXT, ".    
   "City TEXT, ".
   "Council TEXT, ".
   "Features TEXT,".
   "CreatedBy INTEGER ZEROFILL";
              
my $SQL_CREATE_RENTALS_TABLE_BODY = 
   "DateEntered DATETIME NOT NULL, ".
   "LastEncountered DATETIME, ".
   "SourceName TEXT, ".
   "SourceURL TEXT, ".
   "SourceID VARCHAR(20), ".
   "Checksum INTEGER, ".
   "InstanceID TEXT, ".
   "TransactionNo INTEGER, ".
   "Identifier INTEGER ZEROFILL PRIMARY KEY AUTO_INCREMENT, ".    
   "SuburbIndex INTEGER UNSIGNED ZEROFILL, ".
   "SuburbName TEXT, ".
   "State TEXT, ".
   "Type VARCHAR(10), ".
   "TypeIndex INTEGER, ".
   "Bedrooms INTEGER, ".
   "Bathrooms INTEGER, ".        
   "Land INTEGER, ".
   "YearBuilt VARCHAR(5), ".
   "AdvertisedWeeklyRent DECIMAL(10,2), ".        
   "Description TEXT, ".    
   "StreetNumber TEXT, ".
   "Street TEXT, ".    
   "City TEXT, ".
   "Council TEXT, ".
   "Features TEXT, ".
   "CreatedBy INTEGER ZEROFILL"; 

sub createTable

{
   my $this = shift;
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $tableName = $this->{'tableName'};
 
   my $SQL_CREATE_TABLE_PREFIX = "CREATE TABLE IF NOT EXISTS $tableName (";
   my $SQL_CREATE_TABLE_SUFFIX = ")";
   
   if ($sqlClient)
   {
      # append table prefix, original table body and table suffix
      if ($this->{'tableType'} == 0)
      {
         $sqlStatement = $SQL_CREATE_TABLE_PREFIX.$SQL_CREATE_SALES_TABLE_BODY.$SQL_CREATE_TABLE_SUFFIX;
      }
      else
      {
         $sqlStatement = $SQL_CREATE_TABLE_PREFIX.$SQL_CREATE_RENTALS_TABLE_BODY.$SQL_CREATE_TABLE_SUFFIX;
      }
      
      $statement = $sqlClient->prepareStatement($sqlStatement);
      
      if ($sqlClient->executeStatement($statement))
      {
         $success = 1;
         
         # 27Nov04: create the corresponding change table
         $this->_createChangeTable();
         # 29Nov04: create the corresponding working view
         $this->_createWorkingViewTable();
         # 30Nov04: create the corresponding working view
         $this->_createCacheViewTable();
      }
     
   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------
# setDateEntered
# sets the dateEntered field to use for the next add (instead of currentTime)
# 
# Purpose:
#  Storing information in the database
#
# Parameters:
#  date to use
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
sub setDateEntered

{
   my $this = shift;
   my $currentYear = shift;
   my $currentMonth = shift;
   my $currentDay = shift;
   my $currentHour = shift;
   my $currentMin = shift;
   my $currentSec = shift;
   
   $this->{'dateEntered'} = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $currentYear, $currentMonth, $currentDay, $currentHour, $currentMin, $currentSec);
   $this->{'useDifferentTime'} = 1;
}

# -------------------------------------------------------------------------------------------------
# addRecord
# adds a record of data to the AdvertisedxProfiles table
# OPERATES ON ALL VIEWS (cache and working view is updated)
#
# Purpose:
#  Storing information in the database
#
# Parameters:
#  string source name
#  reference to a hash containing the values to insert
#  string sourceURL
#  integer checksum
#  string instanceID
#  integer transactionNo
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
   my $sourceName = shift;
   my $parametersRef = shift;
   my $url = shift;
   my $checksum = shift;
   my $instanceID = shift;
   my $transactionNo = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   my $tableName = $this->{'tableName'};
   my $localTime;
   
   my $identifier = -1;
   
   if ($sqlClient)
   {
      $statementText = "INSERT INTO $tableName (";
      
      @columnNames = keys %$parametersRef;
      
      # modify the statement to specify each column value to set 
      $appendString = "DateEntered, identifier, sourceName, sourceURL, checksum, instanceID, transactionNo, ";
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
      $quotedSource = $sqlClient->quote($sourceName);
      $quotedUrl = $sqlClient->quote($url);
      $quotedInstance = $sqlClient->quote($instanceID);
      
      if (!$this->{'useDifferentTime'})
      {
         $localTime = "localtime()";
      }
      else
      {
         # use the specified date instead of the current time
         $localTime = $sqlClient->quote($this->{'dateEntered'});
         $this->{'useDifferentTime'} = 0;  # reset the flag
      }      
      
      $appendString = "$localTime, null, $quotedSource, $quotedUrl, $checksum, $quotedInstance, $transactionNo, ";
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
         
         # 27Nov04 - get the identifier (primaryKey) of the record just created and return it
         # note the most recent DateEntered can't be used reliably (if recovering from logs, or if multiple processes running)
         # instead we use: the parameters defining this instance
         $sqlStatement = "select identifier from $tableName where sourceName=$quotedSource and sourceURL=$quotedUrl and checksum=$checksum and instanceID = $quotedInstance and transactionNo = $transactionNo order by DateEntered";
         @selectResults = $sqlClient->doSQLSelect($sqlStatement);
        
         # only one result should be returned - if there's more than one, then we have a problem, to avoid it always take
         # the most recent entry which is the last in the list due to the 'order by' command
         $lastRecordHashRef = $selectResults[$#selectResults];
         $identifier = $$lastRecordHashRef{'identifier'};
         
         # --- add the new record to the cache and working view ---
         if ($identifier)
         {
            $this->_cacheView_addRecord($identifier, $sourceName, $parametersRef, $checksum);
            $this->_workingView_addRecord($identifier);
            
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
         $statementText = "DROP TABLE CacheView_$tableName";
         $statement = $sqlClient->prepareStatement($statementText);
         
         if ($sqlClient->executeStatement($statement))
         {

            $statementText = "DROP TABLE ChangeTable_$tableName";
            $statement = $sqlClient->prepareStatement($statementText);
            
            if ($sqlClient->executeStatement($statement))
            { 
               
               $statementText = "DROP TABLE WorkingView_$tableName";
               $statement = $sqlClient->prepareStatement($statementText);
               
               if ($sqlClient->executeStatement($statement))
               {       
            
                  $success = 1;
               }
            }
         }
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
# _checkIfTupleExists_Sales  (SALES ONLY VERSION)
# checks whether the specified tuple exists in the table (part of this check uses a checksum)
# OPERATES ON THE CACHEVIEW
#
# Purpose:
#  tracking data parsed by the agent
#
# Parameters:
#  string source
#  string sourceID
#  string checksum (ignored if undef)
#  integer priceLower (ignored if undef)
#  integer priceUpper (not used)

# Constraints:
#  nil
#
# Updates:
#  Nil
#
# Returns:
#   nil
sub _checkIfTupleExists_Sales
{   
   my $this = shift;
   my $sourceName = shift;      
   my $sourceID = shift;
   my $checksum = shift;
   my $advertisedPriceLower = shift;
   my $advertisedPriceUpper = shift;
   my $statement;
   my $found = 0;
   my $statementText;
      
   my $sqlClient = $this->{'sqlClient'};
   my $tableName = $this->{'tableName'};
   
   if ($sqlClient)
   {       
      $quotedSource = $sqlClient->quote($sourceName);
      $quotedSourceID = $sqlClient->quote($sourceID);
      $quotedUrl = $sqlClient->quote($url);
      
      if (defined $checksum)
      {
         if ($advertisedPriceLower)
         {
            $statementText = "SELECT sourceName, sourceID, checksum, advertisedPriceLower FROM CacheView_$tableName WHERE sourceName = $quotedSource and sourceID = $quotedSourceID and checksum = $checksum and advertisedPriceLower = $advertisedPriceLower";
         }
         else
         {
            $statementText = "SELECT sourceName, sourceID, checksum FROM CacheView_$tableName WHERE sourceName = $quotedSource and sourceID = $quotedSourceID and checksum = $checksum";
         }
      }
      else
      {
         #print "   checkIfTupleExists:noChecksum\n";
         if ($advertisedPriceLower)
         {
            #print "   checkIfTupleExists:apl=$advertisedPriceLower\n";

            $statementText = "SELECT sourceName, sourceID, advertisedPriceLower FROM CacheView_$tableName WHERE sourceName = $quotedSource and sourceID = $quotedSourceID and advertisedPriceLower = $advertisedPriceLower";
         }
         else
         {
            #print "   checkIfTupleExists:no apl\n";

            $statementText = "SELECT sourceName, sourceID FROM CacheView_$tableName WHERE sourceName = $quotedSource and sourceID = $quotedSourceID";
         }
      }
      
      #print "   checkIfTupleExists: $statementText\n";      
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
               
               if (($$_{'checksum'} == $checksum) && ($$_{'sourceName'} == $sourceName) && ($$_{'sourceID'} == $sourceID) && ($$_{'advertisedPriceLower'} = $advertisedPriceLower))            
               {
                  # found a match
                  $found = 1;
                  last;
               }
            }
            else
            {
               # $_ is a reference to a hash
               if (($$_{'checksum'} == $checksum) && ($$_{'sourceName'} == $sourceName) && ($$_{'sourceID'} == $sourceID))            
               {
                  # found a match
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
# _checkIfTupleExists_Rentals (RENTALS ONLY VERSION)
# checks whether the specified tuple exists in the table (part of this check uses a checksum)
#
# Purpose:
#  tracking data parsed by the agent
#
# Parameters:
#  string source
#  string sourceID
#  string checksum (ignored if undef)
# integer advertisedWeeklyRent
# Constraints:
#  nil
#
# Updates:
#  Nil
#
# Returns:
#   nil
sub _checkIfTupleExists_Rentals
{   
   my $this = shift;
   my $sourceName = shift;      
   my $sourceID = shift;
   my $checksum = shift;
   my $advertisedWeeklyRent = shift;
   my $statement;
   my $found = 0;
   my $statementText;
   
   my $sqlClient = $this->{'sqlClient'};
   my $tableName = $this->{'tableName'};
   
   if ($sqlClient)
   {       
      $quotedSource = $sqlClient->quote($sourceName);
      $quotedSourceID = $sqlClient->quote($sourceID);
      $quotedUrl = $sqlClient->quote($url);
      if (defined $checksum)
      {  
         if ($advertisedWeeklyRent)
         {
            $statementText = "SELECT sourceName, sourceID, checksum, advertisedWeeklyRent FROM CacheView_$tableName WHERE sourceName = $quotedSource and sourceID = $quotedSourceID and checksum = $checksum and advertisedWeeklyRent = $advertisedWeeklyRent";
         }
         else
         {
            $statementText = "SELECT sourceName, sourceID, checksum FROM CacheView_$tableName WHERE sourceName = $quotedSource and sourceID = $quotedSourceID and checksum = $checksum";
         }
      }
      else
      {
         if ($advertisedWeeklyRent)
         {
            $statementText = "SELECT sourceName, sourceID, advertisedWeeklyRent FROM CacheView_$tableName WHERE sourceName = $quotedSource and sourceID = $quotedSourceID and advertisedWeeklyRent = $advertisedWeeklyRent";
         }
         else
         {
            $statementText = "SELECT sourceName, sourceID FROM CacheView_$tableName WHERE sourceName = $quotedSource and sourceID = $quotedSourceID";
         }
      }      
            
      $statement = $sqlClient->prepareStatement($statementText);
      
      if ($sqlClient->executeStatement($statement))
      {
         # get the array of rows from the table
         @checksumList = $sqlClient->fetchResults();
                           
         foreach (@checksumList)
         {        
            if ($advertisedWeeklyRent)
            {
               # $_ is a reference to a hash
               if (($$_{'checksum'} == $checksum) && ($$_{'sourceName'} == $sourceName) && ($$_{'sourceID'} == $sourceID) && ($$_{'advertisedWeeklyRent'} == $advertisedWeeklyRent))            
               {
                  # found a match
                  $found = 1;
                  last;
               }
            }
            else
            {
               # $_ is a reference to a hash
               if (($$_{'checksum'} == $checksum) && ($$_{'sourceName'} == $sourceName) && ($$_{'sourceID'} == $sourceID))            
               {
                  # found a match
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
# OPERATES ON THE CACHEVIEW
#
# Purpose:
#  tracking data parsed by the agent
#
# Parameters:
#  string source
#  string sourceID
#  string checksum (ignored if undef)
#  integer priceLower (ignored if undef)
#  integer priceUpper (not used)

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
   my $sourceName = shift;      
   my $sourceID = shift;
   my $checksum = shift;
   my $priceLower = shift;
   my $priceUpper = shift;

   my $tableType = $this->{'tableType'};
   
   if ($tableType == 0)
   {
      $found = $this->_checkIfTupleExists_Sales($sourceName, $sourceID, $checksum, $priceLower, $priceUpper);
   }
   else
   {      
      $found = $this->_checkIfTupleExists_Rentals($sourceName, $sourceID, $checksum, $priceLower);
   }

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
         $localTime = "localtime()";
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
           "WHERE (sourceID = $quotedSourceID AND sourceName = $quotedSource AND checksum = $checksum)";
      }
      else
      {
         $statementText = "UPDATE $tableName ".
           "SET LastEncountered = $localTime ".
           "WHERE (sourceID = $quotedSourceID AND sourceName = $quotedSource)";
      }
      
      $statement = $sqlClient->prepareStatement($statementText);
      
      if ($sqlClient->executeStatement($statement))
      {
         $success = 1;
      }
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
      "ChangesRecord INTEGER ZEROFILL, ".  # primary key
      "ChangedBy TEXT)";                   # who/what changed it 
      
   if ($sqlClient)
   {
      # append change table prefix, original table body and change table suffix
      if ($this->{'tableType'} == 0)
      {
         $sqlStatement = $SQL_CREATE_CHANGE_TABLE_PREFIX.$SQL_CREATE_SALES_TABLE_BODY.$SQL_CREATE_CHANGE_TABLE_SUFFIX;
      }
      else
      {
         $sqlStatement = $SQL_CREATE_CHANGE_TABLE_PREFIX.$SQL_CREATE_RENTALS_TABLE_BODY.$SQL_CREATE_CHANGE_TABLE_SUFFIX;
      }
      
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
#  data transaction.   Note ONLY the WORKING VIEW is updated, not the main view (and consequently 
# the cacheView also isn't updated)
# 
# Purpose:
#  Storing information in the database
#
# Parameters:
#  reference to a hash containing the values to insert
#  string sourceURL
#  string instanceID
#  integer transactionNo
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
   my $instanceID = shift;
   my $transactionNo = shift;
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
      # order by revese data limit 1 to get the last entry
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
         $appendString = "DateEntered, identifier, instanceID, transactionNo, ChangesRecord, ChangedBy, ";
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
            $localTime = "localtime()";
         }
         else
         {
            # use the specified date instead of the current time
            $localTime = $sqlClient->quote($this->{'dateEntered'});
            $this->{'useDifferentTime'} = 0;  # reset the flag
         }      
         
         $appendString = "$localTime, null, $quotedInstance, $transactionNo, $sourceIdentifier, $quotedChangedBy, ";
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
       "ComponentOf INTEGER ZEROFILL)";           # foreign key to master property table
    
   
   if ($sqlClient)
   {
      # append change table prefix, original table body and change table suffix
      if ($this->{'tableType'} == 0)
      {
         $sqlStatement = $SQL_CREATE_WORKINGVIEW_TABLE_PREFIX.$SQL_CREATE_SALES_TABLE_BODY.$SQL_CREATE_WORKINGVIEW_TABLE_SUFFIX;
      }
      else
      {
         $sqlStatement = $SQL_CREATE_WORKINGVIEW_TABLE_PREFIX.$SQL_CREATE_RENTALS_TABLE_BODY.$SQL_CREATE_WORKINGVIEW_TABLE_SUFFIX;         
      }
      
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

# -------------------------------------------------------------------------------------------------
# _createCacheViewTable
# attempts to create the CacheView_AdvertisedxProfiles table in the database if it doesn't already exist
# This is a smaller view of the table used for faster fetch/comparison
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

sub _createCacheViewTable

{
   my $this = shift;
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $tableName = $this->{'tableName'};

   my $SQL_CREATE_CACHEVIEW_TABLE_PREFIX = "CREATE TABLE IF NOT EXISTS CacheView_$tableName (";
   my $SQL_CREATE_CACHEVIEW_SALES_TABLE_BODY = 
       "SourceName TEXT, ".
       "SourceID VARCHAR(20), ".
       "Checksum INTEGER, ".
       "Identifier INTEGER ZEROFILL PRIMARY KEY AUTO_INCREMENT, ".    
       "AdvertisedPriceLower DECIMAL(10,2)";
   my $SQL_CREATE_CACHEVIEW_RENTALS_TABLE_BODY = 
       "SourceName TEXT, ".
       "SourceID VARCHAR(20), ".
       "Checksum INTEGER, ".
       "Identifier INTEGER ZEROFILL PRIMARY KEY AUTO_INCREMENT, ".    
       "AdvertisedWeeklyRent DECIMAL(10,2)";        
   my $SQL_CREATE_CACHEVIEW_TABLE_SUFFIX = ")";         
   
   if ($sqlClient)
   {
      # append table prefix, original table body and table suffix
      if ($this->{'tableType'} == 0)
      {
         $sqlStatement = $SQL_CREATE_CACHEVIEW_TABLE_PREFIX.$SQL_CREATE_CACHEVIEW_SALES_TABLE_BODY.$SQL_CREATE_CACHEVIEW_TABLE_SUFFIX;
      }
      else
      {
         $sqlStatement = $SQL_CREATE_CACHEVIEW_TABLE_PREFIX.$SQL_CREATE_CACHEVIEW_RENTALS_TABLE_BODY.$SQL_CREATE_CACHEVIEW_TABLE_SUFFIX;
      }
      
      $statement = $sqlClient->prepareStatement($sqlStatement);
      
      if ($sqlClient->executeStatement($statement))
      {
         $success = 1;
      }
     
   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------


# -------------------------------------------------------------------------------------------------
# _cacheView_addRecord
# adds a record of data to the CacheView_AdvertisedxProfiles table
# 
# Purpose:
#  Storing information in the database
#
# Parameters:
#  integer identifier of the master record
#  string source name
#  reference to a hash containing the values to insert - this can be the fullset of parametrs, 
#   as only the cached ones will be extracted anyway
#  integer checksum
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
sub _cacheView_addRecord

{
   my $this = shift;
   my $identifier = shift;
   my $sourceName = shift;
   my $parametersRef = shift;
   my $checksum = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   my $tableName = $this->{'tableName'};
      
   if ($sqlClient)
   {
      $quotedIdentifier = $sqlClient->quote($identifier);
      $quotedSource = $sqlClient->quote($sourceName);
      $quotedID = $sqlClient->quote($$parametersRef{'SourceID'});
      
      if ($this->{'tableType'} == 0)
      {
         $quotedPrice = $sqlClient->quote($$parametersRef{'AdvertisedPriceLower'});
         $statementText = "INSERT INTO CacheView_$tableName (Identifier, SourceName, SourceID, Checksum, AdvertisedPriceLower) VALUES ($quotedIdentifier, $quotedSource, $quotedID, $checksum, $quotedPrice)";
      }
      else
      {
         $quotedPrice = $sqlClient->quote($$parametersRef{'AdvertisedWeeklyRent'});
         $statementText = "INSERT INTO CacheView_$tableName (Identifier, SourceName, SourceID, Checksum, AdvertisedWeeklyRent) VALUES ($quotedIdentifier, $quotedSource, $quotedID, $checksum, $quotedPrice)";         
      }
            
      #print "statement = ", $statementText, "\n";
      
      $statement = $sqlClient->prepareStatement($statementText);
      
      if ($sqlClient->executeStatement($statement))
      {
         $success = 1;
      }
   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------

