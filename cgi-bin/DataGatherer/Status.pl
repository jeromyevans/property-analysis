#!/usr/bin/perl
# Written by Jeromy Evans
# Started 9 May 2004
# 
# Description:
#   
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
use CGI qw(:standard);
use HTTPClient;
use SQLClient;
use SuburbProfiles;
#use URI::URL;
use DebugTools;
use AdvertisedRentalProfiles;
use AdvertisedSaleProfiles;

use HTMLTemplate;

# -------------------------------------------------------------------------------------------------

my $sqlClient;
my $advertisedSaleProfiles;
my $advertisedRentalProfiles;
my $suburbProfiles;

# -------------------------------------------------------------------------------------------------
# callback_noOfAdvertisedSales
# returns the number of advertied sales in the database
sub callback_noOfAdvertisedSales
{
   my $noOfEntries = 0;
   if ($advertisedSaleProfiles)
   {      
      $noOfEntries = $advertisedSaleProfiles->countEntries();
   }
   
   return $noOfEntries;   
}  

# -------------------------------------------------------------------------------------------------
# callback_noOfAdvertisedRentals
# returns the number of advertied sales in the database
sub callback_noOfAdvertisedRentals
{   
   my $noOfEntries = 0;
   if ($advertisedRentalProfiles)
   {   
      $noOfEntries = $advertisedRentalProfiles->countEntries();
   }
   
   return $noOfEntries;   
}  
# -------------------------------------------------------------------------------------------------
# callback_noOfAdvertisedRentals
# returns the number of advertied sales in the database
sub callback_noOfSuburbs
{      
   my $noOfEntries = 0;
   if ($suburbProfiles)
   {
      $noOfEntries = $suburbProfiles->countEntries();
   }
   
   return $noOfEntries;   
}  

# -------------------------------------------------------------------------------------------------

print header();

$sqlClient = SQLClient::new(); 
$advertisedSaleProfiles = AdvertisedSaleProfiles::new($sqlClient);
$advertisedRentalProfiles = AdvertisedRentalProfiles::new($sqlClient);
$suburbProfiles = SuburbProfiles::new($sqlClient);

if ($sqlClient->connect())
{	      

   $registeredCallbacks{"NoOfRentals"} = \&callback_noOfAdvertisedRentals;
   $registeredCallbacks{"NoOfSales"} = \&callback_noOfAdvertisedSales;
   $registeredCallbacks{"NoOfSuburbs"} = \&callback_noOfSuburbs;

   $html = loadTemplate("StatusTemplate.html", \%registeredCallbacks);

   print $html;  
   
   $sqlClient->disconnect();
}
else
{
   print "Couldn't connect to database.";
}
      
# -------------------------------------------------------------------------------------------------

