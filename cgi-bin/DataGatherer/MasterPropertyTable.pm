#!/usr/bin/perl
# Written by Jeromy Evans
# Started 5 December 2004
# 
# WBS: A.01.03.01 Developed On-line Database
# Version 0.1  
#
# Description:
#   Module that encapsulate the MasterPropertyTable database component
# 
# History:

# CONVENTIONS
# _ indicates a private variable or method
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
package MasterPropertyTable;
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

# Contructor for the masterPropertyTable - returns an instance of this object
# PUBLIC
sub new
{   
   my $sqlClient = shift;
   
   my $masterPropertyTable = { 
      sqlClient => $sqlClient,
      tableName => "MasterPropertyTable"
   }; 
      
   bless $masterPropertyTable;     
   
   return $masterPropertyTable;   # return this
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# createTable
# attempts to create the MasterPropertyTable table in the database if it doesn't already exist
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

my $SQL_CREATE_TABLE_PREFIX = "CREATE TABLE IF NOT EXISTS MasterPropertyTable (";
my $SQL_CREATE_TABLE_BODY = 
    "DateEntered DATETIME NOT NULL, ".
    "Identifier INTEGER ZEROFILL PRIMARY KEY AUTO_INCREMENT, ".    
    "StreetNumber TEXT, ".
    "Street TEXT, ".    
    "SuburbName TEXT, ".
    "SuburbIndex INTEGER UNSIGNED ZEROFILL, ".
    "State TEXT";
my $SQL_CREATE_TABLE_SUFFIX = ")";
           
sub createTable

{
   my $this = shift;
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   
   if ($sqlClient)
   {
      # append table prefix, original table body and table suffix
      $sqlStatement = $SQL_CREATE_TABLE_PREFIX.$SQL_CREATE_TABLE_BODY.$SQL_CREATE_TABLE_SUFFIX;
      
      $statement = $sqlClient->prepareStatement($sqlStatement);
      
      if ($sqlClient->executeStatement($statement))
      {
         $success = 1;
      }
     
   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------
# lookupPropertyIdentifier
# Returns the identifier of the property matching the specified address
#
# Purpose:
#  Storing information in the database
#
# Parameters:
# 
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
sub lookupPropertyIdentifier

{
   my $this = shift;
   my $parametersRef = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   my $tableName = $this->{'tableName'};
   my $localTime;
   
   my $identifier = -1;

   if ($sqlClient)
   {
      $quotedStreetNumber = $sqlClient->quote($$parametersRef{'StreetNumber'});
      $quotedStreet = $sqlClient->quote($$parametersRef{'Street'});
      $suburbIndex = $$parametersRef{'SuburbIndex'};

      # 27Nov04 - check if there's already a record defined for that address
      $sqlStatement = "select identifier from $tableName where StreetNumber=$quotedStreetNumber and Street=$quotedStreet and SuburbIndex=$suburbIndex";
      @selectResults = $sqlClient->doSQLSelect($sqlStatement);
     
      # only ZERO or ONE result should be returned - if there's more than one, then we have a problem, to avoid it always take
      # the most recent entry which is the last in the list due to the 'order by' command
      $lastRecordHashRef = $selectResults[$#selectResults];
      $identifier = $$lastRecordHashRef{'identifier'};

      if (!defined $identifier)
      {
         $identifier = -1;
      }
   }
   
   return $identifier;
}
# -------------------------------------------------------------------------------------------------
# linkRecord
# links a record of data to the MasterPropertyTable table
#
# Purpose:
#  Storing information in the database
#
# Parameters:
# 
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
sub linkRecord

{
   my $this = shift;
   my $parametersRef = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   my $tableName = $this->{'tableName'};
   
   my $identifier = -1;
  
   if ($sqlClient)
   {
      # check if the property already exists for the specified address...
      $identifier = $this->lookupPropertyIdentifier($parametersRef);
      
      if ($identifier >= 0)
      {
         # that property record already exists - the identifier can be returned as-as
         #print "   property($identifier) already created.\n";
      }
      else
      {
         # add a new record to the master property table
         $quotedStreetNumber = $sqlClient->quote($$parametersRef{'StreetNumber'});
         $quotedStreet = $sqlClient->quote($$parametersRef{'Street'});
         $quotedSuburbName = $sqlClient->quote($$parametersRef{'SuburbName'});
         $suburbIndex = $$parametersRef{'SuburbIndex'};
         $quotedState = $sqlClient->quote($$parametersRef{'State'});
         
         $statementText = "INSERT INTO $tableName (DateEntered, Identifier, StreetNumber, Street, SuburbName, SuburbIndex, State) VALUES ";
         $statementText .= "(localtime(), null, $quotedStreetNumber, $quotedStreet, $quotedSuburbName, $suburbIndex, $quotedState)";
      
         #print "statement = ", $statementText, "\n";
      
         $statement = $sqlClient->prepareStatement($statementText);
         
         if ($sqlClient->executeStatement($statement))
         {
            $success = 1;
         
            # lookup the property identifier just created
            $identifier = $this->lookupPropertyIdentifier($parametersRef);  
          
            #print "   created new property($identifier).\n";

         }
      }
   }
   
   return $identifier;   
}

# -------------------------------------------------------------------------------------------------
# dropTable
# attempts to drop the MasterPropertyTable table 
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
my $SQL_DROP_TABLE_STATEMENT = "DROP TABLE MasterPropertyTable";
        
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
# returns the number of properties in the database
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