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
                    'yield'=>"");

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
# estimate the rent for a particular property using the current analysis parameters
sub estimateRent

{      
   my $analysisTools = shift;
   my $propertyDataHashRef = shift;
   
   my $housePrice;
   my %salesMean;
   my %salesStdDev;
   my %rentalStdDev;
   my %rentalMean;                         
     
   $suburbName = $$propertyDataHashRef{'SuburbName'};       
   $suburbName =~ tr/[A-Z]/[a-z]/;      
   
   ($officialSalesMean, $officialRentalMean) = $analysisTools->fetchOfficialMeans($suburbName);
   
   # for the house price, use the lower of the two available values
   # (to give worse result)
   $housePrice = $$propertyDataHashRef{'AdvertisedPriceLower'};  
      
   
   $salesMean = $analysisTools->getSalesMeanHash();
   $salesStdDev = $analysisTools->getSalesStdDevHash();
   $rentalMean = $analysisTools->getRentalMeanHash();
   $rentalStdDev = $analysisTools->getRentalStdDevHash();
   
   if ($housePrice > 0)
   {
      #$delta = $housePrice - $$salesMean{$suburbName};
      $delta = $housePrice - $officialSalesMean;
           
      if ($$salesStdDev{$suburbName} > 0)
      {
         $ratio = $delta / $$salesStdDev{$suburbName};                 
      }
      else
      {      
         $ratio = 0;         
      }
      
         
      if ($$rentalStdDev{$suburbName} > 0)
      {
         #$estimatedRent = ($ratio * $$rentalStdDev{$suburbName}) + $$rentalMean{$suburbName};
         $estimatedRent = ($ratio * $$rentalStdDev{$suburbName}) + $officialRentalMean;         
         # round down to the nearest $10.
         $estimatedRent = int($estimatedRent / 10) * 10;         
      }
      else
      {
         $estimatedRent = 0;
      }              
      
      $estimatedYield = ($estimatedRent * 5200) /  $housePrice;      
   }       
      
   return ($estimatedRent, $estimatedYield);   
}

