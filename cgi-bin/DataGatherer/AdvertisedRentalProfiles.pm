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
      sqlClient => $sqlClient
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
    "Identifier INTEGER ZEROFILL PRIMARY KEY AUTO_INCREMENT, ".    
    "SuburbIdentifier INTEGER, ".
    "SuburbName TEXT, ".
    "Type VARCHAR(10), ".
    "Bedrooms INTEGER, ".
    "Bathrooms INTEGER, ".        
    "Land INTEGER, ".
    "YearBuilt VARCHAR(5), ".
    "AdvertisedWeeklyRent DECIMAL(10,2), ".    
    "SourceID VARCHAR(20), ".    
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
   my $parametersRef = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   
   if ($sqlClient)
   {
      $statementText = "INSERT INTO AdvertisedRentalProfiles (";
      
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

