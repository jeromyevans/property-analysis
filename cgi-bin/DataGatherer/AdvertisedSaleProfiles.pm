#!/usr/bin/perl
# Written by Jeromy Evans
# Started 13 March 2004
# 
# WBS: A.01.03.01 Developed On-line Database
# Version 0.0  
#
# Description:
#   Module that encapsulate the AdvertisedSaleProfiles database component
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
      sqlClient => $sqlClient
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
my $SQL_CREATE_TABLE_STATEMENT = "CREATE TABLE IF NOT EXISTS AdvertisedSaleProfiles ".
   "(DateEntered DATETIME NOT NULL, ".
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
# adds a record of data to the AdvertisedSaleProfiles table
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
      $statementText = "INSERT INTO AdvertisedSaleProfiles (";
      
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

