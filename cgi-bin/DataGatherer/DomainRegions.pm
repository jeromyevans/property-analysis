#!/usr/bin/perl
# Written by Jeromy Evans
# Started 29 October 2004
# 
# WBS: A.01.03.01 Developed On-line Database
# Version 0.0  
#
# Description:
#   Module that encapsulate the DomainRegions database component
#
# History:
#   
#
# CONVENTIONS
# _ indicates a private variable or method
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
package DomainRegions;
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

# Contructor for the DomainRegions - returns an instance of an DomainRegions object
# PUBLIC
sub new
{   
   my $sqlClient = shift;
   
   my $domainRegions = { 
      sqlClient => $sqlClient,
      tableName => "DomainRegions"
   }; 
      
   bless $domainRegions;     
   
   return $domainRegions;   # return this
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# createTable
# attempts to create the domainRegions table in the database if it doesn't already exist
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
my $SQL_CREATE_TABLE_STATEMENT = "CREATE TABLE IF NOT EXISTS DomainRegions ".
   "(Identifier INTEGER ZEROFILL PRIMARY KEY AUTO_INCREMENT, ".
    "Region TEXT, ".
    "Suburb TEXT, ".
    "State TEXT)";
      
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
# adds a record of data to the DomainRegions table
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
   my $parametersRef = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   
   if ($sqlClient)
   {
      $statementText = "INSERT INTO DomainRegions ";
         
      @columnNames = keys %$parametersRef;
      
      # modify the statement to specify each column value to set 
      $appendString = "(identifier, ";
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
      $appendString = "null, ";
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
my $SQL_DROP_TABLE_STATEMENT = "DROP TABLE DomainRegions";
        
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
      my $statementText = "SELECT count(Identifier) FROM DomainRegions";
   
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

