#!/usr/bin/perl
# Written by Jeromy Evans
# Started 22 August 2004 2004
# 
# WBS: A.01.03.01 Developed On-line Database
# Version 0.1  
#
# Description:
#   Module that encapsulate the PropertyTypes database component
# 
#   TYPE_HOUSE=4   (houses)
#   TYPE_UNIT=1    (units, flats, villas, etc)
#   TYPE_LAND=5    (land)
#   TYPE_ALL=9     (houses, units, tourist, non-commercial, non-rural)
#   TYPE_UNKNOWN=0
#
# History:
#  13 November 2004 - this module isn't working yet.
#  13 March 2005 - Major change for use by SuburbPerformanceTable
#
# CONVENTIONS
# _ indicates a private variable or method
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
package PropertyTypes;
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

# Contructor for the PropertyTypes - returns an instance of this object
# PUBLIC
sub new
{   
   my $sqlClient = shift;
   my $typeDefinitions = 
   {
      TYPE_UNKNOWN => 0,
      TYPE_UNIT => 1,
      TYPE_COMMERCIAL => 2,
      TYPE_RURAL => 3,
      TYPE_HOUSE => 4,
      TYPE_LAND => 5,
      TYPE_SENIORS => 6,
      TYPE_TOURIST => 7,
      TYPE_OTHER => 8,
      TYPE_ALL => 9
   };
   
   my $propertyTypes = { 
      sqlClient => $sqlClient,
      tableName => "PropertyTypes",
      typeDefinitions => $typeDefinitions
   }; 
      
   bless $propertyTypes;     
   
   return $propertyTypes;   # return this
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# createTable
# attempts to create the PropertyTypes table in the database if it doesn't already exist
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
   
my $SQL_CREATE_TABLE_STATEMENT = "CREATE TABLE IF NOT EXISTS PropertyTypes ".
   "(TypeIndex INTEGER ZEROFILL PRIMARY KEY,".
    "Type VARCHAR(10))";    
    
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
                  
         while(($key, $value) = each(%$this)) 
         {
            # only use the TYPE_ definitions in the this hash
            if ($key =~ /TYPE_/)
            {
               # add the key and record to the SQL table
               $this->addRecord($value, $key);
            }
         }
      }
   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------
