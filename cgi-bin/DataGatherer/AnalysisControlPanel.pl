#!/usr/bin/perl
# Written by Jeromy Evans
# Started 22 May 2004
# 
# Description:
#   Provides controls for performing analysis of the PropertyData
#
# CONVENTIONS
# _ indicates a private variable or method
#
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#

#
use PrintLogger;
use CGI qw(:standard escape_html);
use HTTPClient;
use SQLClient;
use SuburbProfiles;
use DebugTools;
use AdvertisedPropertyProfiles;
use AnalysisTools;
use HTMLTemplate;
#use URI::Escape::uri_escape;
use URI;

# instance of the analysis tools object
my $analysisTools;
my $suburbConstraintSet;

# -------------------------------------------------------------------------------------------------
# commify - inserts commas into a number - directly out of Perl Cookbook 2.17
sub commify {
    my $text = reverse $_[0];
    $text =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
    return scalar reverse $text;
}

# -------------------------------------------------------------------------------------------------

my $sqlClient;
my $advertisedSaleProfiles;
my $advertisedRentalProfiles;
my $suburbProfiles;
my $orderBy;

# -------------------------------------------------------------------------------------------------
# The following are set by getBedrooms/Bathrooms/Type 
my $typeDescription;
my $bedroomsDescription;
my $bathroomsDescription;
my $typeSearch;
my $bedroomsSearch;
my $bathroomsSearch;

# ------------------------------------------------------------------------------------------------
# This hash defines valid keys for the number of bedrooms
my %validBedrooms= (1=>"", 
                    2=>"", 
                    3=>"",
                    4=>"",
                    5=>"");

# -------------------------------------------------------------------------------------------------
# getBedrooms
# returns a value representing the number of bedrooms
sub getBedrooms
{     
   my $analysisTools = shift;
   my $bedroomsParam = param('bedrooms');

   if ((defined $bedroomsParam) && (exists $validBedrooms{$bedroomsParam}))
   
   {                 
      $bedroomsDescription = $bedroomsParam;
      if ($analysisTools)
      {
         $analysisTools->setBedroomsConstraint($bedroomsParam);
      }
   }
   else
   {      
      $bedroomsDescription = "any";
      if ($analysisTools)
      {
         $analysisTools->setBedroomsConstraint(undef);
      }
   }
   
   return $bedroomsDescription;   
}

# ------------------------------------------------------------------------------------------------
# This hash defines valid keys for the number of bathrooms
my %validBathrooms= (1=>"", 
                     2=>"", 
                     3=>"");                

# -------------------------------------------------------------------------------------------------
# getBathrooms
# returns a value representing the number of bathrooms
sub getBathrooms
{   
   my $analysisTools = shift;   
   my $bathroomsParam = param('bathrooms');
      
   if ((defined $bathroomsParam) && (exists $validBathrooms{$bathroomsParam}))
   {           
      $bathroomsDescription = $bathroomsParam;
      if ($analysisTools)
      {
         $analysisTools->setBathroomsConstraint($bathroomsParam);
      }
   }
   else
   {                  
      $bathroomsDescription = "any";
      if ($analysisTools)
      {
         $analysisTools->setBathroomsConstraint(undef);
      }
   }
      
   return $bathroomsDescription;
}

# ------------------------------------------------------------------------------------------------
# This hash defines valid keys for the number of Types
my %validTypes = ('house'=>"",
                  'unit'=>"");

# -------------------------------------------------------------------------------------------------
# getType
# returns a value representing the type for the search
sub getType
{  
   my $analysisTools = shift;
   my $typeParam = param('type');
           
   if ((defined $typeParam) && (exists $validTypes{$typeParam}))
   {   
      if ($typeParam == 'house')
      {         
         $typeDescription = "Houses";
      }
      elsif ($typeParam == 'unit') 
      {         
         $typeDescription = "Units, Flats, Townhouses, Villas etc";
      }
      else
      {         
         $typeDescription = "any";
      }
      
      if ($analysisTools)
      {
         $analysisTools->setTypeConstraint($typeParam);
      }
   }
   else
   {      
      $typeDescription = "any";
      if ($analysisTools)
      {
         $analysisTools->setTypeConstraint(undef);
      }
   }   
   
   return $typeDescription;
}

