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
use AdvertisedRentalProfiles;
use AdvertisedSaleProfiles;

use HTMLTemplate;
#use URI::Escape::uri_escape;
use URI;

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
   my $bedroomsParam = param('bedrooms');

   if ((defined $bedroomsParam) && (exists $validBedrooms{$bedroomsParam}))
   
   {     
      $bedroomsSearch = "and Bedrooms = $bedroomsParam";
      $bedroomsDescription = $bedroomsParam;
   }
   else
   {
      $bedroomsSearch = "";
      $bedroomsDescription = "any";
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
   my $bathroomsParam = param('bathrooms');
      
   if ((defined $bathroomsParam) && (exists $validBathrooms{$bathroomsParam}))
   {     
      $bathroomsSearch = "and Bathrooms = $bathroomsParam";
      $bathroomsDescription = $bathroomsParam;
   }
   else
   {            
      $bathroomsSearch = "";
      $bathroomsDescription = "any";
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
   my $typeParam = param('type');
           
   if ((defined $typeParam) && (exists $validTypes{$typeParam}))
   {   
      if ($typeParam == 'house')
      {
         $typeSearch = "Type like '%house%'";
         $typeDescription = "Houses";
      }
      elsif ($typeParam == 'unit') 
      {
         $typeSearch = "Type like '%Apartment%' or Type like '%Flats%' or Type like '%Unit%' or Type like '%Townhouse%' or Type like '%Villa%'";
         $typeDescription = "Units, Flats, Townhouses, Villas etc";
      }
      else
      {
         $typeSearch = "Type not like '%Land%' and Type not like '%Lifestyle%'";
         $typeDescription = "any";
      }
   }
   else
   {
      $typeSearch = "Type not like '%Land%' and Type not like '%Lifestyle%'";
      $typeDescription = "any";
   }   
   
   return $typeDescription;
}

# ------------------------------------------------------------------------------------------------
# This hash defines valid keys for the orderby parameter
my %validOrderBy = ('suburb'=>"",
                    'sale'=>"",
                    'rent'=>"");

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
# callback_analysisDataTable
# returns a table containing a list of all the analysis restuls
sub callback_analysisDataTable
{   
   my @tableLines;
   my $index = 0;
   my $agentStatusClient;
   my @selectResults;
             
   $index = 0;           
                 
   getBedrooms();
   getBathrooms();
   getType();
   getOrderBy();
      
   print "<table><tr><th>Suburb</th><th>Field</th><th>Min</th><th>Mean</th><th>Max</th><th>(Sample Size)</th></tr>\n";      
      
   @selectResults = $sqlClient->doSQLSelect("select SuburbName, AdvertisedPriceLower, AdvertisedPriceUpper, Bedrooms, Bathrooms from AdvertisedSaleProfiles where ".$typeSearch." ".$bedroomsSearch." ".$bathroomsSearch." order by SuburbName, Bedrooms, Bathrooms");   
      
   $length = @selectResults;
   
   #selectResults is a big array of hashes      
   foreach (@selectResults)
   {
      $suburbName = $$_{'SuburbName'};
      $suburbName =~ tr/[A-Z]/[a-z]/;
      
      # use the max of the two prices (sometimes only the lower is defined)
      if (defined $$_{'AdvertisedSalePriceHigher'})
      {
         $highPrice = $$_{'AdvertisedPriceHigher'};
      }
      else
      {
         $highPrice = $$_{'AdvertisedPriceLower'};  
      }              
         
      # calculate the total of price for calculation of the mean
      if (defined $meanTotal{$suburbName})
      {
         $meanTotal{$suburbName} += $highPrice;
      }
      else
      {
         $meanTotal{$suburbName} = $highPrice;
      }      
      
      # count the number of listings in the suburb
      if (defined $listings{$suburbName})
      {         
         $listings{$suburbName} += 1;
      }
      else
      {
         $listings{$suburbName} = 1;
      }
                  
      # record the lowest-high price listed for this suburb
      if ((!defined $minPrice{$suburbName}) || ($highPrice < $minPrice{$suburbName}))
      {
         $minPrice{$suburbName} = $highPrice;
      }
      
      # record the highest-high price listed for this suburb
      if ((!defined $maxPrice{$suburbName}) || ($highPrice > $maxPrice{$suburbName}))
      {
         $maxPrice{$suburbName} = $highPrice;
      }      
   }         
   
   # ------------ Get rental properties -----------------
   @selectResults = $sqlClient->doSQLSelect("select SuburbName, AdvertisedWeeklyRent, Bedrooms, Bathrooms from AdvertisedRentalProfiles where ".$typeSearch." ".$bedroomsSearch." ".$bathroomsSearch." order by SuburbName, Bedrooms, Bathrooms");      
   
   $length = @selectResults;
      
   #selectResults is a big array of hashes      
   foreach (@selectResults)
   {
   
      $suburbName = $$_{'SuburbName'};
      $suburbName =~ tr/[A-Z]/[a-z]/;
   
      # calculate the total of price for calculation of the mean
      if (defined $rentalMeanTotal{$suburbName})
      {
         $rentalMeanTotal{$suburbName} += $$_{'AdvertisedWeeklyRent'};
      }
      else
      {
         $rentalMeanTotal{$suburbName} = $$_{'AdvertisedWeeklyRent'};
      }      
      
      # count the number of listings in the suburb
      if (defined $rentalListings{$suburbName})
      {         
         $rentalListings{$suburbName} += 1;
      }
      else
      {
         $rentalListings{$suburbName} = 1;
      }
                  
      # record the lowest-high price listed for this suburb
      if ((!defined $rentalMinPrice{$suburbName}) || ($$_{'AdvertisedWeeklyRent'} < $rentalMinPrice{$suburbName}))
      {
         $rentalMinPrice{$suburbName} = $$_{'AdvertisedWeeklyRent'};
      }
      
      # record the highest-high price listed for this suburb
      if ((!defined $rentalMaxPrice{$suburbName}) || ($$_{'AdvertisedWeeklyRent'} > $rentalMaxPrice{$suburbName}))
      {
         $rentalMaxPrice{$suburbName} = $$_{'AdvertisedWeeklyRent'};
      }      
   }
         
   # loop through all the suburbs again to calculate the yield
   foreach (keys %listings)
   {   
      if ($minPrice{$_} > 0)
      {         
         $minYield{$_} = ($rentalMinPrice{$_} * 5200) / $minPrice{$_};      
      }
      else
      {
         $minYield{$_} = 0;
      }
      if ($maxPrice{$_} > 0)
      {
         $maxYield{$_} = ($rentalMaxPrice{$_} * 5200) / $maxPrice{$_};
      }
      else
      {
         $maxYield{$_} = 0;
      }
      if (($rentalListings{$_} > 0) && ($listings{$_} > 0))
      {
         $meanYield{$_} = (($rentalMeanTotal{$_} / $rentalListings{$_}) * 5200) / ($meanTotal{$_} / $listings{$_});
      }
      else
      {
         $meanYield{$_} = 0;
      }
   }
         
   # get the list of suburbs from the keys of listings (any of the hashes would do)
   # and sort it into alphabetical order   
   if ($orderBy eq 'suburbs')
   {
      # order by suburbs alphabetically
      @suburbList = sort keys %listings;
   }
   elsif ($orderBy eq 'sale')
   {            
      $index = 0;
      # sort the suburb names by the values of the mean total
      # ie. calls sort on the keys (suburbs) of meanTotal but uses cmp to compare the values of each key      
      foreach (sort { $meanTotal{$a} cmp $meanTotal{$b} } keys %meanTotal)           
      {                              
          $suburbList[$index] = $_;
          $index++;
      }            
   }
   elsif ($orderby eq 'rent')
   {
      $index = 0;
      # sort the suburb names by the values of the rental mean total
      # ie. calls sort on the keys (suburbs) of rentalmeanTotal but uses cmp to compare the values of each key      
      foreach (sort { $rentalMeanTotal{$a} cmp $rentalMeanTotal{$b} } keys %rentalMeanTotal)           
      {                              
          $suburbList[$index] = $_;
          $index++;
      }      
   }
   elsif ($orderby eq 'yield')
   {
      $index = 0;
      # sort the suburb names by the values of the yield
      # ie. calls sort on the keys (suburbs) of yeild but uses cmp to compare the values of each key      
      foreach (sort { $meanYield{$a} cmp $meanYield{$b} } keys %meanYield)           
      {                              
          $suburbList[$index] = $_;
          $index++;
      }      
   }
   else
   {
      # order by suburbs alphabetically
      @suburbList = sort keys %listings;
   }   
   
   #DebugTools::printList("suburbList", \@suburbList);
   
   # generate the table to display
   foreach (@suburbList)
   {      
      # $_ is the suburb name
      
      #$suburbName = URI::Escape::uri_escape($_);
      $suburbName = $_;
      $minPriceInstance = commify(sprintf("\$%.0f", $minPrice{$_}));
      $maxPriceInstance = commify(sprintf("\$%.0f", $maxPrice{$_}));
      $noOfSaleListings = $listings{$_};
      if ($noOfSaleListings > 0)
      {
         $meanPriceInstance = commify(sprintf("\$%.0f", $meanTotal{$_} / $noOfSaleListings));
      }
      else
      {
         $meanPriceInstance = "\$0";
      }
       
      $minRentInstance = commify(sprintf("\$%.0f", $rentalMinPrice{$_}));
      $maxRentInstance = commify(sprintf("\$%.0f", $rentalMaxPrice{$_}));
      $noOfRentListings = $rentalListings{$_};
      if ($noOfRentListings > 0)
      {
         $meanRentInstance = commify(sprintf("\$%.0f", $rentalMeanTotal{$_} / $noOfRentListings));                  
         
         $minYieldInstance = sprintf("%.1f", $minYield{$_});
         $maxYieldInstance = sprintf("%.1f", $maxYield{$_});
         $meanYieldInstance = sprintf("%.1f", $meanYield{$_});
                
         #<th>2br</th><th>3x1</th><th>3x2</th><th>4x2</th><th>4x3</th><th>5br</th></tr>\n";
         print "<tr><td rows='2'>$suburbName</td><td>Sale</td><td>$minPriceInstance</td><td>$meanPriceInstance</td><td>$maxPriceInstance</td><td>($noOfSaleListings)</td></tr>\n";
         print "<tr><td></td><td>Rent</td><td>$minRentInstance</td><td>$meanRentInstance</td><td>$maxRentInstance</td><td>($noOfRentListings)</td></tr>\n";
         print "<tr><td></td><td>Yield</td><td>%$minYieldInstance</td><td>%$meanYieldInstance</td><td>%$maxYieldInstance</td><td></td></tr>\n";
      }
   }
      
   print "</table>\n";
      
   return undef;   
}
  
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

print header();

$sqlClient = SQLClient::new(); 
$advertisedSaleProfiles = AdvertisedSaleProfiles::new($sqlClient);
$advertisedRentalProfiles = AdvertisedRentalProfiles::new($sqlClient);
$suburbProfiles = SuburbProfiles::new($sqlClient);

if ($sqlClient->connect())
{	      
   $registeredCallbacks{"AnalysisDataTable"} = \&callback_analysisDataTable;
   $registeredCallbacks{"Bedrooms"} = \&callback_bedrooms;
   $registeredCallbacks{"Bathrooms"} = \&callback_bathrooms;
   $registeredCallbacks{"Type"} = \&callback_type;       
      
   $html = HTMLTemplate::printTemplate("AnalysisControlPanelTemplate.html", \%registeredCallbacks);

   #print $html;  
   
   $sqlClient->disconnect();
}
else
{
   print "Couldn't connect to database.";
}
      
# -------------------------------------------------------------------------------------------------

