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
      bedroomsSearch => $DEFAULT_BEDROOMS_CONSTRAINT      
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
      $this->{'suburbSearch'} = "SuburbName like '%$suburbParam%' and ";      
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
      if ($typeParam == 'house')
      {
         $this->{'typeSearch'} = "Type like '%house%'";         
      }
      elsif ($typeParam == 'unit') 
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
   my @salesResults = $sqlClient->doSQLSelect("select StreetNumber, Street, SuburbName, AdvertisedPriceLower, AdvertisedPriceUpper, Bedrooms, Bathrooms from MasterPropertyTable where ".$this->{'suburbSearch'}." ".$this->{'typeSearch'}." ".$this->{'bedroomsSearch'}." ".$this->{'bathroomsSearch'}." order by SuburbName, Street, StreetNumber, Bedrooms, Bathrooms");
   my @rentalResults = $sqlClient->doSQLSelect("select StreetNumber, Street, SuburbName, AdvertisedWeeklyRent, Bedrooms, Bathrooms from WorkingView_AdvertisedRentalProfiles where ".$this->{'suburbSearch'}." ".$this->{'typeSearch'}." ".$this->{'bedroomsSearch'}." ".$this->{'bathroomsSearch'}." order by SuburbName, Bedrooms, Bathrooms");
   
   $this->{'salesResultsList'} = \@salesResults;
   $this->{'rentalResultsList'} = \@rentalResults;
}

# -------------------------------------------------------------------------------------------------
# Fetches data from the database using the search constraints and calculates analysis parameters
sub calculateSalesAnalysis

{
   my $this = shift;
    
   my $index;
   my $suburbName;
   my $highPrice;
   my %sumOfSalePrices;
   my %sumOfSquaredSalePrices;
   my %minSalePrice;
   my %maxSalePrice;
   my %noOfAdvertisedSales;
   my %salesMean;
   my %salesStdDev;
   my %salesStdDevPercent;  
   my %salesMedian;
   
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
         # calculate the total of price for calculation of the mean
         if (defined $sumOfSalePrices{$suburbName})
         {
            $sumOfSalePrices{$suburbName} += $advertisedPrice;
         }
         else
         {
            $sumOfSalePrices{$suburbName} = $advertisedPrice;
         }
            
         # calculate the total of squared prices for calculation of the standard deviation
         if (defined $sumOfSquaredSalePrices{$suburbName})
         {
            $sumOfSquaredSalePrices{$suburbName} += ($advertisedPrice**2);
         }
         else
         {
            $sumOfSquaredSalePrices{$suburbName} = ($advertisedPrice**2);            
         }         
        
        
         # count the number of listings in the suburb
         if (defined $noOfAdvertisedSales{$suburbName})
         {        
            $noOfAdvertisedSales{$suburbName} += 1;
         }
         else
         {
            $noOfAdvertisedSales{$suburbName} = 1;
            my @newList;
            $advertisedPriceList{$suburbName} = \@newList;  # initialise a new array
         }
             
         # record the advertised price in a list for this suburb - the list is used later to calculate the 
         # median advertised price for that suburb
         $listRef = $advertisedPriceList{$suburbName};
         #print "advertisedPriceList{$suburbName}=", $advertisedPriceList{$suburbName}, "\n";
         push @$listRef, $advertisedPrice;
         #$advertisedPriceList{$suburbName} = \@listRef;
         
         #$$advertisedPriceList{$suburbName}[$noOfAdvertisedSales{$suburbName}-1] = $advertisedPrice;      
         #print "advertisedPriceList{$suburbName}[", $noOfAdvertisedSales{$suburbName}-1, "] = $advertisedPrice\n";
   
         # record the lowest-high price listed for this suburb
         if ((!defined $minSalePrice{$suburbName}) || ($advertisedPrice < $minSalePrice{$suburbName}))
         {
            $minSalePrice{$suburbName} = $advertisedPrice;
         }
      
         # record the highest-high price listed for this suburb
         if ((!defined $maxSalePrice{$suburbName}) || ($advertisedPrice > $maxSalePrice{$suburbName}))
         {
            $maxSalePrice{$suburbName} = $advertisedPrice;
         }
      }
   
   }         
   
   # loop through all the results once more to calculate the mean and stddev (couldn't do this
   # until the number of listings was known)
   # the keys of noOfSales is the suburblist
   foreach (keys %noOfAdvertisedSales)
   {            
      if (defined $sumOfSalePrices{$_} && ($noOfAdvertisedSales{$_} > 0))
      {
         $salesMean{$_} = $sumOfSalePrices{$_} / $noOfAdvertisedSales{$_};
      }
      
      # unbiased stddev = sqrt(n*sum(x^2) - (sum(x))^2 / (n(n-1))
      if (($noOfAdvertisedSales{$_} > 1) && ($sumOfSquaredSalePrices{$_} > 0))
      {         
         $salesStdDev{$_}  = sqrt(($noOfAdvertisedSales{$_} * $sumOfSquaredSalePrices{$_} - ($sumOfSalePrices{$_}**2)) / ($noOfAdvertisedSales{$_} * ($noOfAdvertisedSales{$_} - 1)));                                                 
      }                           
   }

   # now calculate the median advertised sale price for the suburb
   foreach (keys %noOfAdvertisedSales)
   {
      $listRef = $advertisedPriceList{$_};
      #print "listRef = $listRef\n";
      @priceList = sort @$listRef;
      
      $listLength = @priceList;
      #print "listLength{$_} = $listLength (";
      if (($listLength % 2) == 0)
      {
         # if the list length is even...find the middle pair of numbers and take the centre of those
         $medianLower = $priceList[($listLength / 2)-1];
         $medianUpper = $priceList[$listLength / 2];
#print "lower=$medianLower, upper=$medianUpper\n";
         $medianPrice = $medianLower + ($medianUpper - $medianLower) / 2;
      }
      else
      {
         # the list length is odd, so the median value is the one in the middle
         $medianPrice = $priceList[$listLength / 2];
      }
      
      $salesMedian{$_} = $medianPrice;
#     print ") median = \$",  $salesMedian{$suburbName}, "\n";

   }
   
   $this->{'noOfSalesHash'} = \%noOfAdvertisedSales;
   $this->{'minSalePriceHash'} = \%minSalePrice;
   $this->{'maxSalePriceHash'} = \%maxSalePrice;
   $this->{'salesMeanHash'} = \%salesMean;
   $this->{'salesMedianHash'} = \%salesMedian;
   $this->{'salesStdDevHash'} = \%salesStdDev;      
}