# ------------------------------------------------------------------------------------------------
# This hash defines valid keys for the orderby parameter
my %validOrderBy = ('suburb'=>"",
                    'sale'=>"",
                    'rent'=>"",
                    'yield'=>"",
                    'cf'=>"");

# -------------------------------------------------------------------------------------------------
# getOrderBy
# returns a value representing how the data should be ordered
sub getOrderBy
{ 
   my $orderByParam = param('orderby');
           
   if ((defined $orderByParam) && (exists $validOrderBy{$orderByParam}))
   {   
      $orderBy = $orderByParam;
   }
   else
   {
      $orderBy = 'suburb';
   }   
   
   return $typeDescription;
}

# -------------------------------------------------------------------------------------------------
# getSuburbName
# returns a value representing which suburb to limit the analysis to
sub getSuburbName
{ 
   my $suburbParam = param('suburb');
           
   if (defined $suburbParam)
   {         
      $analysisTools->setSuburbConstraint($suburbParam);
      $suburbConstraintSet = 1;
   }
   else
   {
      $analysisTools->setSuburbConstraint(undef);
      $suburbConstraintSet = 0;
   }   
   
   return $typeDescription;
}

# -------------------------------------------------------------------------------------------------
# callback_bedrooms
# returns a value representing the number of bedrooms
sub callback_bedrooms
{          
   return getBedrooms();   
}

# -------------------------------------------------------------------------------------------------
# callback_bathrooms
# returns a value representing the number of bathrooms
sub callback_bathrooms
{   
   return getBathrooms();   
}

