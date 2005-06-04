#!/usr/bin/perl
# 24 Apr 05
# Parses the directory of logged OriginatingHTML files and upgrades them to the current version
# in this case, prefixes each originatingHTML file with a header
#
# History:
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
use HTMLSyntaxTree;
use SQLClient;
use SuburbProfiles;
#use URI::URL;
use DebugTools;
use DocumentReader;
use AdvertisedPropertyProfiles;
use AgentStatusServer;
use PropertyTypes;
use DomainRegions;
use Validator_RegExSubstitutes;
use MasterPropertyTable;
use StatusTable;
use SuburbAnalysisTable;
use Time::Local;

# -------------------------------------------------------------------------------------------------    

my $SOURCE_NAME = undef;


my $printLogger = PrintLogger::new("", "upgradeOriginatingHTML.stdout", 1, 1, 0);

$printLogger->printHeader("Upgrade OriginatingHTML files.\n");

my $content;
     
# initialise the objects for communicating with database tables
($sqlClient, $advertisedSaleProfiles, $advertisedRentalProfiles, $propertyTypes, $suburbProfiles, $domainRegions, 
      $originatingHTML, $validator_RegExSubstitutes, $masterPropertyTable) = initialiseTableObjects();
 
my $originatingHTML = OriginatingHTML::new($sqlClient);
      
$sqlClient->connect();          


$printLogger->print("   Fetching OriginatingHTML table...\n");
   
# get the content of the table
@selectResult = $sqlClient->doSQLSelect("select DateEntered, Identifier, SourceURL from OriginatingHTML");
   
$length = @selectResult;
$printLogger->print("   $length records.\n");

$printLogger->print("   Searching for OriginatingHTML and upgrading found files...\n");
   
$recordsParsed = 0;
$recordsFound = 0;
# loop through each OriginatingHTML file and read it in
foreach (@selectResult)
{
   $identifier = $$_{'Identifier'};
   $localTime = $$_{'DateEntered'};
   $url = $$_{'SourceURL'};
   
   # read the source originating HTML file
   $content = $originatingHTML->readHTMLContent($identifier, 1);
   if ($content)
   {
      $recordsFound++;
      print "$identifier timestamp=$localTime\n";
   
      # write the content back again with the prefix
      $originatingHTML->saveHTMLContent($identifier, $content, $url, $localTime);
   }
   $recordsParsed++;
}
         
print "Updgraded $recordsFound of $recordsParsed total records ", $recordsParsed-$recordsFound, " files were missing)\n";

$sqlClient->disconnect();


$printLogger->printFooter("Finished\n");

exit 0;
# -------------------------------------------------------------------------------------------------

# initialiseTableObjects
# instantiates table objects
#
# Purpose:
#  initialisation of the agent
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
#  SQL client
#  list of tables
#    
sub initialiseTableObjects
{
   my $sqlClient = SQLClient::new(); 
    
   my $advertisedRentalProfiles = AdvertisedPropertyProfiles::new($sqlClient, 'Rentals');
   my $advertisedSaleProfiles = AdvertisedPropertyProfiles::new($sqlClient, 'Sales');
   my $propertyTypes = PropertyTypes::new($sqlClient);
   my $suburbProfiles = SuburbProfiles::new($sqlClient);
   my $domainRegions = DomainRegions::new($sqlClient);
   my $originatingHTML = OriginatingHTML::new($sqlClient);
   my $validator_RegExSubstitutes = Validator_RegExSubstitutes::new($sqlClient);
   my $masterPropertyTable = MasterPropertyTable::new($sqlClient);

   return ($sqlClient, $advertisedSaleProfiles, $advertisedRentalProfiles, $propertyTypes, $suburbProfiles, $domainRegions, $originatingHTML, $validator_RegExSubstitutes, $masterPropertyTable);
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

