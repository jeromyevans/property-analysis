#!/usr/bin/perl
# 16 June 2004
# Jeromy Evans
#
# Provides functions for performing analysis of the property database
#
# Started: 16 June 2004
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
   my @salesResults = $sqlClient->doSQLSelect("select StreetNumber, Street, SuburbName, AdvertisedPriceLower, AdvertisedPriceUpper, Bedrooms, Bathrooms from AdvertisedSaleProfiles where ".$this->{'suburbSearch'}." ".$this->{'typeSearch'}." ".$this->{'bedroomsSearch'}." ".$this->{'bathroomsSearch'}." order by SuburbName, Bedrooms, Bathrooms");
   my @rentalResults = $sqlClient->doSQLSelect("select StreetNumber, Street, SuburbName, AdvertisedWeeklyRent, Bedrooms, Bathrooms from AdvertisedRentalProfiles where ".$this->{'suburbSearch'}." ".$this->{'typeSearch'}." ".$this->{'bedroomsSearch'}." ".$this->{'bathroomsSearch'}." order by SuburbName, Bedrooms, Bathrooms");
   
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
   my %noOfSales;
   my %salesMean;
   my %salesStdDev;
   my %salesStdDevPercent;  
             
   $index = 0;                               
        
   my $sqlClient = $this->{'sqlClient'};
   my $selectResults =  $this->{'salesResultsList'};
            
   #selectResults is a big array of hashes      
   foreach (@$selectResults)
   {
      $suburbName = $$_{'SuburbName'};
      $suburbName =~ tr/[A-Z]/[a-z]/;
   
      # make sure the upper or lower value is defined
      if (($$_{'AdvertisedPriceUpper'} > 0) || ($$_{'AdvertisedPriceLower'} > 0))
      {            
         # use the max of the two prices (sometimes only the lower is defined)
         if (defined $$_{'AdvertisedPriceUpper'} && ($$_{'AdvertisedPriceUpper'}) > 0)
         {
            $highPrice = $$_{'AdvertisedPriceUpper'};
         }
         else
         {
            $highPrice = $$_{'AdvertisedPriceLower'};  
         }              
         
         # calculate the total of price for calculation of the mean
         if (defined $sumOfSalePrices{$suburbName})
         {
            $sumOfSalePrices{$suburbName} += $highPrice;
         }
         else
         {
            $sumOfSalePrices{$suburbName} = $highPrice;
         }
            
         # calculate the total of squared prices for calculation of the standard deviation
         if (defined $sumOfSquaredSalePrices{$suburbName})
         {
            $sumOfSquaredSalePrices{$suburbName} += ($highPrice**2);
         }
         else
         {
            $sumOfSquaredSalePrices{$suburbName} = ($highPrice**2);            
         }         
        
         # count the number of listings in the suburb
         if (defined $noOfSales{$suburbName})
         {         
            $noOfSales{$suburbName} += 1;
         }
         else
         {
            $noOfSales{$suburbName} = 1;
         }
                  
         # record the lowest-high price listed for this suburb
         if ((!defined $minSalePrice{$suburbName}) || ($highPrice < $minSalePrice{$suburbName}))
         {
            $minSalePrice{$suburbName} = $highPrice;
         }
      
         # record the highest-high price listed for this suburb
         if ((!defined $maxSalePrice{$suburbName}) || ($highPrice > $maxSalePrice{$suburbName}))
         {
            $maxSalePrice{$suburbName} = $highPrice;
         }
      }
   }         
   
   # loop through all the results once more to calculate the mean and stddev (couldn't do this
   # until the number of listings was known)
   foreach (keys %noOfSales)
   {            
      if (defined $sumOfSalePrices{$_} && ($noOfSales{$_} > 0))
      {
         $salesMean{$_} = $sumOfSalePrices{$_} / $noOfSales{$_};
      }
      
      # unbiased stddev = sqrt(n*sum(x^2) - (sum(x))^2 / (n(n-1))
      if (($noOfSales{$_} > 1) && ($sumOfSquaredSalePrices{$_} > 0))
      {         
         $salesStdDev{$_}  = sqrt(($noOfSales{$_} * $sumOfSquaredSalePrices{$_} - ($sumOfSalePrices{$_}**2)) / ($noOfSales{$_} * ($noOfSales{$_} - 1)));                                                 
      }                           
   }
      
   $this->{'noOfSalesHash'} = \%noOfSales;
   $this->{'minSalePriceHash'} = \%minSalePrice;
   $this->{'maxSalePriceHash'} = \%maxSalePrice;
   $this->{'salesMeanHash'} = \%salesMean;
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
                      
   my $sqlClient = $this->{'sqlClient'};
   my $selectResults =  $this->{'rentalResultsList'};
   
   $index = 0;                               
       
       
   #selectResults is a big array of hashes      
   foreach (@$selectResults)
   {
   
      $suburbName = $$_{'SuburbName'};
      $suburbName =~ tr/[A-Z]/[a-z]/;                       
   
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
         }
                  
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
         
   $this->{'noOfRentalsHash'} = \%noOfRentals;
   $this->{'minRentalPriceHash'} = \%minRentalPrice;
   $this->{'maxRentalPriceHash'} = \%maxRentalPrice;
   $this->{'rentalMeanHash'} = \%rentalMean;
   $this->{'rentalStdDevHash'} = \%rentalStdDev;   
}

