#!/usr/bin/perl
# Written by Jeromy Evans
# Started 13 March 2005
# 
# WBS: A.01.03.01 Developed On-line Database
# Version 0.1  
#
# Description:
#   Module that encapsulate the PropertyCategories database component
# 
#      CATEGORY_ALL => 0,
#      CATEGORY_ONE_BY_ANY => 1,
#      CATEGORY_TWO_BY_ANY => 2,
#      CATEGORY_THREE_BY_ANY => 3,
#      CATEGORY_THREE_BY_ONE => 4,
#      CATEGORY_THREE_BY_TWO => 5,
#      CATEGORY_FOUR_BY_ANY => 6,
#      CATEGORY_FOUR_BY_ONE => 7,
#      CATEGORY_FOUR_BY_TWO => 8,
#      CATEGORY_FIVE_BY_ANY => 9,
   
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
package PropertyCategories;
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

# Contructor for the PropertyCategories - returns an instance of this object
# PUBLIC
sub new
{   
   my $sqlClient = shift;
   my $suburbAnalysisTable = shift;
   
   my $categoryDefinitions = 
   {
      CATEGORY_ALL => 0,
      CATEGORY_ONE_BY_ANY => 1,
      CATEGORY_TWO_BY_ANY => 2,
      CATEGORY_THREE_BY_ANY => 3,
      CATEGORY_THREE_BY_ONE => 4,
      CATEGORY_THREE_BY_TWO => 5,
      CATEGORY_FOUR_BY_ANY => 6,
      CATEGORY_FOUR_BY_ONE => 7,
      CATEGORY_FOUR_BY_TWO => 8,
      CATEGORY_FIVE_BY_ANY => 9
   };
   
   my $categoryNames = 
   {
      0 => 'All',
      1 => ' --1 bed',
      2 => ' --2 beds', 
      3 => ' --3 beds', 
      4 => ' ----3 x 1',
      5 => ' ----3 x 2',
      6 => ' --4 beds', 
      7 => ' ----4 x 1', 
      8 => ' ----4 x 2',
      9 => ' --5 beds'
   };
   
   my $propertyCategories = { 
      sqlClient => $sqlClient,
      tableName => "PropertyCategories",
      suburbAnalysisTable => $suburbAnalysisTable,
      categoryDefinitions => $categoryDefinitions,
      categoryNames => $categoryNames,
      NO_OF_CATEGORIES => 10
   }; 
      
   bless $propertyCategories;     
   
   return $propertyCategories;   # return this
}

# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------

