#!/usr/bin/perl
# 16 June 2004
# Jeromy Evans
#
# Provides functions for performing analysis of the property database
#
# Started: 16 June 2004
#
# History
#   9 Dec 04 - changed to use MasterPropertyTable and WorkingView_AdvertisedRentalProfiles

# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
package AnalysisTools;
require Exporter;
use SQLClient;
use DebugTools;
use PrintLogger;

@ISA = qw(Exporter);

my $DEFAULT_SUBURB_CONSTRAINT = "";
my $DEFAULT_TYPE_CONSTRAINT = "Type not like '%Land%' and Type not like '%Lifestyle%'";
my $DEFAULT_BATHROOMS_CONSTRAINT = "";
my $DEFAULT_BEDROOMS_CONSTRAINT = "";
my $DEFAULT_SALES_ANALYSIS_CONSTRAINT =  "(DateLastAdvertised > date_add(now(), interval -6 month)) and ";
my $DEFAULT_LAST_ADVERTISED_CONSTRAINT = "(DateLastAdvertised > date_add(now(), interval -14 day)) and ";
my $DEFAULT_RENTALS_ADVERTISED_CONSTRAINT = "((DateEntered > date_add(now(), interval -3 month)) or (LastEncountered > date_add(now(), interval -3 month))) and ";

my ($printLogger) = undef;
# -------------------------------------------------------------------------------------------------
# new
# contructor for the analysis toolkit
#
# Purpose:
#  initialisation of the analysis tookkit
#
# Parameters:
#  
#
# Constraints:
#  nil
#
# Updates:
#  Nil
#
# Returns:
#  AnalysisTools object
#    
sub new
{
   my $sqlClient = shift;    
     
   my $analysisTools = {       
      sqlClient => $sqlClient,
      suburbSearch => $DEFAULT_SUBURB_CONSTRAINT,
      typeSearch => $DEFAULT_TYPE_CONSTRAINT,
      bathroomsSearch => $DEFAULT_BATHROOMS_CONSTRAINT,
      bedroomsSearch => $DEFAULT_BEDROOMS_CONSTRAINT,
      dateSearch => $DEFAULT_SALES_ANALYSIS_CONSTRAINT,      
      date14daySearch => $DEFAULT_LAST_ADVERTISED_CONSTRAINT,
      rentalsDateSearch => $DEFAULT_RENTALS_ADVERTISED_CONSTRAINT      
   };               
   
   bless $analysisTools;     
   
   return $analysisTools;   # return this
}

# -------------------------------------------------------------------------------------------------
# setSuburbConstraint
# sets a value representing the suburb to search within
sub setSuburbConstraint
{   
   my $this = shift;   
   my $suburbParam = shift;
      
   if (defined $suburbParam)
   {     
      #$this->{'suburbSearch'} = "SuburbName like '%$suburbParam%' and ";
      $this->{'suburbSearch'} = "SuburbName='$suburbParam' and ";      
   }
   else
   {            
      $this->{'suburbSearch'} = $DEFAULT_SUBURB_CONSTRAINT;      
   }         
}

# -------------------------------------------------------------------------------------------------
# setTypeConstraint
# sets a value representing the type of property for the analysis
sub setTypeConstraint
{  
   my $this = shift;
   my $typeParam = shift;

   if (defined $typeParam)
   {  
      if ($typeParam eq 'house')
      {
         $this->{'typeSearch'} = "Type like '%house%'";         
      }
      elsif ($typeParam eq 'unit') 
      {
         $this->{'typeSearch'} = "Type like '%Apartment%' or Type like '%Flats%' or Type like '%Unit%' or Type like '%Townhouse%' or Type like '%Villa%'";         
      }
      else
      {
         $this->{'typeSearch'} = $DEFAULT_TYPE_CONSTRAINT;        
      }
   }
   else
   {
      $this->{'typeSearch'} = $DEFAULT_TYPE_CONSTRAINT;      
   }         
}

# -------------------------------------------------------------------------------------------------
# setBathroomsConstraint
# sets a value representing the number of bathrooms for the analysis
sub setBathroomsConstraint
{   
   my $this = shift;   
   my $bathroomsParam = shift;
      
   if (defined $bathroomsParam)
   {     
      $this->{'bathroomsSearch'} = "and Bathrooms = $bathroomsParam";     
   }
   else
   {            
      $this->{'bathroomsSearch'} = $DEFAULT_BATHROOMS_CONSTRAINT;      
   }         
}

# -------------------------------------------------------------------------------------------------
# setBedroomsConstraint
# sets a value representing the number of bedrooms for the analysis constraint
sub setBedroomsConstraint
{     
   my $this = shift;
   my $bedroomsParam = shift;

   if (defined $bedroomsParam)
   
   {           
      $this->{'bedroomsSearch'} = "and Bedrooms = $bedroomsParam";     
   }
   else
   {
      $this->{'bedroomsSearch'} = "";      
   }
   
   return $bedroomsDescription;   
}


# -------------------------------------------------------------------------------------------------
# performs the query on the database to get selected data for analysis
sub fetchAnalysisData

{
   my $this = shift;
   my $sqlClient = $this->{'sqlClient'};
   $salesSelectCommand = "select StreetNumber, Street, SuburbName, AdvertisedPriceLower, AdvertisedPriceUpper, Bedrooms, Bathrooms, unix_timestamp(DateLastAdvertised) as DateLastAdvertised from MasterPropertyTable where ".$this->{'dateSearch'}." state='WA' and ".$this->{'suburbSearch'}." ".$this->{'typeSearch'}." ".$this->{'bedroomsSearch'}." ".$this->{'bathroomsSearch'}." order by SuburbName, Street, StreetNumber, Bedrooms, Bathrooms";
   print "<br>", "<tt>SALES  :$salesSelectCommand</tt><br\>";
   my @salesResults = $sqlClient->doSQLSelect($salesSelectCommand);
   
   $rentalsSelectCommand = "select StreetNumber, Street, SuburbName, AdvertisedWeeklyRent, Bedrooms, Bathrooms from WorkingView_AdvertisedRentalProfiles where ".$this->{'rentalsDateSearch'}." state='WA' and ".$this->{'suburbSearch'}." ".$this->{'typeSearch'}." ".$this->{'bedroomsSearch'}." ".$this->{'bathroomsSearch'}." order by SuburbName, Bedrooms, Bathrooms";
   print "<br>", "<tt>RENTALS:$rentalsSelectCommand</tt><br\>";
   my @rentalResults = $sqlClient->doSQLSelect($rentalsSelectCommand);
   #$length=@rentalResults;
   #print "<br>length=", $length, "<br><br>\n";
   $this->{'salesResultsList'} = \@salesResults;
   $this->{'rentalResultsList'} = \@rentalResults;
}

# -------------------------------------------------------------------------------------------------
# Fetches data from the database using the search constraints and calculates analysis parameters
sub calculateSalesAnalysis