# addRecord
# adds a record of data to the PropertyTypes table
# 
# Purpose:
#  Storing information in the database
#
# Parameters:
#  string type name
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
   my $index = shift;
   my $type = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   
   if ($sqlClient)
   {
      $quotedType = $sqlClient->quote($type);
      $statementText = "INSERT INTO ".$this->{'tableName'}." (TypeIndex, Type) VALUES ($index, $quotedType)";
        
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
my $SQL_DROP_TABLE_STATEMENT = "DROP TABLE PropertyTypes";
        
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

# maps the property type specified to a property type index
sub mapPropertyType
{   
   my $this = shift;
   my $typeDescription = shift;
   my $typeName;
   my $matchedType;
   
   my $sqlClient = $this->{'sqlClient'};
   $typeDefinitions = $this->{'typeDefinitions'};
   
   if ($sqlClient)
   {
      if ($typeDescription)
      {
         if ($typeDescription =~ /Apartment|Flat|Unit|Duplex|Semi|Studio|Terrace|Townhouse|Villa/i) 
         {
            # apartment/unit-like properties
            $typeIndex = $typeDefinitions->{'TYPE_UNIT'};
         }
         else
         {
             if ($typeDescription =~ /Commercial|Warehouse/i)
             {
                # commercial/industrial
                $typeIndex = $typeDefinitions->{'TYPE_COMMERCIAL'};
             }
             else
             {
                if ($typeDescription =~ /Farm|Rural/i) 
                {
                   $typeIndex = $typeDefinitions->{'TYPE_RURAL'};
                }
                else
                {
                   if ($typeDescription =~ /Leisure|Tourist/i) 
                   {
                      $typeIndex = $typeDefinitions->{'TYPE_TOURIST'};
                   }
                   else
                   {
                      if ($typeDescription =~ /House/i) 
                      {
                          $typeIndex = $typeDefinitions->{'TYPE_HOUSE'};
                      }
                      else
                      {
                         if ($typeDescription =~ /Land/i) 
                         {
                             $typeIndex = $typeDefinitions->{'TYPE_LAND'};
                         }
                         else
                         {
                            if ($typeDescription =~ /Retirement|Seniors/i) 
                            {
                               $typeIndex = $typeDefinitions->{'TYPE_SENIORS'};
                            }
                            else  
                            {   
                               $typeIndex = $typeDefinitions->{'TYPE_UNKNOWN'};
                            }
                         }
                      }
                   }
                }
             }
         }
      }
      else
      {
         $typeIndex = $typeDefinitions->{'TYPE_UNKNOWN'};
      }
   }
   else
   {   
      $typeIndex = $typeDefinitions->{'TYPE_UNKNOWN'};
   }
   
   return $typeIndex;
}  


# -------------------------------------------------------------------------------------------------

# returns the typeIndex for 'house'
sub houses
{
   my $this = shift;
   
   $typeDefinitions = $this->{'typeDefinitions'};
   $typeIndex = $typeDefinitions->{'TYPE_HOUSE'};
   
   return $typeIndex;
}

# -------------------------------------------------------------------------------------------------

# returns the typeIndex for 'units'
sub units
{
   my $this = shift;
 
   $typeDefinitions = $this->{'typeDefinitions'};
   $typeIndex = $typeDefinitions->{'TYPE_UNIT'};
   
   return $typeIndex;
}

# -------------------------------------------------------------------------------------------------

# returns the typeIndex for 'all'
sub all
{
   my $this = shift;
   
   $typeDefinitions = $this->{'typeDefinitions'};
   $typeIndex = $typeDefinitions->{'TYPE_ALL'};
   
   return $typeIndex;
}

# -------------------------------------------------------------------------------------------------

# returns the typeIndex for 'land'
sub land
{
   my $this = shift;
   
   $typeDefinitions = $this->{'typeDefinitions'};
   $typeIndex = $typeDefinitions->{'TYPE_LAND'};
   
   return $typeIndex;
}

# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------

# returns an SQL search constraint to use in select statements for the specified property type
# The search is based on the string used for the type name, not the type index
# eg. If you specify TYPE_UNIT the name can be apartment, flat, unit, townhouse etc
sub lookupSearchConstraintByTypeName
{
   my $this = shift;
   my $typeIndex = shift;

   my $typeDefinitions = $this->{'typeDefinitions'};
   
   if ($typeIndex == $typeDefinitions->{'TYPE_HOUSE'})
   {  
      $searchConstraint = "Type like '%house%'";         
   }
   elsif ($typeIndex == $typeDefinitions->{'TYPE_UNIT'})
   {
      $searchConstraint = "(Type like '%Apartment%' or Type like '%Flats%' or Type like '%Unit%' or Type like '%Townhouse%' or Type like '%Villa%' or Type like '%Studio%' or Type like '%Terrace%')";         
   }
   elsif ($typeIndex == $typeDefinitions->{'TYPE_LAND'})
   {
      $searchConstraint  = "Type like '%Land%'";         
   }
   elsif ($typeIndex == $typeDefinitions->{'TYPE_ALL'})
   {
      $searchConstraint = "Type not like '%Land%' and Type not like '%Lifestyle%' and Type not like '%Commercial%' and Type not like '%Warehouse%' and Type not like '%Farm%' and Type not like '%Rural%' and Type not like '%Leisure%' and Type not like '%Tourist%' and Type not like '%Retirement%' and Type not like '%Seniors%'";        
   }
   else
   {
      $searchConstraint = "Type not like '%Land%' and Type not like '%Lifestyle%'";        
   }
   
   return $searchConstraint;
}

# -------------------------------------------------------------------------------------------------

# returns the string name for a type
sub getTypeName
{
   my $this = shift;
   my $typeIndex = shift;
   my $typeName = "TYPE_UNKNOWN";
   my $found = 0;
   my $typeDefinitions = $this->{'typeDefinitions'};
   
   # loop through all the defined types to find the key name matching this value
   while(($key, $value) = each(%$typeDefinitions)) 
   {     
      if ($value == $typeIndex)
      {
         $typeName = $key;
         $found = 1;   # NOTE: last can't be used here - breaks each function
      }
   }
   if (!$found)
   {
      $typeName = "TYPE_UNKNOWN";
   }
   
         
   return $typeName;
}