# returns a value (enum) indicating the category of a property with the specified bedrooms and bathrooms
# if the ideal category is statisticaly invalid (insufficient data) it chooses a better fit instead - that's 
# why suburbname also has to be specified
sub lookupBestFitCategory
{
   my $this = shift;
   my $bedrooms = shift;
   my $bathrooms = shift;
   my $suburbIndex = shift;
   my $categorySelected = 0;
   
   $categoryDefinitions = $this->{'categoryDefinitions'};

   my $suburbAnalysisTable = $this->{'suburbAnalysisTable'};
   
   # determine the initial category - this would be used if there is sufficient statistical data
   if ($bedrooms == 5)
   {
      $category = $categoryDefinitions->{'CATEGORY_FIVE_BY_ANY'}; 
   }
   else
   {
      if ($bedrooms == 4)
      {
         if ($bathrooms == 2)
         {
            $category = $categoryDefinitions->{'CATEGORY_FOUR_BY_TWO'}; 
         }
         elsif ($bathrooms == 1)
         {
            $category = $categoryDefinitions->{'CATEGORY_FOUR_BY_ONE'};
         }
         else
         {
            $category = $categoryDefinitions->{'CATEGORY_FOUR_BY_ANY'}; 
         }

      }
      elsif ($bedrooms == 3)
      {
         if ($bathrooms == 2)
         {
            $category = $categoryDefinitions->{'CATEGORY_THREE_BY_TWO'}; 
         }
         elsif ($bathrooms == 1)
         {
            $category = $categoryDefinitions->{'CATEGORY_THREE_BY_ONE'}; 
         }
         else
         {
            $category = $categoryDefinitions->{'CATEGORY_THREE_BY_ANY'}; 
         }
      }
      elsif ($bedrooms == 2)
      {
        $category = $categoryDefinitions->{'CATEGORY_TWO_BY_ANY'};
      }
      elsif ($bedrooms == 1)
      {
        $category = $categoryDefinitions->{'CATEGORY_ONE_BY_ANY'};
      }
      else
      {
         $category = $categoryDefinitions->{'CATEGORY_ALL'};
         $categorySelected = 1;  # no improvements possible
      }
   }

   # check if the suburb statistics are valid for this category - if not, choose a better fit
   $initialCategory = $category;
   while (!$categorySelected)
   {   
      # get the noOfRecords data for the suburb category
      $noOfSalesHash = $suburbAnalysisTable->getNoOfSalesHash($category);
      $noOfRentalsHash = $suburbAnalysisTable->getNoOfRentalsHash($category);
     
#      print "$suburbName:trialCategory = $category sales=", $$noOfSalesHash{$suburbName}, " rentals=", $$noOfRentalsHash{$suburbName}, "\n";

      # check that it's 'statistically valid
      if (($$noOfSalesHash{$suburbIndex} >= 5) && ($$noOfRentalsHash{$suburbIndex} >= 5))
      {
         # this category is fine to work with - exit the loop
         $categorySelected = 1;
      }
      else
      {
         # insufficient data for this category - move to the parent category
         if ($category == $ALL)
         {
            # nowhere else to go - use it
            $categorySelected = 1;
         }
         elsif (($category == $categoryDefinitions->{'CATEGORY_ONE_BY_ANY'}) || ($category == $categoryDefinitions->{'CATEGORY_TWO_BY_ANY'}) || ($category == $categoryDefinitions->{'CATEGORY_THREE_BY_ANY'}) || ($category == $categoryDefinitions->{'CATEGORY_FOUR_BY_ANY'}) || ($category == $categoryDefinitions->{'CATEGORY_FIVE_BY_ANY'}))
         {
            # the parent is the all category - and nowhere else to go!
            $category = $categoryDefinitions->{'CATEGORY_ALL'};
            $categorySelected = 1; 
         }
         elsif (($category == $categoryDefinitions->{'CATEGORY_THREE_BY_ONE'}) || ($category == $categoryDefinitions->{'CATEGORY_THREE_BY_TWO'}))
         {
            # try the three by any category
            $category = $categoryDefinitions->{'CATEGORY_THREE_BY_ANY'}; 
         }
         elsif (($category == $categoryDefinitions->{'CATEGORY_FOUR_BY_ONE'}) || ($category == $categoryDefinitions->{'CATEGORY_FOR_BY_TWO'}))
         {
            # try the four by any category
            $category = $categoryDefinitions->{'CATEGORY_FOUR_BY_ANY'}; 
         }
         else
         {
            # shouldnt' actually get here ever, but just in case, exist
            $category = $categoryDefinitions->{'CATEGORY_ALL'};
            $categorySelected = 1;
         }
      }
   }
   
#   print "$suburbname: $bedrooms x $bathrooms category=$category selected<br/>\n";
   return $category;
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

# returns the string name for a category
sub getCategoryPrettyName
{
   my $this = shift;
   my $categoryIndex = shift;

   $categoryNames = $this->{'categoryNames'};
   $categoryName = $categoryNames->{$categoryIndex};
      
   return $categoryName;
}

# -------------------------------------------------------------------------------------------------

# returns the string name for a category
sub getCategoryName
{
   my $this = shift;
   my $categoryIndex = shift;
   my $categoryName = "CATEGORY_ALL";
   my $found = 0;

   $categoryDefinitions = $this->{'categoryDefinitions'};
      
   # loop through all the defined categories to find the key name matching this value
   while(($key, $value) = each(%$categoryDefinitions)) 
   {     
      if ($value == $categoryIndex)
      {
         $categoryName = $key;
         $found = 1;   # NOTE: last can't be used here - breaks each function
      }
   }
   if (!$found)
   {
      $categoryName = "TYPE_UNKNOWN";
   }
   
   return $categoryName;
}

# -------------------------------------------------------------------------------------------------

# returns the list of defined categories (numbers)
sub getCategoryIndexList
{
   my $this = shift;
   my @categoryList;
   $categoryDefinitions = $this->{'categoryDefinitions'};
      
   # loop through all the values defined for category keys
   # and add them to the list
   $index = 0;
   while(($key, $value) = each(%$categoryDefinitions)) 
   {  
      # only use the CATEGORY_ definitions in the this hash
      if ($key =~ /CATEGORY_/)
      {
         $categoryList[$index++] = $value;
      }
   }
   
   # sort numerically
   @categoryList = sort { $a <=> $b } @categoryList;
   
   return @categoryList;
}

# -------------------------------------------------------------------------------------------------
# returns the number of beds and baths for the specified category
# if the value is ZERO then it doesn't matter how many
#
# Category Beds  Baths
#    0       x    x
#    1       1    x
#    2       2    x
#    3       3    x
#    4       3    1
#    5       3    2
#    6       4    x
#    7       4    1
#    8       4    2
#    9       5    x
sub lookupBedsandBathsFromCategory
{
   my $this = shift;
   my $category = shift;
   my @lookupBeds  = (0, 1, 2, 3, 3, 3, 4, 4, 4, 5);
   my @lookupBaths = (0, 0, 0, 0, 1, 2, 0, 1, 2, 0);
   
   return ($lookupBeds[$category], $lookupBaths[$category]);
}

# -------------------------------------------------------------------------------------------------


# checks if the property with specified beds and baths fits in the specified category or one of 
# the subset categories 
# eg. if it's 3 beds, 2 baths, it fits in the ANY, THREE_BY_ANY and THREE_BY_TWO classes

#
sub checkIfPropertyInCategorySubset
{
   my $this = shift;
   my $category = shift;
   my $bedrooms = shift;
   my $bathrooms = shift;
   my $bedsOk = 0;
   my $bathsOk = 0;
   
   # get the number of beds and baths for this category 
   # a ZERO value means it doesn't matter (any)
   ($checkBeds, $checkBaths) = $this->lookupBedsandBathsFromCategory($category);
   
   # check if the bedrooms is in range (or don't care)
   if (($bedrooms == $checkBeds) || ($checkBeds == 0))
   {
      $bedsOk = 1;
   }
   
   # check if the bathrooms are in range (or don't care)
   if (($bathrooms == $checkBaths) || ($checkBaths == 0))
   {
      $bathsOk = 1;
   }
   
   # return true if both ok
   if (($bedsOk) && ($bathsOk))
   {
      return 1;
   }
   else
   {
      return 0;
   }
}



# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

