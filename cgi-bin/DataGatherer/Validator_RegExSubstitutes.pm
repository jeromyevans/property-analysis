#!/usr/bin/perl
# Written by Jeromy Evans
# Started 27 November 2004
# 
# WBS: A.01.03.01 Developed On-line Database
# Version 0.0  
#
# Description:
#   Module that encapsulate the Validator_RegExSubstitutes database table
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
package Validator_RegExSubstitutes;
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

# Contructor for the Validator_RegExSubstitutes - returns an instance of an Validator_RegExSubstitutes object
# PUBLIC
sub new
{   
   my $sqlClient = shift;
   
   my $Validator_RegExSubstitutes = { 
      sqlClient => $sqlClient,
      tableName => "Validator_RegExSubstitutes"
   }; 
      
   bless $Validator_RegExSubstitutes;     
   
   return $Validator_RegExSubstitutes;   # return this
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# createTable
# attempts to create the Validator_RegExSubstitutes table in the database if it doesn't already exist
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
# IMPORTANT NOTE: the "IF NOT EXISTS" statement is not used here - if it already exists we want to 
# fail creating it so the default regex patterns aren't added again and existing patterns aren't lost
my $SQL_CREATE_TABLE_STATEMENT = "CREATE TABLE Validator_RegExSubstitutes ".
   "(DateEntered DATETIME NOT NULL, ".
   "Identifier INTEGER ZEROFILL PRIMARY KEY AUTO_INCREMENT, ".
   "FieldName TEXT, ".
   "RegEx TEXT, ".
   "Substitute TEXT)";
      
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
         
         # add default records - if the table already exists this section isn't entered, otherwise
         # duplicates would be created for these default patterns

         $this->addRecord('SuburbName', '^Mt\W', 'Mount ');         
         $this->addRecord('SuburbName', '\WUnder Offer', ' ');
         $this->addRecord('SuburbName', '\WOffers From', ' ');
         $this->addRecord('SuburbName', '\WOffer From', ' ');
         $this->addRecord('SuburbName', '\WOffers Above', ' ');
         $this->addRecord('SuburbName', '\WDeposit Taken', ' ');
         $this->addRecord('SuburbName', '\WSold\s', ' ');
         $this->addRecord('SuburbName', '\WSold$', ' ');
         $this->addRecord('SuburbName', '\WOffers In Excess Of', ' ');
         $this->addRecord('SuburbName', '\WPrice start From', ' ');
         $this->addRecord('SuburbName', '\WNegotiate', ' ');
         $this->addRecord('SuburbName', '\WPriced From', ' ');
         $this->addRecord('SuburbName', '\WPrice From', ' ');
         $this->addRecord('SuburbName', '\WBuyers From', ' ');
         $this->addRecord('SuburbName', '\WBidding From', ' ');
         $this->addRecord('SuburbName', '\WBids From', ' ');
         $this->addRecord('SuburbName', '\Approx', ' ');
         $this->addRecord('SuburbName', '\WFrom\s', ' ');
         $this->addRecord('SuburbName', '\WFrom$', ' ');
       

         
         $this->addRecord('Street', '\WRd$',  ' Road ');         
         $this->addRecord('Street', '\WSt$',  ' Street ');
         $this->addRecord('Street', '\WAve$', ' Avenue ');
         $this->addRecord('Street', '\WAv$', ' Avenue ');
         $this->addRecord('Street', '\WPl$',  ' Place ');
         $this->addRecord('Street', '\WDr$',  ' Drive ');
         $this->addRecord('Street', '\WDve$',  ' Drive ');
         $this->addRecord('Street', '\WHwy$',  ' Highway ');
         $this->addRecord('Street', '\WCt$',  ' Court ');
         $this->addRecord('Street', '\WCl$',  ' Close ');
         $this->addRecord('Street', '\WPd$',  ' Parade ');
         $this->addRecord('Street', '\WPde$',  ' Parade ');
         $this->addRecord('Street', '\WWy$',  ' Way ');
         $this->addRecord('Street', '\WCres$',  ' Crescent ');
         $this->addRecord('Street', '\WCresent$',  ' Cresent ');
         $this->addRecord('Street', '\WCrt$',  ' Court ');
         $this->addRecord('Street', '\WCir$',  ' Circle ');
         $this->addRecord('Street', '^Cnr\s', ' Corner ');
         $this->addRecord('Street', '\WBlvd$', ' Boulevard ');
         $this->addRecord('Street', '\WBlvde$', ' Boulevard ');
         $this->addRecord('Street', '\WGrds$', ' Gardens ');
         $this->addRecord('Street', '\WPkwy$', ' Parkway ');
         $this->addRecord('Street', '\WTce$', ' Terrace ');
         $this->addRecord('Street', '[\W]*Under Offer', ' ');
         $this->addRecord('Street', '[\W]*Sale By Negotiation', ' ');
         $this->addRecord('Street', '[\W]*Price On Application', ' ');
         $this->addRecord('Street', '[\W]*Sale By Negotiation', ' ');
         $this->addRecord('Street', '[\W]*Auction', ' ');
         $this->addRecord('Street', '[\W]*Bedrooms', ' ');
         $this->addRecord('Street', '[\W]*Bathrooms', ' ');
         $this->addRecord('Street', '[\W]*Add To Shortlist', ' ');
         
         $this->addRecord('StreetNumber', 'Prop[\d|\s]*', ' ');
      }
   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------
# addRecord
# adds a record of data to the Validator_RegExSubstitutes table
# 
# Purpose:
#  Storing information in the database
#
# Parameters:
#  string FieldName   
#  string RegEx       - pattern to match
#  string Substitute  - pattern to substitute
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
   my $fieldName = shift;
   my $regEx = shift;
   my $substitute = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   my $identifier = -1;
   
   if ($sqlClient)
   {
      $statementText = "INSERT INTO Validator_RegExSubstitutes (";
            
      # modify the statement to specify each column value to set 
      $appendString = "DateEntered, identifier, FieldName, RegEx, Substitute";
      
      $statementText = $statementText.$appendString . ") VALUES (";
      
      # modify the statement to specify each column value to set 
      $index = 0;
      $quotedFieldName = $sqlClient->quote($fieldName);
      $quotedRegEx = $sqlClient->quote($regEx);
      $quotedSubstitute = $sqlClient->quote($substitute);

      $appendString = "localtime(), null, $quotedFieldName, $quotedRegEx, $quotedSubstitute)";

      $statementText = $statementText.$appendString;
      
      # prepare and execute the statement
      $statement = $sqlClient->prepareStatement($statementText);         
      if ($sqlClient->executeStatement($statement))
      {
         $success = 1;
      }
   }
   
   return $identifier;   
}

# -------------------------------------------------------------------------------------------------

# dropTable
# attempts to drop the Validator_RegExSubstitutes table 
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
my $SQL_DROP_TABLE_STATEMENT = "DROP TABLE Validator_RegExSubstitutes";
        
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
