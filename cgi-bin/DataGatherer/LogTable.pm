#!/usr/bin/perl
# Written by Jeromy Evans
# Started 14 March 2004
# 
# WBS: A.01.03.01 Developed On-line Database
# Version 0.0  
#
# Description:
#   Module that encapsulate the LogTable database components
#
# History
#  18 May 2004 - fixed bug in CheckIfUniqueIDExists that used a lowercase U in the 
#    hash field name, causing it to never mactch the ID in the database - the 
#    query would work, but the comparison wouldn't.  Perhaps the table in the database 
#    during testing was 'uniqueID' not 'UniqueID' - entirely possible as it was created
#    by 'update table' instead of 'create table'

# CONVENTIONS
# _ indicates a private variable or method
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
package LogTable;
require Exporter;

use DBI;
use SQLClient;
use DebugTools;

@ISA = qw(Exporter);


#@EXPORT = qw(&parseContent);

# -------------------------------------------------------------------------------------------------
# PUBLIC enumerations
#
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

# Contructor for the LogTable - returns an instance of the LogTable object
# PUBLIC
sub new
{   
   my $sqlClient = shift;
   my $tableName = shift;
   
   my $logTable = { 
      sqlClient => $sqlClient,
      tableName => $tableName
   }; 
      
   bless $logTable;         
   
   return $logTable;   # return this
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# createTable
# attempts to create the LogTable table in the database if it doesn't already exist
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

sub createTable

{
   my $this = shift;      
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $tableName = $this->{'tableName'};    
   
   if ($sqlClient)
   {
      $statement = $sqlClient->prepareStatement("CREATE TABLE IF NOT EXISTS $tableName (DateEntered DATETIME, SourceURL TEXT, UniqueID TEXT, CheckSum INTEGER, TimesEncountered INTEGER, LastEncountered DATETIME)");
      
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
        
sub dropTable

{
   my $this = shift;
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $tableName = $this->{'tableName'};  
   
   if ($sqlClient)
   {
      $statement = $sqlClient->prepareStatement("DROP TABLE $tableName");
      
      if ($sqlClient->executeStatement($statement))
      {
         $success = 1;
      }
   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------
# checkIfTupleExists
# checks whether the specified tuple checksum exists in the logfile
#
# Purpose:
#  tracking data parsed by the agent
#
# Parameters:
#  string url
#  string checksum
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
   my $url = shift;
   my $checksum = shift;
   my $statement;
   my $found = 0;
   
   my $sqlClient = $this->{'sqlClient'};
   my $tableName = $this->{'tableName'};
   
   if ($sqlClient)
   {       
      $quotedUrl = $sqlClient->quote($url);      
      my $statementText = "SELECT sourceurl, checksum FROM $tableName WHERE sourceurl = $quotedUrl and checksum = $checksum";
   
      $statement = $sqlClient->prepareStatement($statementText);
      
      if ($sqlClient->executeStatement($statement))
      {
         # get the array of rows from the table
         @checksumList = $sqlClient->fetchResults();
                           
         foreach (@checksumList)
         {        
            # $_ is a reference to a hash
            if (($$_{'sourceurl'} eq $url) && ($$_{'checksum'} == $checksum))            
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
# checkIfUniqueIDExists
# checks whether the specified unqiue ID exists in the logfile
#
# Purpose:
#  tracking data parsed by the agent
#
# Parameters:
#  string unqiueID
#
# Constraints:
#  nil
#
# Updates:
#  Nil
#
# Returns:
#   boolean found
sub checkIfUniqueIDExists
{   
   my $this = shift;      
   my $uniqueID = shift;
   my $statement;
   my $found = 0;
   
   my $sqlClient = $this->{'sqlClient'};
   my $tableName = $this->{'tableName'};
   
   if ($sqlClient)
   {           
      $quotedUniqueID = $sqlClient->quote($uniqueID);
      my $statementText = "SELECT UniqueID FROM $tableName WHERE UniqueID=$quotedUniqueID";
   
      $statement = $sqlClient->prepareStatement($statementText);
      
      if ($sqlClient->executeStatement($statement))
      {
         # get the array of rows from the table
         @checksumList = $sqlClient->fetchResults();
                           
         foreach (@checksumList)
         {        
            # $_ is a reference to a hash
            if ($$_{'UniqueID'} eq $uniqueID)            
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
# addEncounter
# records in the log that a unique tuple with has been encountered again
# (used for tracking how often unchanged data is encountered, parsed and rejected)
# 
# Purpose:
#  Logging information in the database
#
# Parameters: 
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
      
sub addEncounterRecord

{
   my $this = shift;
   my $url = shift;
   my $checksum = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};  
   my $tableName = $this->{'tableName'};
   my $statementText;
   
   if ($sqlClient)
   {
      $statementText = "UPDATE $tableName ".
        "SET TimesEncountered = TimesEncountered+1,  LastEncountered = localtime() ".
        "WHERE (sourceURL = \"$url\" AND checksum = $checksum)";         
      
      $statement = $sqlClient->prepareStatement($statementText);
      
      if ($sqlClient->executeStatement($statement))
      {
         $success = 1;
      }
   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------
# addRecord
# adds a record of data to the log table
# 
# Purpose:
#  Logging information in the database
#
# Parameters:
#  string url
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
      
sub addRecord ($ $ $)

{
   my $this = shift;
   my $url = shift;
   my $uniqueID = shift;
   my $checksum = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};  
   my $tableName = $this->{'tableName'};
   my $statementText;
   
   if ($sqlClient)
   {
      $quotedURL = $sqlClient->quote($url);
      $quotedUniqueID = $sqlClient->quote($uniqueID);
      
      $statementText = "INSERT INTO $tableName ".
        "(DateEntered, SourceURL, UniqueID, Checksum, TimesEncountered, LastEncountered) VALUES ".
        "(localtime(), $quotedURL, $quotedUniqueID, $checksum, 0, null)";         
      
      $statement = $sqlClient->prepareStatement($statementText);
      
      if ($sqlClient->executeStatement($statement))
      {
         $success = 1;
      }
   }
   
   return $success;   
}