# -------------------------------------------------------------------------------------------------

# Fetches data from the database using the search constraints and calculates analysis parameters
sub calculateRentalAnalysis

{
   my $this = shift;
      
   my $index;
   my $suburbName;   
   my %sumOfRentalPrices;
   my %sumOfSquaredRentalPrices;
   my %minRentalPrice;
   my %maxRentalPrice;
   my %noOfRentals;
   my %rentalMean;
   my %rentalStdDev;
   my %rentalStdDevPercent;  
   my %rentalMedian;  

   
   my $sqlClient = $this->{'sqlClient'};
   my $selectResults =  $this->{'rentalResultsList'};
   
   $index = 0;                               
       
       
   #selectResults is a big array of hashes      
   foreach (@$selectResults)
   {   
      $suburbName = $$_{'SuburbName'};
   
      if ($$_{'AdvertisedWeeklyRent'} > 0)
      {
         # calculate the total of price for calculation of the mean
         if (defined $sumOfRentalPrices{$suburbName})
         {
            $sumOfRentalPrices{$suburbName} += $$_{'AdvertisedWeeklyRent'};
         }
         else
         {
            $sumOfRentalPrices{$suburbName} = $$_{'AdvertisedWeeklyRent'};
         }
         
         # calculate the total of squared prices for calculation of the standard deviation
         if (defined $sumOfSquaredRentalPrices{$suburbName})
         {
            $sumOfSquaredRentalPrices{$suburbName} += ($$_{'AdvertisedWeeklyRent'}**2);
         }
         else
         {
            $sumOfSquaredRentalPrices{$suburbName} = ($$_{'AdvertisedWeeklyRent'}**2);
         }
      
     
         # count the number of listings in the suburb
         if (defined $noOfRentals{$suburbName})
         {         
            $noOfRentals{$suburbName} += 1;
         }
         else
         {
            $noOfRentals{$suburbName} = 1;
            my @newList;
            $advertisedPriceList{$suburbName} = \@newList;  # initialise a new array
         }
                  
           # record the advertised price in a list for this suburb - the list is used later to calculate the 
         # median advertised price for that suburb
         $listRef = $advertisedPriceList{$suburbName};
         #print "advertisedPriceList{$suburbName}=", $advertisedPriceList{$suburbName}, "\n";
         push @$listRef, $$_{'AdvertisedWeeklyRent'};
         #$advertisedPriceList{$suburbName} = \@listRef;
         
         #$$advertisedPriceList{$suburbName}[$noOfAdvertisedSales{$suburbName}-1] = $advertisedPrice;      
         #print "advertisedPriceList{$suburbName}[", $noOfAdvertisedSales{$suburbName}-1, "] = $advertisedPrice\n";
         
         # record the lowest-high price listed for this suburb
         if ((!defined $minRentalPrice{$suburbName}) || ($$_{'AdvertisedWeeklyRent'} < $minRentalPrice{$suburbName}))
         {
            $minRentalPrice{$suburbName} = $$_{'AdvertisedWeeklyRent'};
         }
      
         # record the highest-high price listed for this suburb
         if ((!defined $maxRentalPrice{$suburbName}) || ($$_{'AdvertisedWeeklyRent'} > $maxRentalPrice{$suburbName}))
         {
            $maxRentalPrice{$suburbName} = $$_{'AdvertisedWeeklyRent'};
         }
      }
   }
     
   # loop through all VALID results once more to calculate the mean
   foreach (keys %noOfRentals)
   {          
      if ((defined $sumOfRentalPrices{$_}) && ($noOfRentals{$_} > 0))
      {
         $rentalMean{$_} = $sumOfRentalPrices{$_} / $noOfRentals{$_};
      }      
      # unbiased stddev = sqrt(n*sum(x^2) - (sum(x))^2 / (n(n-1))      
      if (($noOfRentals{$_} > 1) && ($sumOfSquaredRentalPrices{$_} > 0))
      {                                                      
         $rentalStdDev{$_} = sqrt(($noOfRentals{$_} * $sumOfSquaredRentalPrices{$_} - ($sumOfRentalPrices{$_}**2)) / ($noOfRentals{$_} * ($noOfRentals{$_} - 1)));                     
      }                     
   }
   
   # now calculate the median advertised sale price for the suburb
   foreach (keys %noOfRentals)
   {
      $listRef = $advertisedPriceList{$_};
      #print "listRef = $listRef\n";
      @priceList = sort @$listRef;
      
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
      
      $rentalMedian{$_} = $medianPrice;
   }
   
   $this->{'noOfRentalsHash'} = \%noOfRentals;
   $this->{'minRentalPriceHash'} = \%minRentalPrice;
   $this->{'maxRentalPriceHash'} = \%maxRentalPrice;
   $this->{'rentalMeanHash'} = \%rentalMean;
   $this->{'rentalMedianHash'} = \%rentalMedian;
   $this->{'rentalStdDevHash'} = \%rentalStdDev;   
}

