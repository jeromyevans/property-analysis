#!/usr/bin/perl
# 31 Mar 04
# Parses the detailed real-estate sales information to extract fields
#
#
# 16 May 04 - bugfixed algorithm checking search range
#           - bugfix parseSearchDetails - was looking for wrong keyword to identify page
#           - bugfix wasn't using parameters{'url'} as start URL
#           - added AgentStatusServer support to send status info over a TCP connection
#
#   9 July 2004 - Merged with LogTable to record encounter information (date last encountered, url, checksum)
#  to support searches like get records 'still advertised'
#  25 July 2004 - added support for instanceID and transactionNo parameters in parser callbacks
#  30 July 2004 - changed parseSearchDetails to only parse the page if it contains 'Property Details' - was encountering 
#   empty responses from the server that yielded an empty database entry.
#  21 August 2004 - changed parseSearchForm to set the main area to all of the state instead of just perth metropolitan.
#  21 August 2004 - added requirement to specify state as a parameter - used for postcode lookup
#  28 September 2004 - use the thread command to specify a threadID to continue from - this allows the URL stack and cookies
#   from a previous instance to be reused in the same 'thread'.  Implemented to support automatic restart of a thread in a loop and
#   automatic exit if an instance runs out of memory.  (exit, then restart from same point)
#  28 September 2004 - Combined multiple sources to publishedMaterialScanner instead of one for each type and source of adverisement in 
#   to leverage off common code instead of duplicating it
#                    - improved parameter parsing to support generic functions.  Generic configuration file for parameters, checking
#   and reporting of mandatory paramneters.
#  29 October 2004 - added support for DomainRegionsn table - needed to parse domain website
#  27 November 2004 - added support for the OriginatingHTML table - used to log the HTMLRecord that created a table entry
#    as part of the major change to support ChangeTables
#  28 November 2004 - added support for Validator_RegExSubstitutes table - used to store regular expressions and substitutions
#    for use by the validation functions.  The intent it is allow new substititions to be added dynamically without 
#    modifying the code (ie. from the exception reporting/administration page)
#  30 November 2004 - added support for the WorkingView and CacheView tables in the maintanence tasks.  The workingView is 
#   the baseview with aggregated changes applied.  The CacheView is a subset of fields of the original table used to 
#   improve the speed of queries during DataGathering (checkIfTupleExists).
#  7 December 2004 - added maintenance task supporting construction of the MasterPropertyComponentsXRef table from the
#   componentOf relationships in the workingView
# To do:
#
#  RUN PARSERS IN A SEPARATE PROCESS | OR RUN DECODER (eg. htmlsyntaxtree) in separate process - need way to pass data in and out of the
#   process though
#  USE DATABASE TO SPECIFY PARSERS AND RECOVERY POINTS
#   NEED TO GET AGENT NAME
#  - front page for monitoring progress
#
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
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
use WebsiteParser_Common;
use WebsiteParser_REIWASales;
use WebsiteParser_DomainSales;
use WebsiteParser_REIWARentals;
use WebsiteParser_REIWASuburbs;
use WebsiteParser_RealEstateSales;
use WebsiteParser_DomainRentals;
use WebsiteParser_RealEstateRentals;
use DomainRegions;
use Validator_RegExSubstitutes;
use MasterPropertyTable;

# -------------------------------------------------------------------------------------------------    
my %parameters = undef;

# load/read parameters for the application
($parseSuccess, %parameters) = parseParameters();
my $printLogger = PrintLogger::new($parameters{'agent'}, $parameters{'instanceID'}.".stdout", 1, $parameters{'useText'}, $parameters{'useHTML'});
my $statusServer;

$printLogger->printHeader($parameters{'agent'}."\n");

if (($parseSuccess) && (!($parameters{'command'} =~ /maintenance/i)))
{
   # if a status port has been specified, start the TCP server
   if ($parameters{'statusPort'})
   {      
      $statusServer = AgentStatusServer::new($parameters{'statusPort'});
      $statusServer->setStatus("running", "1");
      $statusServer->start();
      $printLogger->print("   main: started agent status server (port=", $parameters{'statusPort'}, ")\n");
   }            
   
   # initialise the objects for communicating with database tables
   ($sqlClient, $advertisedSaleProfiles, $advertisedRentalProfiles, $propertyTypes, $suburbProfiles, $domainRegions, 
      $originatingHTML, $validator_RegExSubstitutes, $masterPropertyTable) = initialiseTableObjects();
 
   # enable logging to disk by the SQL client
   $sqlClient->enableLogging($parameters{'instanceID'});
   $sqlClient->connect();
   
   # hash of table objects - the key's are only significant to the local callback functions   
   $myTableObjects{'advertisedSaleProfiles'} = $advertisedSaleProfiles;
   $myTableObjects{'advertisedRentalProfiles'} = $advertisedRentalProfiles;
   $myTableObjects{'propertyTypes'} = $propertyTypes;
   $myTableObjects{'suburbProfiles'} = $suburbProfiles;
   $myTableObjects{'domainRegions'} = $domainRegions;
   $myTableObjects{'originatingHTML'} = $originatingHTML;
   $myTableObjects{'validator_RegExSubstitutes'} = $validator_RegExSubstitutes;
   $myTableObjects{'masterPropertyTable'} = $masterPropertyTable;
   
   # parsed into the parser functions
   $parameters{'printLogger'} = $printLogger;
   
   # depending on the command specified, initialise HTML parsers
   if ($parameters{'config'} =~ /REIWAsales/i)
   {
      $myParsers{"searchdetails"} = \&parseREIWASalesSearchDetails;
      $myParsers{"search.cfm"} = \&parseREIWASalesSearchForm;
      $myParsers{"content-home"} = \&parseREIWASalesHomePage;
      $myParsers{"searchquery"} = \&parseREIWASalesSearchQuery;
      $myParsers{"searchlist"} = \&parseREIWASalesSearchList;
   }
   else
   {
      if ($parameters{'config'} =~ /Domainsales/i)
      {
         $myParsers{"advancedsearch"} = \&parseDomainSalesChooseState;
         $myParsers{"ChooseRegions"} = \&parseDomainSalesChooseRegions;
         $myParsers{"ChooseSuburbs"} = \&parseDomainSalesChooseSuburbs;   
         $myParsers{"SearchResults"} = \&parseDomainSalesSearchResults;   
         $myParsers{"PropertyDetails"} = \&parseDomainSalesPropertyDetails;
      }
      else
      {
         if ($parameters{'config'} =~ /REIWArentals/i)
         {
            $myParsers{"searchdetails"} = \&parseREIWARentalsSearchDetails;
            $myParsers{"search.cfm"} = \&parseREIWARentalsSearchForm;
            $myParsers{"content-home"} = \&parseREIWARentalsHomePage;
            $myParsers{"searchquery"} = \&parseREIWARentalsSearchQuery;
            $myParsers{"searchlist"} = \&parseREIWARentalsSearchList;
         }
         else
         {
            if ($parameters{'config'} =~ /REIWAsuburbs/i)
            {
               $myParsers{"content-home"} = \&parseREIWASuburbsHomePage;
               $myParsers{"content-suburb.cfm"} = \&parseREIWASuburbLetters;
               $myParsers{"content-suburb-letter"} = \&parseREIWASuburbNames;
               $myParsers{"content-suburb-detail"} = \&parseREIWASuburbProfilePage;
            }
            else
            {
               if ($parameters{'config'} =~ /RealEstateSales/i)
               {
                  $myParsers{"rsearch?a=sf&"} = \&parseRealEstateSearchForm;
                  $myParsers{"rsearch?a=s&"} = \&parseRealEstateSearchResults;
                  $myParsers{"rsearch?a=d&"} = \&parseRealEstateSearchResults;
                  $myParsers{"rsearch?a=o&"} = \&parseRealEstateSearchDetails;
               }
               else
               {
                  if ($parameters{'config'} =~ /DomainRentals/i)
                  {
                     $myParsers{"advancedsearch"} = \&parseDomainRentalChooseState;
                     $myParsers{"ChooseRegions"} = \&parseDomainRentalChooseRegions;
                     $myParsers{"ChooseSuburbs"} = \&parseDomainRentalChooseSuburbs;   
                     $myParsers{"SearchResults"} = \&parseDomainRentalSearchResults;   
                     $myParsers{"PropertyDetails"} = \&parseDomainRentalPropertyDetails;
                  }
                  else
                  {
                     if ($parameters{'config'} =~ /RealEstateRentals/i)
                     {
                        $myParsers{"rsearch?a=sf&"} = \&parseRealEstateRentalsSearchForm;
                        $myParsers{"rsearch?a=s&"} = \&parseRealEstateRentalsSearchResults;
                        $myParsers{"rsearch?a=d&"} = \&parseRealEstateRentalsSearchResults;
                        $myParsers{"rsearch?a=o&"} = \&parseRealEstateRentalsSearchDetails;
                     }
                  }
               }
            }
         }
      }
   }
   
   my $myDocumentReader = DocumentReader::new($parameters{'agent'}, $parameters{'instanceID'}, $parameters{'url'}, $sqlClient, 
      \%myTableObjects, \%myParsers, $printLogger, $parameters{'thread'}, \%parameters);
      
   #if ($parameters{'proxy'})
   #{
   #   $myDocumentReader->setProxy($parameters{'proxy'});
   #}
   #$myDocumentReader->setProxy("http://localhost:8080/");
   $myDocumentReader->run($parameters{'command'});
   
   $sqlClient->disconnect();
 
}
else
{
   if ($parameters{'command'} =~ /maintenance/i)
   {
      doMaintenance($printLogger, \%parameters);
   }
   else
   {
      $printLogger->print("   main: exit due to parameter error\n");
   }
}