# -------------------------------------------------------------------------------------------------
# callback_analysisDataTable
# returns a table containing a list of all the analysis restuls
sub callback_analysisDataTable
{         
   my @suburbList;
   my $index = 0;   
   
   getOrderBy();
      
   print "<table><tr><th>Suburb</th><th>Field</th><th>Min</th><th>Mean</th><th>Median</th><th>Max</th><th>StdDev</th><th>(Sample Size)</th></tr>\n";            
   
   $analysisTools->calculateSalesAnalysis();
   $analysisTools->calculateRentalAnalysis();
   $analysisTools->calculateYield();   
      
   $noOfSales = $analysisTools->getNoOfSalesHash();
   $noOfRentals = $analysisTools->getNoOfRentalsHash();
   $salesMean = $analysisTools->getSalesMeanHash();
   $rentalMean = $analysisTools->getRentalMeanHash();
   $meanYield = $analysisTools->getMeanYieldHash();
   
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
   
      # sort the suburb names by the values of the mean                   
      foreach (sort { $$salesMean{$b} <=> $$salesMean{$a} } keys %$salesMean)           
      {                                        
          $suburbList[$index] = $_;
          $index++;
      }            
   }
   elsif ($orderBy eq 'rent')
   {
      $index = 0;
      # sort the suburb names by the values of the rental mean total
      # ie. calls sort on the keys (suburbs) of rentalsumOfSalePrices but uses <=> to compare the values of each key      
      foreach (sort { $$rentalMean{$b} <=> $$rentalMean{$a} } keys %$rentalMean)           
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
      foreach (sort { $$meanYield{$b} <=> $$meanYield{$a} } keys %$meanYield)           
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

   $minSalePrice = $analysisTools->getSalesMinHash();
   $maxSalePrice = $analysisTools->getSalesMaxHash();
   $salesStdDev = $analysisTools->getSalesStdDevHash();
   $minRentalPrice = $analysisTools->getRentalMinHash();
   $maxRentalPrice = $analysisTools->getRentalMaxHash();
   $rentalStdDev = $analysisTools->getRentalStdDevHash();
   $officialSalesMedian = $analysisTools->getOfficialSalesMedianHash();
   $officialRentalMedian = $analysisTools->getOfficialRentalMedianHash();
   
   # generate the table to display
   foreach (@suburbList)
   {      
      # $_ is the suburb name
      
      #$suburbName = URI::Escape::uri_escape($_);
      $suburbName = $_;
            
      $minPriceInstance = commify(sprintf("\$%.0f", $$minSalePrice{$_}));
      $maxPriceInstance = commify(sprintf("\$%.0f", $$maxSalePrice{$_}));
      $salesStdDevInstance = commify(sprintf("\$%.0f", $$salesStdDev{$_}));
      $rentalStdDevInstance = commify(sprintf("\$%.0f", $$rentalStdDev{$_}));     
      if ($$salesMean{$_} > 0)
      {
         $salesStdDevPercentInstance = commify(sprintf("%.2f", $$salesStdDev{$_}*100/$$salesMean{$_}));
      }
      if ($$rentalMean{$_} > 0)
      {
         $rentalStdDevPercentInstance = commify(sprintf("%.2f", $$rentalStdDev{$_}*100/$$rentalMean{$_}));
      }
      $noOfSaleListings = $$noOfSales{$_};      
      if ($noOfSaleListings > 0)
      {
         $meanPriceInstance = commify(sprintf("\$%.0f", $$salesMean{$suburbName}));
      }
      else
      {
         $meanPriceInstance = "\$0";         
      }
       
      $minRentInstance = commify(sprintf("\$%.0f", $$minRentalPrice{$_}));
      $maxRentInstance = commify(sprintf("\$%.0f", $$maxRentalPrice{$_}));
      $noOfRentListings = $$noOfRentals{$_};
      if ($noOfRentListings > 0)
      {
         $meanRentInstance = commify(sprintf("\$%.0f", $$rentalMean{$suburbName}));                  
                  
         $meanYieldInstance = sprintf("%.1f", $$meanYield{$_});
         $medianSaleInstance = commify(sprintf("\$%.0f", $$officialSalesMedian{$_}));
         $medianRentalInstance = commify(sprintf("\$%.0f", $$officialRentalMedian{$_}));         
                
         #<th>2br</th><th>3x1</th><th>3x2</th><th>4x2</th><th>4x3</th><th>5br</th></tr>\n";
         print "<tr><td rows='2'>$suburbName</td><td>Sale</td><td>$minPriceInstance</td><td>$meanPriceInstance</td><td>$medianSaleInstance</td><td>$maxPriceInstance</td><td>$salesStdDevInstance/(%$salesStdDevPercentInstance)</td><td><a href='", self_url(), "&suburb=", URI::Escape::uri_escape($suburbName),"'>$noOfSaleListings listings</a></td></tr>\n";
         print "<tr><td></td><td>Rent</td><td>$minRentInstance</td><td>$meanRentInstance</td><td>$medianRentalInstance</td><td>$maxRentInstance</td><td>$rentalStdDevInstance/(%$rentalStdDevPercentInstance)</td><td>($noOfRentListings)</td></tr>\n";
         print "<tr><td></td><td>Yield</td><td></td><td></td><td>%$meanYieldInstance</td></tr>\n";
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
   
   if ($suburbConstraintSet)
   {
      print "<table><tr><th>Address</th><th>Lower</th><th>Upper</th><th>Estimated Rent</th><th>Estimated Yield</th></tr>\n";            
   
      my $salesList = $analysisTools->getSalesDataList();         
   
      # generate the table to display
      foreach (@$salesList)
      {      
         # $_ is a reference to a hash
         
         #$suburbName = URI::Escape::uri_escape($_);      
         $suburbName = $$_{'SuburbName'};
         
         $addressInstance = $$_{'StreetNumber'}." ".$$_{'Street'}." ".$$_{'SuburbName'};
         $lowerPriceInstance = commify(sprintf("\$%.0f", $$_{'AdvertisedPriceLower'}));
         $upperPriceInstance = commify(sprintf("\$%.0f", $$_{'AdvertisedPriceUpper'}));         
         ($estimatedRent, $estimatedYield) = estimateRent($analysisTools, $_);
         $estimatedRentInstance = commify(sprintf("\$%.0f", $estimatedRent));
         $estimatedYieldInstance = sprintf("%.1f", $estimatedYield);
         
         #<th>2br</th><th>3x1</th><th>3x2</th><th>4x2</th><th>4x3</th><th>5br</th></tr>\n";
         print "<tr><td>$addressInstance</td><td>$lowerPriceInstance</td><td>$upperPriceInstance</td><td>$estimatedRentInstance</td><td>%$estimatedYieldInstance</td></tr>\n";            
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

