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
# 
#   NEED TO DO RETRY ON 500 HTTP ERROR
#   NEED TO ADD SUPPORT FOR SUBURB PROFILES
#   NEED TO GET AGENT NAME
#   NEED TO FIND WAY FOR PARSERS TO BE SPECIFIED THROUGH THE CONFIG FILE (low priority)
# To do:
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
use AdvertisedSaleProfiles;
use AdvertisedRentalProfiles;
use AgentStatusServer;
use PropertyTypes;
use WebsiteParser_Common;
use WebsiteParser_REIWASales;
use WebsiteParser_DomainSales;
use WebsiteParser_REIWARentals;
use WebsiteParser_REIWASuburbs;
  
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
   ($sqlClient, $advertisedSaleProfiles, $advertisedRentalProfiles, $propertyTypes, $suburbProfiles) = initialiseTableObjects();
 
   # enable logging to disk by the SQL client
   $sqlClient->enableLogging($parameters{'instanceID'});
   $sqlClient->connect();
   
   # hash of table objects - the key's are only significant to the local callback functions   
   $myTableObjects{'advertisedSaleProfiles'} = $advertisedSaleProfiles;
   $myTableObjects{'advertisedRentalProfiles'} = $advertisedRentalProfiles;
   $myTableObjects{'propertyTypes'} = $propertyTypes;
   $myTableObjects{'suburbProfiles'} = $suburbProfiles;
   
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
    
   my $advertisedRentalProfiles = AdvertisedRentalProfiles::new($sqlClient);
   my $advertisedSaleProfiles = AdvertisedSaleProfiles::new($sqlClient);
   my $propertyTypes = PropertyTypes::new($sqlClient);
   my $suburbProfiles = SuburbProfiles::new($sqlClient);

   return ($sqlClient, $advertisedSaleProfiles, $advertisedRentalProfiles, $propertyTypes, $suburbProfiles);
}

# -------------------------------------------------------------------------------------------------

sub doMaintenance
{   
   my $printLogger = shift;   
   my $parametersRef = shift;
   my $actionOk = 0;
   
   my $sqlClient = SQLClient::new(); 
   my $advertisedSaleProfiles = AdvertisedSaleProfiles::new($sqlClient);
   my $propertyTypes = PropertyTypes::new($sqlClient);
   
   my $targetSQLClient = SQLClient::new($$parametersRef{'database'});
   my $targetAdvertisedSaleProfiles = AdvertisedSaleProfiles::new($targetSQLClient);
  
   if ($$parametersRef{'action'} =~ /validatesale/i)
   {
      $printLogger->print("---Performing Maintenance - Validate Sales---\n");
      maintenance_ValidateSaleContents($printLogger, $$parametersRef{'instanceID'}, $$parametersRef{'database'});
      $printLogger->print("---Finished Maintenance---\n");
      $actionOk = 1;
   }
   
   if ($$parametersRef{'action'} =~ /validaterental/i)
   {
      $printLogger->print("---Performing Maintenance - Validate Rentals---\n");
      maintenance_ValidateRentalContents($printLogger, $$parametersRef{'instanceID'}, $$parametersRef{'database'});
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
   
   if (!$actionOk)
   {
      $printLogger->print("maintenance: requested action isn't recognised\n");
      $printLogger->print("   validateSale     - validate & update the sales database entries\n");
      $printLogger->print("   validateRental   - validate & update the rental database entries\n");
      $printLogger->print("   duplicateSale    - delete duplicate sales database entries\n");
      $printLogger->print("   duplicateRental  - delete duplicate rental database entries\n");
   }
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# iterates through every field of the database and runs the validate function on it
# updated fields are stored in the target database
sub maintenance_ValidateSaleContents
{   
   my $printLogger = shift;   
   my $instanceID = shift;
   my $targetDatabase = shift;
  
   my $sqlClient = SQLClient::new(); 
   my $advertisedSaleProfiles = AdvertisedSaleProfiles::new($sqlClient);
   my $propertyTypes = PropertyTypes::new($sqlClient);
   my $targetSQLClient = SQLClient::new($targetDatabase);
   my $targetAdvertisedSaleProfiles = AdvertisedSaleProfiles::new($targetSQLClient);
  
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
   
         validateProfile($sqlClient, $_);
         
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
sub maintenance_ValidateRentalContents
{   
   my $printLogger = shift;   
   my $instanceID = shift;
   my $targetDatabase = shift;
  
   my $sqlClient = SQLClient::new(); 
   my $advertisedRentalProfiles = AdvertisedRentalProfiles::new($sqlClient);
   my $propertyTypes = PropertyTypes::new($sqlClient);
   my $targetSQLClient = SQLClient::new($targetDatabase);
   my $targetAdvertisedRentalProfiles = AdvertisedRentalProfiles::new($targetSQLClient);
  
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
   
         validateProfile($sqlClient, $_);
         
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
   my $advertisedSaleProfiles = AdvertisedSaleProfiles::new($sqlClient);
   my $propertyTypes = PropertyTypes::new($sqlClient);
   my $targetSQLClient = SQLClient::new($targetDatabase);
   my $targetAdvertisedSaleProfiles = AdvertisedSaleProfiles::new($targetSQLClient);
  
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
   my $advertisedRentalProfiles = AdvertisedRentalProfiles::new($sqlClient);
   my $propertyTypes = PropertyTypes::new($sqlClient);
   my $targetSQLClient = SQLClient::new($targetDatabase);
   my $targetAdvertisedRentalProfiles = AdvertisedRentalProfiles::new($targetSQLClient);
  
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
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
    
# -------------------------------------------------------------------------------------------------


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
   my @maintenanceCommands = ('database', 'action');   
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
      if (defined $mandatoryParameters{$parameters{'command'}})
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