$printLogger->printFooter("Finished\n");

# -------------------------------------------------------------------------------------------------
# parserWrapper
# parser that just displays the content of a response 
#
# Purpose:
#  testing
#
# Parameters:
#  DocumentReader
#  HTMLSyntaxTree to use
#  String URL
#
# Constraints:
#  nil
#
# Updates:
#  database
#
# Returns:
#  a list of HTTP transactions or URL's.
#    
sub parserWrapper

{	
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;         
   my $instanceID = shift;   
   my $transactionNo = shift;
   my @transactionList;
   
   # get the value from the hash with the pattern matching the callback function
	# the value in the cash is a code reference (to the callback function)		            
   #my $callbackFunction = $$parserHashRef{$parserPatternList[$parserIndex]};		  		  
   #my @callbackTransactionStack = &$callbackFunction($this, $htmlSyntaxTree, $url, $this->{'instanceID'}, $this->{'transactionNo'});
		  
   return @callbackTransactionStack;
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
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

sub doMaintenance
{   
   my $printLogger = shift;   
   my $parametersRef = shift;
   my $actionOk = 0;
   
   my $sqlClient = SQLClient::new(); 
   my $advertisedSaleProfiles = AdvertisedPropertyProfiles::new($sqlClient, 'Sales');
   my $propertyTypes = PropertyTypes::new($sqlClient);
   
   my $targetSQLClient = SQLClient::new($$parametersRef{'database'});
   my $targetAdvertisedSaleProfiles = AdvertisedPropertyProfiles::new($targetSQLClient, 'Sales');
  
   if ($$parametersRef{'action'} =~ /tidysale/i)
   {
      $printLogger->print("---Performing Maintenance - Tidy Sales---\n");
      maintenance_TidySaleContents($printLogger, $$parametersRef{'instanceID'}, $$parametersRef{'database'});
      $printLogger->print("---Finished Maintenance---\n");
      $actionOk = 1;
   }
   
   if ($$parametersRef{'action'} =~ /tidyrental/i)
   {
      $printLogger->print("---Performing Maintenance - Tidy Rentals---\n");
      maintenance_TidyRentalContents($printLogger, $$parametersRef{'instanceID'}, $$parametersRef{'database'});
      $printLogger->print("---Finished Maintenance---\n");
      $actionOk = 1;

   }
   
   if ($$parametersRef{'action'} =~ /duplicatesale/i)
   {
      $printLogger->print("---Performing Maintenance - Delete duplicate sales ---\n");            
      maintenance_DeleteSaleDuplicates($printLogger, $$parametersRef{'instanceID'}, $$parametersRef{'database'});            
      $printLogger->print("---Finished Maintenance---\n");
      $actionOk = 1;
   }
   
   if ($$parametersRef{'action'} =~ /duplicaterental/i)
   {
      $printLogger->print("---Performing Maintenance - Delete duplicate rentals ---\n");            
      maintenance_DeleteRentalDuplicates($printLogger, $$parametersRef{'instanceID'}, $$parametersRef{'database'});            
      $printLogger->print("---Finished Maintenance---\n");
      $actionOk = 1;
   }
   
   if ($$parametersRef{'action'} =~ /validatesale/i)
   {
      $printLogger->print("---Performing Maintenance - Validate Sales---\n");
      maintenance_ValidateSaleContents($printLogger, $$parametersRef{'instanceID'}, $$parametersRef{'database'});
      $printLogger->print("---Finished Maintenance---\n");
      $actionOk = 1;
   }
   
   if ($$parametersRef{'action'} =~ /ConstructWorkingViewSales/i)
   {
      $printLogger->print("---Performing Maintenance - Construct Working View---\n");
      maintenance_ConstructWorkingViewSales($printLogger, $$parametersRef{'instanceID'}, $$parametersRef{'database'});
      $printLogger->print("---Finished Maintenance---\n");
      $actionOk = 1;
   }
   
   if ($$parametersRef{'action'} =~ /ConstructCacheViewSales/i)
   {
      $printLogger->print("---Performing Maintenance - Construct Cache View---\n");
      maintenance_ConstructCacheViewSales($printLogger, $$parametersRef{'instanceID'}, $$parametersRef{'database'});
      $printLogger->print("---Finished Maintenance---\n");
      $actionOk = 1;
   }
   
   if ($$parametersRef{'action'} =~ /ConstructWorkingViewRentals/i)
   {
      $printLogger->print("---Performing Maintenance - Construct Working View---\n");
      maintenance_ConstructWorkingViewRentals($printLogger, $$parametersRef{'instanceID'}, $$parametersRef{'database'});
      $printLogger->print("---Finished Maintenance---\n");
      $actionOk = 1;
   }
   
   if ($$parametersRef{'action'} =~ /ConstructCacheViewRentals/i)
   {
      $printLogger->print("---Performing Maintenance - Construct Cache View---\n");
      maintenance_ConstructCacheViewRentals($printLogger, $$parametersRef{'instanceID'}, $$parametersRef{'database'});
      $printLogger->print("---Finished Maintenance---\n");
      $actionOk = 1;
   }
   
   if ($$parametersRef{'action'} =~ /ConstructPropertyTable/i)
   {
      $printLogger->print("---Performing Maintenance - Construct MasterPropertyTable---\n");
      maintenance_ConstructPropertyTable($printLogger, $$parametersRef{'instanceID'}, $$parametersRef{'database'});
      $printLogger->print("---Finished Maintenance---\n");
      $actionOk = 1;
   }
   
   if ($$parametersRef{'action'} =~ /updateProperties/i)
   {
      $printLogger->print("---Performing Maintenance - updateProperties ---\n");
      maintenance_UpdateProperties($printLogger, $$parametersRef{'instanceID'}, $$parametersRef{'database'});
      $printLogger->print("---Finished Maintenance---\n");
      $actionOk = 1;
   }
   
   if ($$parametersRef{'action'} =~ /_rebuild/i)
   {
      $printLogger->print("---Performing Maintenance - rebuilding!!! ---\n");
      maintenance_Rebuild($printLogger, $$parametersRef{'instanceID'}, $$parametersRef{'database'});
      $printLogger->print("---Finished Maintenance---\n");
      $actionOk = 1;
   }
   
   
   if ($$parametersRef{'action'} =~ /constructXRef/i)
   {
      $printLogger->print("---Performing Maintenance - constructing Property->Components XRef ---\n");
      maintenance_ConstructXRef($printLogger, $$parametersRef{'instanceID'}, $$parametersRef{'database'});
      $printLogger->print("---Finished Maintenance---\n");
      $actionOk = 1;
   }
   
   if ($$parametersRef{'action'} =~ /constructMasterComponents/i)
   {
      $printLogger->print("---Performing Maintenance - constructing Master Components for Properties ---\n");
      maintenance_ConstructMasterComponents($printLogger, $$parametersRef{'instanceID'}, $$parametersRef{'database'});
      $printLogger->print("---Finished Maintenance---\n");
      $actionOk = 1;
   }
   
   if (!$actionOk)
   {
      $printLogger->print("maintenance: requested action isn't recognised\n");
      $printLogger->print("   tidySale         - tidy & update the sales database entries\n");
      $printLogger->print("   tidyRental       - tidy & update the rental database entries\n");
      $printLogger->print("   duplicateSale    - delete duplicate sales database entries\n");
      $printLogger->print("   duplicateRental  - delete duplicate rental database entries\n");
      $printLogger->print("   validateSale     - validate sales database entries\n");
      $printLogger->print("   constructWorkingViewSales   - rebuild the WorkingView table\n");
      $printLogger->print("   constructCacheViewSales     - rebuild the CacheView table\n");
      $printLogger->print("   constructWorkingViewRentals - rebuild the WorkingView table\n");
      $printLogger->print("   constructCacheViewRentals   - rebuild the CacheView table\n");
      $printLogger->print("   constructPropertyTable      - rebuild the MasterPropertyTable\n");
      $printLogger->print("   updateProperties  - process recently added advertisements\n");
      $printLogger->print("   constructXRef     - construct the Property->Component XRef table (built by constructPropertyTable automatically)\n");            
      $printLogger->print("   constructMasterComponents   - calculate the components of MasterPropertyTable (built by constructPropertyTable automatically)\n");            
      $printLogger->print("   _rebuild          - dump all views and rebuild from raw advertisements (MANUAL CHANGES WILL BE LOST)\n");            
   }
   
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# iterates through every field of the database and runs the validate function on it
# updated fields are stored in the target database
sub maintenance_TidySaleContents
{   
   my $printLogger = shift;   
   my $instanceID = shift;
   my $targetDatabase = shift;
  
   my $sqlClient = SQLClient::new(); 
   my $advertisedSaleProfiles = AdvertisedPropertyProfiles::new($sqlClient, 'Sales');
   my $propertyTypes = PropertyTypes::new($sqlClient);
   my $targetSQLClient = SQLClient::new($targetDatabase);
   my $targetAdvertisedSaleProfiles = AdvertisedPropertyProfiles::new($targetSQLClient, 'Sales');
  
   if ($targetDatabase)
   {
      # enable logging to disk by the SQL client
      $sqlClient->enableLogging($instanceID);
      # enable logging to disk by the SQL client
      $targetSQLClient->enableLogging("t_".$instanceID);
      
      $sqlClient->connect();
      $targetSQLClient->connect();
      
      $printLogger->print("Dropping Target Database table...\n");
      $targetAdvertisedSaleProfiles->dropTable();
      
      $printLogger->print("Creating Target Database emptytable...\n");
      $targetAdvertisedSaleProfiles->createTable();
      
      $printLogger->print("Performing Source database validation...\n");
      
      @selectResult = $sqlClient->doSQLSelect("select * from AdvertisedSaleProfiles order by DateEntered");
      $length = @selectResult;
      $printLogger->print("   $length records.\n");
      foreach (@selectResult)
      {
         # $_ is a reference to a hash for the row of the table
         $oldChecksum = $$_{'checksum'};
         #$printLogger->print($$_{'DateEntered'}, " ", $$_{'SourceName'}, " ", $$_{'SuburbName'}, "(", $_{'SuburbIndex'}, ") oldChecksum=", $$_{'Checksum'});
   
         tidyRecord($sqlClient, $_);
         
         # IMPORTANT: delete the Identifier element of the hash so it's not included in the checksum - otherwise the checksum 
         # would always differ between attributes
         delete $$_{'Identifier'};
         $checksum = DocumentReader::calculateChecksum(undef, $_);
         #$printLogger->print(" | ", $$_{'SuburbName'}, "(", $$_{'SuburbIndex'}, ") newChecksum=$checksum\n");
 
         $printLogger->print("---", $$_{'DateEntered'}, " ", $$_{'SuburbName'}, "(", $$_{'SuburbIndex'}, ")\n");
         $$_{'Checksum'} = $checksum;
         
         #   $printLogger->print($$_{'Description'}, "\n");
         #DebugTools::printHash("data", $_);
         
         # do an sql insert into the target database
         $printLogger->print("   Inserting into target database...\n");        
         $targetSQLClient->doSQLInsert("AdvertisedSaleProfiles", $_);
      }
      $targetSQLClient->disconnect();
      $sqlClient->disconnect();
   }
   else
   {
       $printLogger->print("   target database name not specified\n");
   }
}

# -------------------------------------------------------------------------------------------------
# iterates through every field of the database and runs the validate function on it
# updated fields are stored in the target database
sub maintenance_TidyRentalContents
{   
   my $printLogger = shift;   
   my $instanceID = shift;
   my $targetDatabase = shift;
  
   my $sqlClient = SQLClient::new(); 
   my $advertisedRentalProfiles = AdvertisedPropertyProfiles::new($sqlClient, 'Rentals');
   my $propertyTypes = PropertyTypes::new($sqlClient);
   my $targetSQLClient = SQLClient::new($targetDatabase);
   my $targetAdvertisedRentalProfiles = AdvertisedPropertyProfiles::new($targetSQLClient, 'Rentals');
  
   if ($targetDatabase)
   {
      # enable logging to disk by the SQL client
      $sqlClient->enableLogging($instanceID);
      # enable logging to disk by the SQL client
      $targetSQLClient->enableLogging("t_".$instanceID);
      
      $sqlClient->connect();
      $targetSQLClient->connect();
      
      $printLogger->print("Dropping Target Database table...\n");
      $targetAdvertisedRentalProfiles->dropTable();
      
      $printLogger->print("Creating Target Database emptytable...\n");
      $targetAdvertisedRentalProfiles->createTable();
      
      $printLogger->print("Performing Source database validation...\n");
      
      @selectResult = $sqlClient->doSQLSelect("select * from AdvertisedRentalProfiles order by DateEntered");
      $length = @selectResult;
      $printLogger->print("   $length records.\n");
      foreach (@selectResult)
      {
         # $_ is a reference to a hash for the row of the table
         $oldChecksum = $$_{'checksum'};
         #$printLogger->print($$_{'DateEntered'}, " ", $$_{'SourceName'}, " ", $$_{'SuburbName'}, "(", $_{'SuburbIndex'}, ") oldChecksum=", $$_{'Checksum'});
   
         tidyRecord($sqlClient, $_);
         
         # IMPORTANT: delete the Identifier element of the hash so it's not included in the checksum - otherwise the checksum 
         # would always differ between attributes
         delete $$_{'Identifier'};
         $checksum = DocumentReader::calculateChecksum(undef, $_);
         #$printLogger->print(" | ", $$_{'SuburbName'}, "(", $$_{'SuburbIndex'}, ") newChecksum=$checksum\n");
 
         $printLogger->print("---", $$_{'DateEntered'}, " ", $$_{'SuburbName'}, "(", $$_{'SuburbIndex'}, ")\n");
         $$_{'Checksum'} = $checksum;
         
         #   $printLogger->print($$_{'Description'}, "\n");
         #DebugTools::printHash("data", $_);
         
         # do an sql insert into the target database
         $printLogger->print("   Inserting into target database...\n");        
         $targetSQLClient->doSQLInsert("AdvertisedRentalProfiles", $_);
      }
      $targetSQLClient->disconnect();
      $sqlClient->disconnect();
   }
   else
   {
       $printLogger->print("   target database name not specified\n");
   }
}

# -------------------------------------------------------------------------------------------------

sub maintenance_DeleteSaleDuplicates
{   
   my $printLogger = shift;   
   my $instanceID = shift;
   my $targetDatabase = shift;
  
   my $sqlClient = SQLClient::new(); 
   my $advertisedSaleProfiles = AdvertisedPropertyProfiles::new($sqlClient, 'Sales');
   my $propertyTypes = PropertyTypes::new($sqlClient);
   my $targetSQLClient = SQLClient::new($targetDatabase);
   my $targetAdvertisedSaleProfiles = AdvertisedPropertyProfiles::new($targetSQLClient, 'Sales');
  
   if ($targetDatabase)
   {
      # enable logging to disk by the SQL client
      $sqlClient->enableLogging($instanceID);
      # enable logging to disk by the SQL client
      $targetSQLClient->enableLogging("dups_".$instanceID);
      
      $sqlClient->connect();
      $targetSQLClient->connect();
      
      $printLogger->print("Deleting duplicate entries...\n");
      @selectResult = $targetSQLClient->doSQLSelect("select identifier, sourceID, checksum from AdvertisedSaleProfiles order by sourceID, checksum");
      $length = @selectResult;
      $index = 0;
      print "$length total records...\n";
      $duplicates = 0;
      foreach (@selectResult)
      {
         if ($index > 0)
         {
            print "$index...", $$_{'sourceID'}, "\n";
            # check if this record exactly matches the last one
            if (($$_{'sourceID'} eq $$lastRecord{'sourceID'}) && ($$_{'checksum'} eq $$lastRecord{'checksum'}))
            {
               print "Duplicate found: ", $$_{'sourceID'}, " (", $$_{'checksum'}, "): identifiers: ", $$lastRecord{'identifier'}, " and ", $$_{'identifier'}, "\n";
               $printLogger->print("   Deleteing from target database...\n");     
               if ($targetSQLClient->prepareStatement("delete from AdvertisedSaleProfiles where identifier = ".$targetSQLClient->quote($$_{'identifier'})))
               {
                  $targetSQLClient->executeStatement();
                  $duplicates++;
               }
            }
         }
         $lastRecord=$_;
         $index++;
      }
      print "$duplicates deleted.\n";

      $targetSQLClient->disconnect();
      $sqlClient->disconnect();
   }
   else
   {
       $printLogger->print("   target database name not specified\n");
   }
}


# -------------------------------------------------------------------------------------------------

sub maintenance_DeleteRentalDuplicates
{   
   my $printLogger = shift;   
   my $instanceID = shift;
   my $targetDatabase = shift;
  
   my $sqlClient = SQLClient::new(); 
   my $advertisedRentalProfiles = AdvertisedPropertyProfiles::new($sqlClient, 'Rentals');
   my $propertyTypes = PropertyTypes::new($sqlClient);
   my $targetSQLClient = SQLClient::new($targetDatabase);
   my $targetAdvertisedRentalProfiles = AdvertisedPropertyProfiles::new($targetSQLClient, 'Rentals');
  
   if ($targetDatabase)
   {
      # enable logging to disk by the SQL client
      $sqlClient->enableLogging($instanceID);
      # enable logging to disk by the SQL client
      $targetSQLClient->enableLogging("dups_".$instanceID);
      
      $sqlClient->connect();
      $targetSQLClient->connect();
      
      $printLogger->print("Deleting duplicate entries...\n");
      @selectResult = $targetSQLClient->doSQLSelect("select identifier, sourceID, checksum from AdvertisedRentalProfiles order by sourceID, checksum");
      $length = @selectResult;
      $index = 0;
      print "$length total records...\n";
      $duplicates = 0;
      foreach (@selectResult)
      {
         if ($index > 0)
         {
            print "$index...", $$_{'sourceID'}, "\n";
            # check if this record exactly matches the last one
            if (($$_{'sourceID'} eq $$lastRecord{'sourceID'}) && ($$_{'checksum'} eq $$lastRecord{'checksum'}))
            {
               print "Duplicate found: ", $$_{'sourceID'}, " (", $$_{'checksum'}, "): identifiers: ", $$lastRecord{'identifier'}, " and ", $$_{'identifier'}, "\n";
               $printLogger->print("   Deleteing from target database...\n");     
               if ($targetSQLClient->prepareStatement("delete from AdvertisedRentalProfiles where identifier = ".$targetSQLClient->quote($$_{'identifier'})))
               {
                  $targetSQLClient->executeStatement();
                  $duplicates++;
               }
            }
         }
         $lastRecord=$_;
         $index++;
      }
      print "$duplicates deleted.\n";

      $targetSQLClient->disconnect();
      $sqlClient->disconnect();
   }
   else
   {
       $printLogger->print("   target database name not specified\n");
   }
}


# -------------------------------------------------------------------------------------------------
# iterates through every field of the database and runs the validate function on it
# Changes are tracked
sub maintenance_ValidateSaleContents
{   
   my $printLogger = shift;   
   my $instanceID = shift;
  
   my $sqlClient = SQLClient::new(); 
   my $advertisedSaleProfiles = AdvertisedPropertyProfiles::new($sqlClient, 'Sales');
   my $propertyTypes = PropertyTypes::new($sqlClient);
   my $transactionNo = 0;
   
   # enable logging to disk by the SQL client
   $sqlClient->enableLogging($instanceID);
   
   $sqlClient->connect();
   
   $printLogger->print("Fetching Validator RegEx patterns...\n");

   # load the table of validator substitutions defined in the database
   @regExSubstitutionPatterns = $sqlClient->doSQLSelect("select * from Validator_RegExSubstitutes"); 

   $printLogger->print("Fetching INVALID database records from WORKING VIEW...\n");
     
   @selectResult = $sqlClient->doSQLSelect("select count(suburbname) as Count from WorkingView_AdvertisedSaleProfiles where ValidityCode > 0 order by DateEntered");
   $noOfRecords = $selectResult[0]{'Count'};
   $recordsProcessed = 0;
   $printLogger->print("   $noOfRecords invalid records...processing in segments (to limit memory consumption)\n");
   $offset = 0;
   $validRecords = 0;
   $recordsChanged = 0;
   $length = 1;
  
   while (($recordsProcessed < $noOfRecords) && ($length > 0))
   {
      #print "select * from WorkingView_AdvertisedSaleProfiles where ValidityCode > 0 order by DateEntered limit $offset, 10000\n";
      @selectResult = $sqlClient->doSQLSelect("select * from WorkingView_AdvertisedSaleProfiles where ValidityCode > 0 order by DateEntered limit $offset, 10000");
      $length = @selectResult;
      $printLogger->print("   processing $length records...\n");

      $printLogger->print("      performing record validation...\n");
      $validRecords = 0;
      foreach (@selectResult)
      {
         # $_ is a reference to a hash for the row of the table
         $oldChecksum = $$_{'checksum'};
         #$printLogger->print($$_{'DateEntered'}, " ", $$_{'SourceName'}, " ", $$_{'SuburbName'}, "(", $_{'SuburbIndex'}, ") oldChecksum=", $$_{'Checksum'});
   
         ($changed, $validityCode) = validateRecord($sqlClient, $_, \@regExSubstitutionPatterns, $advertisedSaleProfiles, $instanceID, $transactionNo);
         if ($changed)
         {
            $transactionNo++;
            $recordsChanged++;
         }
         if ($validityCode == 0)
         {
            $validRecords++;
         }
      }
      
      $percent = sprintf("%0.2f", ($validRecords / $length) * 100.0);
      print "      changed $transactionNo records ($validRecords ($percent%) records marked valid)\n";
      
      # count the total number of records processed
      $recordsProcessed += $length;
      # the offset is updated by the number of records read SUBTRACT the number of records that were 
      # marked invalid because the next select won't include those
      $offset += ($length - $validRecords);
      #print "offset=$offset\n";
   }
   
   print "   Validation complete. $recordsChanged records 'changed'.\n";

   $sqlClient->disconnect();

}

# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# iterates through every field of the database and all changes to construct the working view
sub maintenance_ConstructWorkingViewSales
{   
   my $printLogger = shift;   
   my $instanceID = shift;
  
   my $sqlClient = SQLClient::new(); 
   my $advertisedSaleProfiles = AdvertisedPropertyProfiles::new($sqlClient, 'Sales');
   my $propertyTypes = PropertyTypes::new($sqlClient);
   my $transactionNo = 0;
   
   # enable logging to disk by the SQL client
   $sqlClient->enableLogging($instanceID);
   
   $sqlClient->connect();
   
   $printLogger->print("Fetching database records...\n");
   
   # get the content of the database
   @selectResult = $sqlClient->doSQLSelect("select Identifier from AdvertisedSaleProfiles order by DateEntered");
   
   # add to the workingView...
   $length = @selectResult;
   $printLogger->print("   $length records.\n");
    
   $printLogger->print("Erasing the working view...\n");
   
   $statement = $sqlClient->prepareStatement("delete from WorkingView_AdvertisedSaleProfiles");
   $sqlClient->executeStatement($statement);
   
   $printLogger->print("Constructing original view...\n");
   
   foreach (@selectResult)
   {
      # $_ is a reference to a hash for the row of the table
      $advertisedSaleProfiles->copyToWorkingView($$_{'Identifier'});
   }
   
   $printLogger->print("Fetching change records...\n");
    # get the content of the database
   @selectResult = $sqlClient->doSQLSelect("select * from ChangeTable_AdvertisedSaleProfiles order by DateEntered");
   $length = @selectResult;
   $printLogger->print("   $length records.\n");
   $printLogger->print("Applying changes...\n");
   
   foreach (@selectResult)
   {
      $changesRecord = $$_{'ChangesRecord'};
      # delete special fields from the record
      delete $$_{'ChangesRecord'};  # not used in workingVIew
      delete $$_{'ChangedBy'};      # not used in workingView
      delete $$_{'Identifier'};     # not used in workingView - changesRecord is used
      delete $$_{'InstanceID'};     # original to be maintained
      delete $$_{'DateEntered'};    # original to be maintained
      delete $$_{'TransactionNo'};  # original to be maintained

      # delete null fields from the record (no changes)
      while(($key, $value) = each(%$_))
      {
         if (!defined $value)
         {
            # remove this parameter
            delete $$_{$key};
         }
      }
      
      $advertisedSaleProfiles->_workingView_changeRecord($_, $changesRecord);
   }
   
   print "WorkingView is synchronised\n";
   
}

# -------------------------------------------------------------------------------------------------
# iterates through every field of the database and all changes to construct the working view
sub maintenance_ConstructWorkingViewRentals
{   
   my $printLogger = shift;   
   my $instanceID = shift;
  
   my $sqlClient = SQLClient::new(); 
   my $advertisedRentalProfiles = AdvertisedPropertyProfiles::new($sqlClient, 'Rentals');
   my $propertyTypes = PropertyTypes::new($sqlClient);
   my $transactionNo = 0;
   
   # enable logging to disk by the SQL client
   $sqlClient->enableLogging($instanceID);
   
   $sqlClient->connect();
   
   $printLogger->print("Fetching database records...\n");
   
   # get the content of the database
   @selectResult = $sqlClient->doSQLSelect("select Identifier from AdvertisedRentalProfiles order by DateEntered");
   
   # add to the workingView...
   $length = @selectResult;
   $printLogger->print("   $length records.\n");
    
   $printLogger->print("Erasing the working view...\n");
   
   $statement = $sqlClient->prepareStatement("delete from WorkingView_AdvertisedRentalProfiles");
   $sqlClient->executeStatement($statement);
   
   $printLogger->print("Constructing original view...\n");
   
   foreach (@selectResult)
   {
      # $_ is a reference to a hash for the row of the table
      $advertisedRentalProfiles->copyToWorkingView($$_{'Identifier'});
   }
   
   $printLogger->print("Fetching change records...\n");
    # get the content of the database
   @selectResult = $sqlClient->doSQLSelect("select * from ChangeTable_AdvertisedRentalProfiles order by DateEntered");
   $length = @selectResult;
   $printLogger->print("   $length records.\n");
   $printLogger->print("Applying changes...\n");
   
   foreach (@selectResult)
   {
      $changesRecord = $$_{'ChangesRecord'};
      # delete special fields from the record
      delete $$_{'ChangesRecord'};  # not used in workingVIew
      delete $$_{'ChangedBy'};      # not used in workingView
      delete $$_{'Identifier'};     # not used in workingView - changesRecord is used
      delete $$_{'InstanceID'};     # original to be maintained
      delete $$_{'DateEntered'};    # original to be maintained
      delete $$_{'TransactionNo'};  # original to be maintained

      # delete null fields from the record (no changes)
      while(($key, $value) = each(%$_))
      {
         if (!defined $value)
         {
            # remove this parameter
            delete $$_{$key};
         }
      }
      
      $advertisedRentalProfiles->_workingView_changeRecord($_, $changesRecord);
   }
   
   print "WorkingView is synchronised\n";
}

# -------------------------------------------------------------------------------------------------
# iterates through every field of the database and all changes to construct the cache view
sub maintenance_ConstructCacheViewSales
{   
   my $printLogger = shift;   
   my $instanceID = shift;
  
   my $sqlClient = SQLClient::new(); 
   my $advertisedSaleProfiles = AdvertisedPropertyProfiles::new($sqlClient, 'Sales');
   my $propertyTypes = PropertyTypes::new($sqlClient);
   my $transactionNo = 0;
   
   # enable logging to disk by the SQL client
   $sqlClient->enableLogging($instanceID);
   
   $sqlClient->connect();
   
   $printLogger->print("Fetching database records...\n");
   
   # get the content of the database
   @selectResult = $sqlClient->doSQLSelect("select Identifier, SourceName, SourceID, Checksum, AdvertisedPriceLower from AdvertisedSaleProfiles order by DateEntered");
   
   # add to the workingView...
   $length = @selectResult;
   $printLogger->print("   $length records.\n");
    
   $printLogger->print("Erasing the cache view...\n");
   
   $statement = $sqlClient->prepareStatement("delete from CacheView_AdvertisedSaleProfiles");
   $sqlClient->executeStatement($statement);
   
   $printLogger->print("Constructing cache view...\n");
   
   foreach (@selectResult)
   {
      # $_ is a reference to a hash for the row of the table
      # add the cached fields to the cacheView
      $advertisedSaleProfiles->_cacheView_addRecord($$_{'Identifier'}, $$_{'SourceName'}, $_, $$_{'Checksum'});
   }
   
   print "CacheView is synchronised\n";
   
}


# -------------------------------------------------------------------------------------------------
# iterates through every field of the database and all changes to construct the cache view
sub maintenance_ConstructCacheViewRentals
{   
   my $printLogger = shift;   
   my $instanceID = shift;
  
   my $sqlClient = SQLClient::new(); 
   my $advertisedRentalProfiles = AdvertisedPropertyProfiles::new($sqlClient, 'Rentals');
   my $propertyTypes = PropertyTypes::new($sqlClient);
   my $transactionNo = 0;
   
   # enable logging to disk by the SQL client
   $sqlClient->enableLogging($instanceID);
   
   $sqlClient->connect();
   
   $printLogger->print("Fetching database records...\n");
   
   # get the content of the database
   @selectResult = $sqlClient->doSQLSelect("select Identifier, SourceName, SourceID, Checksum, AdvertisedWeeklyRent from AdvertisedRentalProfiles order by DateEntered");
   
   # add to the workingView...
   $length = @selectResult;
   $printLogger->print("   $length records.\n");
    
   $printLogger->print("Erasing the cache view...\n");
   
   $statement = $sqlClient->prepareStatement("delete from CacheView_AdvertisedRentalProfiles");
   $sqlClient->executeStatement($statement);
   
   $printLogger->print("Constructing cache view...\n");
   
   foreach (@selectResult)
   {
      # $_ is a reference to a hash for the row of the table
      # add the cached fields to the cacheView
      $advertisedRentalProfiles->_cacheView_addRecord($$_{'Identifier'}, $$_{'SourceName'}, $_, $$_{'Checksum'});
   }
   
   print "CacheView is synchronised\n";   
}


# -------------------------------------------------------------------------------------------------
# iterates through every field of the database and all changes to construct the PropertyTable
sub maintenance_ConstructPropertyTable
{   
   my $printLogger = shift;   
   my $instanceID = shift;
  
   my $sqlClient = SQLClient::new(); 
   my $advertisedSaleProfiles = AdvertisedPropertyProfiles::new($sqlClient, 'Sales');
   my $masterPropertyTable = MasterPropertyTable::new($sqlClient, $advertisedSaleProfiles);
   my $transactionNo = 0;
   my $propertiesCreated = 0;
   
   # enable logging to disk by the SQL client
   $sqlClient->enableLogging($instanceID);
   
   $sqlClient->connect();
   
   $printLogger->print("Fetching VALID WORKING VIEW database records...\n");
   
   # get the content of the database
   @selectResult = $sqlClient->doSQLSelect("select Identifier, StreetNumber, Street, SuburbName, SuburbIndex, State from WorkingView_AdvertisedSaleProfiles where ValidityCode = 0 order by DateEntered");
   
   # add to the workingView...
   $length = @selectResult;
   $printLogger->print("   $length records.\n");
    
   #$printLogger->print("Erasing the MasterPropertyTable...\n");
   
   #$statement = $sqlClient->prepareStatement("delete from MasterPropertyTable");
   #$sqlClient->executeStatement($statement);
   
   $printLogger->print("Constructing MasterPropertyTable (continuing existing)...\n");
   
   foreach (@selectResult)
   {
      $identifier = $masterPropertyTable->linkRecord($_);
      if ((defined $identifier) && ($identifier >= 0))
      {
         # link the workingview record as a componentOf the property using the returned identifier
         $propertiesCreated++;
        
         # the link below was moved into linkRecord 
         # $advertisedSaleProfiles->workingView_setSpecialField($$_{'Identifier'}, 'ComponentOf', $identifier);   
      }
   }
   $totalProperties = $masterPropertyTable->countEntries();
   
   print "   Linked $propertiesCreated records ($totalProperties total properties).\n";
   print "MasterPropertyTable is synchronised\n";   
}


# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# iterates through every field of the database and all changes to construct the PropertyTable
sub maintenance_UpdateProperties
{   
   my $printLogger = shift;   
   my $instanceID = shift;
  
   
   $printLogger->print("Updating properties...\n");

   #maintenance_ValidateSaleContents($printLogger, $instanceID);
   
   
   my $sqlClient = SQLClient::new(); 
   my $advertisedSaleProfiles = AdvertisedPropertyProfiles::new($sqlClient, 'Sales');
   my $masterPropertyTable = MasterPropertyTable::new($sqlClient, $advertisedSaleProfiles);
   my $transactionNo = 0;
   my $propertiesCreated = 0;
   
   # enable logging to disk by the SQL client
   $sqlClient->enableLogging($instanceID);
   
   $sqlClient->connect();
   
   $printLogger->print("Fetching UNLINKED VALID WORKING VIEW database records...\n");
   
   # get the content of the database
   @selectResult = $sqlClient->doSQLSelect("select Identifier, StreetNumber, Street, SuburbName, SuburbIndex, State from WorkingView_AdvertisedSaleProfiles where ValidityCode = 0 and ComponentOf is null order by DateEntered");
   
   # add to the workingView...
   $length = @selectResult;
   $printLogger->print("   $length records.\n");
   
   $printLogger->print("Updating MasterPropertyTable...\n");
   
   foreach (@selectResult)
   {
      $identifier = $masterPropertyTable->linkRecord($_);
      if ((defined $identifier) && ($identifier >= 0))
      {
         # link the workingview record as a componentOf the property using the returned identifier
         $propertiesCreated++;
        
         # the line below was moved into linkRecord
         #$advertisedSaleProfiles->workingView_setSpecialField($$_{'Identifier'}, 'ComponentOf', $identifier);   
      }
   }
   $totalProperties = $masterPropertyTable->countEntries();
   
   print "   Linked $propertiesCreated records ($totalProperties total properties).\n";
   print "MasterPropertyTable is synchronised\n";
   

}


# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# dumps all views and rebuilds from scratch - shouldn't ever need to do this (only during 
#  debugging/development).  Manual changes will be lost
sub maintenance_Rebuild
{   
   my $printLogger = shift;   
   my $instanceID = shift;
   my $sqlClient = SQLClient::new(); 

   $printLogger->print("--- Rebuilding database views from the unprocessed advertisements --- \n");

   # rebuild the cache
   $printLogger->print("STEP ONE of FIVE: Constructing cacheviews...\n");
   maintenance_ConstructCacheViewSales($printLogger, $instanceID);
   maintenance_ConstructCacheViewRentals($printLogger, $instanceID);

    # enable logging to disk by the SQL client
   $sqlClient->enableLogging($instanceID);
   
   $sqlClient->connect();
   
   $printLogger->print("STEP TWO of FIVE: Erasing the ChangeTable...\n");
   $statement = $sqlClient->prepareStatement("delete from ChangeTable_AdvertisedSaleProfiles");
   $sqlClient->executeStatement($statement);
   $statement = $sqlClient->prepareStatement("delete from ChangeTable_AdvertisedRentalProfiles");
   $sqlClient->executeStatement($statement);
   
   $printLogger->print("STEP THREE of FIVE: Rebuilding the clean WorkingView...\n");
   # rebuild the clean working view (no changes)
   maintenance_ConstructWorkingViewSales($printLogger, $instanceID);
   maintenance_ConstructWorkingViewRentals($printLogger, $instanceID);
   
   $printLogger->print("STEP FOUR of FIVE: Applying validation changes...\n");
   maintenance_ValidateSaleContents($printLogger, $instanceID);
   
   $printLogger->print("STEP FIVE of FIVE: Constructing MasterPropertiesTable...\n");
   maintenance_ConstructPropertyTable($printLogger, $instanceID);
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# iterates through every field of the working view that are a component of a property and updates
# the XRef table
sub maintenance_ConstructXRef
{   
   my $printLogger = shift;   
   my $instanceID = shift;
   my $componentsLinked = 0;
   
   $printLogger->print("Rebuilding Property->Component XRef table...\n");
   
   my $sqlClient = SQLClient::new();
   my $masterPropertyTable = MasterPropertyTable::new($sqlClient, undef);
   
   # enable logging to disk by the SQL client
   $sqlClient->enableLogging($instanceID);
   
   $sqlClient->connect();
   
   $printLogger->print("Erasing the MasterPropertyComponentsXRef table...\n");
   
   $statement = $sqlClient->prepareStatement("delete from MasterPropertyComponentsXRef");
   $sqlClient->executeStatement($statement);
   
   $printLogger->print("Fetching WORKING VIEW database records that have ComponentOf set...\n");
   
   # get the content of the table
   @selectResult = $sqlClient->doSQLSelect("select Identifier, ComponentOf from WorkingView_AdvertisedSaleProfiles where ComponentOf is not null order by ComponentOf, DateEntered");
   
   $length = @selectResult;
   $printLogger->print("   $length records.\n");
   
   $printLogger->print("Updating MasterPropertyComponentsXRef...\n");
   
   foreach (@selectResult)
   {
      $propertyID = $$_{'ComponentOf'};
      $componentID = $$_{'Identifier'};
      $success = $masterPropertyTable->_addXRef($propertyID, $componentID);
      if ($success)
      {
         $componentsLinked++;
      }
      
   }
   $totalProperties = $masterPropertyTable->countEntries();
   
   print "   Linked $componentsLinked components\n";
   print "MasterPropertyComponentsXRef is synchronised\n";

}

# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# iterates through all the properties and used the XRef and a selection algorithm to set
# the master components of the MasterPropertyTable
sub maintenance_ConstructMasterComponents
{   
   my $printLogger = shift;   
   my $instanceID = shift;
   my $propertiesUpdated = 0;
   
   $printLogger->print("Recaclulating MasterComponents of MasterPropertyTable table...\n");
   
   my $sqlClient = SQLClient::new(); 
   my $advertisedSaleProfiles = AdvertisedPropertyProfiles::new($sqlClient, 'Sales');
   my $masterPropertyTable = MasterPropertyTable::new($sqlClient, $advertisedSaleProfiles);
   
   # enable logging to disk by the SQL client
   $sqlClient->enableLogging($instanceID);
   
   $sqlClient->connect();
   
   $printLogger->print("Fetching MasterPropertyTable identifiers...\n");
   
   # get the content of the table
   @selectResult = $sqlClient->doSQLSelect("select Identifier from MasterPropertyTable ");
   
   $length = @selectResult;
   $printLogger->print("   $length records.\n");
   
   $printLogger->print("Updating Master Components from XRef for each property...\n");
   
   foreach (@selectResult)
   {
      $propertyID = $$_{'Identifier'};
     
      $success = $masterPropertyTable->_calculateMasterComponents($propertyID);
      if ($success)
      {
         $propertiesUpdated++;
      }
      
   }
   
   print "   Updated $propertiesUpdated properties\n";
   
   print "MasterPropertyTable is synchronised\n";
}


# -------------------------------------------------------------------------------------------------

# parses the parameters mandatory for the specified command
sub parseMandatoryParameters
{
   my $parametersHashRef = shift;
   my $mandatoryParametersRef = shift;
   my $success = 1;
   
   # mandatory parameters
   foreach (@$mandatoryParametersRef)
   {
      # if the parameter is on the command line, get it
      
      $newValue = param("$_");
      if (defined $newValue)
      {
         $$parametersHashRef{$_} = $newValue;
      }
         
      # check if the mandatory parameter is set (either previously from the config file or now through command line)
      if (!defined $$parametersHashRef{$_})
      {
         # missing parameter
         $success = 0;
         # report missing option name
         $$parametersHashRef{'missingOptions'} .= "$_ ";
      }
   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------
# parses the optional parameters applicable to one or more command
sub parseOptionalParameters
{
   my $parametersHashRef = shift;
   my @optionalParameters = ('startrange', 'endrange', 'statusPort', 'proxy');
   my $success = 1;
 
   # optional parameters
   foreach (@optionalParameters)
   {
      # if the parameter is on the command line, get it
      $newValue = param($_);
      if (defined $newValue)
      {
         $$parametersHashRef{$_} = $newValue;
      }
   }
   
   return $success;
}

# -------------------------------------------------------------------------------------------------
# loadConfiguration
# loads a text file that contains a list of parameters for the application
#
# Purpose:
#  configuration
#
# Parameters:
#  nil
#
# Updates:
#  nil
#
# Returns:
#  %parameters
#    
sub loadConfiguration
{ 
   my $filename = shift;  
   my $parametersHashRef = shift;
      
   $filename .= ".config";
   if (-e $filename)
   {          
      open(PARAM_FILE, "<$filename") || print("   main: Can't open configuration file: $!"); 
                 
      # loop through the content of the file
      while (<PARAM_FILE>) # read a line into $_
      {
         # remove end of line marker from $_
         chomp;
         # split on null character
         ($key, $value) = split(/=/, $_, 2);	 	           
         $$parametersHashRef{$key} = $value;                                    
      }
      
      close(PARAM_FILE);
   }         
   else
   {
      print("   main: NOTE: configuration file '$filename' not found."); 
   }
}


# -------------------------------------------------------------------------------------------------
# parses any specified command-line parameters
# MUST specify 'command' on the command line
#  optional 'configFile' of additional parameters
# and MANDATORY parameters for 'command'
# and OPTIONAL parameters for 'command'
sub parseParameters
{      
   my %parameters;
   my $success = 0;
   my @startCommands = ('url', 'source', 'state');
   my @continueCommands = ('url', 'thread', 'source', 'state');
   my @maintenanceCommands = ('action');   
   # this hash of lists defines the commands supported and mandatory options for each command
   my %mandatoryParameters = (
      'start' => \@startCommands,
      'continue' => \@continueCommands,
      'create' => undef,
      'drop' => undef,
      'maintenance' => \@maintenanceCommands
   );   
   my %commandDescription = (
         'help' => "Display this information",
         'start' => "start a new session to download advertisements",
         'continue' => "continue an existing session downloading advertisements from the last recovery position",
         'create' => "create the database tables",
         'drop' => "drop the database tables (and all data)",
         'maintenance' => "run maintenance option on the database"
   );
 
   # see which command is specified
   $parameters{'command'} = param("command");
   $parameters{'config'} = param("config");
   if ($parameters{'config'})
   {
      # read the default configuration file
      print "   main: loading configuration for ", $parameters{'config'}, "\n";
      loadConfiguration($parameters{'config'}, \%parameters);
   }

   if ($parameters{'command'})
   {
      # if a command has been specified, parse the parameters
      if (exists $mandatoryParameters{$parameters{'command'}})
      {
         $success = parseMandatoryParameters(\%parameters, $mandatoryParameters{$parameters{'command'}});
            
         if (!$success)
         {
            print "   main: At least one mandatory parameter for command '".$parameters{'command'}."' is missing.\n";
            print "   main:   missing parameters: ".$parameters{'missingOptions'}."\n";
         }
      }
      else
      {
         print "   main: command '".$parameters{'command'}."' not recognised\n"; 
      }
   }
   else
   {      
      if (!$parameters{'command'})
      {
         print "main: command not specified\n";
      }
      else
      {
         print "main: config not specified\n";
      }
      print "   USAGE: $0 command=a&configFile=b&mandatoryParams[&optionalParams]\n";
      print "   where a=\n";
      foreach (keys (%commandDescription))
      {
         print "      $_: ".$commandDescription{$_}."\n";
      }
      print "   and b is an identifier for this scanner configuration.\n"
      
   }

   # if successfully read the mandatory parameters, now get optional ones...
   if ($success)
   {
      # set the special parameter 'agent' that's derived from multiple other variables
      if (($parameters{'startrange'}) || ($parameters{'endrange'}))
      {
         if ($parameters{'startrange'})
         {
            if ($parameters{'endrange'})
            {
               $parameters{'agent'} = "PublishedMaterialScanner_".$parameters{'config'}."_".$parameters{'startrange'}."-".$parameters{'endrange'};
            }
            else
            {
               $parameters{'agent'} = "PublishedMaterialScanner_".$parameters{'config'}."_".$parameters{'startrange'}."-ZZZ"
            }
         }
         else
         { 
            $parameters{'agent'} = "PublishedMaterialScanner_".$parameters{'config'}."_AAA-".$parameters{'endrange'};
         }     
      }
      else
      {
         if ($parameters{'config'})
         {
            $parameters{'agent'} = "PublishedMaterialScanner_".$parameters{'config'};
         }
         else
         {
            $parameters{'agent'} = "PublishedMaterialScanner";         
         }
      }
      
      # parse the optional parameters
      parseOptionalParameters(\%parameters);
      
      # temporary hack so the useText command doesn't have to be explicit
      if (!$parameters{'useHTML'})
      {
         $parameters{'useText'} = 1;
      }
      # 25 July 2004 - generate an instance ID based on current time and a random number.  The instance ID is 
      # used in the name of the logfile
      my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
      $year += 1900;
      $mon++;
      my $randNo = rand 1000;
      my $instanceID = sprintf("%s_%4i%02i%02i%02i%02i%02i_%04i", $parameters{'agent'}, $year, $mon, $mday, $hour, $min, $sec, $randNo);
      $parameters{'instanceID'} = $instanceID;
     
   }
   
   return ($success, %parameters);   
}


