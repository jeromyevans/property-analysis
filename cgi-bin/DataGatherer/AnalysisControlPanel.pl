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
use SuburbAnalysisTable;

# instance of the analysis tools object
my $analysisTools;
my $suburbAnalysisTable;
my $propertyCategories;
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
# This hash defines valid keys for the number of Types
my %validTypes = ('4'=>"",
                  '1'=>"");

# -------------------------------------------------------------------------------------------------
# getType
# returns a value representing the type for the search
sub getType
{  
   my $analysisTools = shift;
   my $typeParam = param('type');
           
   if ((defined $typeParam) && (exists $validTypes{$typeParam}))
   {   
      if ($typeParam == 4)
      {         
         $typeDescription = "Houses";
      }
      elsif ($typeParam == 1) 
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

# -------------------------------------------------------------------------------------------------
# getState
# returns a value representing how the data should be ordered
sub getState
{ 
   my $stateParam = param('state');
       
   $analysisTools->setStateConstraint($stateParam);

   return $stateParam;
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
# getSuburbIndex
# returns a param specifying the suburb for detailed analysis
sub getSuburbIndex
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
# callback_suburbList
# returns a table containing a list of all the analysis restuls
sub callback_suburbList
{         
   my @suburbList;
   my $index = 0;
         
   getOrderBy();
         
   $state = $analysisTools->getState();
   $typeIndex = $analysisTools->getTypeIndex();
   
   print "<br>State: $state, Type: $typeIndex<br/>\n";
   #print "<table><tr><th>Suburb</th><th>Type</th><th>Field</th><th>Min</th><th>Median</th><th>REIWA Median</th><th>Max</th><th>StdDev</th><th>Yield</th><th>(Sample Size)</th></tr>\n";            
   print "<table  border='1' cellspacing='0' cellpadding='0'><tr><th>Suburb</th><th colspan=1>Type</th><th>Field</th><th>Min</th><th>Median</th><th>Max</th><th>StdDev</th><th>Yield</th><th>Median Cashflow</th><th>Listings</th></tr>\n";
           
   # get the list of analysis categories
   @categoryList = $propertyCategories->getCategoryIndexList();

   $suburbNameHash = $suburbAnalysisTable->getSuburbNameHash();
   $suburbIndexHash = $suburbAnalysisTable->getSuburbIndexHash();
   
   $noOfSales = $suburbAnalysisTable->getNoOfSalesHash(0);
   $noOfRentals = $suburbAnalysisTable->getNoOfRentalsHash(0);
   $salesMedian = $suburbAnalysisTable->getSalesMedianHash(0);
   $rentalMedian = $suburbAnalysisTable->getRentalMedianHash(0);
   $medianYield = $suburbAnalysisTable->getMedianYieldHash(0);
   $cashflowMedian = $suburbAnalysisTable->getCashflowMedianHash(0);         
   
   # get the list of suburbs from the keys of listings (any of the hashes would do)
   # and sort it into alphabetical order   
   if ($orderBy eq 'suburb')
   {      
      # order by suburbs alphabetically - but get the suburbindex, not the suburb name for the list
      
      $index = 0;      
      # sort the suburb names - but use the suburb index in the list
      # keys of suburbIndexHash are suburbNames
      foreach (sort { $a cmp $b } keys %$suburbIndexHash)           
      {                              
         # $_ is suburbName - get the suburb index
         $suburbList[$index] = $$suburbIndexHash{$_};
         $index++;
      }      
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
       # order by suburbs alphabetically - but get the suburbindex, not the suburb name for the list
      
      $index = 0;      
      # sort the suburb names - but use the suburb index in the list
      foreach (sort { $a cmp $b } keys %$suburbIndexHash)           
      {                              
         # $_ is suburbName - get the suburb index
         $suburbList[$index] = $$suburbIndexHash{$_};
         $index++;
      }    
   }   
   $length=@suburbList;
   
   print "<br/>$length records to display<br/>\n";
   # generate the table to display
   $oddEvenToggle = 0; 
   $bgColour[0] = "#ffffbb";
   $bgColour[1] = "#ffffff";
   foreach (@suburbList)
   {
      # $_ is the suburb index
      $suburbIndex = $_;
      $suburbName = $$suburbNameHash{$suburbIndex};
      
      $outputSomething = 0;
   
      # loop through all the defined category types
      # and test if this property is in the subset of each category
      foreach (@categoryList)
      {
         $category = $_;
         
         #print "<br>Category=$category</br>\n";
         $noOfSales = $suburbAnalysisTable->getNoOfSalesHash($category);
         $noOfAdvertised = $suburbAnalysisTable->getNoOfAdvertisedHash($category);
         $noOfRentals = $suburbAnalysisTable->getNoOfRentalsHash($category);
         $salesMedian = $suburbAnalysisTable->getSalesMedianHash($category);
         $rentalMedian = $suburbAnalysisTable->getRentalMedianHash($category);
         $medianYield = $suburbAnalysisTable->getMedianYieldHash($category);
         
         $minSalePrice = $suburbAnalysisTable->getSalesMinHash($category);
         $maxSalePrice = $suburbAnalysisTable->getSalesMaxHash($category);
         $salesStdDev = $suburbAnalysisTable->getSalesStdDevHash($category);
         $minRentalPrice = $suburbAnalysisTable->getRentalMinHash($category);
         $maxRentalPrice = $suburbAnalysisTable->getRentalMaxHash($category);
         $rentalStdDev = $suburbAnalysisTable->getRentalStdDevHash($category);
         #$officialSalesMedian = $analysisTools->getOfficialSalesMedianHash();
         #$officialRentalMedian = $analysisTools->getOfficialRentalMedianHash();
         $cashflowMedian = $suburbAnalysisTable->getCashflowMedianHash($category);
                
         
         $minPriceInstance = commify(sprintf("\$%.0f", $$minSalePrice{$suburbIndex}));
         $maxPriceInstance = commify(sprintf("\$%.0f", $$maxSalePrice{$suburbIndex}));
         $salesStdDevInstance = commify(sprintf("\$%.0f", $$salesStdDev{$suburbIndex}));
         $rentalStdDevInstance = commify(sprintf("\$%.0f", $$rentalStdDev{$suburbIndex}));     
         if ($$salesMedian{$suburbIndex} > 0)
         {
            $salesStdDevPercentInstance = commify(sprintf("%.2f", $$salesStdDev{$suburbIndex}*100/$$salesMedian{$suburbIndex}));
         }
         if ($$rentalMedian{$suburbIndex} > 0)
         {
            $rentalStdDevPercentInstance = commify(sprintf("%.2f", $$rentalStdDev{$suburbIndex}*100/$$rentalMedian{$suburbIndex}));
         }
         #$noOfSaleListings = $$noOfSales{$suburbIndex};      
         #if ($noOfSaleListings > 0)
         #{
            $medianPriceInstance = commify(sprintf("\$%.0f", $$salesMedian{$suburbIndex}));
         #}
         #else
         #{
         #   $medianPriceInstance = "\$0";         
         #}
         
         #if ($noOfSaleListings > 0)
         #{
            $cashflowInstance = commify(sprintf("\$%.0f", $$cashflowMedian{$suburbIndex}));
         #}
         #else
         #{
         #   $cashflowInstance = "?";         
         #}
         
         $noOfAdvertisedListings = $$noOfAdvertised{$suburbIndex};
          
         $minRentInstance = commify(sprintf("\$%.0f", $$minRentalPrice{$suburbIndex}));
         $maxRentInstance = commify(sprintf("\$%.0f", $$maxRentalPrice{$suburbIndex}));
         $noOfSaleListings = $$noOfSales{$suburbIndex};
         $noOfRentListings = $$noOfRentals{$suburbIndex};

         $medianRentInstance = commify(sprintf("\$%.0f", $$rentalMedian{$suburbIndex}));                  
   #      print "yield{$suburbIndex}=", $$medianYield{$suburbIndex}, "\n";
         $medianYieldInstance = sprintf("%.1f", $$medianYield{$suburbIndex});
                
         #<th>2br</th><th>3x1</th><th>3x2</th><th>4x2</th><th>4x3</th><th>5br</th></tr>\n";
         #print "<tr><td rows='2'>$suburbIndex</td><td rowspan='2'>$category</td><td>Sale</td><td>$minPriceInstance</td><td>$medianPriceInstance</td><td>$officialSalesInstance</td><td>$maxPriceInstance</td><td>$salesStdDevPercentInstance%</td><td rowspan='2'>%$medianYieldInstance</td><td><a href='", self_url(), "&suburb=", URI::Escape::uri_escape($suburbIndex),"'>$noOfSaleListings listings</a></td></tr>\n";
         #print "<tr><td></td><td>Rent</td><td>$minRentInstance</td><td>$medianRentInstance</td><td>$officialRentalInstance</td><td>$maxRentInstance</td><td>$rentalStdDevPercentInstance%</td><td>($noOfRentListings)</td></tr>\n";
         if ($$minSalePrice{$suburbIndex})
         {   
            if ($$minRentalPrice{$suburbIndex})
            {
               if ($noOfAdvertisedListings > 0)
               {
                  print "<tr bgcolor='", $bgColour[$oddEvenToggle], "'><td rowspan='2'><a href='", self_url(), "&suburb=", $suburbIndex,"&state=$state&type=$typeIndex'>$suburbName</a></td><td rowspan='2'>", $propertyCategories->getCategoryPrettyName($category), "</td><td>Sale</td><td>$minPriceInstance</td><td>$medianPriceInstance</td><td>$maxPriceInstance</td><td>$salesStdDevPercentInstance%</td><td rowspan='2'>%$medianYieldInstance</td><td rowspan='2'>$cashflowInstance</td><td rowspan='2'>$noOfAdvertisedListings listing(s)</td></tr>\n";
               }
               else
               {
                  print "<tr bgcolor='", $bgColour[$oddEvenToggle], "'><td rowspan='2'><a href='", self_url(), "&suburb=", $suburbIndex,"&state=$state&type=$typeIndex'>$suburbName</a></td><td rowspan='2'>", $propertyCategories->getCategoryPrettyName($category), "</td><td>Sale</td><td>$minPriceInstance</td><td>$medianPriceInstance</td><td>$maxPriceInstance</td><td>$salesStdDevPercentInstance%</td><td rowspan='2'>%$medianYieldInstance</td><td rowspan='2'>$cashflowInstance</td></tr>\n";
               }
               print "<tr bgcolor='", $bgColour[$oddEvenToggle]," '><td>Rent</td><td>$minRentInstance</td><td>$medianRentInstance</td><td>$maxRentInstance</td><td>$rentalStdDevPercentInstance%</td></tr>\n";
               $outputSomething = 1;
           }
           #else
           #{
               #print "<tr><td rowspan='2'>$suburbName</td><td rowspan='2'>$categoryName[$category]</td><td>Sale</td><td>$minPriceInstance</td><td>$medianPriceInstance</td><td>$maxPriceInstance</td><td>$salesStdDevPercentInstance%</td><td rowspan='2'>?</td><td><a href='", self_url(), "&suburb=", URI::Escape::uri_escape($suburbName),"'>$noOfSaleListings listings</a></td></tr>\n";
               #print "<tr><td>Rent</td><td colspan='4'>Insuffient Data Available</td></tr>\n";
            #}
         }
         #else
         #{
           # print "<tr><td rowspan='1'>$suburbName</td><td rowspan='1'>$categoryName[$category]</td><td colspan='8'>Insufficient Data Available</td></tr>\n";
         #}
      
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
      
   $suburbIndex = param('suburb');
   $state = param('state');
   $typeIndex = param('type');
      
   if (($suburbIndex) && ($state))
   {
      
      print "<h2>Suburb Property List (suburbIndex=$suburbIndex)...</h2>";
      print "<h3>Properties currently advertised in My Region...</h3>";
      print "<tt>Advertised in the last 14 days...</tt><br/>";
      print "Order by address | Order by Cashflow | Order by Yield | Order by Price <br/>";
      
      my $salesList = $analysisTools->getSalesDataList($suburbIndex);         
         
      print "<table border='0' cellspacing='0' cellpadding='0'><tr><th align='center' colspan='5'>Advertised Property</th><th align='center' colspan='10'>Estimated Performance</th></tr>";
      print "<tr><th>Last Seen</th><th>Address</th><th>Price</th><th>Beds</th><th>Baths</th><th>Rent Range</th><th>Rent p/w</th><th>Yield</th><th>Purchase Fees</th><th>Mortgage Fees</th><th>Annual Income</th><th>Annual Expenses</th><th>Cashflow</th><th>Year Built</th><th>Median Cashflow</th></tr>\n";            
  
      $length = @$salesList;
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
         
         $category = $propertyCategories->lookupBestFitCategory($$_{'Bedrooms'}, $$_{'Bathrooms'}, $suburbIndex);
         $minRentalPrice = $suburbAnalysisTable->getRentalMinHash($category);
         $maxRentalPrice = $suburbAnalysisTable->getRentalMaxHash($category);
            
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
         $rentRangeInstance = sprintf("\$%.0f - \$%.0f", $$minRentalPrice{$suburbIndex}, $$maxRentalPrice{$suburbIndex}); 
         $yearBuiltInstance = $$_{'YearBuilt'};
         
         #<th>2br</th><th>3x1</th><th>3x2</th><th>4x2</th><th>4x3</th><th>5br</th></tr>\n";
         print "<tr><td>$lastSeenInstance</td><td><a href='http://localhost/cgi-bin/DataGatherer/AnalysisControlPanel.pl?identifier=".$$_{'Identifier'}."'>$addressInstance</a></td><td>$priceInstance</td><td align='center'>$bedsInstance</td><td align='center'>$bathsInstance</td><td>$rentRangeInstance</td><td>$estimatedRentInstance</td><td>$estimatedYieldInstance%</td><td>$estimatedPurchaseCostsInstance</td><td>$estimatedMortgageCostsInstance</td><td>$estimatedAnnualIncomeInstance</td><td>$estimatedAnnualExpensesInstance</td><td>$estimatedCashflowInstance p/w</td><td>$yearBuiltInstance</td></tr>\n";            
      }
      
      print "</table>\n";
      
      print "<h2>Recently advertised Properties for Sale in My Regions...</h2>";
      print "<tt>Properties seen advertised in the last 3 months...</tt><br/>";
      my $relatedSalesList = $analysisTools->getRelatedSalesDataList($suburbIndex);
       
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

         $category = $propertyCategories->lookupBestFitCategory($$_{'Bedrooms'}, $$_{'Bathrooms'}, $suburbIndex);
         $minRentalPrice = $suburbAnalysisTable->getRentalMinHash($category);
         $maxRentalPrice = $suburbAnalysisTable->getRentalMaxHash($category);
         
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
         $rentRangeInstance = sprintf("\$%.0f - \$%.0f", $$minRentalPrice{$suburbIndex}, $$maxRentalPrice{$suburbIndex}); 

         $yearBuiltInstance = $$_{'YearBuilt'};
         
         #<th>2br</th><th>3x1</th><th>3x2</th><th>4x2</th><th>4x3</th><th>5br</th></tr>\n";
         print "<tr><td>$lastSeenInstance</td><td><a href='http://localhost/cgi-bin/DataGatherer/AnalysisControlPanel.pl?identifier=".$$_{'Identifier'}."'>$addressInstance</a></td><td>$priceInstance</td><td align='center'>$bedsInstance</td><td align='center'>$bathsInstance</td><td>$rentRangeInstance</td><td>$estimatedRentInstance</td><td>$estimatedYieldInstance%</td><td>$estimatedPurchaseCostsInstance</td><td>$estimatedMortgageCostsInstance</td><td>$estimatedAnnualIncomeInstance</td><td>$estimatedAnnualExpensesInstance</td><td>$estimatedCashflowInstance p/w</td><td>$yearBuiltInstance</td></tr>\n";            
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
         print "<tr><td>$lastSeenInstance</td><td><a href='http://localhost/cgi-bin/DataGatherer/AnalysisControlPanel.pl?identifier=".$$_{'Identifier'}."'>$addressInstance</a></td><td>$rentInstance</td><td align='center'>$bedsInstance</td><td align='center'>$bathsInstance</td></tr>\n";            
      }
      
      print "</table>\n";
   }     
   else
   {
      print "bad parameters Jez<br/>\n";  
   }
   
   return undef;   
}

  

# -------------------------------------------------------------------------------------------------
# callback_propertyDetails
# returns a table containing a list of all the property data
sub callback_propertyDetails
{            
   my $index = 0;   
   my %propertyData;
   my @monthString = ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec");
   
   $cmpTime = time() - (14*24*60*60);
      
   # this is a temporary hack while there isn't a proper dispatcher to load the correct template
   if (param("identifier"))
   {
      $identifier = param("identifier");
      print "<h2>Property Details</h2>";
      
      # fetch the profile from the database      
      $profileRef = $analysisTools->getPropertyProfile($identifier);         
      # estimate sale price
      $salePrice = $analysisTools->estimateSalePrice($profileRef);
      # estimate rent
      ($estimatedRent, $estimatedYield) = $analysisTools->estimateRent($salePrice, $profileRef);

      # estimate purchase costs
      $purchaseCosts = $analysisTools->estimatePurchaseCosts($salePrice);
      $apportionedMortgageFees = $analysisTools->estimateMortgageCosts($salePrice, $purchaseCosts);
      
      $annualIncome = $analysisTools->estimateAnnualIncome($estimatedRent);
      $annualExpenses = $analysisTools->estimateAnnualExpenses($purchaseCosts, $annualIncome);
      
      $totalCosts = $$purchaseCosts{'totalPurchaseFees'}+$$purchaseCosts{'totalMortgageFees'}+$salePrice;
      $LVR = 0.8;
      $totalDeposit = $totalCosts * (1-$LVR);
      $loanRequired = $totalCosts - $totalDeposit;
      $cashDeposit = 0;
      $equityDeposit = $totalDeposit;
      
      $taxableIncome = $$annualIncome{'annualIncome'} - $$annualExpenses{'annualExpenses'} - $unrealisedExpenses- $apportionedMortgageFees;
      $taxRate = 0.485;
      if ($taxableIncome > 0)
      {
         $taxOwed = $taxableIncome * $taxRate;
         $taxRefund = 0;
      }
      else
      {
         $taxOwed = 0;
         $taxRefund = $taxableIncome * $taxRate;
      }
      $cashExpenses = $$annualIncome{'annualIncome'} - $$annualExpenses{'annualExpenses'};
      $annualCashflow = $cashExpenses - $taxRefund;
      $weeklyCashflow = $annualCashflow / 52;
      
      # --- prepare to display results ---
      
      $addressInstance = $$profileRef{'StreetNumber'}." ".$$profileRef{'Street'};
      $suburbInstance = $$profileRef{'SuburbName'};
      
      $lowerPriceInstance = commify(sprintf("\$%.0f", $$profileRef{'AdvertisedPriceLower'}));
      if ($$profileRef{'AdvertisedPriceUpper'})
      {
         $upperPriceInstance = commify(sprintf("\$%.0f", $$profileRef{'AdvertisedPriceUpper'}));         
         $priceInstance = $lowerPriceInstance." - ". $upperPriceInstance;
      }
      else
      {
         $priceInstance = $lowerPriceInstance;
      }
            
      $estimatedPurchaseCostsInstance = sprintf("\$%.0f", $$purchaseCosts{'totalPurchaseFees'});
      $estimatedMortgageCostsInstance = sprintf("\$%.0f", $$purchaseCosts{'totalMortgageFees'});
      $totalCostsInstance = sprintf("\$%.0f", $totalCosts);

      
      $typeInstance = sprintf($$profileRef{'Type'});
      $bedsInstance = sprintf("%i", $$profileRef{'Bedrooms'});        
      $bathsInstance = sprintf("%i", $$profileRef{'Bathrooms'});
      $salePriceInstance = sprintf("\$%.0f", $salePrice);
     
      $LVRInstance = sprintf("%.0f\%", $LVR*100);
      $depositInstance = sprintf("\$%.0f", $totalDeposit);
      $loanInstance = sprintf("\$%.0f", $loanRequired);
      $cashDepositInstance = sprintf("\$%.0f", $cashDeposit);
      $equityDepositInstance = sprintf("\$%.0f", $equityDeposit);
      
      print "<table>\n";
      print "<tr><td>Identifier</td><td>".$$profileRef{'Identifier'}."</td></tr>";
      print "<tr><td>Address</td><td>$addressInstance</td></tr>";
      print "<tr><td>Suburb</td><td>$suburbInstance</td></tr>";
      print "<tr><td>Advertised Price</td><td>$priceInstance</td></tr>";
      print "<tr><td>Type</td><td>$typeInstance</td></tr>";
      print "<tr><td>Beds</td><td>$bedsInstance</td></tr>";
      print "<tr><td>Baths</td><td>$bathsInstance</td></tr>";
      print "<tr><td>Year Built</td><td>$yearBuiltInstance</td></tr>";
      print "<tr><td>---</td></tr>";
      print "<tr><td>Estimated Purchase Price</td><td>$salePriceInstance</td></tr>";
      print "<tr><td>LVR</td><td>$LVRInstance</td></tr>";
      print "<tr><td>Estimated Purchase Costs</td><td>$estimatedPurchaseCostsInstance (see calculation below)</td></tr>";
      print "<tr><td>Estimated Mortgage Costs</td><td>$estimatedMortgageCostsInstance (see calculation below)</td></tr>";
      print "<tr><td>Estimated Total Cost</td><td>$totalCostsInstance</td></tr>";
      print "<tr><td>---</td></tr>";
      print "<tr><td>Loan Required</td><td>$loanInstance</td></tr>";
      print "<tr><td>Deposit Required</td><td>$depositInstance</td></tr>";
      print "<tr><td>Deposit using cash</td><td>$cashDepositInstance</td></tr>";
      print "<tr><td>Deposit using equity</td><td>$equityDepositInstance</td></tr>";
      print "<tr><td>---</td></tr>";
      print "</table>";
      print "<table>\n";
      print "<tr><td>Cashflow Summary</td><td></td><td></td></tr>";
      $valueInstance = sprintf("\$%.0f", $taxableIncome);
      print "<tr><td>Annual Taxable Income</td><td>$valueInstance</td><td></td></tr>";
      if ($taxableIncome < 0)
      {
         $valueInstance = sprintf("\$%.0f", $taxRefund);
         print "<tr><td>Borrowing Status</td><td>NEGATIVELY GEARED</td></tr>";
         print "<tr><td>Tax Return (1st year)</td><td>$valueInstance</td><td></td></tr>";
      }
      else
      {
         $valueInstance = sprintf("\$%.0f", $taxOwed);
         print "<tr><td>Borrowing Status</td><td>POSITIVELY GEARED</td></tr>";
         print "<tr><td>Tax Owed (1st year)</td><td>$valueInstance</td><td></td></tr>";         
      }
      
      if ($weeklyCashflow >= 0)
      {
         print "<tr><td>Cashflow Status</td><td>POSITIVE CASHFLOW</td></tr>";
      }
      else
      {
         print "<tr><td>Cashflow Status</td><td>NEGATIVE CASHFLOW</td></tr>";
      }

      $valueInstance = sprintf("\$%.0f", $weeklyCashflow);
      print "<tr><td>Cashflow per week(1st year)</td><td>$valueInstance</td><td></td></tr>";

      print "</table>\n";
      
      print "<table border='1'>";
      print "<tr><th colspan='2'>Estimated Setup and Establishment Costs (Non-Recurring Expenses)</th></tr>";
      print "<tr><td align='center' width='50%'>Income</td><td align='center' width='50%'>Expense</td></tr>\n";
      
      print "<tr valign='top'>";
      # ----- first row, left table--------
      print "<td><table>";
      print "<tr><th colspan='4' align='center'>Non-Recurring Income (Taxable)</th></tr>";      
      # loop through and display all of the non-recurring income 
      print "<tr><td></td><td>Nil</td><td>\$0.00</td></tr>";      
      # (none to loop through)
      print "<tr><td></td><td align='right'>Total</td><td></td><td>\$0.00</td></tr>";      
      print "</table></td>";
      # --------- first row, right table ----------
      print "<td><table>";
      print "<tr><th colspan='4' align='center'>Non-Recurring Expenses (Deductable)</th></tr>";      
      # loop through and display all of the mortgage establishment components
      print "<tr><td colspan='2'>Mortgage Establishment</td></tr>";
      $nre_me_total = 0;      
      foreach (keys %$purchaseCosts)
      {
         if ($_ =~ /nre_me_/)
         {
            $nre_me_total += $$purchaseCosts{$_};
            $valueInstance = sprintf("\$%.0f", $$purchaseCosts{$_});
            print "<tr><td></td><td>$_</td><td>$valueInstance</td><td></td></tr>";      
         }
      }
      $valueInstance = sprintf("\$%.0f", $nre_me_total);
      print "<tr><td></td><td align='right'>Total</td><td></td><td>$valueInstance</td></tr>";      
      
      # loop through and display all of the purchase cost components
      print "<tr><td colspan='2'>Purchase Costs</td></tr>";  
      $nre_pc_total = 0;      
      foreach (keys %$purchaseCosts)
      {
         if ($_ =~ /nre_pc_/)
         {
            $nre_pc_total += $$purchaseCosts{$_};
            $valueInstance = sprintf("\$%.0f", $$purchaseCosts{$_});
            print "<tr><td></td><td>$_</td><td>$valueInstance</td><td></td></tr>";      
         }
      }
      $valueInstance = sprintf("\$%.0f", $nre_pc_total);
      print "<tr><td></td><td align='right'>Total</td><td></td><td>$valueInstance</td></tr>";

      print "</table></td></tr>";
      
      # ------ second row, left table -------
      # SUMMARY LINE: TOTAL NRI
      print "<tr><td><table>";
      # loop through and display all of the non-recurring income 
      # (none to loop through)
      print "<tr><th align='right'>Total NRI (Taxable): \$0.00</th></tr>";      
      print "</table></td>";
      
      # ------ second row, right table -------
      # SUMMARY LINE: TOTAL NRE
      print "<td><table>";
      $valueInstance = sprintf("\$%.0f", $nre_me_total+$nre_pc_total);
      print "<tr><th align='right'>Total NRE (Deductable): $valueInstance</th></tr>";      
      print "</table></td></tr>";
      
      
      # ----- third row, left table--------
      # NON-RECURRING INCOME (Non-taxable)
      print "<tr valign='top'>";
      print "<td><table>";
      print "<tr><th colspan='4' align='center'>Non-Recurring Income (Non-Taxable)</th></tr>";      
      # loop through and display all of the non-recurring income 
      print "<tr><td></td><td>Nil</td><td>\$0.00</td></tr>";      
      # (none to loop through)
      print "<tr><td></td><td align='right'>Total</td><td></td><td>\$0.00</td></tr>";      
      print "</table></td>";
      # --------- third row, right table ----------
      # NON-RECURRING EXPENSES (Non-deductable)
      print "<td><table>";
      print "<tr><th colspan='4' align='center'>Non-Recurring Expenses (Non-Deductable)</th></tr>";      
      # loop through and display all of the non-recurring expenses (cash deposit) 
      $valueInstance = sprintf("\$%.0f", $cashDeposit);
      print "<tr><td></td><td>Cash Deposit</td><td>$valueInstance</td></tr>";      
      print "<tr><td></td><td align='right'>Total</td><td></td><td>$valueInstance</td></tr>";      
      print "</table></td></tr>";

      # ------ fourth row, left table -------
      # SUMMARY LINE: TOTAL NRI (non-taxable)
      print "<tr><td><table>";
      # loop through and display all of the non-recurring income 
      # (none to loop through)
      print "<tr><th align='right'>Total NRI(Tax Exempt): \$0.00</th></tr>";      
      print "</table></td>";
      
      # ------ fourth row, right table -------
      # SUMMARY LINE: TOTAL NRE (Non-deductable)
      print "<td><table>";
      $valueInstance = sprintf("\$%.0f", $cashDeposit);
      print "<tr><th align='right'>Total NRE(Non-deductable): $valueInstance</th></tr>";      
      print "</table></td></tr>";


      print "<tr><th colspan='2'>Estimated Annual Income and Expenses (Recurring)</th></tr>";
      print "<tr><td align='center' width='50%'>Income</td><td align='center' width='50%'>Expense</td></tr>\n";
       
      
        # ----- fifth row, left table--------
      # RECURRING INCOME (Taxable)
      print "<tr valign='top'>";
      print "<td><table>";
      print "<tr><th colspan='4' align='center'>Recurring Income (Taxable)</th></tr>";      
      # loop through and display all of the non-recurring income 
      $valueInstance = sprintf("\$%.0f", $$annualIncome{'weeklyRent'});
      print "<tr><td></td><td>Weekly Rent</td><td>$valueInstance</td></tr>";      
      $valueInstance = sprintf("%.0f\%", $$annualIncome{'occupancyRate'}*100);
      print "<tr><td></td><td>Occupancy Rate</td><td>$valueInstance</td></tr>";      
      $valueInstance = sprintf("\$%.0f", $$annualIncome{'annualIncome'});
      print "<tr><td></td><td>Annual Rent</td><td>$valueInstance</td></tr>";      
      $valueInstance = sprintf("\$%.0f", $$annualIncome{'annualIncome'});
      print "<tr><td></td><td align='right'>Total</td><td></td><td>$valueInstance</td></tr>";      
      print "</table></td>";
      # --------- fifth row, right table ----------
      # RECURRING EXPENSES (Deductable)
      print "<td><table>";
      print "<tr><th colspan='4' align='center'>Recurring Expenses (Deductable)</th></tr>";      
      # loop through and display all of the recurring expenses (deductable) 
      print "<tr><td colspan='2'>Mortgage Expenses</td></tr>";
      $re_me_total = 0;      
      foreach (keys %$annualExpenses)
      {
         if ($_ =~ /re_me_/)
         {
            $re_me_total += $$annualExpenses{$_};
            $valueInstance = sprintf("\$%.0f", $$annualExpenses{$_});
            print "<tr><td></td><td>$_</td><td>$valueInstance</td><td></td></tr>";      
         }
      }
      $valueInstance = sprintf("\$%.0f", $re_me_total);
      print "<tr><td></td><td align='right'>Total</td><td></td><td>$valueInstance</td></tr>";      
      
      print "<tr><td colspan='2'>Administration & Management</td></tr>";
      $re_am_total = 0;      
      foreach (keys %$annualExpenses)
      {
         if ($_ =~ /re_am_/)
         {
            $re_am_total += $$annualExpenses{$_};
            $valueInstance = sprintf("\$%.0f", $$annualExpenses{$_});
            print "<tr><td></td><td>$_</td><td>$valueInstance</td><td></td></tr>";      
         }
      }
      $valueInstance = sprintf("\$%.0f", $re_am_total);
      print "<tr><td></td><td align='right'>Total</td><td></td><td>$valueInstance</td></tr>";
      print "</table></td></tr>";
      
      # ------ sixth row, left table -------
      # SUMMARY LINE: TOTAL RI (taxable)
      print "<tr><td><table>";
      $valueInstance = sprintf("\$%.0f", $$annualIncome{'annualIncome'});
      print "<tr><th align='right'>Total RI(Taxable): $valueInstance</th></tr>";      
      print "</table></td>";
      
      # ------ sixth row, right table -------
      # SUMMARY LINE: TOTAL RE (deductable)
      print "<td><table>";
      $valueInstance = sprintf("\$%.0f", $re_me_total+$re_am_total);
      print "<tr><th align='right'>Total RE(Deductable): $valueInstance</th></tr>";      
      print "</table></td></tr>";
      
      # ----- seventh row, left table--------
      # RECURRING INCOME (Non-taxable)
      print "<tr valign='top'>";
      print "<td><table>";
      print "<tr><th colspan='4' align='center'>Recurring Income (Non-Taxable)</th></tr>";      
      # loop through and display all of the recurring income 
      print "<tr><td></td><td>Nil</td><td>\$0.00</td></tr>";      
      # (none to loop through)
      print "<tr><td></td><td align='right'>Total</td><td></td><td>\$0.00</td></tr>";      
      print "</table></td>";
      # --------- seventh row, right table ----------
      # RECURRING EXPENSES (Non-deductable)
      print "<td><table>";
      print "<tr><th colspan='4' align='center'>Recurring Expenses (Non-Deductable)</th></tr>";      
      # loop through and display all of the non-recurring expenses (mortgage principle) 
      $valueInstance = sprintf("\$%.0f", 0);
      print "<tr><td></td><td>Mortgage - principle</td><td>$valueInstance</td></tr>";      
      print "<tr><td></td><td align='right'>Total</td><td></td><td>$valueInstance</td></tr>";      
      print "</table></td></tr>";
      
      # ------ eigth row, left table -------
      # SUMMARY LINE: TOTAL RI (non-taxable)
      print "<tr><td><table>";
      $valueInstance = sprintf("\$%.0f", 0);
      print "<tr><th align='right'>Total RI(Tax Exempt): $valueInstance</th></tr>";      
      print "</table></td>";
      
      # ------ eigth row, right table -------
      # SUMMARY LINE: TOTAL RE (non-deductable)
      print "<td><table>";
      $valueInstance = sprintf("\$%.0f", 0);
      print "<tr><th align='right'>Total RE(Non-Deductable): $valueInstance</th></tr>";      
      print "</table></td></tr>";
      
      print "<tr><th colspan='2'>Estimated UNREALISED Income and Expenses (Recurring)</th></tr>";
      print "<tr><td align='center' width='50%'>Income</td><td align='center' width='50%'>Expense</td></tr>\n";
      
      # ----- ninth row, left table--------
      # UNCREALISED RECURRING INCOME (Non-taxable)
      print "<tr valign='top'>";
      print "<td><table>";
      print "<tr><th colspan='4' align='center'>Unrealised Recurring Income (Non-Taxable yet)</th></tr>";      
      # loop through and display all of the recurring income 
      print "<tr><td></td><td>Land Appreciation</td><td>\$0.00</td></tr>";      
      # (none to loop through)
      print "<tr><td></td><td align='right'>Total</td><td></td><td>\$0.00</td></tr>";      
      print "</table></td>";
      # --------- ninth row, right table ----------
      # UNCREALISED RECURRING EXPENSES (deductable)
      print "<td><table>";
      print "<tr><th colspan='4' align='center'>Unrealised recurring Expenses (Deductable)</th></tr>";      
      # loop through and display all of the non-recurring expenses (mortgage principle) 
      $valueInstance = sprintf("\$%.0f", 0);
      print "<tr><td></td><td>Building Depreciation</td><td>$valueInstance</td></tr>";      
      print "<tr><td></td><td align='right'>Total</td><td></td><td>$valueInstance</td></tr>";      
      print "</table></td></tr>";
      
       # ------ eigth row, left table -------
      # SUMMARY LINE: TOTAL URI (non-taxable)
      print "<tr><td><table>";
      $valueInstance = sprintf("\$%.0f", 0);
      print "<tr><th align='right'>Total Unrealised RI(Tax Deferred): $valueInstance</th></tr>";      
      print "</table></td>";
      
      # ------ eigth row, right table -------
      # SUMMARY LINE: TOTAL URE (deductable)
      print "<td><table>";
      $valueInstance = sprintf("\$%.0f", 0);
      print "<tr><th align='right'>Total Unrealised RE(Deductable): $valueInstance</th></tr>";      
      print "</table></td></tr>";      
      
      print "</table>\n";
   }
   else
   {
      print "<br>No property id</br>\n";
   }
   
   return undef;   
}



# -------------------------------------------------------------------------------------------------
# callback_isStateSelected
# returns selected if the specifeid state is the parameter
sub callback_isStateSelected
{            
   my $parameter = shift;
   my $status = undef;
   my $selected = 'selected';
   $state = param('state');
   
   if (defined $state)
   {
      if (($parameter =~ /WA/g) && ($state eq 'WA'))
      {
         $status = $selected;
      }
      elsif (($parameter =~ /VIC/g) && ($state eq 'VIC'))
      {
         $status = $selected;
      }
      elsif (($parameter =~ /NSW/g) && ($state eq 'NSW'))
      {
         $status = $selected;
      }
      elsif (($parameter =~ /SA/g) && ($state eq 'SA'))
      {
         $status = $selected;
      }
      elsif (($parameter =~ /NT/g) && ($state eq 'NT'))
      {
         $status = $selected;
      }
      elsif (($parameter =~ /TAS/g) && ($state eq 'TAS'))
      {
         $status = $selected;
      }
      elsif (($parameter =~ /ACT/g) && ($state eq 'ACT'))
      {
         $status = $selected;
      }
      elsif (($parameter =~ /QLD/g) && ($state eq 'QLD'))
      {
         $status = $selected;
      }
         
   }
   
   return $status;   
}


# -------------------------------------------------------------------------------------------------
# callback_isTyprSelected
# returns selected if the specifeid type is the parameter
sub callback_isTypeSelected
{            
   my $parameter = shift;
   my $status = undef;
   my $selected = 'selected';
   $type = param('type');
   
   if (defined $type)
   {
      if (($parameter =~ /unit/gi) && ($type == 1))
      {
         $status = $selected;
      }
      elsif (($parameter =~ /house/gi) && ($type == 4))
      {
         $status = $selected;
      }
         
   }
   
   return $status;   
}

# -------------------------------------------------------------------------------------------------
# callback_isOrderSelected
# returns selected if the specifeid order is the parameter
sub callback_isOrderSelected
{            
   my $parameter = shift;
   my $status = undef;
   my $selected = 'selected';
   $orderby = param('orderby');
   
   if (defined $state)
   {
      if (($parameter =~ /suburb/gi) && ($orderby eq 'suburb'))
      {
         $status = $selected;
      }
      elsif (($parameter =~ /sale/gi) && ($orderby eq 'sale'))
      {
         $status = $selected;
      }
      elsif (($parameter =~ /rent/gi) && ($orderby eq 'rent'))
      {
         $status = $selected;
      }
      elsif (($parameter =~ /yield/gi) && ($orderby eq 'yield'))
      {
         $status = $selected;
      }
      elsif (($parameter =~ /cashflow/g) && ($orderby eq 'cf'))
      {
         $status = $selected;
      }
         
   }
   
   return $status;   
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
   $suburbAnalysisTable = $analysisTools->getSuburbAnalysisTable();
   $propertyCategories = $analysisTools->getPropertyCategories();
   $propertyTypes = $analysisTools->getPropertyTypes();
   
   getType($analysisTools);
   getState($analysisTools);
   getSuburbIndex($analysisTools);
      
   $analysisTools->fetchAnalysisResults();
   
   $registeredCallbacks{"AnalysisDataTable"} = \&callback_suburbList;
   $registeredCallbacks{"PropertyList"} = \&callback_propertyList;
   $registeredCallbacks{"PropertyDetails"} = \&callback_propertyDetails;
   $registeredCallbacks{"isWASelected"} = \&callback_isStateSelected;
   $registeredCallbacks{"isVICSelected"} = \&callback_isStateSelected;
   $registeredCallbacks{"isNSWSelected"} = \&callback_isStateSelected;
   $registeredCallbacks{"isSASelected"} = \&callback_isStateSelected;
   $registeredCallbacks{"isNTSelected"} = \&callback_isStateSelected;
   $registeredCallbacks{"isTASSelected"} = \&callback_isStateSelected;
   $registeredCallbacks{"isACTSelected"} = \&callback_isStateSelected;
   $registeredCallbacks{"isQLDSelected"} = \&callback_isStateSelected;
   $registeredCallbacks{"isHouseSelected"} = \&callback_isTypeSelected; 
   $registeredCallbacks{"isUnitSelected"} = \&callback_isTypeSelected;
   $registeredCallbacks{"isSuburbSelected"} = \&callback_isOrderSelected;
   $registeredCallbacks{"isSaleSelected"} = \&callback_isOrderSelected;
   $registeredCallbacks{"isRentSelected"} = \&callback_isOrderSelected;
   $registeredCallbacks{"isYieldSelected"} = \&callback_isOrderSelected;
   $registeredCallbacks{"isCashflowSelected"} = \&callback_isOrderSelected;
    
   if (param('identifier'))
   {
      $html = HTMLTemplate::printTemplate("PropertyDetailsTemplate.html", \%registeredCallbacks);
   }
   else
   {
      if (!$suburbConstraintSet)
      {
         $html = HTMLTemplate::printTemplate("AnalysisControlPanelTemplate.html", \%registeredCallbacks);
      }
      else
      {
         $html = HTMLTemplate::printTemplate("SuburbDetailsTemplate.html", \%registeredCallbacks);
      }
   }
   
   $sqlClient->disconnect();
}
else
{
   print "Couldn't connect to database.";
}
      
# -------------------------------------------------------------------------------------------------