# -------------------------------------------------------------------------------------------------
# callback_type
# returns a value representing the type for the search
sub callback_type
{  
   return getType();   
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# callback_analysisDataTable
# returns a table containing a list of all the analysis restuls
sub callback_analysisDataTable
{         
   my @suburbList;
   my $index = 0;
  
   my @categoryName = (["Any", "",      "",   "",   "",      "",   "",   ""],
                       ["",   "3 beds", "",   "",   "4 beds", "",   "",   "5 beds"],
                       ["",   "",      "3x1", "3x2", "",      "4x1", "4x2", ""]);          
                       
   getOrderBy();
      
   #print "<table><tr><th>Suburb</th><th>Type</th><th>Field</th><th>Min</th><th>Median</th><th>REIWA Median</th><th>Max</th><th>StdDev</th><th>Yield</th><th>(Sample Size)</th></tr>\n";            
   print "<table  border='1' cellspacing='0' cellpadding='0'><tr><th>Suburb</th><th colspan=3>Type</th><th>Field</th><th>Min</th><th>Median</th><th>Max</th><th>StdDev</th><th>Yield</th><th>(Sample Size)</th><th>Median Cashflow</th></tr>\n";
   
   $analysisTools->calculateSalesAnalysis();
   $analysisTools->calculateRentalAnalysis();
   $analysisTools->calculateCashflowAnalysis();
   $analysisTools->calculateYield();   
      
   
   $noOfSales = $analysisTools->getNoOfSalesHash(0);
   $noOfRentals = $analysisTools->getNoOfRentalsHash(0);
   $salesMedian = $analysisTools->getSalesMedianHash(0);
   $rentalMedian = $analysisTools->getRentalMedianHash(0);
   $medianYield = $analysisTools->getMedianYieldHash(0);
   $cashflowMedian = $analysisTools->getCashflowMedianHash(0);         
         
   # get the list of suburbs from the keys of listings (any of the hashes would do)
   # and sort it into alphabetical order   
   if ($orderBy eq 'suburb')
   {      
      # order by suburbs alphabetically
      @suburbList = sort keys %$noOfSales;      
   }
   elsif ($orderBy eq 'sale')
   {            
      $index = 0;
   
      # sort the suburb names by the values of the median                   
      foreach (sort { $$salesMedian{$b} <=> $$salesMedian{$a} } keys %$salesMedian)           
      {                                        
          $suburbList[$index] = $_;
          $index++;
      }            
   }
   elsif ($orderBy eq 'rent')
   {
      $index = 0;
      # sort the suburb names by the values of the rental median total
      # ie. calls sort on the keys (suburbs) of rentalsumOfSalePrices but uses <=> to compare the values of each key      
      foreach (sort { $$rentalMedian{$b} <=> $$rentalMedian{$a} } keys %$rentalMedian)           
      {                              
          $suburbList[$index] = $_;
          $index++;
      }      
   }
   elsif ($orderBy eq 'yield')
   {
      $index = 0;      
      # sort the suburb names by the values of the yield
      # ie. calls sort on the keys (suburbs) of yeild but uses cmp to compare the values of each key      
      foreach (sort { $$medianYield{$b} <=> $$medianYield{$a} } keys %$medianYield)           
      {                              
          $suburbList[$index] = $_;
          $index++;
      }      
   }
   elsif ($orderBy eq 'cf')
   {
      $index = 0;      
      # sort the suburb names by the values of the yield
      # ie. calls sort on the keys (suburbs) of yeild but uses cmp to compare the values of each key      
      foreach (sort { $$cashflowMedian{$b} <=> $$cashflowMedian{$a} } keys %$cashflowMedian)           
      {                              
          $suburbList[$index] = $_;
          $index++;
      }      
   }
   else
   {      
      # order by suburbs alphabetically
      @suburbList = sort keys %$noOfSales;
   }   
      
   $length=@suburbList;

   # generate the table to display
   $oddEvenToggle = 0; 
   $bgColour[0] = "#ccffff";
   $bgColour[1] = "#ffffff";
   foreach (@suburbList)
   {
      # $_ is the suburb name
      $suburbName = $_;
      
      $outputSomething = 0;
      for ($category = 0; $category < 8; $category++)
      {
         
         $noOfSales = $analysisTools->getNoOfSalesHash($category);
         $noOfAdvertised = $analysisTools->getNoOfAdvertisedHash($category);
         $noOfRentals = $analysisTools->getNoOfRentalsHash($category);
         $salesMedian = $analysisTools->getSalesMedianHash($category);
         $rentalMedian = $analysisTools->getRentalMedianHash($category);
         $medianYield = $analysisTools->getMedianYieldHash($category);
         
         $minSalePrice = $analysisTools->getSalesMinHash($category);
         $maxSalePrice = $analysisTools->getSalesMaxHash($category);
         $salesStdDev = $analysisTools->getSalesStdDevHash($category);
         $minRentalPrice = $analysisTools->getRentalMinHash($category);
         $maxRentalPrice = $analysisTools->getRentalMaxHash($category);
         $rentalStdDev = $analysisTools->getRentalStdDevHash($category);
         #$officialSalesMedian = $analysisTools->getOfficialSalesMedianHash();
         #$officialRentalMedian = $analysisTools->getOfficialRentalMedianHash();
         $cashflowMedian = $analysisTools->getCashflowMedianHash($category);
         
         $minPriceInstance = commify(sprintf("\$%.0f", $$minSalePrice{$_}));
         $maxPriceInstance = commify(sprintf("\$%.0f", $$maxSalePrice{$_}));
         $salesStdDevInstance = commify(sprintf("\$%.0f", $$salesStdDev{$_}));
         $rentalStdDevInstance = commify(sprintf("\$%.0f", $$rentalStdDev{$_}));     
         if ($$salesMedian{$_} > 0)
         {
            $salesStdDevPercentInstance = commify(sprintf("%.2f", $$salesStdDev{$_}*100/$$salesMedian{$_}));
         }
         if ($$rentalMedian{$_} > 0)
         {
            $rentalStdDevPercentInstance = commify(sprintf("%.2f", $$rentalStdDev{$_}*100/$$rentalMedian{$_}));
         }
         $noOfSaleListings = $$noOfSales{$_};      
         if ($noOfSaleListings > 0)
         {
            $medianPriceInstance = commify(sprintf("\$%.0f", $$salesMedian{$suburbName}));
         }
         else
         {
            $medianPriceInstance = "\$0";         
         }
         
         if ($noOfSaleListings > 0)
         {
            $cashflowInstance = commify(sprintf("\$%.0f", $$cashflowMedian{$suburbName}));
         }
         else
         {
            $cashflowInstance = "?";         
         }
         
         $noOfAdvertisedListings = $$noOfAdvertised{$_};
          
         $minRentInstance = commify(sprintf("\$%.0f", $$minRentalPrice{$_}));
         $maxRentInstance = commify(sprintf("\$%.0f", $$maxRentalPrice{$_}));
         $noOfSaleListings = $$noOfSales{$_};
         $noOfRentListings = $$noOfRentals{$_};

         $medianRentInstance = commify(sprintf("\$%.0f", $$rentalMedian{$suburbName}));                  
   #      print "yield{$_}=", $$medianYield{$_}, "\n";
         $medianYieldInstance = sprintf("%.1f", $$medianYield{$_});
         $officialSalesInstance = commify(sprintf("\$%.0f", $$officialSalesMedian{$_}));
         $officialRentalInstance = commify(sprintf("\$%.0f", $$officialRentalMedian{$_}));         
                
         #<th>2br</th><th>3x1</th><th>3x2</th><th>4x2</th><th>4x3</th><th>5br</th></tr>\n";
         #print "<tr><td rows='2'>$suburbName</td><td rowspan='2'>$category</td><td>Sale</td><td>$minPriceInstance</td><td>$medianPriceInstance</td><td>$officialSalesInstance</td><td>$maxPriceInstance</td><td>$salesStdDevPercentInstance%</td><td rowspan='2'>%$medianYieldInstance</td><td><a href='", self_url(), "&suburb=", URI::Escape::uri_escape($suburbName),"'>$noOfSaleListings listings</a></td></tr>\n";
         #print "<tr><td></td><td>Rent</td><td>$minRentInstance</td><td>$medianRentInstance</td><td>$officialRentalInstance</td><td>$maxRentInstance</td><td>$rentalStdDevPercentInstance%</td><td>($noOfRentListings)</td></tr>\n";
         if ($noOfSaleListings > 5)
         {   
            if ($noOfRentListings > 5)
            {
               if ($noOfAdvertisedListings > 0)
               {
                  print "<tr bgcolor='", $bgColour[$oddEvenToggle], "'><td rowspan='2'><a href='", self_url(), "&suburb=", URI::Escape::uri_escape($suburbName),"'>$suburbName</a></td><td rowspan='2'>$categoryName[0][$category]</td><td rowspan='2'>$categoryName[1][$category]</td><td rowspan='2'>$categoryName[2][$category]</td><td>Sale</td><td>$minPriceInstance</td><td>$medianPriceInstance</td><td>$maxPriceInstance</td><td>$salesStdDevPercentInstance%</td><td rowspan='2'>%$medianYieldInstance</td><td>$noOfAdvertisedListings adverts</td><td>$cashflowInstance</td></tr>\n";
               }
               else
               {
                  print "<tr bgcolor='", $bgColour[$oddEvenToggle], "'><td rowspan='2'><a href='", self_url(), "&suburb=", URI::Escape::uri_escape($suburbName),"'>$suburbName</a></td><td rowspan='2'>$categoryName[0][$category]</td><td rowspan='2'>$categoryName[1][$category]</td><td rowspan='2'>$categoryName[2][$category]</td><td>Sale</td><td>$minPriceInstance</td><td>$medianPriceInstance</td><td>$maxPriceInstance</td><td>$salesStdDevPercentInstance%</td><td rowspan='2'>%$medianYieldInstance</td><td></td><td>$cashflowInstance</td></tr>\n";
               }
               print "<tr bgcolor='", $bgColour[$oddEvenToggle]," '><td>Rent</td><td>$minRentInstance</td><td>$medianRentInstance</td><td>$maxRentInstance</td><td>$rentalStdDevPercentInstance%</td><td>($noOfRentListings)</td></tr>\n";
               $outputSomething = 1;
            }
            else
            {
               #print "<tr><td rowspan='2'>$suburbName</td><td rowspan='2'>$categoryName[$category]</td><td>Sale</td><td>$minPriceInstance</td><td>$medianPriceInstance</td><td>$maxPriceInstance</td><td>$salesStdDevPercentInstance%</td><td rowspan='2'>?</td><td><a href='", self_url(), "&suburb=", URI::Escape::uri_escape($suburbName),"'>$noOfSaleListings listings</a></td></tr>\n";
               #print "<tr><td>Rent</td><td colspan='4'>Insuffient Data Available</td></tr>\n";
            }
         }
         else
         {
            #print "<tr><td rowspan='1'>$suburbName</td><td rowspan='1'>$categoryName[$category]</td><td colspan='8'>Insufficient Data Available</td></tr>\n";
         }
      
      }
      
      if ($outputSomething)
      {
         # alternate odd/even count
         $oddEvenToggle = !$oddEvenToggle;  
      }
      
   }
      
   print "</table>\n";
      
   return undef;   
}

# -------------------------------------------------------------------------------------------------
# callback_propertyList
# returns a table containing a list of all the property data
sub callback_propertyList
{            
   my $index = 0;   
   my %propertyData;
   my @monthString = ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec");
   
   $cmpTime = time() - (14*24*60*60);
      
   if ($suburbConstraintSet)
   {
      print "<h2>Properties currently advertised in My Regions...</h2>";
      print "<tt>Seen advertised in the last 14 days...</tt><br/>";
      print "Order by address | Order by Cashflow | Order by Yield | Order by Price <br/>";
      
      my $salesList = $analysisTools->getSalesDataList();         
   
      print "<table border='0' cellspacing='0' cellpadding='0'><tr><th align='center' colspan='5'>Advertised Property</th><th align='center' colspan='10'>Estimated Performance</th></tr>";
      print "<tr><th>Last Seen</th><th>Address</th><th>Price</th><th>Beds</th><th>Baths</th><th>Rent Range</th><th>Rent p/w</th><th>Yield</th><th>Purchase Fees</th><th>Mortgage Fees</th><th>Annual Income</th><th>Annual Expenses</th><th>Cashflow</th><th>Year Built</th><th>Median Cashflow</th></tr>\n";            
    
      # generate the table to display
      foreach (@$salesList)
      {      
         # $_ is a reference to a hash
         
         #$suburbName = URI::Escape::uri_escape($_);      
         $suburbName = $$_{'SuburbName'};
          
         $addressInstance = $$_{'StreetNumber'}." ".$$_{'Street'}." ".$$_{'SuburbName'};
         $lowerPriceInstance = commify(sprintf("\$%.0f", $$_{'AdvertisedPriceLower'}));
         if ($$_{'AdvertisedPriceUpper'})
         {
            $upperPriceInstance = commify(sprintf("\$%.0f", $$_{'AdvertisedPriceUpper'}));         
            $priceInstance = $lowerPriceInstance." - ". $upperPriceInstance;
         }
         else
         {
            $priceInstance = $lowerPriceInstance;
         }
         
         
         $lastSeen = $$_{'UnixTimeStamp'};       
         if ($lastSeen > $cmpTime)
         {
            $lastSeenInstance = 'Current';
         }
         else
         {
            ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($lastSeen);
            $lastSeenInstance = sprintf("%s%02i", $monthString[$mon], $year-100);
         }
         
         $category = $analysisTools->lookupBestFitCategory($$_{'Bedrooms'}, $$_{'Bathrooms'}, $suburbName);
         $minRentalPrice = $analysisTools->getRentalMinHash($category);
         $maxRentalPrice = $analysisTools->getRentalMaxHash($category);
            
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
         
         ($estimatedRent, $estimatedYield) = $analysisTools->estimateRent($advertisedPrice, $_);
         $estimatedCashflow = $analysisTools->estimateWeeklyCashflow($advertisedPrice, $estimatedRent, $_);
         
         $estimatedRentInstance = commify(sprintf("\$%.0f", $estimatedRent));
         $estimatedYieldInstance = sprintf("%.1f", $estimatedYield);
         $estimatedPurchaseCostsInstance = sprintf("\$%.0f", $$estimatedCashflow{'purchaseCosts'});
         $estimatedMortgageCostsInstance = sprintf("\$%.0f", $$estimatedCashflow{'mortgageCosts'});
         $estimatedAnnualIncomeInstance = sprintf("\$%.0f", $$estimatedCashflow{'annualIncome'});
         $estimatedAnnualExpensesInstance = sprintf("\$%.0f", $$estimatedCashflow{'annualExpenses'});
         $estimatedCashflowInstance = sprintf("\$%.2f", $$estimatedCashflow{'weeklyCashflow'});
         
         $bedsInstance = sprintf("%i", $$_{'Bedrooms'});        
         $bathsInstance = sprintf("%i", $$_{'Bathrooms'});
         $rentRangeInstance = sprintf("\$%.0f - \$%.0f", $$minRentalPrice{$suburbName}, $$maxRentalPrice{$suburbName}); 
         $yearBuiltInstance = $$_{'YearBuilt'};
         
         #<th>2br</th><th>3x1</th><th>3x2</th><th>4x2</th><th>4x3</th><th>5br</th></tr>\n";
         print "<tr><td>$lastSeenInstance</td><td><a href=''>$addressInstance</a></td><td>$priceInstance</td><td>$bedsInstance</td><td>$bathsInstance</td><td>$rentRangeInstance</td><td>$estimatedRentInstance</td><td>$estimatedYieldInstance%</td><td>$estimatedPurchaseCostsInstance</td><td>$estimatedMortgageCostsInstance</td><td>$estimatedAnnualIncomeInstance</td><td>$estimatedAnnualExpensesInstance</td><td>$estimatedCashflowInstance p/w</td><td>$yearBuiltInstance</td></tr>\n";            
      }
      
      print "</table>\n";
      
      print "<h2>Recently advertised Properties for Sale in My Regions...</h2>";
      print "<tt>Properties seen advertised in the last 3 months...</tt><br/>";
      my $relatedSalesList = $analysisTools->getRelatedSalesDataList();
       
      print "<table border='0' cellspacing='0' cellpadding='0'><tr><th align='center' colspan='5'>Advertised Property</th><th align='center' colspan='9'>Estimated Performance</th></tr>";
      print "<tr><th>Last Seen</th><th>Address</th><th>Price</th><th>Beds</th><th>Baths</th><th>Rent Range</th><th>Rent p/w</th><th>Yield</th><th>Purchase Fees</th><th>Mortgage Fees</th><th>Annual Income</th><th>Annual Expenses</th><th>Cashflow</th><th>Year Built</th></tr>\n";            
   
      # generate the table to display
      foreach (@$relatedSalesList)
      {      
         # $_ is a reference to a hash
         
         #$suburbName = URI::Escape::uri_escape($_);      
         $suburbName = $$_{'SuburbName'};
         
         $addressInstance = $$_{'StreetNumber'}." ".$$_{'Street'}." ".$$_{'SuburbName'};
         $lowerPriceInstance = commify(sprintf("\$%.0f", $$_{'AdvertisedPriceLower'}));
         if ($$_{'AdvertisedPriceUpper'})
         {
            $upperPriceInstance = commify(sprintf("\$%.0f", $$_{'AdvertisedPriceUpper'}));         
            $priceInstance = $lowerPriceInstance." - ". $upperPriceInstance;
         }
         else
         {
            $priceInstance = $lowerPriceInstance;
         }
         
         $lastSeen = $$_{'UnixTimeStamp'};       
         if ($lastSeen > $cmpTime)
         {
            $lastSeenInstance = 'Current';
         }
         else
         {
            ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($lastSeen);
            $lastSeenInstance = sprintf("%s%02i", $monthString[$mon], $year-100);
         }

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

         $category = $analysisTools->lookupBestFitCategory($$_{'Bedrooms'}, $$_{'Bathrooms'}, $suburbName);
         $minRentalPrice = $analysisTools->getRentalMinHash($category);
         $maxRentalPrice = $analysisTools->getRentalMaxHash($category);
         
         ($estimatedRent, $estimatedYield) = $analysisTools->estimateRent($advertisedPrice, $_);
         $estimatedCashflow = $analysisTools->estimateWeeklyCashflow($advertisedPrice, $estimatedRent, $_);
         
         $estimatedRentInstance = commify(sprintf("\$%.0f", $estimatedRent));
         $estimatedYieldInstance = sprintf("%.1f", $estimatedYield);
         $estimatedPurchaseCostsInstance = sprintf("\$%.0f", $$estimatedCashflow{'purchaseCosts'});
         $estimatedMortgageCostsInstance = sprintf("\$%.0f", $$estimatedCashflow{'mortgageCosts'});
         $estimatedAnnualIncomeInstance = sprintf("\$%.0f", $$estimatedCashflow{'annualIncome'});
         $estimatedAnnualExpensesInstance = sprintf("\$%.0f", $$estimatedCashflow{'annualExpenses'});
         $estimatedCashflowInstance = sprintf("\$%.2f", $$estimatedCashflow{'weeklyCashflow'});
         $bedsInstance = sprintf("%i", $$_{'Bedrooms'});        
         $bathsInstance = sprintf("%i", $$_{'Bathrooms'});
         $rentRangeInstance = sprintf("\$%.0f - \$%.0f", $$minRentalPrice{$suburbName}, $$maxRentalPrice{$suburbName}); 

         $yearBuiltInstance = $$_{'YearBuilt'};
         
         #<th>2br</th><th>3x1</th><th>3x2</th><th>4x2</th><th>4x3</th><th>5br</th></tr>\n";
         print "<tr><td>$lastSeenInstance</td><td><a href=''>$addressInstance</a></td><td>$priceInstance</td><td>$bedsInstance</td><td>$bathsInstance</td><td>$rentRangeInstance</td><td>$estimatedRentInstance</td><td>$estimatedYieldInstance%</td><td>$estimatedPurchaseCostsInstance</td><td>$estimatedMortgageCostsInstance</td><td>$estimatedAnnualIncomeInstance</td><td>$estimatedAnnualExpensesInstance</td><td>$estimatedCashflowInstance p/w</td><td>$yearBuiltInstance</td></tr>\n";            
      }
      print "</table>\n";
      
      print "<h2>Related Rental Properties in My Regions...</h2>";
      print "<tt>Rental properties seen advertised in the last 3 months...</tt><br/>";
      my $rentalsList = $analysisTools->getRentalDataList();
       
      print "<table  border='0' cellspacing='0' cellpadding='0'><tr><th align='center' colspan='4'>Advertised Rental</th></tr>";
      print "<tr><th>Last Seen</th><th>Address</th><th>Rent p/w</th><th>Beds</th><th>Baths</th></tr>\n";            
      
      # generate the table to display
      foreach (@$rentalsList)
      {      
         # $_ is a reference to a hash
         
         #$suburbName = URI::Escape::uri_escape($_);      
         $suburbName = $$_{'SuburbName'};

         $lastSeen = $$_{'LastSeen'};
       
         if ($lastSeen > $cmpTime)
         {
            $lastSeenInstance = 'Current';
         }
         else
         {
            ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($lastSeen);
            $lastSeenInstance = sprintf("%s%02i", $monthString[$mon], $year-100);
         }
         
         $addressInstance = $$_{'StreetNumber'}." ".$$_{'Street'}." ".$$_{'SuburbName'};
         $rentInstance = commify(sprintf("\$%.0f", $$_{'AdvertisedWeeklyRent'}));
         $bedsInstance = sprintf("%i", $$_{'Bedrooms'});        
         $bathsInstance = sprintf("%i", $$_{'Bathrooms'});

         
         #<th>2br</th><th>3x1</th><th>3x2</th><th>4x2</th><th>4x3</th><th>5br</th></tr>\n";
         print "<tr><td>$lastSeenInstance</td><td><a href=''>$addressInstance</a></td><td>$rentInstance</td><td>$bedsInstance</td><td>$bathsInstance</td></tr>\n";            
      }
      
      print "</table>\n";
   }
      
   
   return undef;   
}

  
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

print header();

$sqlClient = SQLClient::new(); 
$suburbProfiles = SuburbProfiles::new($sqlClient);

if ($sqlClient->connect())
{	
   # create the analysis tools instance...
   $analysisTools = AnalysisTools::new($sqlClient);
      
   getBedrooms($analysisTools);
   getBathrooms($analysisTools);
   getType($analysisTools);
   getSuburbName($analysisTools);
   # and load the data for analysis from the database
   $analysisTools->fetchAnalysisData();
      
   $registeredCallbacks{"AnalysisDataTable"} = \&callback_analysisDataTable;
   $registeredCallbacks{"Bedrooms"} = \&callback_bedrooms;
   $registeredCallbacks{"Bathrooms"} = \&callback_bathrooms;
   $registeredCallbacks{"Type"} = \&callback_type;       
   $registeredCallbacks{"PropertyList"} = \&callback_propertyList;
   
   $html = HTMLTemplate::printTemplate("AnalysisControlPanelTemplate.html", \%registeredCallbacks);

   #print $html;  
   
   $sqlClient->disconnect();
}
else
{
   print "Couldn't connect to database.";
}
      
# -------------------------------------------------------------------------------------------------