# -------------------------------------------------------------------------------------------------

sub calculateYield
{
   my $this = shift;   
   my $noOfSales = $this->{'noOfSalesHash'};
   my $noOfRentals = $this->{'noOfRentalsHash'};
   my $rentalMedian = $this->{'rentalMedianHash'};
   my $salesMedian= $this->{'salesMedianHash'};
   my %medianYield;
   
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
   
   return $this->{'noOfSalesHash'};
}
# ------------------------------------------------------------------------------------------------- 
# returns the hash of sales minimum 
sub getSalesMinHash
{
   my $this = shift;   
   
   return $this->{'minSalePriceHash'};
}

# ------------------------------------------------------------------------------------------------- 
# returns the hash of sales maximum 
sub getSalesMaxHash
{
   my $this = shift;   
   
   return $this->{'maxSalePriceHash'};
}

# ------------------------------------------------------------------------------------------------- 
# returns the hash of sales mean 
sub getSalesMeanHash
{
   my $this = shift;   
   
   return $this->{'salesMeanHash'};
}

# ------------------------------------------------------------------------------------------------- 
# returns the hash of sales median 
sub getSalesMedianHash
{
   my $this = shift;   
   
   return $this->{'salesMedianHash'};
}

# ------------------------------------------------------------------------------------------------- 
# returns the hash of sales standard deviation 
sub getSalesStdDevHash
{
   my $this = shift;   
   
   return $this->{'salesStdDevHash'};
}


