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
#  7 Dec 2004 - extended MasterPropertyTable to include fields for the master associated property details with 
#    references to each of the components (property details can be associated from more than one source)
#             - added support for MasterPropertyComponentsXRef table that provides a cross-reference of properties 
#    to the source components (opposite of the componentOf relationship)
#  8 Dec 2004 - added code to calculate and set the master component fields of an entry in the MasterPropertyTable
#    by looking up the components (via the XRef) and applying a selection algorithm.
#             - needed to use AdvertisedPropertyProfiles reference to lookup components (of workingview) - impacts
#    constructor
#
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
use AdvertisedPropertyProfiles;

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
   my $advertisedSaleProfiles = shift;
   
   my $masterPropertyTable = { 
      sqlClient => $sqlClient,
      tableName => "MasterPropertyTable",
      advertisedSaleProfiles => $advertisedSaleProfiles
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
    "State TEXT, ".
    "TypeSource INTEGER UNSIGNED ZEROFILL, ".
    "Type VARCHAR(10), ".
    "BedroomsSource INTEGER UNSIGNED ZEROFILL, ".
    "Bedrooms INTEGER, ".
    "BathroomsSource INTEGER UNSIGNED ZEROFILL, ".
    "Bathrooms INTEGER, ".
    "LandSource INTEGER UNSIGNED ZEROFILL, ".
    "Land INTEGER, ". 
    "YearBuiltSource INTEGER UNSIGNED ZEROFILL, ".
    "YearBuilt VARCHAR(5), ".
    "AdvertisedPriceSource INTEGER UNSIGNED ZEROFILL, ".
    "AdvertisedPriceLower DECIMAL(10,2), ".
    "AdvertisedPriceUpper DECIMAL(10,2), ".
    "AdvertisedWeeklyRentSource INTEGER UNSIGNED ZEROFILL, ".
    "AdvertisedWeeklyRent DECIMAL(10,2)";        
    
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
         $success = $this->_createXRefTable();
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
#  hash of component parameters
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
   my $advertisedSaleProfiles = $this{'advertisedSaleProfiles'};
   
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
          
            # set the componentOf relationship for the source record
            $advertisedSaleProfiles->workingView_setSpecialField($$parametersRef{'Identifier'}, 'ComponentOf', $identifier);   
            
            # add the XRef to the PropertyComponentXRef table - for faster lookup of property components
            $this->_addXRef($identifier, $$parametersRef{'Identifier'});
            #print "   created new property($identifier).\n";
            
            # lookup & calculate the master components for the property
            $this->_calculateMasterComponents($identifier);

         }
      }
   }
   
   return $identifier;   
}


# -------------------------------------------------------------------------------------------------
# _setMasterComponents
# sets the master components of a property 
#
# Purpose:
#  Storing information in the database
#
# Parameters:
#  propertyIdentifier
#  $typeSource
#  $type
#  $bedroomsSource 
#  $bedrooms
#  $bathroomsSource 
#  $bathrooms
#  $landSource 
#  $land
#  $yearBuiltSource 
#  $yearBuilt 
#  $advertisedPriceSource 
#  $advertisedPriceLower
#  $advertisedPriceUpper
#  $advertisedRentSource
#  $advertisedWeeklyRent
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
sub _setMasterComponents

