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
      sqlClient => $sqlClient
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
   my $parametersRef = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   
   if ($sqlClient)
   {
      $statementText = "INSERT INTO SuburbProfiles (";
      
      @columnNames = keys %$parametersRef;
      
      # modify the statement to specify each column value to set 
      $appendString = "DateEntered, identifier, ";
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
      $appendString = "localtime(), null, ";
      foreach (@columnValues)
      {
	 if ($index != 0)
	 {
	    $appendString = $appendString.", ";
	 }
	
	 $appendString = $appendString . "\"".$_."\"";
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