# ------------------------------------------------------------------------------------------------- 
# returns the hash of number of retnals
sub getNoOfRentalsHash
{
   my $this = shift;   
   
   return $this->{'noOfRentalsHash'};
}


# ------------------------------------------------------------------------------------------------- 
# returns the hash of rental minimum 
sub getRentalMinHash
{
   my $this = shift;   
   
   return $this->{'minRentalPriceHash'};
}

# ------------------------------------------------------------------------------------------------- 
# returns the hash of rental maximum 
sub getRentalMaxHash
{
   my $this = shift;   
   
   return $this->{'maxRentalPriceHash'};
}

# ------------------------------------------------------------------------------------------------- 
# returns the hash of rental mean 
sub getRentalMeanHash
{
   my $this = shift;   
   
   return $this->{'rentalMeanHash'};
}


# ------------------------------------------------------------------------------------------------- 
# returns the hash of rental median 
sub getRentalMedianHash
{
   my $this = shift;   
   
   return $this->{'rentalMedianHash'};
}

# ------------------------------------------------------------------------------------------------- 
# returns the hash of rental standard deviations 
sub getRentalStdDevHash
{
   my $this = shift;   
   
   return $this->{'rentalStdDevHash'};
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
   
   return $this->{'salesResultsList'};
}

# ------------------------------------------------------------------------------------------------- 
# returns the list of hashes of rental data used in the analysis
sub getRentalDataList
{
   my $this = shift;   
   
   return $this->{'rentalResultsList'};
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
   
   # cash deposit has no interest on it
   $cashDeposit = $$purchaseParametersRef{'cashDeposit'};
   
   # --- estimate mortgage fees ---
                        
   $purchaseCosts{'loanApplicationFee'} = 600.00;
   #### shoud use actual mortgage costs, rather than estimated price, as the costs are capitalised ointo the loan
   $estimatedMortgateStampDuty = $estimatedPrice/100*0.4;   # based on WA state fees only, for investment property
   $purchaseCosts{'mortgateRegistration'} = 75.00;
   $purchaseCosts{'titleSearch'} = 18.00;
   $purchaseCosts{'valuationFee'} = 300.00;
   $purchaseCosts{'lmiFee'} = 0.00;                                 # currently assumes no lenders mortgage insurance
      
   $purchaseCosts{'totalMortgageFees'} = $purchaseCosts{'loanApplicationFee'} +
                        $purchaseCosts{'mortgateRegistration'} +
                        $purchaseCosts{'titleSearch'} +
                        $purchaseCosts{'valuationFee'} +
                        $purchaseCosts{'lmiFee'};
                        # important STAMP DUTY IS CACLULATED AND ADDED LATER 
                        
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

   $purchaseCosts{'totalPurchaseFees'} = $purhcaseCosts{'conveyancy'} +
                        $purhcaseCosts{'landTitleSearch'} +
                        $purhcaseCosts{'landTaxDept'} +
                        $purhcaseCosts{'councilRatesEnquiry'} +
                        $purhcaseCosts{'waterRatesEnquiry'} +
                        $purhcaseCosts{'govtBankCharge'} +
                        $purhcaseCosts{'transferRegistration'} +
                        $purhcaseCosts{'conveyancyStampDuty'} +
                        $purhcaseCosts{'section43Certificate'} +
                        $purhcaseCosts{'bankChequeFees'} +
                        $purhcaseCosts{'buildingInspection'};

   # --- calculate loan required and adjust mortgage stamp duty to match---
  
   $stampDutyError = 2; 
   $totalMortgageFees = $purchaseCosts{'totalMortgageFees'};
   $totalPurchaseFees = $purchaseCosts{'totalPurchaseFees'};
   
   #iterate to calculate the actual mortgage stamp duty (which is included in the mortgage)
   while ($stampDutyError > 1 )
   {
     
      $totalPurchaseCosts = $estimatedPrice + $totalMortgageFees + $estimatedMortgageStampDuty + $totalPurchaseFees;
      
      $depositRequired = $totalPurchaseCosts * (1 - 0.8);   # 80% LVR
      
      $loanRequired = $estimatedPrice - $depositRequired;
      
      $adjustedMortgageStampDuty = $loanRequired/100*0.4;   # based on WA state fees only, for investment property
      
      $stampDutyError = abs($adjustedMortgageStampDuty - $estimatedMortgageStampDuty);
      if ($stampDutyError > 1)
      {
         $estimatedMortageStampDuty = $adjustedMortgageStampDuty;
      }
   }
   
   
   $purchaseCosts{'mortgageStampDuty'} = $estimatedMortgageStampDuty;
   # adjust the total mortgage fees to include the refined stamp duty component
   $purchaseCosts{'totalMortgageFees'} += $estimatedMortgageStampDuty;  # add mortgage stamp duty to total fees
   
   $purchaseCosts{'totalPurchasePrice'} = $totalPurchaseCosts;
   $purchaseCosts{'despositRequired'} = $depositRequired; 
   $purchaseCosts{'loanRequired'} = $loanRequired;    
   
   return \%purchaseCosts;   
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
   $vacancyRate = 0.8;    # banks use 0.7
   $annualIncome{'annualIncome'} = $estimatedRent * 52 * $vacancyRate;
   
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
   my $estimatedRent;
   my $purchaseParametersRef = $this->{'purchaseParametersHash'};
   my %annualExpenses;
   
   # --- calculate the interest on the equity portion used as deposit ---
   $equityRequired = $$purchaseCostsRef{'depositRequired'} - $$purchaseCostsRef{'cashDeposit'} 
   
   # interest-only - calculate annual interest on the equity component
   $annualExpenses{'equityInterest'} = $$purchaseParametersRef{'equityInterestRate'} * $equityRequired;
   
   # interest-only - calculate annual interest on the mortgage
   $annualExpenses{'mortgageInterest'} = $$purchaseParametersRef{'interestRate'} * $$purchaseCostsRef{'loanRequired'};
   
   $annualExpenses{'mortgageAdminFees'} = 300.00;
   
   $annualExpenses{'totalAnnualMortgageCosts'} = $annualExpenses{'equityInterest'} +
                                                 $annualExpenses{'mortgageInterets'} +
                                                 $annualExpenses{'mortgageAdminFees'};                        
                         
   # --- estimate management fees ---
                         
   $annualExpenses{'rentalCommission'} = 0.1;                        
   $annualExpenses{'initialLettingFee'} = $estimatedRent / 2;                      
   $annualExpenses{'reLettingFee'} = $estimatedRent;                      
   $annualExpenses{'avgLengthOfStay'} = 9;
   
   $annualExpenses{'totalManagementFees'} = $annualExpenses{'rentalCommission'} * $estimatedRent * 52 +
                                            $annualExpenses{'initalLettingFee'} +
                                            $annualExpenses{'avgLengthOfStay'}/12 * $annualExpenses{'reLettingFee'};
                                       
   # --- estimate maintenance & ownership costs ---
   $annualExpenses{'maintenance'} = 500.00;
   $annualExpenses{'strataFees'} = 360.00;
   $annualExpenses{'propertyInsurance'} = 120.00;
   $annualExpenses{'councilRates'} = 700.00;    # related to land area and suburb
   $annualExpenses{'waterRates'} = 700.00;      # related to bathrooms and state?
   
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
                                       
   $annualExpenses{'annualExpenses'} = $annualExpenses{'totalMortgageCosts'} + 
                                       $annualExpenses{'totalManagementFees'} + 
                                       $annualExpenses{'totalOwnershipCosts'};
                                       
   return \%annualExpenses;   
}

# -------------------------------------------------------------------------------------------------
# estimate the cost of ownership for a particular property using the current analysis parameters
sub estimateCostOfOwnership
{      
   my $this = shift;
   my $estimatedRent = shift;
   
   $purchaseCosts = $this->estimatePurchaseCosts($estimatedPrice);
   $recurringIncome = $this->estimateAnnualIncome($estimatedRent);
   $purchaseCosts = $this->estimateAnnualExpenses($purchaseCosts);
   $deductions = $this->estimateDeductions($purchaseCosts);
   
   $grossIncome = $$annualIncome{'annualIncome'} - $$annualExpenses{'annualExpenses'};
   # minus depreciation minus apportioned(over 5 years?) purchase costs
   
     
   return \%annualExpenses;   
}

