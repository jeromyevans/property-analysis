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
# History:

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
   
   my $propertyTypes = { 
      sqlClient => $sqlClient,
      tableName => "PropertyTypes"
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
   
   
   my $DEFINED_PROPERTY_TYPES = {
      Unknown => 0,
      Unit => 1,
      Commercial => 2,
      Rural => 3,
      House => 4,
      Land => 5,
      Seniors => 6,
      Tourist => 7,
      Other => 8
   };
   
   if ($sqlClient)
   {
      $statement = $sqlClient->prepareStatement($SQL_CREATE_TABLE_STATEMENT);
      
      if ($sqlClient->executeStatement($statement))
      {
         $success = 1;
                  
         while(($key, $value) = each(%$DEFINED_PROPERTY_TYPES)) 
         {
            # do something with $key and $value
            $this->addRecord($value, $key);
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
   my $sqlClient = shift;
   my $typeDescription = shift;
   my $typeName;
   my $matchedType;
   
   if ($sqlClient)
   {
      
      if ($typeDescription)
      {
         if ($typeDescription /Apartment|Flat|Unit|Duplex|Semi|Studio|Terrace|Townhouse|Villa/i) 
         {
            # apartment/unit-like properties
            $typeIndex = $DEFINED_PROPERTY_TYPES{'Unit'}
         }
         else
         {
             if ($typeDescription /Commercial|Warehouse/i)
             {
                # commercial/industrial
                $typeIndex = $DEFINED_PROPERTY_TYPES{'Commercial'}
             }
             else
             {
                if ($typeDescription /Farm|Rural/i) 
                {
                   $typeIndex = $DEFINED_PROPERTY_TYPES{'Rural'}
                }
                else
                {
                   if ($typeDescription /Farm|Rural/i) 
                   {
                      $typeIndex = $DEFINED_PROPERTY_TYPES{'Tourist'}
                   }
                   else
                   {
                      if ($typeDescription /House/i) 
                      {
                          $typeIndex = $DEFINED_PROPERTY_TYPES{'House'}
                      }
                      else
                      {
                         if ($typeDescription /Land/i) 
                         {
                             $typeIndex = $DEFINED_PROPERTY_TYPES{'Land'}
                         }
                         else
                         {
                            if ($typeDescription /Retirement|Seniors/i) 
                            {
                               $typeIndex = $DEFINED_PROPERTY_TYPES{'Seniors'}
                            }
                            else  
                            {   
                               $typeIndex = $DEFINED_PROPERTY_TYPES{'Unknown'}
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
         $typeIndex = $DEFINED_PROPERTY_TYPES{'Unknown'}
      }
   }   
   return $typeIndex;
}  


# -------------------------------------------------------------------------------------------------


