#!/usr/bin/perl
# Written by Jeromy Evans
# Started 13 March 2005
# 
# WBS: A.01.03.01 Developed On-line Database
# Version 0.1  
#
# Description:
#   Module that encapsulate the SuburbAnalysisTable database component
# 
# History:

# CONVENTIONS
# _ indicates a private variable or method
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
package SuburbAnalysisTable;
require Exporter;

use DBI;
use SQLClient;
use AdvertisedPropertyProfiles;
use PropertyTypes;
use PropertyCategories;


@ISA = qw(Exporter);

#@EXPORT = qw(&parseContent);

# -------------------------------------------------------------------------------------------------
# PUBLIC enumerations
#
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

my $DEFAULT_SALES_ANALYSIS_CONSTRAINT =  "(DateLastAdvertised > date_add(now(), interval -6 month))";
my $DEFAULT_RENTALS_ADVERTISED_CONSTRAINT = "((DateEntered > date_add(now(), interval -6 month)) or (LastEncountered > date_add(now(), interval -6 month)))";

# -------------------------------------------------------------------------------------------------

# Contructor for the suburbAnalysisTable - returns an instance of this object
# PUBLIC
sub new
{   
   my $sqlClient = shift;
#####   my $advertisedSaleProfiles = shift;
   
   my $suburbAnalysisTable = { 
      sqlClient => $sqlClient,
      tableName => "SuburbAnalysisTable",
      salesResultsList => undef,
      rentalResultsList => undef,
      dateSearch => $DEFAULT_SALES_ANALYSIS_CONSTRAINT,
      rentalsDateSearch => $DEFAULT_RENTALS_ADVERTISED_CONSTRAINT,
      propertyCategories => undef,

      suburbIndexHash => undef,
      noOfSalesCategoryHash => undef,    
      minSalePriceCategoryHash => undef,
      maxSalePriceCategoryHash => undef,
      salesMeanCategoryHash => undef,
      salesMedianCategoryHash => undef,
      salesStdDevCategoryHash => undef,
      noOfAdvertisedCategoryHash => undef,   
      noOfRentalsCategoryHash => undef,   
      minRentalPriceCategoryHash => undef,
      maxRentalPriceCategoryHash => undef,
      rentalMeanCategoryHash => undef,
      rentalMedianCategoryHash => undef,
      rentalStdDevCategoryHash => undef,
   
      medianYieldCategoryHash => undef
   }; 
      
   bless $suburbAnalysisTable;     
   
   # initialise the propertyCategories object - it needs this
   $suburbAnalysisTable->{'propertyCategories'} = PropertyCategories::new($sqlClient, $suburbAnalysisTable);
   
   return $suburbAnalysisTable;   # return this
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# createTable
# attempts to create the SuburbAnalysisTable table in the database if it doesn't already exist
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

my $SQL_CREATE_TABLE_PREFIX = "CREATE TABLE IF NOT EXISTS SuburbAnalysisTable (";
my $SQL_CREATE_TABLE_BODY = 
    "DateEntered DATETIME NOT NULL, ".
    "SuburbIndex INTEGER UNSIGNED ZEROFILL, ".
    "SuburbName TEXT, ".
    "State TEXT, ".
    "TypeIndex INTEGER UNSIGNED, ".
    "Category INTEGER UNSIGNED, ".
    "NoOfSales INTEGER UNSIGNED, ".
    "MinAdvertisedSalePrice DECIMAL(10,2), ".
    "MaxAdvertisedSalePrice DECIMAL(10,2), ".
    "CurrentSalesAdvertised INTEGER UNSIGNED, ".
    "MeanAdvertisedSalePrice DECIMAL(10,2),".
    "StdDevAdvertisedSalePrice DECIMAL(10,2),".
    "MedianAdvertisedSalePrice DECIMAL(10,2),".
    "NoOfRentals INTEGER UNSIGNED, ".
    "MinAdvertisedRentalPrice DECIMAL(10,2), ".
    "MaxAdvertisedRentalPrice DECIMAL(10,2), ".
    "CurrentRentalsAdvertised INTEGER UNSIGNED, ".
    "MeanAdvertisedRentalPrice DECIMAL(10,2),".
    "StdDevAdvertisedRentalPrice DECIMAL(10,2),".
    "MedianAdvertisedRentalPrice DECIMAL(10,2),".
    "MedianYield DECIMAL(10,2),".
    "MedianCashflow DECIMAL(10,2),".
    "INDEX (SuburbIndex)";        
    
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
# dropTable
# attempts to drop the SuburbAnalysisTable table 
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
my $SQL_DROP_TABLE_STATEMENT = "DROP TABLE SuburbAnalysisTable";
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
#  ANALYSIS FUNCTIONS FOR GENERATING THE TABLE
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

# performs analysis of all the suburbs in the database in all property categories and 
# updates the SuburbAnalysisTable with the current statistics
sub performSuburbAnalysis

{
   my $this = shift;
   my $propertyTypes = PropertyTypes::new();
   my @typeList;    # list of property types for analysis
   
   # define the types of properties to be analysed
   $typeList[0] = $propertyTypes->all();
   $typeList[1] = $propertyTypes->houses();
   $typeList[2] = $propertyTypes->units();
   $typeList[3] = $propertyTypes->land();
   
   # first, fetch ALL the data for THIS TYPE of property (all categories) (this is a very large structure)
   foreach (@typeList)
   {
      print "$_:", $propertyTypes->getTypeName($_), ":\n";
      #_ is a typeIndex - lookup the constraint to use in the sql select statement to limit the type of property
      # data to only this list
      $typeSearchConstraint = $propertyTypes->lookupSearchConstraintByTypeName($_);
      
      # fetch the raw data for this type of property
      $this->_fetchAnalysisData($typeSearchConstraint);
      
      # calculate the analysis data for this type of property
      # analysis data is grouped by category in these functions
      print "   performing sales analysis...\n";
      $this->_calculateSalesAnalysis();
      print "   performing rentals analysis...\n";
      $this->_calculateRentalAnalysis();
      print "   performing yield analysis...\n";
      $this->_calculateYieldAnalysis();
      print "   updating table...\n";
      # insert the analysis data into the SuburbAnalysisTable for this property type
      $this->_updateAnalysisTable($_);
   }
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# performs the query on the database to get selected data for analysis
sub _fetchAnalysisData

{
   my $this = shift;
   my $typeSearchConstraint = shift;

   print "   Fetching analysis data...\n";      
   my $sqlClient = $this->{'sqlClient'};
   $salesSelectCommand = "select SuburbIndex, Type, AdvertisedPriceLower, AdvertisedPriceUpper, Bedrooms, Bathrooms, unix_timestamp(DateLastAdvertised) as DateLastAdvertised from MasterPropertyTable where ".$this->{'dateSearch'}." and ".$typeSearchConstraint." order by SuburbName, Type, Bedrooms, Bathrooms";
   #print "<br>", "<tt>SALES  :$salesSelectCommand</tt><br\>";
   my @salesResults = $sqlClient->doSQLSelect($salesSelectCommand);
   $salesLength = @salesResults;
   print "      $salesLength sales records\n";   
   $rentalsSelectCommand = "select SuburbIndex, Type, AdvertisedWeeklyRent, Bedrooms, Bathrooms from WorkingView_AdvertisedRentalProfiles where ".$this->{'rentalsDateSearch'}." and ".$typeSearchConstraint." order by SuburbName, Type, Bedrooms, Bathrooms";
   #print "<br>", "<tt>RENTALS:$rentalsSelectCommand</tt><br\>";
   my @rentalResults = $sqlClient->doSQLSelect($rentalsSelectCommand);
   $rentalsLength = @rentalResults;

   print "      $rentalsLength rental records\n";   
     
   $this->{'salesResultsList'} = \@salesResults;
   $this->{'rentalResultsList'} = \@rentalResults;
}


# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# Fetches data from the database using the search constraints and calculates analysis parameters
sub _calculateSalesAnalysis

{
   my $this = shift;
  
   my $index;
   my $suburbIndex;
   my $highPrice;
   my @sumOfSalePrices;          # array of hashes, one element for each property TYPE
   my @sumOfSquaredSalePrices;
   my @minSalePrice;
   my @maxSalePrice;
   my @noOfAdvertisedSales;
   my @salesMean;
   my @salesStdDev;
   my @salesStdDevPercent;  
   my @salesMedian;
   my @noOfCurrentlyAdvertised;
   
   $index = 0;                               
        
   my $sqlClient = $this->{'sqlClient'};
   my $propertiesListRef =  $this->{'salesResultsList'};
   my $propertyCategories = $this->{'propertyCategories'};

   # get the list of analysis categories
   @categoryList = $propertyCategories->getCategoryIndexList();
   
   # loop through the very large array of properties
   foreach (@$propertiesListRef)
   {
      $profileRef = $_;
      $suburbIndex = $$profileRef{'SuburbIndex'};
      
      # if a buyer enquiry range is specified, take 2/3rds of the range as the price.
      if (defined $$profileRef{'AdvertisedPriceUpper'} && ($$profileRef{'AdvertisedPriceUpper'}) > 0)
      {
         $distance = $$profileRef{'AdvertisedPriceUpper'} - $$profileRef{'AdvertisedPriceLower'};
         $advertisedPrice = $$profileRef{'AdvertisedPriceLower'} + ($distance * 2 / 3)
      }
      else
      {
         $advertisedPrice = $$profileRef{'AdvertisedPriceLower'};  
      }              

      if ($advertisedPrice > 0)
      {  
         # calculate the total of price for calculation of the mean
         if (!defined $sumOfSalePrices[0]{$suburbIndex})
         {
            # reset values for each category (this is first run)           
            foreach (@categoryList)
            {
               $category = $_;
               # initialise counters for the first time for this suburbname
               $sumOfSalePrices[$category]{$suburbIndex} = 0;
               $sumOfSquaredSalePrices[$category]{$suburbIndex} = 0;
               $noOfAdvertisedSales[$category]{$suburbIndex} = 0;
               $noOfCurrentlyAdvertised[$category]{$suburbIndex} = 0;
            
               my @newList;
               $advertisedPriceList[$category]{$suburbIndex} = \@newList;  # initialise a new array
            }
         }

         $cmpTime = time() - (14*24*60*60);
         #$cmpTime = time();
         #print "DLA=", $$_{'DateLastAdvertised'}, " cmpTime= $cmpTime\n";
         ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =  localtime($cmpTime);
               #print " cmpTime:", $year-100, "-", $mon+1, "-$mday, $hour:$min:$sec\n";

         
         # loop through all the defined category types
         # and test if this property is in the subset of each category
         foreach (@categoryList)
         {
            $category = $_;
            
            # check if this property is in this category (or a subset of this category)
            if ($propertyCategories->checkIfPropertyInCategorySubset($category, $$profileRef{'Bedrooms'}, $$profileRef{'Bathrooms'}))
            {         
               # add the advertised price to the totals for the suburb
               $sumOfSalePrices[$category]{$suburbIndex} += $advertisedPrice;
               # calculate the total of squared prices for calculation of the standard deviation
               $sumOfSquaredSalePrices[$category]{$suburbIndex} += ($advertisedPrice**2);
               # count the number of listings in the suburb
               $noOfAdvertisedSales[$category]{$suburbIndex} += 1;
               # record the advertised price in a list for this suburb - the list is used later to calculate the 
               # median advertised price for that suburb
               $listRef = $advertisedPriceList[$category]{$suburbIndex};
               #print "advertisedPriceList{$suburbIndex}=", $advertisedPriceList{$suburbIndex}, "\n";
               push @$listRef, $advertisedPrice;
               
               # record the lowest-high price listed for this suburb
               if ((!defined $minSalePrice[$category]{$suburbIndex}) || ($advertisedPrice < $minSalePrice[$category]{$suburbIndex}))
               {
                  $minSalePrice[$category]{$suburbIndex} = $advertisedPrice;
               }
            
               # record the highest-high price listed for this suburb
               if ((!defined $maxSalePrice[$category]{$suburbIndex}) || ($advertisedPrice > $maxSalePrice[$category]{$suburbIndex}))
               {
                  $maxSalePrice[$category]{$suburbIndex} = $advertisedPrice;
               }
              
               if ($$profileRef{'DateLastAdvertised'} > $cmpTime)
               {
                  # count the number of listings in the suburb 'still advertised'
                  #print "   count this\n";
                  $noOfCurrentlyAdvertised[$category]{$suburbIndex} += 1;
               }
            }
         }     
      }
   }         
   
   # loop through all the results once more to calculate the mean and stddev (couldn't do this
   # until the number of listings was known)
   # the keys of noOfSales is the suburblist
   $suburbList = $noOfAdvertisedSales[0];
   foreach (keys %$suburbList)
   {   
      $suburbIndex = $_;
      
      # loop for all the different categories
      foreach (@categoryList)
      {
         $category = $_;
         
         if (defined $sumOfSalePrices[$category]{$suburbIndex} && ($noOfAdvertisedSales[$category]{$suburbIndex} > 0))
         {
            $salesMean[$category]{$suburbIndex} = $sumOfSalePrices[$category]{$suburbIndex} / $noOfAdvertisedSales[$category]{$suburbIndex};
         }
         
         # unbiased stddev = sqrt(n*sum(x^2) - (sum(x))^2 / (n(n-1))
         #print "noas[$category]{$suburbIndex} = ", $noOfAdvertisedSales[$category]{$suburbIndex}, "sossp[$category]{$suburbIndex} = ", $sumOfSquaredSalePrices[$category]{$suburbIndex}, "\n";
         if (($noOfAdvertisedSales[$category]{$suburbIndex} > 1) && ($sumOfSquaredSalePrices[$category]{$suburbIndex} > 0))
         {         
            $salesStdDev[$category]{$suburbIndex}  = sqrt(($noOfAdvertisedSales[$category]{$suburbIndex} * $sumOfSquaredSalePrices[$category]{$suburbIndex} - ($sumOfSalePrices[$category]{$suburbIndex}**2)) / ($noOfAdvertisedSales[$category]{$suburbIndex} * ($noOfAdvertisedSales[$category]{$suburbIndex} - 1)));
            #print "   salesStdDev[$category]{$suburbIndex}=", $salesStdDev[$category]{$suburbIndex}, "\n";
         }
      }
   }

   # now calculate the median advertised sale price for the suburb
   $suburbList = $noOfAdvertisedSales[0];
   foreach (keys %$suburbList)
   {
      $suburbIndex = $_;
      # loop for all the different categories
      foreach (@categoryList)
      {
         $category = $_;
         
         $listRef = $advertisedPriceList[$category]{$suburbIndex};
         @priceList = sort { $a <=> $b } @$listRef;   # sort numerically
         
         #if ($_ eq "Cable Beach")
         #{
         #   DebugTools::printList("sales", \@priceList);
         #}
         
         $listLength = @priceList;
         #if ($_ eq "Cable Beach")
         #{
         #   print "listLength{$_} = $listLength (";
         #}
         if (($listLength % 2) == 0)
         {
            # if the list length is even...find the middle pair of numbers and take the centre of those
            $medianLower = $priceList[($listLength / 2)-1];
            $medianUpper = $priceList[$listLength / 2];
            #if ($_ eq "Cable Beach")
            #{
            #   print "lower=$medianLower, upper=$medianUpper\n";
            #}
            $medianPrice = $medianLower + ($medianUpper - $medianLower) / 2;
         }
         else
         {
            # the list length is odd, so the median value is the one in the middle
            $medianPrice = $priceList[$listLength / 2];
         }
         
         $salesMedian[$category]{$suburbIndex} = $medianPrice;
      }
   }

   $this->{'noOfSalesCategoryHash'} = \@noOfAdvertisedSales;
   $this->{'minSalePriceCategoryHash'} = \@minSalePrice;
   $this->{'maxSalePriceCategoryHash'} = \@maxSalePrice;
   $this->{'salesMeanCategoryHash'} = \@salesMean;
   $this->{'salesMedianCategoryHash'} = \@salesMedian;
   $this->{'salesStdDevCategoryHash'} = \@salesStdDev;
   $this->{'noOfAdvertisedCategoryHash'} = \@noOfCurrentlyAdvertised;      
}   

# -------------------------------------------------------------------------------------------------

# Fetches data from the database using the search constraints and calculates analysis parameters
sub _calculateRentalAnalysis

{
   my $this = shift;
   
   my $index;
   my $suburbIndex;   
   my @sumOfRentalPrices;
   my @sumOfSquaredRentalPrices;
   my @minRentalPrice;
   my @maxRentalPrice;
   my @noOfRentals;
   my @rentalMean;
   my @rentalStdDev;
   my @rentalStdDevPercent;  
   my @rentalMedian;  

   
   my $sqlClient = $this->{'sqlClient'};
   my $propertiesListRef =  $this->{'rentalResultsList'};
   my $propertyCategories = $this->{'propertyCategories'};

   $index = 0;                               
    
   # get the list of analysis categories
   @categoryList = $propertyCategories->getCategoryIndexList();
      
       
   #propertiesListRef is a big array of hashes      
   foreach (@$propertiesListRef)
   {   
      $profileRef = $_;
      $suburbIndex = $$profileRef{'SuburbIndex'};
   
      if ($$profileRef{'AdvertisedWeeklyRent'} > 0)
      {
         
         if (!defined $sumOfRentalPrices[0]{$suburbIndex})
         {
            # reset values for each category (this is first run)           
            foreach (@categoryList)
            {
               $category = $_;
               $sumOfRentalPrices[$category]{$suburbIndex} = 0;
               $sumOfSquaredRentalPrices[$category]{$suburbIndex} = 0;
               $noOfRentals[$category]{$suburbIndex} = 0;
               my @newList;
               $advertisedPriceList[$category]{$suburbIndex} = \@newList;  # initialise a new array
            }
         }
         
          # reset values for each category (this is first run)           
          foreach (@categoryList)
          {
            $category = $_;
            
            if ($propertyCategories->checkIfPropertyInCategorySubset($category, $$profileRef{'Bedrooms'}, $$profileRef{'Bathrooms'}))
            {
               # calculate the total of price for calculation of the mean
               $sumOfRentalPrices[$category]{$suburbIndex} += $$profileRef{'AdvertisedWeeklyRent'};
               
               # calculate the total of squared prices for calculation of the standard deviation
               $sumOfSquaredRentalPrices[$category]{$suburbIndex} += ($$profileRef{'AdvertisedWeeklyRent'}**2);
              
               # count the number of listings in the suburb
               $noOfRentals[$category]{$suburbIndex} += 1;
                        
               # record the advertised price in a list for this suburb - the list is used later to calculate the 
               # median advertised price for that suburb
               $listRef = $advertisedPriceList[$category]{$suburbIndex};
               #print "advertisedPriceList{$suburbIndex}=", $advertisedPriceList{$suburbIndex}, "\n";
               push @$listRef, $$profileRef{'AdvertisedWeeklyRent'};
               #$advertisedPriceList{$suburbIndex} = \@listRef;
               
               #$$advertisedPriceList{$suburbIndex}[$noOfAdvertisedSales{$suburbIndex}-1] = $advertisedPrice;      
               #print "advertisedPriceList{$suburbIndex}[", $noOfAdvertisedSales{$suburbIndex}-1, "] = $advertisedPrice\n";
               
               # record the lowest-high price listed for this suburb
               if ((!defined $minRentalPrice[$category]{$suburbIndex}) || ($$profileRef{'AdvertisedWeeklyRent'} < $minRentalPrice[$category]{$suburbIndex}))
               {
                  $minRentalPrice[$category]{$suburbIndex} = $$profileRef{'AdvertisedWeeklyRent'};
               }
            
               # record the highest-high price listed for this suburb
               if ((!defined $maxRentalPrice[$category]{$suburbIndex}) || ($$profileRef{'AdvertisedWeeklyRent'} > $maxRentalPrice[$category]{$suburbIndex}))
               {
                  $maxRentalPrice[$category]{$suburbIndex} = $$profileRef{'AdvertisedWeeklyRent'};
               }
               
    #           print "sumOfRentalPrices[$category]{$suburbIndex}(", $$profileRef{'Bedrooms'}, "x", $$profileRef{'Bathrooms'}, ")=", $sumOfRentalPrices[0]{$suburbIndex}, "\n";
            }
         }
         
      }
   }
     
   # loop through all VALID results once more to calculate the mean
   $hashRef = $noOfRentals[0];
   foreach (keys %$hashRef)
   {          
      $suburbIndex = $_;
      # loop for all the different categories
      foreach (@categoryList)
      {
         $category = $_;
         if ((defined $sumOfRentalPrices[$category]{$suburbIndex}) && ($noOfRentals[$category]{$suburbIndex} > 0))
         {
            $rentalMean[$category]{$suburbIndex} = $sumOfRentalPrices[$category]{$suburbIndex} / $noOfRentals[$category]{$suburbIndex};
         }      
         # unbiased stddev = sqrt(n*sum(x^2) - (sum(x))^2 / (n(n-1))      
         if (($noOfRentals[$category]{$suburbIndex} > 1) && ($sumOfSquaredRentalPrices[$category]{$suburbIndex} > 0))
         {                                                      
            $rentalStdDev[$category]{$suburbIndex} = sqrt(($noOfRentals[$category]{$suburbIndex} * $sumOfSquaredRentalPrices[$category]{$suburbIndex} - ($sumOfRentalPrices[$category]{$suburbIndex}**2)) / ($noOfRentals[$category]{$suburbIndex} * ($noOfRentals[$category]{$suburbIndex} - 1)));                     
         }
      }
   }
   
   # now calculate the median advertised sale price for the suburb
   foreach (keys %$hashRef)
   {
      $suburbIndex = $_;
      # loop for all the different categories
      foreach (@categoryList)
      {
         $category = $_;
      
         $listRef = $advertisedPriceList[$category]{$suburbIndex};
         #print "listRef = $listRef\n";
         @priceList = sort { $a <=> $b } @$listRef;   # sort numerically
         
         $listLength = @priceList;
         if (($listLength % 2) == 0)
         {
            # if the list length is even...find the middle pair of numbers and take the centre of those
            $medianLower = $priceList[($listLength / 2)-1];
            $medianUpper = $priceList[$listLength / 2];
            $medianPrice = $medianLower + ($medianUpper - $medianLower) / 2;
         }
         else
         {
            # the list length is odd, so the median value is the one in the middle
            $medianPrice = $priceList[$listLength / 2];
         }
      
         $rentalMedian[$category]{$suburbIndex} = $medianPrice;
      }
   }
   
   #DebugTools::printList("sumOfRentalPrices", \@noOfRentals);
   #print "sumOfRentalPrices[0]=", $sumOfRentalPrices[0], "\n";
   #$hashRef = $sumOfRentalPrices[0];
   #DebugTools::printHash("sumOfRentalPrices[0]", $hashRef);
   
   $this->{'noOfRentalsCategoryHash'} = \@noOfRentals;
   $this->{'minRentalPriceCategoryHash'} = \@minRentalPrice;
   $this->{'maxRentalPriceCategoryHash'} = \@maxRentalPrice;
   $this->{'rentalMeanCategoryHash'} = \@rentalMean;
   $this->{'rentalMedianCategoryHash'} = \@rentalMedian;
   $this->{'rentalStdDevCategoryHash'} = \@rentalStdDev;   
}

# -------------------------------------------------------------------------------------------------
# note this function requires the sales and rental analysis to be current (and in the hash)
# as median yield is directly proportional to the division of the medians
sub _calculateYieldAnalysis
{
   my $this = shift;   
   my @medianYield;
      
   my $propertyCategories = $this->{'propertyCategories'};
   
   @categoryList = $propertyCategories->getCategoryIndexList();

   # loop through every category - 
   foreach (@categoryList)
   {
      $category = $_;

      $salesMedian = $this->getSalesMedianHash($category);
      $rentalMedian = $this->getRentalMedianHash($category);

      # loop through all the suburbs again to calculate the yield   
      foreach (keys %$salesMedian)
      {  
         
         $suburbIndex = $_;
         #($officialSalesMedian{$suburbIndex}, $officialRentalMedian{$suburbIndex}) = $this->fetchOfficialMedians($suburbIndex);
    
         #if (($$noOfRentals{$suburbIndex} > 0) && ($$noOfSales{$suburbIndex} > 0))
         #$meanYield{$suburbIndex} = ($$rentalMean{$suburbIndex} * 5200) / $$salesMean{$suburbIndex};
         if ($$salesMedian{$suburbIndex} > 0)
         {
            $medianYield[$category]{$suburbIndex} = ($$rentalMedian{$suburbIndex} * 5200) / $$salesMedian{$suburbIndex};
         }
         else
         {
            $medianYield[$category]{$suburbIndex} = 0;
         }
         #print "$suburbIndex ", $$salesMedian{$suburbIndex}, " ", $$rentalMedian{$suburbIndex}, " ", $medianYield{$suburbIndex}, "\n";               
      }
   }
 
  
   $this->{'medianYieldCategoryHash'} = \@medianYield;
}

# -------------------------------------------------------------------------------------------------

# uses the results of the analysis data to update the suburbanalysistable
sub _updateAnalysisTable

{
   my $this = shift;
   my $typeIndex = shift;
   my %suburbProfile;
   
   # get the default list of suburb index (use the all category which is the superset of data)
   $noOfSales = $this->getNoOfSalesHash(0);
   my $propertyCategories = $this->{'propertyCategories'};

   $index = 0;                               
    
   # get the list of analysis categories
   @categoryList = $propertyCategories->getCategoryIndexList();
   
   # sort the list of suburb indexes numerically
   @suburbList = keys %$noOfSales;
   $length = @suburbList;
   print "      $length suburbs...\n";
      
   # loop through all of the suburbs
   $hashRef = $noOfSales;
   foreach (keys %$hashRef)
   {
      # $_ is the suburb index
      $suburbIndex = $_;
      
      # get the name of the suburb (for info only in the table)
      ($suburbName, $state) = $this->lookupSuburbName($suburbIndex);
      #print "$suburbIndex $suburbName $state:\n";
      # loop through all the categories
      foreach (@categoryList)
      {
         $category = $_;
         
         $noOfSales = $this->getNoOfSalesHash($category);
         $minSalePrice = $this->getSalesMinHash($category);
         $maxSalePrice = $this->getSalesMaxHash($category);
         $noOfAdvertised = $this->getNoOfAdvertisedHash($category);
         $salesMean = $this->getSalesMeanHash($category);
         $salesStdDev = $this->getSalesStdDevHash($category);
         $salesMedian = $this->getSalesMedianHash($category);

         $noOfRentals = $this->getNoOfRentalsHash($category);        
         $minRentalPrice = $this->getRentalMinHash($category);
         $maxRentalPrice = $this->getRentalMaxHash($category);
         $rentalMean = $this->getRentalMeanHash($category);
         $rentalStdDev = $this->getRentalStdDevHash($category);         
         $rentalMedian = $this->getRentalMedianHash($category);
   
         $medianYield = $this->getMedianYieldHash($category);
         
      
         $suburbProfile{'noOfSales'} = $$noOfSales{$suburbIndex};
         $suburbProfile{'minAdvertisedSalePrice'} = $$minSalePrice{$suburbIndex};
         $suburbProfile{'maxAdvertisedSalePrice'} = $$maxSalePrice{$suburbIndex};
         $suburbProfile{'currentSalesAdvertised'} = $$noOfAdvertised{$suburbIndex};
         $suburbProfile{'meanAdvertisedSalePrice'} = $$salesMean{$suburbIndex};
         $suburbProfile{'stdDevAdvertisedSalePrice'} = $$salesStdDev{$suburbIndex};
         $suburbProfile{'medianAdvertisedSalePrice'} = $$salesMedian{$suburbIndex};
         $suburbProfile{'noOfRentals'} = $$noOfRentals{$suburbIndex};
         $suburbProfile{'minAdvertisedRentalPrice'} = $$minRentalPrice{$suburbIndex};
         $suburbProfile{'maxAdvertisedRentalPrice'} = $$maxRentalPrice{$suburbIndex};
         $suburbProfile{'meanAdvertisedRentalPrice'} = $$rentalMean{$suburbIndex};
         $suburbProfile{'stdDevAdvertisedRentalPrice'} = $$rentalStdDev{$suburbIndex};
         $suburbProfile{'medianAdvertisedRentalPrice'} = $$rentalMedian{$suburbIndex};  

         $suburbProfile{'medianYield'} = $$medianYield{$suburbIndex};  
         
         # update the record in the table...
         $this->_updateRecord($suburbIndex, $suburbName, $state, $typeIndex, $category, \%suburbProfile);
      
      }
   }
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# _updateRecord
# updates the analysis data for the specified suburb
#
# Purpose:
#  Storing information in the database
#
# Parameters:
# $suburbIndex
# $typeIndex
# $category
#   ...data...
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
sub _updateRecord

{
   my $this = shift;
   my $suburbIndex = shift;
   my $suburbName = shift;
   my $state = shift;
   my $typeIndex = shift;
   my $category = shift;
   my $suburbProfileRef = shift;
 
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   my $tableName = $this->{'tableName'};
     
   if ($sqlClient)
   {
      # first, attempt to delete the entry that this is going to replace
      $deleteStatement = "DELETE FROM $tableName WHERE SuburbIndex = $suburbIndex AND TypeIndex = $typeIndex AND Category = $category";
      $statement = $sqlClient->prepareStatement($deleteStatement);
      
      if ($sqlClient->executeStatement($statement))
      {
         $success = 1;
      }
      
      $statementText = "INSERT INTO $tableName (";
      
      @columnNames = keys %$suburbProfileRef;
      
      # modify the statement to specify each column value to set 
      $appendString = "DateEntered, SuburbIndex, SuburbName, State, TypeIndex, Category, ";
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
      @columnValues = values %$suburbProfileRef;
      $index = 0;
      $quotedSuburbName = $sqlClient->quote($suburbName);
      $quotedState = $sqlClient->quote($state);
      
      if (!$this->{'useDifferentTime'})
      {
         $localTime = "localtime()";
      }
      else
      {
         # use the specified date instead of the current time
         $localTime = $sqlClient->quote($this->{'dateEntered'});
         $this->{'useDifferentTime'} = 0;  # reset the flag
      }      
      
      $appendString = "$localTime, $suburbIndex, $quotedSuburbName, $quotedState, $typeIndex, $category, ";
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

# searches the postcode list for the suburb name matching the specified index
# return suburb, state
sub lookupSuburbName
{   
   my $this = shift;
   my $suburbIndex = shift;
   my $sqlClient = $this->{'sqlClient'};
   my $suburbName;
   my $state;
   
   if ($sqlClient)
   {       
      $statementText = "SELECT locality, state FROM AusPostCodes WHERE SuburbIndex = $suburbIndex";
            
      @suburbList = $sqlClient->doSQLSelect($statementText);
      
      if ($suburbList[0])
      {
         $suburbName = $suburbList[0]{'locality'};
         $state = $suburbList[0]{'state'};              
      }                    
   }   
   return ($suburbName, $state);
}  

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
#  FUNCTIONS FOR GETTING INFORMATION FROM THE TABLE
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------


# ------------------------------------------------------------------------------------------------- 
# returns a hash of the suburb names (index=name)
sub getSuburbNameHash
{
   my $this = shift;   

   $listRef = $this->{'suburbNameHash'};

   return $listRef;
}


# ------------------------------------------------------------------------------------------------- 
# returns a hash of the suburb indexes (name=index)
sub getSuburbIndexHash
{
   my $this = shift;   

   $listRef = $this->{'suburbIndexHash'};

   return $listRef;
}


# ------------------------------------------------------------------------------------------------- 
# returns the hash of number of sales 
sub getNoOfSalesHash
{
   my $this = shift;   
   my $category = shift;

   $listRef = $this->{'noOfSalesCategoryHash'};
   #print "noslistRef[$category]=", $$listRef[$category], "\n";
   return $$listRef[$category];
}


# ------------------------------------------------------------------------------------------------- 
# returns the hash of number of sales 'currently advertised' 
sub getNoOfAdvertisedHash
{
   my $this = shift;   
   my $category = shift;

   $listRef = $this->{'noOfAdvertisedCategoryHash'};
   #print "noslistRef[$category]=", $$listRef[$category], "\n";
   return $$listRef[$category];
}

# ------------------------------------------------------------------------------------------------- 
# returns the hash of sales minimum 
sub getSalesMinHash
{
   my $this = shift;   
   my $category = shift;

   $listRef = $this->{'minSalePriceCategoryHash'};
   #print "smilistRef[$category]=", $$listRef[$category], "\n";
   return $$listRef[$category];
}

# ------------------------------------------------------------------------------------------------- 
# returns the hash of sales maximum 
sub getSalesMaxHash
{
   my $this = shift;   
   my $category = shift;

   $listRef = $this->{'maxSalePriceCategoryHash'};
   #print "smalistRef[$category]=", $$listRef[$category], "\n";

   return $$listRef[$category];
}

# ------------------------------------------------------------------------------------------------- 
# returns the hash of sales mean 
sub getSalesMeanHash
{
   my $this = shift;   
   my $category = shift;

   $listRef = $this->{'salesMeanCategoryHash'};
  # print "smnlistRef[$category]=", $$listRef[$category], "\n";
   return $$listRef[$category];
}

# ------------------------------------------------------------------------------------------------- 
# returns the hash of sales median 
sub getSalesMedianHash
{
   my $this = shift;   
   my $category = shift;

   $listRef = $this->{'salesMedianCategoryHash'};
 #  print "smelistRef[$category]=", $$listRef[$category], "\n";
   return $$listRef[$category];
}

# ------------------------------------------------------------------------------------------------- 
# returns the hash of sales standard deviation 
sub getSalesStdDevHash
{
   my $this = shift;   
   my $category = shift;

   $listRef = $this->{'salesStdDevCategoryHash'};
   #print "ssdlistRef[$category]=", $$listRef[$category], "\n";
   return $$listRef[$category];
}


# ------------------------------------------------------------------------------------------------- 
# returns the hash of cashflow median 
sub getCashflowMedianHash
{
   my $this = shift;   
   my $category = shift;

   $listRef = $this->{'medianCashflowCategoryHash'};
 #  print "smelistRef[$category]=", $$listRef[$category], "\n";
   return $$listRef[$category];
}


# ------------------------------------------------------------------------------------------------- 
# returns the hash of number of retnals
sub getNoOfRentalsHash
{
   my $this = shift;   
   my $category = shift;

   $listRef = $this->{'noOfRentalsCategoryHash'};
   #print "norlistRef[$category]=", $$listRef[$category], "\n";
   return $$listRef[$category];   
}


# ------------------------------------------------------------------------------------------------- 
# returns the hash of rental minimum 
sub getRentalMinHash
{
   my $this = shift;
   my $category = shift;

   $listRef = $this->{'minRentalPriceCategoryHash'};
   #print "mirlistRef[$category]=", $$listRef[$category], "\n";
   return $$listRef[$category];      
}

# ------------------------------------------------------------------------------------------------- 
# returns the hash of rental maximum 
sub getRentalMaxHash
{
   my $this = shift;      
   my $category = shift;

   $listRef = $this->{'maxRentalPriceCategoryHash'};
   #print "marlistRef[$category]=", $$listRef[$category], "\n";
   return $$listRef[$category];
}

# ------------------------------------------------------------------------------------------------- 
# returns the hash of rental mean 
sub getRentalMeanHash
{
   my $this = shift;   
   my $category = shift;

   $listRef = $this->{'rentalMeanCategoryHash'};
   #print "smilistRef[$category]=", $$listRef[$category], "\n";
   return $$listRef[$category];
}


# ------------------------------------------------------------------------------------------------- 
# returns the hash of rental median 
sub getRentalMedianHash
{
   my $this = shift;   
   my $category = shift;

   $listRef = $this->{'rentalMedianCategoryHash'};
   #print "smilistRef[$category]=", $$listRef[$category], "\n";
   return $$listRef[$category];
}

# ------------------------------------------------------------------------------------------------- 
# returns the hash of rental standard deviations 
sub getRentalStdDevHash
{
   my $this = shift;      
   my $category = shift;

   $listRef = $this->{'rentalStdDevCategoryHash'};
   #print "smilistRef[$category]=", $$listRef[$category], "\n";
   return $$listRef[$category];
}

# -------------------------------------------------------------------------------------------------
# ------------------------------------------------------------------------------------------------- 
# returns the hash of yeild mean 
sub getMedianYieldHash
{
   my $this = shift;   
   my $category = shift;

   $listRef = $this->{'medianYieldCategoryHash'};
   #print "smilistRef[$category]=", $$listRef[$category], "\n";
   return $$listRef[$category];
}
# ------------------------------------------------------------------------------------------------- 
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# performs the query on the database to get selected data for analysis
sub getAnalysisResults

{
   my $this = shift;
   my $state = shift;
   my $typeIndex = shift;

   my $sqlClient = $this->{'sqlClient'};
   my $quotedState = $sqlClient->quote($state);
   my %suburbName;
   
   $salesSelectCommand = "select * from SuburbAnalysisTable where State=$quotedState and TypeIndex=$typeIndex";
   
   my @analysisResults = $sqlClient->doSQLSelect($salesSelectCommand);
   
   $this->{'analysisResultsList'} = \@analysisResults;
   
   
   $length = @analysisResults;
   print "<br>decoding $length analysis results...</br>\n";
      
   foreach (@analysisResults)
   {
      # $_ are analysis results for one |suburb|type|category|
      
      $suburbIndex = $$_{'SuburbIndex'};
      $suburbName = $$_{'SuburbName'};
      $typeIndex = $$_{'TypeIndex'};
      $category = $$_{'Category'};

      $suburbIndexHash{$suburbName} = $suburbIndex;
      $suburbNameHash{$suburbIndex} = $suburbName;
      $noOfSales[$category]{$suburbIndex} = $$_{'NoOfSales'};
      $minSalePrice[$category]{$suburbIndex} = $$_{'MinAdvertisedSalePrice'};
      $maxSalePrice[$category]{$suburbIndex} = $$_{'MaxAdvertisedSalePrice'};
      $salesMean[$category]{$suburbIndex} = $$_{'MeanAdvertisedSalePrice'};
      $salesMedian[$category]{$suburbIndex} = $$_{'MedianAdvertisedSalePrice'};
      $salesStdDev[$category]{$suburbIndex} = $$_{'StdDevAdvertisedSalePrice'};
      $noOfCurrentlyAdvertised[$category]{$suburbIndex} = $$_{'CurrentSalesAdvertised'};
      $noOfRentals[$category]{$suburbIndex} = $$_{'NoOfRentals'};
      $minRentalPrice[$category]{$suburbIndex} = $$_{'MinAdvertisedRentalPrice'};
      $maxRentalPrice[$category]{$suburbIndex} = $$_{'MaxAdvertisedRentalPrice'};
      $rentalMean[$category]{$suburbIndex} = $$_{'MeanAdvertisedRentalPrice'};
      $rentalMedian[$category]{$suburbIndex} = $$_{'MedianAdvertisedRentalPrice'};
      $rentalStdDev[$category]{$suburbIndex} = $$_{'StdDevAdvertisedRentalPrice'};
      $medianYield[$category]{$suburbIndex} = $$_{'MedianYield'};
      
   }

   $this->{'suburbNameHash'} = \%suburbNameHash;     
   $this->{'suburbIndexHash'} = \%suburbIndexHash;     
   $this->{'noOfSalesCategoryHash'} = \@noOfSales;    
   $this->{'minSalePriceCategoryHash'} = \@minSalePrice;
   $this->{'maxSalePriceCategoryHash'} = \@maxSalePrice;
   $this->{'salesMeanCategoryHash'} = \@salesMean;
   $this->{'salesMedianCategoryHash'} = \@salesMedian;
   $this->{'salesStdDevCategoryHash'} = \@salesStdDev;
   $this->{'noOfAdvertisedCategoryHash'} = \@noOfCurrentlyAdvertised;

   $this->{'noOfRentalsCategoryHash'} = \@noOfRentals;   
   $this->{'minRentalPriceCategoryHash'} = \@minRentalPrice;
   $this->{'maxRentalPriceCategoryHash'} = \@maxRentalPrice;
   $this->{'rentalMeanCategoryHash'} = \@rentalMean;
   $this->{'rentalMedianCategoryHash'} = \@rentalMedian;
   $this->{'rentalStdDevCategoryHash'} = \@rentalStdDev;

   $this->{'medianYieldCategoryHash'} = \@medianYield;
   
   
   return @analysisResults;
}

# -------------------------------------------------------------------------------------------------