{
   my $this = shift;
   my $propertyIdentifier = shift;
   
   my $typeSource = shift;
   my $type = shift;
   my $bedroomsSource = shift;
   my $bedrooms = shift;
   my $bathroomsSource = shift;
   my $bathrooms = shift;
   my $landSource = shift;
   my $land = shift;
   my $yearBuiltSource = shift;
   my $yearBuilt = shift;
   my $advertisedPriceSource = shift;
   my $advertisedPriceLower = shift;
   my $advertisedPriceUpper = shift;
   my $advertisedRentSource = shift;
   my $advertisedWeeklyRent = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   my $tableName = $this->{'tableName'};
     
   if ($sqlClient)
   {
      # update a record in the master property table
      $quotedPID = $sqlClient->quote($propertyIdentifier);
     
      $statementText = "UPDATE $tableName SET ".
                       "TypeSource = ". $sqlClient->quote($typeSource). ", ".
                       "Type = ". $sqlClient->quote($type). ", ".
                       "BedroomsSource = ". $sqlClient->quote($bedroomsSource). ", ".
                       "Bedrooms = ". $sqlClient->quote($bedrooms). ", ".
                       "BathroomsSource = ". $sqlClient->quote($bathroomsSource). ", ".
                       "Bathrooms = ". $sqlClient->quote($bathrooms). ", ".
                       "LandSource = ". $sqlClient->quote($landSource). ", ".
                       "Land = ". $sqlClient->quote($land). ", ".
                       "YearBuiltSource = ". $sqlClient->quote($yearBuiltSource). ", ".
                       "YearBuilt = ". $sqlClient->quote($yearBuilt). ", ".
                       "AdvertisedPriceSource = ". $sqlClient->quote($advertisedPriceSource). ", ".
                       "AdvertisedPriceLower = ". $sqlClient->quote($advertisedPriceLower). ", ".
                       "AdvertisedPriceUpper = ". $sqlClient->quote($advertisedPriceUpper). ", ".
                       "AdvertisedWeeklyRentSource = ". $sqlClient->quote($advertisedRentSource). ", ".
                       "AdvertisedWeeklyRent = ". $sqlClient->quote($advertisedWeeklyRent). " ".
                       "WHERE Identifier = $quotedPID";
                       
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
my $SQL_DROP_XREF_TABLE_STATEMENT = "DROP TABLE MasterPropertyComponentsXRef";
        
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
         $statement = $sqlClient->prepareStatement($SQL_DROP_XREF_TABLE_STATEMENT);
      
         if ($sqlClient->executeStatement($statement))
         {
             $success = 1;
         }
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
# -------------------------------------------------------------------------------------------------
# _createXRefTable
# attempts to create the MasterPropertyComponentsXRef table in the database if it doesn't already exist
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

my $SQL_CREATE_XREF_TABLE_PREFIX = "CREATE TABLE IF NOT EXISTS MasterPropertyComponentsXRef (";
my $SQL_CREATE_XREF_TABLE_BODY = 
    "DateEntered DATETIME NOT NULL, ".
    "Identifier INTEGER UNSIGNED ZEROFILL, ".  
    "hasComponent INTEGER UNSIGNED ZEROFILL";        
    
my $SQL_CREATE_XREF_TABLE_SUFFIX = ")";
           
sub _createXRefTable

{
   my $this = shift;
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   
   if ($sqlClient)
   {
      # append table prefix, original table body and table suffix
      $sqlStatement = $SQL_CREATE_XREF_TABLE_PREFIX.$SQL_CREATE_XREF_TABLE_BODY.$SQL_CREATE_XREF_TABLE_SUFFIX;
      
      $statement = $sqlClient->prepareStatement($sqlStatement);
      
      if ($sqlClient->executeStatement($statement))
      {
         $success = 1;
      }
     
   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# _addXRef
# adds the XRef between the MasterPropertyTable Identifer and an associated component
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
sub _addXRef

{
   my $this = shift;
   my $propertyIdentifier = shift;
   my $componentIdentifier = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   my $tableName = "MasterPropertyComponentsXRef";
     
   if ($sqlClient)
   {
      # add a new record to the master property table
      $quotedPID = $sqlClient->quote($propertyIdentifier);
      $quotedCID = $sqlClient->quote($componentIdentifier);
     
      $statementText = "INSERT INTO $tableName (DateEntered, Identifier, hasComponent) VALUES (localtime(), $quotedPID, $quotedCID)";
   
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
# -------------------------------------------------------------------------------------------------

# _calculateMasterComponents
# determines which components to use as the master components for the specified property
#   looks up the components from the XRef table AND WORKINGVIEW_ADVERTISEDSALEPROFILES
#
# Purpose:
#  Association
#
# Parameters:
#  integer propertyIdentifier
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
sub _calculateMasterComponents

{
   my $this = shift;
   my $propertyIdentifier = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   my $tableName = "MasterPropertyComponentsXRef";
   my @profileRef;
   my %masterProfile;
   
   if ($sqlClient)
   {
      $quotedPID = $sqlClient->quote($propertyIdentifier);
     
      # get all the components for the property
      
      @selectResults = $sqlClient->doSQLSelect("select Identifier, AdvertisedPriceUpper, AdvertisedPriceLower, Type, Bedrooms, Bathrooms, Land, YearBuilt from WorkingView_AdvertisedSaleProfiles where ComponentOf = $quotedPID order by DateEntered desc");
             
      # --- apply association/master component selection algorithms ---
      
      $length = @selectResults;
      print "PID $propertyIdentifier : $length components ";
      $advertisedPriceComponent = undef;
      $typeComponent = undef;
      $bedroomsComponent = undef;
      $bathroomsComponent = undef;
      $landComponent = undef;
      $yearBuiltComponent = undef;
      $advertisedPriceUpper = undef;
      $advertisedPriceLower = undef;
      $type = undef;
      $bedrooms = undef;
      $bathrooms = undef;
      $land = undef;
      $yearBuilt = undef;
      
      # loop through all the components... 
      foreach (@selectResults)
      {
         #print "CID:", $$_{'Identifier'}, "\n";
         # if price isn't set yet
         if ((!$advertisedPriceComponent) && ($$_{'AdvertisedPriceLower'}))
         {
            # set the price - (it's defined and this is the newest record)
            $advertisedPriceComponent = $$_{'Identifier'};
            $advertisedPriceLower = $$_{'AdvertisedPriceLower'};
            $advertisedPriceUpper = $$_{'AdvertisedPriceUpper'};
         }
         
         if ((!$bedroomsComponent) && ($$_{'Bedrooms'}))
         {
            # set the number of bedrooms (it's defined and this is the newest record)
            $bedroomsComponent = $$_{'Identifier'};
            $bedrooms = $$_{'Bedrooms'};
         }
         
         if ((!$bathroomsComponent) && ($$_{'Bathrooms'}))
         {
            # set the number of bathrooms (it's defined and this is the newest record)
            $bathroomsComponent = $$_{'Identifier'};
            $bathrooms = $$_{'Bathrooms'};
         }
         
         if ((!$landComponent) && ($$_{'Land'}))
         {
            # set the land area (it's defined and this is the newest record
            $landComponent = $$_{'Identifier'};
            $land = $$_{'Land'};
         }
         
         if ((!$yearBuiltComponent) && ($$_{'YearBuilt'}))
         {
            # set the year built (it's defined and this is the newest record)
            $yearBuiltComponent = $$_{'Identifier'};
            $yearBuilt = $$_{'YearBuilt'};
         }
         
         if ((!$typeComponent) && ($$_{'Type'}))
         {
            # set the type (it's defined and this is the newest record)
            $typeComponent = $$_{'Identifier'};
            $type = $$_{'Type'};
         }  
      }
      
      #print "$propertyIdentifier: $typeComponent=$type, $bedroomsComponent=$bedrooms, $bathroomsComponent=$bathrooms, $landComponent=$land, $yearBuiltComponent=$yearBuilt, $advertisedPriceComponent=$advertisedPriceLower&$advertisedPriceUpper\n";
print "T", defined $typeComponent || 0, "B", defined $bedroomsComponent || 0, "B", defined $bathroomsComponent || 0, "L", defined $landComponent || 0, "Y", defined $yearBuiltComponent || 0, "P", defined $advertisedPriceComponent || 0, "Rx\n";
      # update the MasterPropertyTable with the master profile and component identifier references
      $success = $this->_setMasterComponents($propertyIdentifier, $typeComponent, $type, $bedroomsComponent, $bedrooms, $bathroomsComponent, 
         $bathrooms, $landComponent, $land, $yearBuiltComponent, $yearBuilt, $advertisedPriceComponent, $advertisedPriceLower,
         $advertisedPriceUpper, undef, undef);
   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

