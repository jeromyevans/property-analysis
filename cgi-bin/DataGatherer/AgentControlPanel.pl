#!/usr/bin/perl
# Written by Jeromy Evans
# Started 16 May 2004
# 
# Description:
#   Provides controls for starting and stopping the DataGatherer agent via CGI
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
use AgentStatusClient;

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

my $SALES_AGENT = "/cgi-bin/DataGatherer/GetAdvertisedSales.pl";
my $RENTAL_AGENT = "/cgi-bin/DataGatherer/GetAdvertisedRentals.pl";

# -------------------------------------------------------------------------------------------------
# callback_suburbTable
# returns a table containing a list of all the suburbs
sub callback_suburbTable
{   
   my @tableLines;
   my $index = 0;
   my $agentStatusClient;
   
   open(SUBURB_FILE, "<suburblist.txt") || print "Can't open list: $!"; 
         
   $index = 0;
   # loop through the content of the file
   while (<SUBURB_FILE>) # read a line into $_
   {
      # remove end of line marker from $_
      chomp;
	          
      $suburbList[$index] = $_;

      $index++;                    
   }
   
   close(SUBURB_FILE);
      
   $index = 0;            
   #$tableLines[$index++] = "<table><tr><th>Suburb</th><th>Reached</th><th>SalesAgent</th><th>Reached</th><th>RentalAgent</th></tr>\n";      
   print "<table><tr><th>Suburb</th><th>Reached</th><th>SalesAgent</th><th>Reached</th><th>RentalAgent</th></tr>\n";    
   foreach (@suburbList)
   {        
      $portA = $index + 20000;
      $portB = $index + 21000;            
      
      $agentStatusClientA = AgentStatusClient::new($portA);      
      %agentStatusA = $agentStatusClientA->getStatus();
      
#      DebugTools::printHash("agentStatusA", \%agentStatusA);
      
      $agentStatusClientB = AgentStatusClient::new($portB);
      %agentStatusB = $agentStatusClientB->getStatus();
      
#      DebugTools::printHash("agentStatusB", \%agentStatusB);
      
      $encodedName = URI::Escape::uri_escape($_);
      
      #$tableLines[$index] = "<tr><td>$_</td><td>". $agentStatusA{'reached'}. "</td><td><a href=\"$SALES_AGENT?start=1&startrange=$encodedName&endrange=$encodedName&html=1&port=$portA\">START</a></td><td>".$agentStatusA{'reached'}."</td><td><a href=\"$RENTAL_AGENT?start=1&startrange=$encodedName&endrange=$encodedName&html=1&port=$portB\">START</a></td></tr>\n";
      print "<tr><td>$_</td><td>".$agentStatusA{'reached'}."</td><td><a href=\"$SALES_AGENT?start=1&startrange=$encodedName&endrange=$encodedName&html=1&port=$portA\">START</a></td><td>".$agentStatusB{'reached'}."</td><td><a href=\"$RENTAL_AGENT?start=1&startrange=$encodedName&endrange=$encodedName&html=1&port=$portB\">START</a></td></tr>\n";
      $index++;      
   }
      
   #$tableLines[$index] = "</table>\n";
   print "</table>\n";
      
   foreach (@tableLines)
   {
      $response .= $_;
   }   
      
   return $response;   
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

   $registeredCallbacks{"SuburbTable"} = \&callback_suburbTable;       
      
   $html = HTMLTemplate::printTemplate("AgentControlPanelTemplate.html", \%registeredCallbacks);

   #print $html;  
   
   $sqlClient->disconnect();
}
else
{
   print "Couldn't connect to database.";
}
      
# -------------------------------------------------------------------------------------------------

