#!/usr/bin/perl
# Written by Jeromy Evans
# Started 13 March 2004
# 
# WBS: A.01.03.01 Developed On-line Database
# Version 0.0  
#
# Description:
#   Module that encapsulate the SuburbProfiles database component
#
# History:
#   18 May 2004 - fixed bug in addRecord that failed to properly quote every
#     variable (it addded quotes, but didn't call use the sqlclient quote method
#     to escape quotes contained inside the value.
#
# CONVENTIONS
# _ indicates a private variable or method
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
package SuburbProfiles;
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

# Contructor for the SQLClient - returns an instance of an HTTPClient object
# PUBLIC
sub new
{   
   my $sqlClient = shift;
   
   my $suburbProfiles = { 
      sqlClient => $sqlClient,
      tableName => "SuburbProfiles"
   }; 
      
   bless $suburbProfiles;     
   
   return $suburbProfiles;   # return this
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# createTable
# attempts to create the SuburbProfiles table in the database if it doesn't already exist
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
my $SQL_CREATE_TABLE_STATEMENT = "CREATE TABLE IF NOT EXISTS SuburbProfiles ".
   "(DateEntered DATETIME NOT NULL, ".
    "LastEncountered DATETIME, ".
    "SourceName TEXT, ".
    "SourceURL TEXT, ".
    "SourceID VARCHAR(20), ".
    "Checksum INTEGER, ".
    "SuburbName VARCHAR(30) NOT NULL, ".
    "Identifier INTEGER ZEROFILL PRIMARY KEY AUTO_INCREMENT, ".
    "PostCode INTEGER, ".
    "Population INTEGER, ".
    "MedianAge INTEGER, ".
    "PercentOver65 DECIMAL(5,2), ".
    "DistanceToGPO DECIMAL(5,2), ".
    "NoOfHomes INTEGER, ".
    "PercentOwned DECIMAL(5,2), ".
    "PercentMortgaged DECIMAL(5,2), ".
    "PercentRental DECIMAL(5,2), ".
    "PercentNotStated DECIMAL(5,2), ".
    "MedianPrice DECIMAL(10,2), ".
    "MedianPercentChange12Months DECIMAL(5,2), ".
    "MedianPercentChange5Years DECIMAL(5,2), ".
    "HighestSale DECIMAL(10,2), ".
    "MedianWeeklyRent DECIMAL(5,2), ".
    "MedianMonthlyLoan DECIMAL(5,2), ".
    "MedianWeeklyIncome DECIMAL(5,2), ".
    "Schools TEXT, ".
    "Shops TEXT, ".
    "Trains TEXT, ".
    "Buses TEXT)";
      
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
# adds a record of data to the SuburbProfiles table
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
      $statementText = "INSERT INTO SuburbProfiles (";
      
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
# attempts to drop the SuburbProfiles table 
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
my $SQL_DROP_TABLE_STATEMENT = "DROP TABLE SuburbProfiles";
        
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
      my $statementText = "SELECT count(DateEntered) FROM SuburbProfiles";
   
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
#  string sourceName
#  string suburbName
#  string checksum (ignored if undef)
#
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
   my $suburbName = shift;
   my $checksum = shift;
   my $statement;
   my $found = 0;
   my $statementText;
   
   my $sqlClient = $this->{'sqlClient'};
   my $tableName = $this->{'tableName'};
   
   if ($sqlClient)
   {       
      $quotedSource = $sqlClient->quote($sourceName);
      $quotedSuburbName = $sqlClient->quote($suburbName);
      $quotedUrl = $sqlClient->quote($url);
      if (defined $checksum)
      {      
         $statementText = "SELECT sourceName, suburbName, checksum FROM $tableName WHERE sourceName = $quotedSource and suburbName = $quotedSuburbName and checksum = $checksum";
      }
      else
      {
         $statementText = "SELECT sourceName, suburbName FROM $tableName WHERE sourceName = $quotedSource and suburbName = $quotedSuburbName";
      }      
            
      $statement = $sqlClient->prepareStatement($statementText);
      
      if ($sqlClient->executeStatement($statement))
      {
         # get the array of rows from the table
         @checksumList = $sqlClient->fetchResults();
                           
         foreach (@checksumList)
         {        
            # $_ is a reference to a hash
            if (($$_{'checksum'} == $checksum) && ($$_{'sourceName'} == $sourceName) && ($$_{'suburbName'} == $suburbName))            
            {
               # found a match
               $found = 1;
               last;
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
#  string suburbName
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
   my $suburbName = shift;
   my $checksum = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};  
   my $tableName = $this->{'tableName'};
   my $statementText;
   
   if ($sqlClient)
   {
      $quotedSource = $sqlClient->quote($sourceName);
      $quotedSuburbName = $sqlClient->quote($suburbName);
      $quotedUrl = $sqlClient->quote($url);
  
      if (defined $checksum)
      {
         $statementText = "UPDATE $tableName ".
           "SET LastEncountered = localtime() ".
           "WHERE (suburbName = $quotedSuburbName AND sourceName = $quotedSource AND checksum = $checksum)";
      }
      else
      {
         $statementText = "UPDATE $tableName ".
           "SET LastEncountered = localtime() ".
           "WHERE (suburbName = $quotedSuburbName AND sourceName = $quotedSource)";
      }
      
      $statement = $sqlClient->prepareStatement($statementText);
      
      if ($sqlClient->executeStatement($statement))
      {
         $success = 1;
      }
   }
   
   return $success;   
}