{
   my $this = shift;
    
   my $ALL = 0;
   my $THREE_BY_ANY = 1;
   my $THREE_BY_ONE = 2;
   my $THREE_BY_TWO = 3;
   my $FOUR_BY_ANY = 4;
   my $FOUR_BY_ONE = 5;
   my $FOUR_BY_TWO = 6;
   my $FIVE_BY_ANY = 7;
   my $NO_OF_CATEGORIES = 8;
   
   my $index;
   my $suburbName;
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
   
   # loop through the very large array of properties
   foreach (@$propertiesListRef)
   {
      $suburbName = $$_{'SuburbName'};
   
      # if a buyer enquiry range is specified, take 2/3rds of the range as the price.
      if (defined $$_{'AdvertisedPriceUpper'} && ($$_{'AdvertisedPriceUpper'}) > 0)
      {
         $distance = $$_{'AdvertisedPriceUpper'} - $$_{'AdvertisedPriceLower'};
         $advertisedPrice = $$_{'AdvertisedPriceLower'} + ($distance * 2 / 3)
      }
      else
      {
         $advertisedPrice = $$_{'AdvertisedPriceLower'};  
      }              
   
      if ($advertisedPrice > 0)
      {
         
         #print "sumOfSalePrices[0]{$suburbName}=", $sumOfSalePrices[0]{$suburbName}, "\n";
         #print "sumOfSalePrices[1]{$suburbName}=", $sumOfSalePrices[1]{$suburbName}, "\n";
         #print "sumOfSalePrices[2]{$suburbName}=", $sumOfSalePrices[2]{$suburbName}, "\n";
         #print "sumOfSalePrices[3]{$suburbName}=", $sumOfSalePrices[3]{$suburbName}, "\n";
         #print "sumOfSalePrices[4]{$suburbName}=", $sumOfSalePrices[4]{$suburbName}, "\n";
         #print "sumOfSalePrices[5]{$suburbName}=", $sumOfSalePrices[5]{$suburbName}, "\n";
         #print "sumOfSalePrices[6]{$suburbName}=", $sumOfSalePrices[6]{$suburbName}, "\n";
         #print "sumOfSalePrices[7]{$suburbName}=", $sumOfSalePrices[7]{$suburbName}, "\n";
         # calculate the total of price for calculation of the mean
         if (!defined $sumOfSalePrices[$ALL]{$suburbName})
         {
            # initialise counters for the first time for this suburbname
            $sumOfSalePrices[$ALL]{$suburbName} = 0;
            $sumOfSalePrices[$THREE_BY_ANY]{$suburbName} = 0;
            $sumOfSalePrices[$THREE_BY_ONE]{$suburbName} = 0;
            $sumOfSalePrices[$THREE_BY_TWO]{$suburbName} = 0;
            $sumOfSalePrices[$FOUR_BY_ANY]{$suburbName} = 0;
            $sumOfSalePrices[$FOUR_BY_ONE]{$suburbName} = 0;
            $sumOfSalePrices[$FOUR_BY_TWO]{$suburbName} = 0;
            $sumOfSalePrices[$FIVE_BY_ANY]{$suburbName} = 0;
            
            $sumOfSquaredSalePrices[$ALL]{$suburbName} = 0;
            $sumOfSquaredSalePrices[$THREE_BY_ANY]{$suburbName} = 0;
            $sumOfSquaredSalePrices[$THREE_BY_ONE]{$suburbName} = 0;
            $sumOfSquaredSalePrices[$THREE_BY_TWO]{$suburbName} = 0;
            $sumOfSquaredSalePrices[$FOUR_BY_ANY]{$suburbName} = 0;
            $sumOfSquaredSalePrices[$FOUR_BY_ONE]{$suburbName} = 0;
            $sumOfSquaredSalePrices[$FOUR_BY_TWO]{$suburbName} = 0;
            $sumOfSquaredSalePrices[$FIVE_BY_ANY]{$suburbName} = 0;
            
            $noOfAdvertisedSales[$ANY]{$suburbName} = 0;
            $noOfAdvertisedSales[$THREE_BY_ANY]{$suburbName} = 0;
            $noOfAdvertisedSales[$THREE_BY_ONE]{$suburbName} = 0;
            $noOfAdvertisedSales[$THREE_BY_TWO]{$suburbName} = 0;
            $noOfAdvertisedSales[$FOUR_BY_ANY]{$suburbName} = 0;
            $noOfAdvertisedSales[$FOUR_BY_ONE]{$suburbName} = 0;
            $noOfAdvertisedSales[$FOUR_BY_TWO]{$suburbName} = 0;
            $noOfAdvertisedSales[$FIVE_BY_ANY]{$suburbName} = 0;
            
            $noOfCurrentlyAdvertised[$ANY]{$suburbName} = 0;
            $noOfCurrentlyAdvertised[$THREE_BY_ANY]{$suburbName} = 0;
            $noOfCurrentlyAdvertised[$THREE_BY_ONE]{$suburbName} = 0;
            $noOfCurrentlyAdvertised[$THREE_BY_TWO]{$suburbName} = 0;
            $noOfCurrentlyAdvertised[$FOUR_BY_ANY]{$suburbName} = 0;
            $noOfCurrentlyAdvertised[$FOUR_BY_ONE]{$suburbName} = 0;
            $noOfCurrentlyAdvertised[$FOUR_BY_TWO]{$suburbName} = 0;
            $noOfCurrentlyAdvertised[$FIVE_BY_ANY]{$suburbName} = 0;
            
            my @newList;
            $advertisedPriceList[$ANY]{$suburbName} = \@newList;  # initialise a new array
            my @newList;
            $advertisedPriceList[$THREE_BY_ANY]{$suburbName}  = \@newList;  # initialise a new array
            my @newList;
            $advertisedPriceList[$THREE_BY_ONE]{$suburbName}  = \@newList;  # initialise a new array
            my @newList;
            $advertisedPriceList[$THREE_BY_TWO]{$suburbName}  = \@newList;  # initialise a new array
            my @newList;
            $advertisedPriceList[$FOUR_BY_ANY]{$suburbName} = \@newList;  # initialise a new array
            my @newList;
            $advertisedPriceList[$FOUR_BY_ONE]{$suburbName}  = \@newList;  # initialise a new array
            my @newList;
            $advertisedPriceList[$FOUR_BY_TWO]{$suburbName}  = \@newList;  # initialise a new array
            my @newList;
            $advertisedPriceList[$FIVE_BY_ANY]{$suburbName}  = \@newList;  # initialise a new array
            
         }
         
         # add the advertised price to the totals for the suburb
         $sumOfSalePrices[$ALL]{$suburbName} += $advertisedPrice;
         # calculate the total of squared prices for calculation of the standard deviation
         $sumOfSquaredSalePrices[$ALL]{$suburbName} += ($advertisedPrice**2);
         # count the number of listings in the suburb
         $noOfAdvertisedSales[$ALL]{$suburbName} += 1;
         # record the advertised price in a list for this suburb - the list is used later to calculate the 
         # median advertised price for that suburb
         $listRef = $advertisedPriceList[$ANY]{$suburbName};
         #print "advertisedPriceList{$suburbName}=", $advertisedPriceList{$suburbName}, "\n";
         push @$listRef, $advertisedPrice;
         
         # record the lowest-high price listed for this suburb
         if ((!defined $minSalePrice[$ALL]{$suburbName}) || ($advertisedPrice < $minSalePrice[$ALL]{$suburbName}))
         {
            $minSalePrice[$ALL]{$suburbName} = $advertisedPrice;
         }
      
         # record the highest-high price listed for this suburb
         if ((!defined $maxSalePrice[$ALL]{$suburbName}) || ($advertisedPrice > $maxSalePrice[$ALL]{$suburbName}))
         {
            $maxSalePrice[$ALL]{$suburbName} = $advertisedPrice;
         }
         
         $cmpTime = time() - (14*24*60*60) ;
         #$cmpTime = time();
         #print "DLA=", $$_{'DateLastAdvertised'}, " cmpTime= $cmpTime\n";
         ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =  localtime($cmpTime);
         #print " cmpTime:", $year-100, "-", $mon+1, "-$mday, $hour:$min:$sec\n";
        
         if ($$_{'DateLastAdvertised'} > $cmpTime)
         {
            # count the number of listings in the suburb 'still advertised'
            #print "   count this\n";
            $noOfCurrentlyAdvertised[$ALL]{$suburbName} += 1;
         }
         
         if ($$_{'Bedrooms'} == 3)
         {
            $sumOfSalePrices[$THREE_BY_ANY]{$suburbName} += $advertisedPrice;
            $sumOfSquaredSalePrices[$THREE_BY_ANY]{$suburbName} += ($advertisedPrice**2);
            $noOfAdvertisedSales[$THREE_BY_ANY]{$suburbName} += 1;
            $listRef = $advertisedPriceList[$THREE_BY_ANY]{$suburbName};
            push @$listRef, $advertisedPrice;
            
            # record the lowest-high price listed for this suburb
            if ((!defined $minSalePrice[$THREE_BY_ANY]{$suburbName}) || ($advertisedPrice < $minSalePrice[$THREE_BY_ANY]{$suburbName}))
            {
               $minSalePrice[$THREE_BY_ANY]{$suburbName} = $advertisedPrice;
            }
         
            # record the highest-high price listed for this suburb
            if ((!defined $maxSalePrice[$THREE_BY_ANY]{$suburbName}) || ($advertisedPrice > $maxSalePrice[$THREE_BY_ANY]{$suburbName}))
            {
               $maxSalePrice[$THREE_BY_ANY]{$suburbName} = $advertisedPrice;
            }
            
            if ($$_{'DateLastAdvertised'} > $cmpTime)
            {
               # count the number of listings in the suburb 'still advertised'
               $noOfCurrentlyAdvertised[$THREE_BY_ANY]{$suburbName} += 1;
            }
            
            if ($$_{'Bathrooms'} == 1)
            {
               $sumOfSalePrices[$THREE_BY_ONE]{$suburbName} += $advertisedPrice;
               $sumOfSquaredSalePrices[$THREE_BY_ONE]{$suburbName} += ($advertisedPrice**2);
               $noOfAdvertisedSales[$THREE_BY_ONE]{$suburbName} += 1;
               $listRef = $advertisedPriceList[$THREE_BY_ONE]{$suburbName};
               push @$listRef, $advertisedPrice;
               
               # record the lowest-high price listed for this suburb
               if ((!defined $minSalePrice[$THREE_BY_ONE]{$suburbName}) || ($advertisedPrice < $minSalePrice[$THREE_BY_ONE]{$suburbName}))
               {
                  $minSalePrice[$THREE_BY_ONE]{$suburbName} = $advertisedPrice;
               }
            
               # record the highest-high price listed for this suburb
               if ((!defined $maxSalePrice[$THREE_BY_ONE]{$suburbName}) || ($advertisedPrice > $maxSalePrice[$THREE_BY_ONE]{$suburbName}))
               {
                  $maxSalePrice[$THREE_BY_ONE]{$suburbName} = $advertisedPrice;
               }
            
               if ($$_{'DateLastAdvertised'} > $cmpTime)
               {
                  # count the number of listings in the suburb 'still advertised'
                  $noOfCurrentlyAdvertised[$THREE_BY_ONE]{$suburbName} += 1;
               }
               
            }
            elsif ($$_{'Bathrooms'} == 2)
            {
               $sumOfSalePrices[$THREE_BY_TWO]{$suburbName} += $advertisedPrice;          
               $sumOfSquaredSalePrices[$THREE_BY_TWO]{$suburbName} += ($advertisedPrice**2);
               $noOfAdvertisedSales[$THREE_BY_TWO]{$suburbName} += 1;
               $listRef = $advertisedPriceList[$THREE_BY_TWO]{$suburbName};
               push @$listRef, $advertisedPrice;
               
                # record the lowest-high price listed for this suburb
               if ((!defined $minSalePrice[$THREE_BY_TWO]{$suburbName}) || ($advertisedPrice < $minSalePrice[$THREE_BY_TWO]{$suburbName}))
               {
                  $minSalePrice[$THREE_BY_TWO]{$suburbName} = $advertisedPrice;
               }
            
               # record the highest-high price listed for this suburb
               if ((!defined $maxSalePrice[$THREE_BY_TWO]{$suburbName}) || ($advertisedPrice > $maxSalePrice[$THREE_BY_TWO]{$suburbName}))
               {
                  $maxSalePrice[$THREE_BY_TWO]{$suburbName} = $advertisedPrice;
               }
               
               if ($$_{'DateLastAdvertised'} > $cmpTime)
               {
                  # count the number of listings in the suburb 'still advertised'
                  $noOfCurrentlyAdvertised[$THREE_BY_TWO]{$suburbName} += 1;
               }
            }
         }
         else
         {
            if ($$_{'Bedrooms'} == 4)
            {
               $sumOfSalePrices[$FOUR_BY_ANY]{$suburbName} += $advertisedPrice;
               $sumOfSquaredSalePrices[$FOUR_BY_ANY]{$suburbName} += ($advertisedPrice**2);
               $noOfAdvertisedSales[$FOUR_BY_ANY]{$suburbName} += 1;
               $listRef = $advertisedPriceList[$FOUR_BY_ANY]{$suburbName};
               push @$listRef, $advertisedPrice;
               
               # record the lowest-high price listed for this suburb
               if ((!defined $minSalePrice[$FOUR_BY_ANY]{$suburbName}) || ($advertisedPrice < $minSalePrice[$FOUR_BY_ANY]{$suburbName}))
               {
                  $minSalePrice[$FOUR_BY_ANY]{$suburbName} = $advertisedPrice;
               }
            
               # record the highest-high price listed for this suburb
               if ((!defined $maxSalePrice[$FOUR_BY_ANY]{$suburbName}) || ($advertisedPrice > $maxSalePrice[$FOUR_BY_ANY]{$suburbName}))
               {
                  $maxSalePrice[$FOUR_BY_ANY]{$suburbName} = $advertisedPrice;
               }
               
               if ($$_{'DateLastAdvertised'} > $cmpTime)
               {
                  # count the number of listings in the suburb 'still advertised'
                  $noOfCurrentlyAdvertised[$FOUR_BY_ANY]{$suburbName} += 1;
               }
               
               if ($$_{'Bathrooms'} == 1)
               {
                  $sumOfSalePrices[$FOUR_BY_ONE]{$suburbName} += $advertisedPrice;
                  $sumOfSquaredSalePrices[$FOUR_BY_ONE]{$suburbName} += ($advertisedPrice**2);
                  $noOfAdvertisedSales[$FOUR_BY_ONE]{$suburbName} += 1;
                  $listRef = $advertisedPriceList[$FOUR_BY_ONE]{$suburbName};
                  push @$listRef, $advertisedPrice;
                  
                   # record the lowest-high price listed for this suburb
                  if ((!defined $minSalePrice[$FOUR_BY_ONE]{$suburbName}) || ($advertisedPrice < $minSalePrice[$FOUR_BY_ONE]{$suburbName}))
                  {
                     $minSalePrice[$FOUR_BY_ONE]{$suburbName} = $advertisedPrice;
                  }
               
                  # record the highest-high price listed for this suburb
                  if ((!defined $maxSalePrice[$FOUR_BY_ONE]{$suburbName}) || ($advertisedPrice > $maxSalePrice[$FOUR_BY_ONE]{$suburbName}))
                  {
                     $maxSalePrice[$FOUR_BY_ONE]{$suburbName} = $advertisedPrice;
                  }
                  
                  if ($$_{'DateLastAdvertised'} > $cmpTime)
                  {
                     # count the number of listings in the suburb 'still advertised'
                     $noOfCurrentlyAdvertised[$FOUR_BY_ONE]{$suburbName} += 1;
                  }
               }
               elsif ($$_{'Bathrooms'} == 2)
               {
                  $sumOfSalePrices[$FOUR_BY_TWO]{$suburbName} += $advertisedPrice;      
                  $sumOfSquaredSalePrices[$FOUR_BY_TWO]{$suburbName} += ($advertisedPrice**2);
                  $noOfAdvertisedSales[$FOUR_BY_TWO]{$suburbName} += 1;
                  $listRef = $advertisedPriceList[$FOUR_BY_TWO]{$suburbName};
                  push @$listRef, $advertisedPrice;
                  
                   # record the lowest-high price listed for this suburb
                  if ((!defined $minSalePrice[$FOUR_BY_TWO]{$suburbName}) || ($advertisedPrice < $minSalePrice[$FOUR_BY_TWO]{$suburbName}))
                  {
                     $minSalePrice[$FOUR_BY_TWO]{$suburbName} = $advertisedPrice;
                  }
               
                  # record the highest-high price listed for this suburb
                  if ((!defined $maxSalePrice[$FOUR_BY_TWO]{$suburbName}) || ($advertisedPrice > $maxSalePrice[$FOUR_BY_TWO]{$suburbName}))
                  {
                     $maxSalePrice[$FOUR_BY_TWO]{$suburbName} = $advertisedPrice;
                  }
                  
                  if ($$_{'DateLastAdvertised'} > $cmpTime)
                  {
                     # count the number of listings in the suburb 'still advertised'
                     $noOfCurrentlyAdvertised[$FOUR_BY_TWO]{$suburbName} += 1;
                  }
               }
            }
            else
            {
               if ($$_{'Bedrooms'} == 5)
               {
                  $sumOfSalePrices[$FIVE_BY_ANY]{$suburbName} += $advertisedPrice;
                  $sumOfSquaredSalePrices[$FIVE_BY_ANY]{$suburbName} += ($advertisedPrice**2);
                  $noOfAdvertisedSales[$FIVE_BY_ANY]{$suburbName} += 1;
                  $listRef = $advertisedPriceList[$FIVE_BY_ANY]{$suburbName};
                  push @$listRef, $advertisedPrice;
                  
                   # record the lowest-high price listed for this suburb
                  if ((!defined $minSalePrice[$FIVE_BY_ANY]{$suburbName}) || ($advertisedPrice < $minSalePrice[$FIVE_BY_ANY]{$suburbName}))
                  {
                     $minSalePrice[$FIVE_BY_ANY]{$suburbName} = $advertisedPrice;
                  }
               
                  # record the highest-high price listed for this suburb
                  if ((!defined $maxSalePrice[$FIVE_BY_ANY]{$suburbName}) || ($advertisedPrice > $maxSalePrice[$FIVE_BY_ANY]{$suburbName}))
                  {
                     $maxSalePrice[$FIVE_BY_ANY]{$suburbName} = $advertisedPrice;
                  }
                  
                  if ($$_{'DateLastAdvertised'} > $cmpTime)
                  {
                     # count the number of listings in the suburb 'still advertised'
                     $noOfCurrentlyAdvertised[$FIVE_BY_ANY]{$suburbName} += 1;
                  }
               }
            }
         }     
      }
   }         
   
   # loop through all the results once more to calculate the mean and stddev (couldn't do this
   # until the number of listings was known)
   # the keys of noOfSales is the suburblist
   $hashRef = $noOfAdvertisedSales[$ALL];
   foreach (keys %$hashRef)
   {   
      $suburbName = $_;
      # loop for all the different categories
      for ($propertyType = 0; $propertyType < $NO_OF_CATEGORIES; $propertyType++)
      {
         if (defined $sumOfSalePrices[$propertyType]{$suburbName} && ($noOfAdvertisedSales[$propertyType]{$suburbName} > 0))
         {
            $salesMean[$propertyType]{$suburbName} = $sumOfSalePrices[$propertyType]{$suburbName} / $noOfAdvertisedSales[$propertyType]{$suburbName};
         }
         
         # unbiased stddev = sqrt(n*sum(x^2) - (sum(x))^2 / (n(n-1))
         #print "noas[$propertyType]{$suburbName} = ", $noOfAdvertisedSales[$propertyType]{$suburbName}, "sossp[$propertyType]{$suburbName} = ", $sumOfSquaredSalePrices[$propertyType]{$suburbName}, "\n";
         if (($noOfAdvertisedSales[$propertyType]{$suburbName} > 1) && ($sumOfSquaredSalePrices[$propertyType]{$suburbName} > 0))
         {         
            $salesStdDev[$propertyType]{$suburbName}  = sqrt(($noOfAdvertisedSales[$propertyType]{$suburbName} * $sumOfSquaredSalePrices[$propertyType]{$suburbName} - ($sumOfSalePrices[$propertyType]{$suburbName}**2)) / ($noOfAdvertisedSales[$propertyType]{$suburbName} * ($noOfAdvertisedSales[$propertyType]{$suburbName} - 1)));
          #  print "   salesStdDev[$propertyType]{$suburbName}=", $salesStdDev[$propertyType]{$suburbName}, "\n";
         }
      }
   }

   # now calculate the median advertised sale price for the suburb
   $hashRef = $noOfAdvertisedSales[$ALL];
   foreach (keys %$hashRef)
   {
      $suburbName = $_;
      # loop for all the different categories
      for ($propertyType = 0; $propertyType < $NO_OF_CATEGORIES; $propertyType++)
      {
         $listRef = $advertisedPriceList[$propertyType]{$suburbName};
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
         
         $salesMedian[$propertyType]{$suburbName} = $medianPrice;
      }
   }


   #DebugTools::printList("noOfAdvertised", \@noOfCurrentlyAdvertised);
   #print "noOfAdvertised[0]=", $noOfCurrentlyAdvertised[0], "\n";
   #$hashRef = $noOfCurrentlyAdvertised[0];
   #DebugTools::printHash("noOfAdvertised[0]", $hashRef);
   
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
sub calculateRentalAnalysis

{
   my $this = shift;
   
   my $ALL = 0;
   my $THREE_BY_ANY = 1;
   my $THREE_BY_ONE = 2;
   my $THREE_BY_TWO = 3;
   my $FOUR_BY_ANY = 4;
   my $FOUR_BY_ONE = 5;
   my $FOUR_BY_TWO = 6;
   my $FIVE_BY_ANY = 7;
   my $NO_OF_CATEGORIES = 8;
   
   my $index;
   my $suburbName;   
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
   my $selectResults =  $this->{'rentalResultsList'};
   
   $index = 0;                               
       
       
   #selectResults is a big array of hashes      
   foreach (@$selectResults)
   {   
      $suburbName = $$_{'SuburbName'};
   
      if ($$_{'AdvertisedWeeklyRent'} > 0)
      {
         
         if (!defined $sumOfRentalPrices[$ALL]{$suburbName})
         {
            for ($category = 0; $category < $NO_OF_CATEGORIES; $category++)
            {
               $sumOfRentalPrices[$category]{$suburbName} = 0;
               $sumOfSquaredRentalPrices[$category]{$suburbName} = 0;
               $noOfRentals[$category]{$suburbName} = 0;
               my @newList;
               $advertisedPriceList[$category]{$suburbName} = \@newList;  # initialise a new array
            }
         }
         
         for ($category = 0; $category < $NO_OF_CATEGORIES; $category++)
         {
            # acertain if this category is applicable for this property
            $useThisCategory = 0;
            if ($category == $ALL)
            {
               $useThisCategory = 1;
            }
            else
            {
               if ($$_{'Bedrooms'} == 3)
               {
                  if ($category == $THREE_BY_ANY)
                  {
                     $useThisCategory = 1;               
                  }
                  else
                  {
                     if (($category == $THREE_BY_ONE) && ($$_{'Bathrooms'} == 1))
                     {
                        $useThisCategory = 1;               
                     }
                     else
                     {
                        if (($category == $THREE_BY_TWO) && ($$_{'Bathrooms'} == 2))
                        {
                           $useThisCategory = 1;               
                        }
                     }
                  }
               }
               else
               {
                  if ($$_{'Bedrooms'} == 4)
                  {
                     if ($category == $FOUR_BY_ANY)
                     {
                        $useThisCategory = 1;               
                     }
                     else
                     {
                        if (($category == $FOUR_BY_ONE) && ($$_{'Bathrooms'} == 1))
                        {
                           $useThisCategory = 1;               
                        }
                        else
                        {
                           if (($category == $FOUR_BY_TWO) && ($$_{'Bathrooms'} == 2))
                           {
                              $useThisCategory = 1;               
                           }
                        }
                     }
                  }
                  else
                  {
                     if ($$_{'Bedrooms'} == 5)
                     {
                        if ($category == $FIVE_BY_ANY)
                        {
                           $useThisCategory = 1;               
                        }
                     }  
                  }
               }
            }

         
            if ($useThisCategory)
            {
               # calculate the total of price for calculation of the mean
               $sumOfRentalPrices[$category]{$suburbName} += $$_{'AdvertisedWeeklyRent'};
               
               # calculate the total of squared prices for calculation of the standard deviation
               $sumOfSquaredRentalPrices[$category]{$suburbName} += ($$_{'AdvertisedWeeklyRent'}**2);
              
               # count the number of listings in the suburb
               $noOfRentals[$category]{$suburbName} += 1;
                        
               # record the advertised price in a list for this suburb - the list is used later to calculate the 
               # median advertised price for that suburb
               $listRef = $advertisedPriceList[$category]{$suburbName};
               #print "advertisedPriceList{$suburbName}=", $advertisedPriceList{$suburbName}, "\n";
               push @$listRef, $$_{'AdvertisedWeeklyRent'};
               #$advertisedPriceList{$suburbName} = \@listRef;
               
               #$$advertisedPriceList{$suburbName}[$noOfAdvertisedSales{$suburbName}-1] = $advertisedPrice;      
               #print "advertisedPriceList{$suburbName}[", $noOfAdvertisedSales{$suburbName}-1, "] = $advertisedPrice\n";
               
               # record the lowest-high price listed for this suburb
               if ((!defined $minRentalPrice[$category]{$suburbName}) || ($$_{'AdvertisedWeeklyRent'} < $minRentalPrice[$category]{$suburbName}))
               {
                  $minRentalPrice[$category]{$suburbName} = $$_{'AdvertisedWeeklyRent'};
               }
            
               # record the highest-high price listed for this suburb
               if ((!defined $maxRentalPrice[$category]{$suburbName}) || ($$_{'AdvertisedWeeklyRent'} > $maxRentalPrice[$category]{$suburbName}))
               {
                  $maxRentalPrice[$category]{$suburbName} = $$_{'AdvertisedWeeklyRent'};
               }
               
    #           print "sumOfRentalPrices[$category]{$suburbName}(", $$_{'Bedrooms'}, "x", $$_{'Bathrooms'}, ")=", $sumOfRentalPrices[0]{$suburbName}, "\n";
            }
         }
         
      }
   }
     
   # loop through all VALID results once more to calculate the mean
   $hashRef = $noOfRentals[$ALL];
   foreach (keys %$hashRef)
   {          
      $suburbName = $_;
      # loop for all the different categories
      for ($category = 0; $category < $NO_OF_CATEGORIES; $category++)
      {
         if ((defined $sumOfRentalPrices[$category]{$suburbName}) && ($noOfRentals[$category]{$suburbName} > 0))
         {
            $rentalMean[$category]{$suburbName} = $sumOfRentalPrices[$category]{$suburbName} / $noOfRentals[$category]{$suburbName};
         }      
         # unbiased stddev = sqrt(n*sum(x^2) - (sum(x))^2 / (n(n-1))      
         if (($noOfRentals[$category]{$suburbName} > 1) && ($sumOfSquaredRentalPrices[$category]{$suburbName} > 0))
         {                                                      
            $rentalStdDev[$category]{$suburbName} = sqrt(($noOfRentals[$category]{$suburbName} * $sumOfSquaredRentalPrices[$category]{$suburbName} - ($sumOfRentalPrices[$category]{$suburbName}**2)) / ($noOfRentals[$category]{$suburbName} * ($noOfRentals[$category]{$suburbName} - 1)));                     
         }
      }
   }
   
   # now calculate the median advertised sale price for the suburb
   foreach (keys %$hashRef)
   {
      $suburbName = $_;
      # loop for all the different categories
      for ($category = 0; $category < $NO_OF_CATEGORIES; $category++)
      {
      
         $listRef = $advertisedPriceList[$category]{$suburbName};
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
      
         $rentalMedian[$category]{$suburbName} = $medianPrice;
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

sub calculateYield
{
   my $this = shift;   
   my $noOfSalesListRef = $this->{'noOfSalesCategoryHash'};
   my $noOfRentalsListRef = $this->{'noOfRentalsCategoryHash'};
   my $rentalMedianListRef = $this->{'rentalMedianCategoryHash'};
   my $salesMedianListRef= $this->{'salesMedianCategoryHash'};
   my %medianYield;
   
   $noOfSales = $$noOfSalesListRef[0];
   $salesMedian = $$salesMedianListRef[0];
   $noOfRentals = $$noOfRentalsListRef[0];
   $rentalMedian = $$rentalMedianListRef[0];
   # loop through all the suburbs again to calculate the yield   
   foreach (keys %$noOfSales)
   {               
      
      ($officialSalesMedian{$_}, $officialRentalMedian{$_}) = $this->fetchOfficialMedians($_);
 
      #if (($$noOfRentals{$_} > 0) && ($$noOfSales{$_} > 0))
      if (($$noOfRentals{$_} > 0) && ($$noOfSales{$_} > 0))
      {                         
         #$meanYield{$_} = ($$rentalMean{$_} * 5200) / $$salesMean{$_};
         if ($$salesMedian{$_} > 0)
         {
            $medianYield{$_} = ($$rentalMedian{$_} * 5200) / $$salesMedian{$_};
         }
         else
         {
            $medianYield{$_} = 0;
         }
         #print "$_ ", $$salesMedian{$_}, " ", $$rentalMedian{$_}, " ", $medianYield{$_}, "\n";

      }      
      else
      {         
         $medianYield{$_} = 0;
      }               
   }
 
  
   $this->{'medianYieldHash'} = \%medianYield;
   $this->{'officialSalesMedian'} = \%officialSalesMedian;
   $this->{'officialRentalMedian'} = \%officialRentalMedian;
   
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
   
   return $this->{'medianYieldHash'};
}

# ------------------------------------------------------------------------------------------------- 
# ------------------------------------------------------------------------------------------------- 
# returns the list of hashes of sales data used in the analysis
sub getSalesDataList
{
   my $this = shift;   
   my $sqlClient = $this->{'sqlClient'};   
   
   $salesSelectCommand = "select StreetNumber, Street, SuburbName, AdvertisedPriceLower, AdvertisedPriceUpper, Bedrooms, Bathrooms from MasterPropertyTable where ".$this->{'date14daySearch'}." state='WA' and ".$this->{'suburbSearch'}." ".$this->{'typeSearch'}." ".$this->{'bedroomsSearch'}." ".$this->{'bathroomsSearch'}." order by SuburbName, Street, StreetNumber";
   print "<br/>", "<tt>SALES  :$salesSelectCommand</tt><br/>";
   my @salesResults = $sqlClient->doSQLSelect($salesSelectCommand);
   
   
   return \@salesResults;
}

# ------------------------------------------------------------------------------------------------- 
# returns the list of hashes of rental data used in the analysis
sub getRentalDataList
{
   my $this = shift;   
   
   my $sqlClient = $this->{'sqlClient'};      
   $rentalsSelectCommand = "select DateEntered, LastEncountered, StreetNumber, Street, SuburbName, AdvertisedWeeklyRent, Bedrooms, Bathrooms from WorkingView_AdvertisedRentalProfiles where ".$this->{'rentalsDateSearch'}." state='WA' and ".$this->{'suburbSearch'}." ".$this->{'typeSearch'}." ".$this->{'bedroomsSearch'}." ".$this->{'bathroomsSearch'}." order by SuburbName, DateEntered desc, Street, StreetNumber";
   print "<br/>", "<tt>RENTALS:$rentalsSelectCommand</tt><br/>";

   my @rentalResults = $sqlClient->doSQLSelect($rentalsSelectCommand);
   
   return \@rentalResults;
}

# ------------------------------------------------------------------------------------------------- 
# returns the hashes of official rental medians
sub getOfficialRentalMedianHash
{
   my $this = shift;   
   
   return $this->{'officialRentalMedian'};
}

# ------------------------------------------------------------------------------------------------- 
# returns the hashes of official sales medians
sub getOfficialSalesMedianHash
{
   my $this = shift;   
   
   return $this->{'officialSalesMedian'};
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# performs the query on the database to get selected suburb information
sub fetchOfficialMedians

{
   my $this = shift;
   my $suburbNameUnquoted = shift;
   my $sqlClient = $this->{'sqlClient'};
   my $suburbName = $sqlClient->quote($suburbNameUnquoted);
   my @suburbResults = $sqlClient->doSQLSelect("select MedianPrice, MedianWeeklyRent from SuburbProfiles where SuburbName like $suburbName order by DateEntered desc");

   foreach (@suburbResults)
   {
      $medianPrice = $$_{'MedianPrice'};
      $medianWeeklyRent = $$_{'MedianWeeklyRent'};    
   }
   
   return ($medianPrice, $medianWeeklyRent);
}

# -------------------------------------------------------------------------------------------------
# estimate the purchase costs for a particular property using the current analysis parameters
sub estimatePurchaseCosts

{      
   my $this = shift;
   my $estimatedPrice = shift;
   my $purchaseParametersRef = $this->{'purchaseParametersHash'};
   my %purchaseCosts;

   $purchaseCosts{'purchasePrice'} = $estimatedPrice;

   
   # --- estimate purchase fees ---
   
   $purchaseCosts{'conveyancy'} = 600.00;
   $purchaseCosts{'landTitleSearch'} = 41.00;  # crap?
   $purchaseCosts{'landTaxDept'} = 30.00;      # crap?
   $purchaseCosts{'councilRatesEnquiry'} = 65.00;      # 
   $purchaseCosts{'waterRatesEnquiry'} = 30.00;      # 
   $purchaseCosts{'govtBankCharge'} = 20.00;      # 
   $purchaseCosts{'transferRegistration'} = 105.00;      # 
   
   # worst case, WA
   if ($estimatedPrice < 80001)
   {
      $purchaseCosts{'conveyancyStampDuty'} = $estimatedPrice/100*2;   
   }
   else
   {
      if ($estimatedPrice < 100001)
      {
         $purchaseCosts{'conveyancyStampDuty'} = 1600+($estimatedPrice-80000)/100*3;            
      }
      else
      {
         if ($estimatedPrice < 250001)
         {
            $purchaseCosts{'conveyancyStampDuty'} = 2200+($estimatedPrice-100000)/100*4;                     
         }
         else
         {
            if ($estimatedPrice < 500001)
            {
               $purchaseCosts{'conveyancyStampDuty'} = 8200+($estimatedPrice-250000)/100*5;                     
            }
            else
            {
               $purchaseCosts{'conveyancyStampDuty'} = 20700+($estimatedPrice-500000)/100*5.4;     
            }
         }
      }
   }
   
   $purchaseCosts{'section43Certificate'} = 55.00;      
   $purchaseCosts{'bankChequeFees'} = 13.00;
   $purchaseCosts{'buildingInspection'} = 300.00;      

   $purchaseCosts{'totalPurchaseFees'} = $purchaseCosts{'conveyancy'} +
                        $purchaseCosts{'landTitleSearch'} +
                        $purchaseCosts{'landTaxDept'} +
                        $purchaseCosts{'councilRatesEnquiry'} +
                        $purchaseCosts{'waterRatesEnquiry'} +
                        $purchaseCosts{'govtBankCharge'} +
                        $purchaseCosts{'transferRegistration'} +
                        $purchaseCosts{'conveyancyStampDuty'} +
                        $purchaseCosts{'section43Certificate'} +
                        $purchaseCosts{'bankChequeFees'} +
                        $purchaseCosts{'buildingInspection'};
   return \%purchaseCosts;   
}

# -------------------------------------------------------------------------------------------------
# estimate the mortgage establishment costs for a particular property using the current analysis parameters
sub estimateMortgageCosts

{      
   my $this = shift;
   my $estimatedPrice = shift;
   my $purchaseCostsRef = shift;
   my $purchaseParametersRef = $this->{'purchaseParametersHash'};
   
   # --- estimate mortgage fees ---
                        
   $$purchaseCostsRef{'loanApplicationFee'} = 600.00;
   #### must use actual mortgage costs, rather than estimated price, as the costs are capitalised onto the loan
   $estimatedMortgageStampDuty = $estimatedPrice/100*0.4;   # based on WA state fees only, for investment property
   $$purchaseCostsRef{'mortgageRegistration'} = 75.00;
   $$purchaseCostsRef{'titleSearch'} = 18.00;
   $$purchaseCostsRef{'valuationFee'} = 300.00;
   $$purchaseCostsRef{'lmiFee'} = 0.00;                                 # currently assumes no lenders mortgage insurance
      
   $totalMortgageFees = $$purchaseCostsRef{'loanApplicationFee'} +
                        $$purchaseCostsRef{'mortgageRegistration'} +
                        $$purchaseCostsRef{'titleSearch'} +
                        $$purchaseCostsRef{'valuationFee'} +
                        $$purchaseCostsRef{'lmiFee'};
                        # important STAMP DUTY IS CACLULATED AND ADDED LATER 

   
   # --- calculate loan required and adjust mortgage stamp duty to match---
  
   $stampDutyError = 2; 
   $totalPurchaseFees = $$purchaseCostsRef{'totalPurchaseFees'};
   
   #iterate to calculate the actual mortgage stamp duty (which is included in the mortgage)
   # it's solved using iteration as the total mortgage includes the stamp duty, but the
   # stamp duty depends on the total mortgage
   while ($stampDutyError > 1)
   {
     
      $totalPurchaseCosts = $estimatedPrice + $totalMortgageFees + $estimatedMortgageStampDuty + $totalPurchaseFees;
      #print "ESD: $estimatedMortgageStampDuty  TPC:$totalPurchaseCosts\n";
      $depositRequired = $totalPurchaseCosts * (1 - 0.8);   # 80% LVR
      
      $loanRequired = $estimatedPrice - $depositRequired;
      
      $adjustedMortgageStampDuty = $loanRequired/100*0.4;   # based on WA state fees only, for investment property
      
      # iterate until a local mininim is found (delta is less than one)
      $stampDutyError = abs($adjustedMortgageStampDuty - $estimatedMortgageStampDuty);
      #print "   AMS: $adjustedMortgageStampDuty error:$stampDutyError\n";
      
      if ($stampDutyError > 1)
      {
         $estimatedMortgageStampDuty = $adjustedMortgageStampDuty;
      }
   }
   
   $$purchaseCostsRef{'mortgageStampDuty'} = $adjustedMortgageStampDuty;
   # adjust the total mortgage fees to include the refined stamp duty component
   $$purchaseCostsRef{'totalMortgageFees'} = $totalMortgageFees + $adjustedMortgageStampDuty;  # add mortgage stamp duty to total fees        
   
   $apportionedMortgageFees = $$purchaseCostsRef{'totalMortgageFees'} * 0.20;
   

   $$purchaseCostsRef{'cashRequired'} = 0.00; 
   $$purchaseCostsRef{'depositRequired'} = $depositRequired; 
   $$purchaseCostsRef{'loanRequired'} = $loanRequired;    
   
   return $apportionedMortgageFees;
}

# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# estimate the annual income for a particular property using the current analysis parameters
sub estimateAnnualIncome

{      
   my $this = shift;
   my $estimatedRent = shift;
   my $purchaseParametersRef = $this->{'purchaseParametersHash'};
   my %annualIncome;
   
   # cash deposit has no interest on it
   $occupancyRate = 0.8;    # banks use 0.7
   $annualIncome{'occupancyRate'} = $occupancyRate;
   $annualIncome{'weeklyRent'} = $estimatedRent;
   $annualIncome{'annualIncome'} = $estimatedRent * 52 * $occupancyRate;
   
   # --- estimate mortgage fees ---
   
   return \%annualIncome;   
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# estimate the recurring expenses for a particular property using the current analysis parameters
sub estimateAnnualExpenses
{      
   my $this = shift;
   my $purchaseCostsRef = shift;
   my $annualIncomeRef = shift;
   my $purchaseParametersRef = $this->{'purchaseParametersHash'};
   my %annualExpenses;
   
   # --- calculate the interest on the equity portion used as deposit ---
   $equityRequired = $$purchaseCostsRef{'depositRequired'} - $$purchaseCostsRef{'cashDeposit'}; 
   
   # interest-only - calculate annual interest on the equity component
   $annualExpenses{'equityInterest'} = 0.0675 * $equityRequired;    # assuming 6.75%
   
   # interest-only - calculate annual interest on the mortgage
   $annualExpenses{'mortgageInterest'} = 0.0675 * $$purchaseCostsRef{'loanRequired'};
   
   $annualExpenses{'mortgageAdminFees'} = 300.00;
   
   $annualExpenses{'totalAnnualMortgageCosts'} = $annualExpenses{'equityInterest'} +
                                                 $annualExpenses{'mortgageInterest'} +
                                                 $annualExpenses{'mortgageAdminFees'};                        
                         
   # --- estimate management fees ---
                         
   $annualExpenses{'rentalCommission'} = 0.1;                        
   $annualExpenses{'initialLettingFee'} = $$annualIncomeRef{'weeklyRent'} / 2;                      
   $annualExpenses{'reLettingFee'} = $$annualIncomeRef{'weeklyRent'};                      
   $annualExpenses{'avgLengthOfStay'} = 9;
   
   $annualExpenses{'totalManagementFees'} = $annualExpenses{'rentalCommission'} * $$annualIncomeRef{'weeklyRent'} * 52 * $$annualIncomeRef{'occupancyRate'} +
                                            $annualExpenses{'initialLettingFee'} +
                                            $annualExpenses{'avgLengthOfStay'}/12 * $annualExpenses{'reLettingFee'};
                                       
   # --- estimate maintenance & ownership costs ---
   
   # **** THIS IS ALL CRAP ********
   $annualExpenses{'maintenance'} = 500.00;
   $annualExpenses{'strataFees'} = 360.00;
   $annualExpenses{'propertyInsurance'} = 120.00;
   $annualExpenses{'councilRates'} = 700.00;    # related to land area and suburb
   $annualExpenses{'waterRates'} = 700.00;      # related to bathrooms and state?
   
   # this is a rough guess at land tax
   $unimprovedLandValue = $$purchaseCostsRef{'purchasePrice'} * 0.5;
   
   # aggregate land tax
   if ($unimprovedLandValue < 100001)
   {
      $annualExpenses{'landTax'} = 0;  
   }
   else
   {
      if ($unimprovedLandValue < 220001)
      {
         $annualExpenses{'landTax'} = 150+($unimprovedLandValue-100000)*0.15;            
      }
      else
      {
         if ($unimprovedLandValue < 570001)
         {
            $annualExpenses{'landTax'} = 330+($unimprovedLandValue-220000)*0.45;            
         }
         else
         {
            if ($unimprovedLandValue < 2000001)
            {
               $annualExpenses{'landTax'} = 1905+($unimprovedLandValue-570000)*1.76;            
            }
            else
            {
               if ($unimprovedLandValue < 5000001)
               {
                  $annualExpenses{'landTax'} = 27073+($unimprovedLandValue-2000000)*2.30;            
               }
               else
               {
                  $annualExpenses{'landTax'} = 96073+($unimprovedLandValue-5000000)*2.50;          
               }
            }
         }
      }
   }
   
   $annualExpenses{'totalOwnershipCosts'} = $annualExpenses{'maintenance'} + 
                                       $annualExpenses{'strataFees'} +
                                       $annualExpenses{'propertyInsurance'} +
                                       $annualExpenses{'councilRates'} +
                                       $annualExpenses{'waterRates'} +
                                       $annualExpenses{'landTax'};
                                       
   $annualExpenses{'annualExpenses'} = $annualExpenses{'totalAnnualMortgageCosts'} + 
                                       $annualExpenses{'totalManagementFees'} + 
                                       $annualExpenses{'totalOwnershipCosts'};
                                       
   return \%annualExpenses;   
}

# -------------------------------------------------------------------------------------------------
# estimate the cost of ownership for a particular property using the current analysis parameters
# as in cost per week
sub estimateWeeklyCashflow
{      
   my $this = shift;
   my $estimatedPrice = shift;
   my $estimatedRent = shift;
   
   $purchaseCosts = $this->estimatePurchaseCosts($estimatedPrice);
   $apportionedMortgageFees = $this->estimateMortgageCosts($estimatedPrice, $purchaseCosts);
   
   $annualIncome = $this->estimateAnnualIncome($estimatedRent);
   $annualExpenses = $this->estimateAnnualExpenses($purchaseCosts, $annualIncome);
   #$depreciation = $this->estimateAnnualDepreciation($purchaseCosts);
   $depreciation = 0.00;
   # calculate the gross annual income before depreciation and apportioned expenses 
#if ($estimatedPrice == 229958)
#{
#   print "annualIncome = ", $$annualIncome{'annualIncome'}, " annualExpenses ] ", $$annualExpenses{'annualExpenses'}, " depreciation=", $$depreciation{'annualDepreciation'}, "apportionedMEF=", $apportionedMortgageFees, "\n";
#}
   $taxableIncome = $$annualIncome{'annualIncome'} - $$annualExpenses{'annualExpenses'} - $$depreciation{'annualDepreciation'} - $apportionedMortgageFees;
   
   if ($taxableIncome < 0)
   {
      # making a loss (negatively geared) - calulate the tax refund      
      $taxRefund = $taxableIncome * 0.485;    # assuming highest tax bracket for now  - this is possibly crap
      # calculate the annual cash outlay which excludes depreciation and apportioned fees and includes the tax refund as income
      # if this is positive the property is cashflow positive
      $annualCashOutlay = $$annualIncome{'annualIncome'} - $$annualExpenses{'annualExpenses'} - $taxRefund;
#if ($estimatedPrice == 229958)
#{
#   print "taxableIncome = $taxableIncome taxRefund = $taxRefund annualCashOutlay=$annualCashOutlay\n";
#}
   }
   else
   {
      # this property makes a profit (positively geared) - calculate the tax owed
      $taxOwed = $taxableIncome * 0.485;     # assuming highest tax bracket for now - this is possibly crap
      
      # calculate the annual cash outlay which excludes depreciation and apportioned fees and includes the tax refund as income
      # if this is positive the property is cashflow positive
      $annualCashOutlay = $$annualIncome{'annualIncome'} - $$annualExpenses{'annualExpenses'} + $taxOwed;    
   }
#if ($estimatedPrice == 229958)
#{
#DebugTools::printHash("purchaseCosts", $purchaseCosts);
#DebugTools::printHash("annualIncome", $annualIncome);
#DebugTools::printHash("annualExpenses", $annualExpenses);
#}
   my %infoHash;
   $infoHash{'purchaseCosts'} = $$purchaseCosts{'totalPurchaseFees'};
   $infoHash{'mortgageCosts'} = $$purchaseCosts{'totalMortgageFees'};
   $infoHash{'annualIncome'} = $$annualIncome{'annualIncome'};
   $infoHash{'annualExpenses'} = $$annualExpenses{'annualExpenses'};
   $infoHash{'taxRefund'} = $taxRefund;
   $infoHash{'weeklyCashflow'} = $annualCashOutlay / 52;
   
   return \%infoHash;   
}

# -------------------------------------------------------------------------------------------------