# -------------------------------------------------------------------------------------------------

sub calculateYield
{
   my $this = shift;   
   my $noOfSales = $this->{'noOfSalesHash'};
   my $noOfRentals = $this->{'noOfRentalsHash'};
   my $rentalMean = $this->{'rentalMeanHash'};
   my $salesMean= $this->{'salesMeanHash'};
   my %meanYield;
   
   # loop through all the suburbs again to calculate the yield   
   foreach (keys %$noOfSales)
   {               
      
      ($officialSalesMedian{$_}, $officialRentalMedian{$_}) = $this->fetchOfficialMeans($_);
                 
      #if (($$noOfRentals{$_} > 0) && ($$noOfSales{$_} > 0))
      if (($$noOfRentals{$_} > 0) && ($$noOfSales{$_} > 0))
      {                         
         #$meanYield{$_} = ($$rentalMean{$_} * 5200) / $$salesMean{$_};
         if ($officialSalesMedian{$_} > 0)
         {
            $meanYield{$_} = ($officialRentalMedian{$_} * 5200) / $officialSalesMedian{$_};
         }
         else
         {
            $meanYield{$_} = 0;
         }
      }      
      else
      {         
         $meanYield{$_} = 0;
      }               
   }
   
   $this->{'meanYieldHash'} = \%meanYield;
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
# returns the hash of rental standard deviations 
sub getRentalStdDevHash
{
   my $this = shift;   
   
   return $this->{'rentalStdDevHash'};
}

# -------------------------------------------------------------------------------------------------
# ------------------------------------------------------------------------------------------------- 
# returns the hash of yeild mean 
sub getMeanYieldHash
{
   my $this = shift;   
   
   return $this->{'meanYieldHash'};
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
sub fetchOfficialMeans

{
   my $this = shift;
   my $suburbNameUnquoted = shift;
   my $sqlClient = $this->{'sqlClient'};
   my $suburbName = $sqlClient->quote($suburbNameUnquoted);
   my @suburbResults = $sqlClient->doSQLSelect("select MedianPrice, MedianWeeklyRent from SuburbProfiles where SuburbName like $suburbName");

   foreach (@suburbResults)
   {
      $medianPrice = $$_{'MedianPrice'};
      $medianWeeklyRent = $$_{'MedianWeeklyRent'};    
   }
   
   return ($medianPrice, $medianWeeklyRent);
}

