#!/usr/bin/perl
# Written by Jeromy Evans
# Started 8 May 2004
# 
# WBS: A.01.03.01 Developed On-line Database
# Version 0.0  
#
# Description:
#   Module that encapsulate the AdvertisedRentalProfiles database component
#
# History:
#   18 May 2004 - fixed bug in addRecord that failed to properly quote every
#     variable (it addded quotes, but didn't call use the sqlclient quote method
#     to escape quotes contained inside the value.
#
#   10 July 2004 - modified to combine with log table (added fields source URL, lastEncountered date etc)
#     to support searches such as 'still advertised'
#
# CONVENTIONS
# _ indicates a private variable or method
#
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#

package AdvertisedRentalProfiles;
require Exporter;

use DBI;
use SQLClient;

@ISA = qw(Exporter);

# -------------------------------------------------------------------------------------------------
# PUBLIC enumerations
#
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

# Contructor for the AdvertisedRentalProfiles - returns an instance of this object
# PUBLIC
sub new
{   
   my $sqlClient = shift;
   
   my $advertisedRentalProfiles = { 
      sqlClient => $sqlClient,
      tableName => "advertisedRentalProfiles"
   }; 
      
   bless $advertisedRentalProfiles;     
   
   return $advertisedRentalProfiles;   # return this
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# createTable
# attempts to create the advertisedRentalProfiles table in the database if it doesn't already exist
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

my $SQL_CREATE_TABLE_STATEMENT = "CREATE TABLE IF NOT EXISTS AdvertisedRentalProfiles ".
   "(DateEntered DATETIME NOT NULL, ".
    "LastEncountered DATETIME, ".
    "SourceName TEXT, ".
    "SourceURL TEXT, ".
    "SourceID VARCHAR(20), ".
    "Checksum INTEGER, ".
    "Identifier INTEGER ZEROFILL PRIMARY KEY AUTO_INCREMENT, ".    
    "SuburbIdentifier INTEGER, ".
    "SuburbName TEXT, ".
    "Type VARCHAR(10), ".
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
    "Features TEXT)";    
      
sub createTable

{
   my $this = shift;
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   
   if ($sqlClient)
   {
      $statement = $sqlClient->prepareStatement($SQL_CREATE_TABLE_STATEMENT);
      
      if ($sqlClient->executeStatement($statement))
      {
         $success = 1;
      }
   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------
# addRecord
# adds a record of data to the AdvertisedRentalProfiles table
# 
# Purpose:
#  Storing information in the database
#
# Parameters:
#  reference to a hash containing the values to insert
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
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   
   if ($sqlClient)
   {
      $statementText = "INSERT INTO AdvertisedRentalProfiles (";
      
      @columnNames = keys %$parametersRef;
      
      # modify the statement to specify each column value to set 
      $appendString = "DateEntered, identifier, sourceName, sourceURL, checksum, ";
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
      $appendString = "localtime(), null, $quotedSource, $quotedUrl, $checksum, ";
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
      }
   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------
# dropTable
# attempts to drop the AdvertisedRentalProfiles table 
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
my $SQL_DROP_TABLE_STATEMENT = "DROP TABLE AdvertisedRentalProfiles";
        
sub dropTable

{
   my $this = shift;
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   
   if ($sqlClient)
   {
      $statement = $sqlClient->prepareStatement($SQL_DROP_TABLE_STATEMENT);
      
      if ($sqlClient->executeStatement($statement))
      {
              $success = 1;
      }
   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# countEntries
# returns the number of advertised sales in the database
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
   my $url = shift;
   my $checksum = shift;
   my $statement;
   my $found = 0;
   my $noOfEntries = 0;
   
   my $sqlClient = $this->{'sqlClient'};
   my $tableName = $this->{'tableName'};
   
   if ($sqlClient)
   {       
      $quotedUrl = $sqlClient->quote($url);      
      my $statementText = "SELECT count(DateEntered) FROM AdvertisedRentalProfiles";
   
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
# checkIfTupleExists
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
sub checkIfTupleExists
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
            $statementText = "SELECT sourceName, sourceID, checksum, advertisedWeeklyRent FROM $tableName WHERE sourceName = $quotedSource and sourceID = $quotedSourceID and checksum = $checksum and advertisedWeeklyRent = $advertisedWeeklyRent";
         }
         else
         {
            $statementText = "SELECT sourceName, sourceID, checksum FROM $tableName WHERE sourceName = $quotedSource and sourceID = $quotedSourceID and checksum = $checksum";
         }
      }
      else
      {
         if ($advertisedWeeklyRent)
         {
            $statementText = "SELECT sourceName, sourceID, advertisedWeeklyRent FROM $tableName WHERE sourceName = $quotedSource and sourceID = $quotedSourceID and advertisedWeeklyRent = $advertisedWeeklyRent";
         }
         else
         {
            $statementText = "SELECT sourceName, sourceID FROM $tableName WHERE sourceName = $quotedSource and sourceID = $quotedSourceID";
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
   
   if ($sqlClient)
   {
      $quotedSource = $sqlClient->quote($sourceName);
      $quotedSourceID = $sqlClient->quote($sourceID);
      $quotedUrl = $sqlClient->quote($url);
  
      if (defined $checksum)
      {
         $statementText = "UPDATE $tableName ".
           "SET LastEncountered = localtime() ".
           "WHERE (sourceID = $quotedSourceID AND sourceName = $quotedSource AND checksum = $checksum)";
      }
      else
      {
         $statementText = "UPDATE $tableName ".
           "SET LastEncountered = localtime() ".
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


