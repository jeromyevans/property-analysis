#!/usr/bin/perl
# Written by Jeromy Evans
# Started 13 March 2004
# 
# WBS: A.01.03.01 Developed On-line Database
# Version 0.1  
#
# Description:
#   Module that encapsulate the AdvertisedSaleProfiles database component
# 
# History:
#   18 May 2004 - fixed bug in addRecord that failed to properly quote every
#     variable (it addded quotes, but didn't call use the sqlclient quote method
#     to escape quotes contained inside the value.
#
#   9 July 2004 - Merged with LogTable to record encounter information (date last encountered, url, checksum)
#  to support searches like get records 'still advertised'
#
# CONVENTIONS
# _ indicates a private variable or method
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
package AdvertisedSaleProfiles;
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

# Contructor for the AdvertisedSaleProfiles - returns an instance of this object
# PUBLIC
sub new
{   
   my $sqlClient = shift;
   
   my $advertisedSaleProfiles = { 
      sqlClient => $sqlClient,
      tableName => "advertisedSaleProfiles"
   }; 
      
   bless $advertisedSaleProfiles;     
   
   return $advertisedSaleProfiles;   # return this
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
# This statement below is just temporary for the statement to modify from the old table form
#INSERT INTO AdvertisedSaleProfiles (DateEntered, LastEncountered, SourceName, SourceURL, SourceID, Checksum,
#   SuburbIdentifier, SuburbName, Type, Bedrooms, Bathrooms, Land, YearBuilt, AdvertisedPriceLower,
#   AdvertisedPriceUpper, Description, StreetNumber, Street, City, Council, Features) 
#   SELECT oldSaleProfiles.DateEntered, LastEncountered, "REIWA", sourceURL, sourceID, checksum,
#   SuburbIdentifier, SuburbName, Type, Bedrooms, bathrooms, Land, YearBuilt, AdvertisedPriceLower, 
#   AdvertisedPriceUpper, Description, StreetNumber, Street, City, Council, Features
#   FROM oldSaleProfiles, oldSaleProfilesLog
#   WHERE oldSaleProfiles.sourceID = oldSaleProfilesLog.uniqueID
#   GROUP BY uniqueID, checksum;
   
my $SQL_CREATE_TABLE_STATEMENT = "CREATE TABLE IF NOT EXISTS AdvertisedSaleProfiles ".
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
    "AdvertisedPriceLower DECIMAL(10,2), ".
    "AdvertisedPriceUpper DECIMAL(10,2), ".
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
# adds a record of data to the AdvertisedSaleProfiles table
# 
# Purpose:
#  Storing information in the database
#
# Parameters:
#  string source name
#  reference to a hash containing the values to insert
#  string sourceURL
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
      $statementText = "INSERT INTO AdvertisedSaleProfiles (";
      
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
# attempts to drop the AdvertisedSaleProfiles table 
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
my $SQL_DROP_TABLE_STATEMENT = "DROP TABLE AdvertisedSaleProfiles";
        
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
      my $statementText = "SELECT count(DateEntered) FROM AdvertisedSaleProfiles";
   
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
            $statementText = "SELECT sourceName, sourceID, checksum, advertisedPriceLower FROM $tableName WHERE sourceName = $quotedSource and sourceID = $quotedSourceID and checksum = $checksum and advertisedPriceLower = $advertisedPriceLower";
         }
         else
         {
            $statementText = "SELECT sourceName, sourceID, checksum FROM $tableName WHERE sourceName = $quotedSource and sourceID = $quotedSourceID and checksum = $checksum";
         }
      }
      else
      {
         if ($advertisedPriceLower)
         {
            $statementText = "SELECT sourceName, sourceID, advertisedPriceLower FROM $tableName WHERE sourceName = $quotedSource and sourceID = $quotedSourceID and advertisedPriceLower = $advertisedPriceLower";
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


