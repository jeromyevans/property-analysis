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
#  28 September 2004 - use the continue command to specify a threadID to continue from - this allows the URL stack and cookies
#   from a previous instance to be reused in the same 'thread'.  Implemented to support automatic restart of a thread in a loop and
#   automatic exit if an instance runs out of memory.  (exit, then restart from same point) 
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
use AgentStatusServer;
use PropertyTypes;

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
   my $printLogger = shift;
   my %parameters;
      
   if (-e $filename)
   {             
      open(PARAM_FILE, "<$filename") || $printLogger->print("   main: Can't open configuration file: $!"); 
                 
      # loop through the content of the file
      while (<PARAM_FILE>) # read a line into $_
      {
         # remove end of line marker from $_
         chomp;
         # split on null character
         ($key, $value) = split /=/;	 	 
         $parameters{$key} = $value;                                    
      }
      
      close(PARAM_FILE);
   }      
   
   return %parameters;
}

#  
# -------------------------------------------------------------------------------------------------    

my $SOURCE_NAME = "REIWA";
my $useText = 0;
my $createTables = 0;
my $getSuburbProfiles = 0;
my $dropTables = 0;
my $continueSession = 0;
my $statusPort = undef;

# these two parameters are used to limit the letter range of suburbs processed
# by this instance of the application
my $startLetter;
my $endLetter;
my $agent;
my $state;
my $targetDatabase;

my $useHTML = param('html');

($parseSuccess, $createTables, $startSession, $continueSession, $dropTables, $maintenance) = parseParameters();

if (!$useHTML)
{
   $useText = 1; 
}

if (!$agent)
{
   $agent = "GetAdvertisedSales";
}


# 25 July 2004 - generate an instance ID based on current time and a random number.  The instance ID is 
   # used in the name of the logfile
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
$year += 1900;
$mon++;
my $randNo = rand 1000;
my $instanceID = sprintf("%s_%4i%02i%02i%02i%02i%02i_%04i", $agent, $year, $mon, $mday, $hour, $min, $sec, $randNo);
   
   
my $printLogger = PrintLogger::new($agent, $instanceID.".stdout", 1, $useText, $useHTML);
my $statusServer;

$printLogger->printHeader("$agent\n");


# load the configuration file
my %parameters = loadConfiguration($agent.".config", $printLogger);

if (!$parameters{'url'})
{
   $printLogger->print("   main: Configuration file not found\n");
}

if (($parseSuccess) && ($parameters{'url'}) && ($state) && (!$maintenance))
{
   # if a status port has been specified, start the TCP server
   if ($statusPort)
   {      
      $statusServer = AgentStatusServer::new($statusPort);
      $statusServer->setStatus("running", "1");
      $statusServer->start();
      $printLogger->print("   main: started agent status server (port=$statusPort)\n");
   }            
   
   ($sqlClient, $advertisedSaleProfiles, $propertyTypes) = initialiseTableObjects();
   # hash of table objects - the key's are only significant to the local callback functions
 
   # enable logging to disk by the SQL client
   $sqlClient->enableLogging($instanceID);
   
   $myTableObjects{'advertisedSaleProfiles'} = $advertisedSaleProfiles;
   $myTableObjects{'propertyTypes'} = $propertyTypes;
   
   $myParsers{"searchdetails"} = \&parseSearchDetails;
   $myParsers{"search.cfm"} = \&parseSearchForm;
   $myParsers{"content-home"} = \&parseHomePage;
   $myParsers{"searchquery"} = \&parseSearchQuery;
   $myParsers{"searchlist"} = \&parseSearchList;
   $myParsers{"CGIPostTest"} = \&parseDisplayResponse;   

   my $myDocumentReader = DocumentReader::new($agent, $instanceID, $parameters{'url'}, $sqlClient, 
      \%myTableObjects, \%myParsers, $printLogger, $continueSession);

   #$myDocumentReader->setProxy("http://localhost:8080");
   $myDocumentReader->run($createTables, $startSession, $continueSession, $dropTables);
 
}
else
{
   if ($maintenance)
   {
      doMaintenance($printLogger);
   }
   else
   {
       
      if (!$state)
      {
         $printLogger->print("   main: state not specified\n");
      }
      $printLogger->print("   main: No action requested\n");
   }
}

$printLogger->printFooter("Finished\n");

# -------------------------------------------------------------------------------------------------
# extractSaleProfile
# extracts property sale information from an HTML Syntax Tree
# assumes the HTML Syntax Tree is in a very specific format
#
# Purpose:
#  parsing document text
#
# Parameters:
#   DocumentReader 
#   HTMLSyntaxTree to parse
#   String URL
#
# Constraints:
#  nil
#
# Updates:
#  Nil
#
# Returns:
#   hash containing the suburb profile.
#      
sub extractSaleProfile
{
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;
   my $text;
   
   my %saleProfile;   
   
   # --- set start contraint to Print to get the first line of text (id, suburb, price)
   #$htmlSyntaxTree->setSearchStartConstraintByText("Print");
 
   # --- set start constraint to the 3rd table (table 2) on the page - this is table
   # --- across the top that MAY contain a title and description
               
   $htmlSyntaxTree->setSearchConstraintsByTable(2);
   $htmlSyntaxTree->setSearchEndConstraintByTag("td"); # until the next table
                    
   $IDSuburbPrice = $htmlSyntaxTree->getNextText();    # always set
   
   #--- followed by optional 'under offer' - ignored
   
   $htmlSyntaxTree->setSearchStartConstraintByTag("tr");  # next row of table   
   $htmlSyntaxTree->setSearchEndConstraintByTag("table");    
   $title = $htmlSyntaxTree->getNextText();            # sometimes undef     
   
   $description = $htmlSyntaxTree->getNextText();      # sometimes undef
   
   ($sourceID, $suburb, $priceLower, $priceHigher) = split /\-/, $IDSuburbPrice;
   
   # --- set start constraint to the 4th table on the page - this is table
   # --- to the right of the image that contains parameters for the property   
   $htmlSyntaxTree->setSearchConstraintsByTable(3);
   $htmlSyntaxTree->setSearchEndConstraintByTag("table"); # until the next table
   
   $type = $htmlSyntaxTree->getNextText();             # always set
   
   $bedrooms = $htmlSyntaxTree->getNextTextContainingPattern("Bedrooms");    # sometimes undef  
   ($bedrooms) = split(/ /, $bedrooms);   
   $bathrooms = $htmlSyntaxTree->getNextTextContainingPattern("Bath");       # sometimes undef
   ($bathrooms) = split(/ /, $bathrooms);
   $land = $htmlSyntaxTree->getNextTextContainingPattern("sqm");             # sometimes undef
   ($crud, $land) = split(/:/, $land);   
   $yearBuilt = $htmlSyntaxTree->getNextTextContainingPattern("Age:");      # sometimes undef
   ($crud, $yearBuilt) = split(/:/, $yearBuilt);
   
   # --- set the start constraint back to the top of the page and tje "for More info" label
   $htmlSyntaxTree->resetSearchConstraints();
            
   $addressString = $htmlSyntaxTree->getNextTextAfterPattern("Address:");
   ($streetNumber, $street) = split(/ /, $addressString, 2);
   
   $city = $htmlSyntaxTree->getNextTextAfterPattern("City:");
   $zone = $htmlSyntaxTree->getNextTextAfterPattern("Zone:");        
   
   $htmlSyntaxTree->setSearchStartConstraintByTag("blockquote");
   $htmlSyntaxTree->setSearchEndConstraintByText("For More Information");
      
   $features = $htmlSyntaxTree->getNextText();                       # sometimes undef
   $features .= $htmlSyntaxTree->getNextText();
   $features .= $htmlSyntaxTree->getNextText();
   $features .= $htmlSyntaxTree->getNextText();
   # ------ now parse the extracted values ----
   
   $priceLower =~ s/ //gi;   # remove space in the number if exist
   $priceHigher =~ s/ //gi;  # remove space in the number if exist
   $sourceID =~ s/ //gi;     # remove spaces if exist
   
   # substitute trailing whitespace characters with blank
   # s/whitespace from end-of-line/all occurances
   # s/\s*$//g;      
   $suburb =~ s/\s*$//g;

   # substitute leading whitespace characters with blank
   # s/whitespace from start-of-line,multiple single characters/blank/all occurances
   #s/^\s*//g;    
   $suburb =~ s/^\s*//g;
   
   $saleProfile{'SourceID'} = $sourceID;      
   
   if ($suburb) 
   {
      $saleProfile{'SuburbName'} = $suburb;
   }
   
   if ($priceHigher) 
   {
      $saleProfile{'AdvertisedPriceUpper'} = $documentReader->parseNumber($priceHigher);
   }
   
   if ($priceLower) 
   {
      $saleProfile{'AdvertisedPriceLower'} = $documentReader->parseNumber($priceLower);
   }
      
   if ($type)
   {
      $saleProfile{'Type'} = $type;
   }
   if ($bedrooms)
   {
      $saleProfile{'Bedrooms'} = $documentReader->parseNumber($bedrooms);
   }
   if ($bathrooms)
   {
      $saleProfile{'Bathrooms'} = $documentReader->parseNumber($bathrooms);
   }
   if ($land)
   {
      $saleProfile{'Land'} = $documentReader->parseNumber($land);
   }
   if ($yearBuilt)
   {
      $saleProfile{'YearBuilt'} = $documentReader->parseNumber($yearBuilt);
   }    
   
   if ($streetNumber)
   {
      $saleProfile{'StreetNumber'} = $streetNumber;
   }
   if ($street)
   {
      $saleProfile{'Street'} = $street;
   }
   
   if ($city)
   {
      $saleProfile{'City'} = $city;
   }
   
   if ($zone)
   {
      $saleProfile{'Council'} = $zone;
   }
   
   if ($description)
   {
      $saleProfile{'Description'} = $description;
   }
   
   if ($features)
   {
      $saleProfile{'Features'} = $features;
   }

   $saleProfile{'State'} = $state;
     
   #DebugTools::printHash("SaleProfile", \%saleProfile);
        
   return %saleProfile;  
}

# -------------------------------------------------------------------------------------------------
$PRETTY_PRINT_WORDS = 1;
$PRETTY_PRINT_SENTANCES = 0;
# ------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# validateProfile
# validates the fields in the property record (for correctness)
#
# Purpose:
#  construction of the repositories
#
# Parameters:
#  saleProfile hash

# Updates:
#  database
#
# Returns:
#  validated sale profile
#    
sub validateProfile
{
   my $sqlClient = shift;
   my $profileRef = shift; 
   
   # match the suburb name to a recognised suburb name
   %matchedSuburb = matchSuburbName($sqlClient, $$profileRef{'SuburbName'}, $$profileRef{'State'});
     
   if (%matchedSuburb)
   {
      $$profileRef{'SuburbIndex'} = $matchedSuburb{'SuburbIndex'};
      $$profileRef{'SuburbName'} = $matchedSuburb{'SuburbName'};
   }
   
   # validate property type
   $$profileRef{'TypeIndex'} = PropertyTypes::mapPropertyType($$profileRef{'Type'});
   
   # validate number of bedrooms
   if (($$profileRef{'Bedrooms'} > 0) || (!defined $$profileRef{'Bedrooms'}))
   {
   }
   else
   {
       delete $$profileRef{'Bedrooms'};
   }

   # validate number of bathrooms
   if (($$profileRef{'Bathrooms'} > 0) || (!defined $$profileRef{'Bathrooms'}))
   {
   }
   else
   {
       delete $$profileRef{'Bathrooms'};
   }
   
   # validate land area
   if (($$profileRef{'Land'} > 0) || (!defined $$profileRef{'Land'}))
   {
   }
   else
   {
       delete $$profileRef{'Land'};
   }
      
   # validate advertised price lower
   if ((($$profileRef{'AdvertisedPriceLower'} > 0)) || (!defined $$profileRef{'AdvertisedPriceLower'}))
   {
   }
   else
   {
       delete $$profileRef{'AdvertisedPriceLower'};
   }
   
   # validate advertised price upper
   if ((($$profileRef{'AdvertisedPriceUpper'} > 0)) || (!defined $$profileRef{'AdvertisedPriceUpper'}))
   {
   }
   else
   {
       delete $$profileRef{'AdvertisedPriceUpper'};
   }
   
   # ---
   # attempt to remove phone numbers and personal details from the description
   #  - a  phone number is 8 to 10 digits.  It may contain zero or more whitespaces between each digit, but nothing else
   $description = $$profileRef{'Description'};
   #if ($description =~ /0(\s*){8,10}/g)
   if ($description =~ /(\d(\s*)){8,10}/g)
   {
      # there is a phone number in the message - delete the entire sentance containing the phone number
      # split into sentances...
      @sentanceList = split /[\.|\?|\!\*]/, $$profileRef{'Description'};
      $index = 0;
      # loop through each sentance looking for the pattern
      foreach (@sentanceList)
      {
         # if this sentance contains a phone number...
         if ($_ =~ /(\d(\s*)){8,10}/g)
         {
            # reject this sentance as it contains the pattern
            #BUGFIX 13 September 2004 - need to escape the sentance before it's included in the
            # regular expression as some characters can break the expression
            # - escape regular expression characters
            $sentanceList[$index] =~ s/(\(|\)|\?|\.|\*|\+|\^|\{|\}|\[|\]|\|)/\\$1/g;
            
            $description =~ s/($sentanceList[$index])([\.|\?|\!\*]*)//g;
         }
         $index++;
      }         
   }
   $$profileRef{'Description'} = $description;
   
   # do another parse of the description to remove phone numbers if a sentance couldn't be identified - replace the number with a blank
   $$profileRef{'Description'} =~ s/(\d(\s*)){8,10}//g;
   
   #---
   # now, search the description for information not provided explicitly in the fields - look for landArea in sqm in the text
   if (!defined $$profileRef{'Land'})
   {
      # determine if the description contains 'sqm' or a variation of that
      #  look for 1 or more digits followed by 0 or more spaces then SQM
      if ($$profileRef{'Description'} =~ /\d+(\s*)sqm/i)
      {
         $description = $$profileRef{'Description'};
         # this expression extracts the sqm number out into $2 and assigns it to $landArea 
         # the 'e' modified ensures the second expresion is executed
         $description =~ s/((\d+)(\s*)sqm)/$landArea = sprintf("$2")/ei;         
      } 
      
      if ((defined $landArea) && ($landArea > 0))
      {
         # assign the land area specified in the description
         $$profileRef{'Land'} = $landArea;
      }
   }

   #---
   # now, search the description for information not provided explicitly in the fields - look for bedrooms in the text
   if (!defined $$profileRef{'Bedrooms'})
   {
      
      # determine if the description contains 'sqm' or a variation of that
      #  look for 1 or more digits followed by any space and charcters until bedrooms.  Note that a non-digit or 
      # non alpha character will break the pattern (for example, a comma implies the number may not be associated with bedrooms)
      # this is pretty rough but should work most of the time
      $description = $$_{'Description'};
      if ($description =~ /(\d+)([\w|\s]*)bedroom/i)
      {
         # this expression extracts the bedrooms number out into $1 and assigns it to $bedrooms 
         # the 'e' modified ensures the second expresion is executed
         $description =~ s/(\d+)([\w|\s]*)bedroom/$bedrooms = sprintf("$1")/ei;         
      } 
      
      if ((defined $bedrooms) && ($bedrooms > 0))
      {
         # assign the land area specified in the description
         $$profileRef{'Bedrooms'} = $bedrooms;
      }
   }
   
    #---
   # now, search the description for information not provided explicitly in the fields - look for bathrooms in the text
   if (!defined $$profileRef{'Bathrooms'})
   {      
      #  look for 1 or more digits followed by any space and charcters until bath.  Note that a non-digit or 
      # non alpha character will break the pattern (for example, a comma implies the number may not be associated with bath)
      # this is pretty rough but should work most of the time
      $description = $$_{'Description'};
      if ($description =~ /(\d+)([\w|\s]*)bath/i)
      {
         # this expression extracts the bedrooms number out into $1 and assigns it to $bedrooms 
         # the 'e' modified ensures the second expresion is executed
         $description =~ s/(\d+)([\w|\s]*)bath/$bathrooms = sprintf("$1")/ei;         
      } 
      
      if ((defined $bathrooms) && ($bathrooms > 0))
      {
         # assign the land area specified in the description
         $$profileRef{'Bathrooms'} = $bathrooms;
      }
   }
   
   # format the text using standard conventions to easy comparison later
   $$profileRef{'SuburbName'} = prettyPrint($$profileRef{'SuburbName'}, 1);

   $$profileRef{'StreetNumber'} = prettyPrint($$profileRef{'StreetNumber'}, 1);

   $$profileRef{'Street'} = prettyPrint($$profileRef{'Street'}, 1);

   $$profileRef{'City'} = prettyPrint($$profileRef{'City'}, 1);

   $$profileRef{'Council'} = prettyPrint($$profileRef{'Council'}, 1);
   
   $$profileRef{'Description'} = prettyPrint($$profileRef{'Description'}, 0);

   $$profileRef{'Features'} = prettyPrint($$profileRef{'Features'}, 0);
}


# -------------------------------------------------------------------------------------------------
# change all characters to lowercase except the first character following a full stop, or the first character in the string
# if the allFirstUpper flag is set, then the first letter of all words is changed to uppercase, otherwise only the
# first letter of a sentance is changed to uppercase.
sub prettyPrint

{
   my $inputText = shift;
   my $allFirstUpper = shift;
   my $SEEKING_DOT = 0;
   my $SEEKING_NEXT_ALPHA = 1;
   my $SEEKING_FIRST_ALPHA = 2;
   my $state;
      
   # --- remove leading and trailing whitespace ---
   # substitute trailing whitespace characters with blank
   # s/whitespace from end-of-line/all occurances
   # s/\s*$//g;      
   $inputText =~ s/\s*$//g;

   # substitute leading whitespace characters and leading non-word characters with blank
   # s/whitespace from start-of-line,multiple single characters/blank/all occurances
   #s/^\s*//g;    
   $inputText =~ s/^[\s|\W]*//g; 
   
   # change all to lowercase
   $inputText =~ tr/[A-Z]/[a-z]/;
   
   
   # if the first upper flag has been set then the first alpha character of every word is to be uppercase
   if ($allFirstUpper)
   {
      # this expression works but it seems overly complicated
      # first it uses a substitution to match a single lowercase character at the start of each word (stored in $1)
      # then it evaluates the second expression which returns $1 in uppercase using sprintf
      # the ge modifiers ensure it's performed for every word and instructs the parser to evalutation the expression
     
      $inputText =~ s/(\b[a-z])/sprintf("\U$1")/ge;
      
      # note the above expression isn't perfect because the boundary of a word isn't just whitespace
      # for example, the above expresion would make isn't into Isn'T and i'm into I'M.
      # the expression below corrects for apostraphies.
      $inputText =~ s/(\'[A-Z])/sprintf("\L$1")/ge;
   }
   else
   {
      # --- change first character in a sentance to uppercase ---
      
      # a state machine is used to perform the special processing of the string.  This should be 
      # possible using a regular expression but I couldn't get it to work in every case.  
      # Instead the string is split into a list of characters...
      @charList = split //, $inputText;
   
      # then set the state machine to search for the next alpha character.  It sets this to uppercase
      # then searches for the next alphacharacter following a full-stop and sets that to uppercase, then 
      # repeats the search
      $state = $SEEKING_NEXT_ALPHA;
      $index = 0;
      foreach (@charList)
      {
        
         if ($state == $SEEKING_DOT)
         {
            if ($_ =~ m/[\.|\?|\!]/g)
            {
               $state = $SEEKING_NEXT_ALPHA;
            }
         }
         else
         {
            if ($state == $SEEKING_NEXT_ALPHA)
            {
               if ($_ =~ m/[a-z]/gi)
               {
                  $_ =~ tr/[a-z]/[A-Z]/;
                  $charList[$index] = $_;
                  $state = $SEEKING_DOT;
               }
            }
         }
       
         $index++;
      }
   
      # rejoin the array into a string
      $inputText = join '', @charList;
       
   }
  
   # special cases
   $inputText =~ s/(i\'m)/I\'m/gi;
   $inputText =~ s/(\si\s)/ I /gi;
   $inputText =~ s/(i\'ve)/I\'ve/gi;
   $inputText =~ s/(i\'d)/I\'d/gi;
      
   # remove multiple whitespaces
   $inputText =~ s/\s+/ /g;
   
   return $inputText;
}

# -------------------------------------------------------------------------------------------------

# searches the postcode list for a suburb matching the name specified
sub matchSuburbName
{   
   my $sqlClient = shift;
   my $suburbName = shift;
   my $state = shift;
   my %matchedSuburb;
   
   if (($sqlClient) && ($suburbName))
   {       
      $quotedSuburbName = $sqlClient->quote($suburbName);
      $quotedState = $sqlClient->quote($state);
      $statementText = "SELECT locality, postcode, SuburbIndex FROM AusPostCodes WHERE locality like $quotedSuburbName and state like $quotedState order by postcode limit 1";
            
      @suburbList = $sqlClient->doSQLSelect($statementText);
      
      if ($suburbList[0])
      {
         $matchedSuburb{'SuburbName'} = $suburbList[0]{'locality'};
         $matchedSuburb{'postcode'} = $suburbList[0]{'postcode'};              
         $matchedSuburb{'SuburbIndex'} = $suburbList[0]{'SuburbIndex'};
      }                    
   }   
   return %matchedSuburb;
}  


# -------------------------------------------------------------------------------------------------
# parseSearchDetails
# parses the htmlsyntaxtree to extract advertised sale information and insert it into the database
#
# Purpose:
#  construction of the repositories
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
sub parseSearchDetails

{	
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;
   my $instanceID = shift;
   my $transactionNo = shift;
   
   my $sqlClient = $documentReader->getSQLClient();
   my $tablesRef = $documentReader->getTableObjects();
   
   my $advertisedSaleProfiles = $$tablesRef{'advertisedSaleProfiles'};
   
   my %saleProfiles;
   my $checksum;   
   $printLogger->print("in parseSearchDetails\n");
   
   if ($htmlSyntaxTree->containsTextPattern("Property Details"))
   {
      # --- now extract the property information for this page ---
      #if ($htmlSyntaxTree->containsTextPattern("Suburb Profile"))
      #{                                    
      # parse the HTML Syntax tree to obtain the advertised sale information
      %saleProfiles = extractSaleProfile($documentReader, $htmlSyntaxTree, $url);  
      validateProfile($sqlClient, \%saleProfiles);
               
      # calculate a checksum for the information - the checksum is used to approximately 
      # identify the uniqueness of the data
      $checksum = $documentReader->calculateChecksum(\%saleProfiles);
            
      $printLogger->print("   parseSearchDetails: extracted checksum = ", $checksum, ". Checking log...\n");
             
      if ($sqlClient->connect())
      {		 	 
         # check if the log already contains this checksum - if it does, assume the tuple already exists                  
         if ($advertisedSaleProfiles->checkIfTupleExists($SOURCE_NAME, $saleProfiles{'SourceID'}, $checksum, $saleProfiles{'AdvertisedPriceLower'}))
         {
            # this tuple has been previously extracted - it can be dropped
            # record that it was encountered again
            $printLogger->print("   parseSearchDetails: identical record already encountered at $SOURCE_NAME.\n");
            $advertisedSaleProfiles->addEncounterRecord($SOURCE_NAME, $saleProfiles{'SourceID'}, $checksum);
         }
         else
         {
            $printLogger->print("   parseSearchDetails: unique checksum/url - adding new record.\n");
            # this tuple has never been extracted before - add it to the database
            $advertisedSaleProfiles->addRecord($SOURCE_NAME, \%saleProfiles, $url, $checksum, $instanceID, $transactionNo);         
         }
      }
      else
      {
         $printLogger->print("   parseSearchDetails:", $sqlClient->lastErrorMessage(), "\n");
      }
   }
   else
   {
      $printLogger->print("   parseSearchDetails: page identifier not found\n");
   }
   
   
   # return an empty list
   return @emptyList;
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# parseSearchForm
# parses the htmlsyntaxtree to post form information
#
# Purpose:
#  construction of the repositories
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
#  nil
#
# Returns:
#  a list of HTTP transactions or URL's.
#    
# http://public.reiwa.com.au/misc/menutypeOK.cfm?menutype=residential
sub parseSearchForm

{	
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;
   my $instanceID = shift;
   my $transactionNo = shift;
   
   my $htmlForm;
   my $actionURL;
   my $httpTransaction;
   my @transactionList;
   my $noOfTransactions = 0;
      
   $printLogger->print("in parseSearchForm\n");
      
   # get the HTML Form instance
   $htmlForm = $htmlSyntaxTree->getHTMLForm("search");
    
   if ($htmlForm)
   {       
      $actionURL = new URI::URL($htmlForm->getAction(), $url)->abs();
           
      %defaultPostParameters = $htmlForm->getPostParameters();            
      
      $defaultPostParameters{'MainArea'} = "0";   # all
      
      # for all of the suburbs defined in the form, create a transaction to get it
      $optionsRef = $htmlForm->getSelectionOptions('subdivision');
      # parse through all those in the perth metropolitan area
      if ($optionsRef)
      {         
         foreach (@$optionsRef)
         {               
            # create a duplicate of the default post parameters
            my %newPostParameters = %defaultPostParameters;
            
            # and set the value to this option in the selection            
            
            $newPostParameters{'subdivision'} = $_->{'value'};
            
            #($firstChar, $restOfString) = split(//, $_->{'text'});
            #print $_->{'text'}, " FC=$firstChar ($startLetter, $endLetter) ";
            $acceptSuburb = 1;
            if ($startLetter)
            {                              
               # if the start letter is defined, use it to constrain the range of 
               # suburbs processed
               # if the first letter if less than the start then reject               
               if ($_->{'text'} lt $startLetter)
               {
                  # out of range
                  $acceptSuburb = 0;
                #  print "out of start range\n";
               }                              
            }
                       
            if ($endLetter)
            {               
               # if the end letter is defined, use it to constrain the range of 
               # suburbs processed
               # if the first letter is greater than the end then reject       
               if ($_->{'text'} gt $endLetter)
               {
                  # out of range
                  $acceptSuburb = 0;
                #  print "out of end range\n";
               }               
            }
                  
            if ($acceptSuburb)
            {         
               #print "accepted\n";               
               my $newHTTPTransaction = HTTPTransaction::new($actionURL, 'POST', \%newPostParameters, $url);
            
               # add this new transaction to the list to return for processing
               $transactionList[$noOfTransactions] = $newHTTPTransaction;
               $noOfTransactions++;
            }
         }
      }
      
      $printLogger->print("   ParseSearchForm:Creating a transaction for $noOfTransactions metropolitan suburbs...\n");                             

      
      # 21 August 2004 - no added regional areas
      # for all of the suburbs defined in the form, create a transaction to get it
      $optionsRef = $htmlForm->getSelectionOptions('SubArea');
      delete $defaultPostParameters{'subdivision'};  # don't set subdivision
      
      if ($optionsRef)
      {         
         foreach (@$optionsRef)
         {               
            # create a duplicate of the default post parameters
            my %newPostParameters = %defaultPostParameters;
                         
            # and set the value to this option in the selection            
            
            if ($_->{'value'} != 0)  # ignore [All]
            {
               $newPostParameters{'SubArea'} = $_->{'value'};
            
               #($firstChar, $restOfString) = split(//, $_->{'text'});
               #print $_->{'text'}, " FC=$firstChar ($startLetter, $endLetter) ";
               $acceptSuburb = 1;
               if ($startLetter)
               {                              
                  # if the start letter is defined, use it to constrain the range of 
                  # suburbs processed
                  # if the first letter if less than the start then reject               
                  if ($_->{'text'} lt $startLetter)
                  {
                     # out of range
                     $acceptSuburb = 0;
                   #  print "out of start range\n";
                  }                              
               }
                          
               if ($endLetter)
               {               
                  # if the end letter is defined, use it to constrain the range of 
                  # suburbs processed
                  # if the first letter is greater than the end then reject       
                  if ($_->{'text'} gt $endLetter)
                  {
                     # out of range
                     $acceptSuburb = 0;
                   #  print "out of end range\n";
                  }               
               }
                     
               if ($acceptSuburb)
               {         
                  #print "accepted\n";               
                  my $newHTTPTransaction = HTTPTransaction::new($actionURL, 'POST', \%newPostParameters, $url);
               
                  # add this new transaction to the list to return for processing
                  $transactionList[$noOfTransactions] = $newHTTPTransaction;
                  $noOfTransactions++;
               }
            }
         }
      }
      
      $printLogger->print("   ParseSearchForm:Creating a transaction for $noOfTransactions total suburbs...\n");                             
   }	  
   else 
   {
      $printLogger->print("   parseSearchForm:Search form not found.\n");
   }
   
   if ($noOfTransactions > 0)
   {      
      return @transactionList;
   }
   else
   {      
      $printLogger->print("   parseSearchForm:returning zero transactions.\n");
      return @emptyList;
   }   
}

# -------------------------------------------------------------------------------------------------
# parseSearchQuery
# parses the htmlsyntaxtree generated in response to a search
#
# Purpose:
#  construction of the repositories
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
#  nil
#
# Returns:
#  a list of HTTP transactions or URL's.
#    
# http://public.reiwa.com.au/misc/searchQuery.cfm???
sub parseSearchQuery

{	
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;
   my $instanceID = shift;
   my $transactionNo = shift;
   
   my $htmlForm;
   my $actionURL;
   my $httpTransaction;
      
   $printLogger->print("in parseSearchQuery\n");
       
   # if this page contains a form to select whether to proceed or not...
   $htmlForm = $htmlSyntaxTree->getHTMLForm();
            
   if ($htmlForm)
   {       
      $actionURL = new URI::URL($htmlForm->getAction(), $url)->abs();
           
      %postParameters = $htmlForm->getPostParameters();
      $printLogger->print("   parseSearchQueury: returning POST transaction for continue form.\n");
      $httpTransaction = HTTPTransaction::new($actionURL, 'POST', \%postParameters, $url);            
   }	  
   else 
   {
      $printLogger->print("   parseSearchQuery: continue form not found\n");
   }
   
   if ($httpTransaction)
   {
      return ($httpTransaction);
   }
   else
   {      
      $printLogger->print("   parseSearchQuery: returning empty list\n");
      return @emptyList;
   }   
}

# -------------------------------------------------------------------------------------------------
# parseHomePage
# parses the htmlsyntaxtree to extract the link to the Advertised Sale page
#
# Purpose:
#  construction of the repositories
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
sub parseHomePage

{	
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;         
   my $instanceID = shift;   
   my $transactionNo = shift;
   
   my @anchors;
   
   # --- now extract the property information for this page ---
   $printLogger->print("inParseHomePage:\n");
   if ($htmlSyntaxTree->containsTextPattern("Real Estate Institute of Western Australia"))
   {                                     
      $anchor = $htmlSyntaxTree->getNextAnchorContainingPattern("Homes for Sale");
      if ($anchor)
      {
         $printLogger->print("   following anchor 'Homes for Sale'...\n");
      }
      else
      {
         $printLogger->print("   anchor 'Homes for Sale' not found!\n");
      }
   }	  
   else 
   {
      $printLogger->print("parseHomePage: pattern not found\n");
   }
   
   # return a list with just the anchor in it
   if ($anchor)
   {
      return ($anchor);
   }
   else
   {
      return @emptyList;
   }
}

# -------------------------------------------------------------------------------------------------
# parseSearchList
# parses the htmlsyntaxtree that contains the list of homes generated in response 
# to a query
#
# Purpose:
#  construction of the repositories
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
sub parseSearchList

{	
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;    
   my $instanceID = shift;
   my $transactionNo = shift;
   
   my @urlList;        
   my $firstRun = 1;
   
   # --- now extract the property information for this page ---
   $printLogger->print("inParseSearchList:\n");
   #$htmlSyntaxTree->printText();
   if ($htmlSyntaxTree->containsTextPattern("matching listings"))
   {         
      # get all anchors containing any text
      if ($housesListRef = $htmlSyntaxTree->getAnchorsAndTextContainingPattern("\#"))
      {  
         
         # loop through all the entries in the log cache
         $printLogger->print("   parseSearchList: checking if unqiue ID exists...\n");
         if ($sqlClient->connect())
         {
            foreach (@$housesListRef)
            {
               $sourceID = $$_{'string'};
               $sourceURL = $$_{'href'};
              
               # get the price range - the price is obtained to see if it's changed from the cache'd value.  If the price has
               # changed then the full record is downloaded again.
               if ($firstRun)
               {
                  $htmlSyntaxTree->setSearchStartConstraintByText($sourceID);
                  $firstRun = 0;
               }
              
               # get the price range - the price is obtained to see if it's changed from the cache'd value.  If the price has
               # changed then the full record is downloaded again.              
               $priceRangeString = $htmlSyntaxTree->getNextTextAfterPattern($sourceID);
               ($priceLowerString, $priceUpperString) = split /\-/, $priceRangeString;
               $priceLower = $documentReader->strictNumber($documentReader->parseNumber($priceLowerString, 1));
               $priceUpper = $documentReader->strictNumber($documentReader->parseNumber($priceUpperString, 1));
               if ($priceLower)
               {
                  $printLogger->print("   printSearchList: checking if price changed (now '$priceLower')\n");
               }
               # check if the cache already contains this unique id
               # $_ is a reference to a hash
               if (!$advertisedSaleProfiles->checkIfTupleExists($SOURCE_NAME, $sourceID, undef, $priceLower, $priceHigher))                              
               {   
                  $printLogger->print("   parseSearchList: adding anchor id ", $sourceID, "...\n");
                  #$printLogger->print("   parseSearchList: url=", $sourceURL, "\n");                  
                  push @urlList, $sourceURL;
               }
               else
               {
                  $printLogger->print("   parseSearchList: id ", $sourceID , " in database. Updating last encountered field...\n");
                  $advertisedSaleProfiles->addEncounterRecord($SOURCE_NAME, $sourceID, undef);
               }
            }
         }
         else
         {
            $printLogger->print("   parseSearchList:", $sqlClient->lastErrorMessage(), "\n");
         }         
         
         # now get the anchor for the NEXT button if it's defined 
         # this is an image with source 'right_btn'
         $nextButtonListRef = $htmlSyntaxTree->getAnchorsContainingImageSrc("right_btn");
                  
         if ($nextButtonListRef)
         {            
            $printLogger->print("   parseSearchList: list includes a 'next' button anchor...\n");
            @anchorsList = (@urlList, $$nextButtonListRef[0]);
         }
         else
         {            
            $printLogger->print("   parseSearchList: list has no 'next' button anchor...\n");
            @anchorsList = @urlList;
         }                      
        
         $length = @anchorsList;         
         $printLogger->print("   parseSearchList: following $length anchors...\n");         
      }
      else
      {
         $printLogger->print("   parseSearchList: no anchors found in list.\n");
      }
   }	  
   else 
   {
      $printLogger->print("   parseSearchList: pattern not found\n");
   }
   
   # return the list or anchors or empty list   
   if ($housesListRef)
   {      
      return @anchorsList;
   }
   else
   {      
      $printLogger->print("   parseSearchList: returning empty anchor list.\n");
      return @emptyList;
   }   
     
}

# -------------------------------------------------------------------------------------------------
# parseDisplayResponse
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
sub parseDisplayResponse

{	
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;         
   my $instanceID = shift;   
   my $transactionNo = shift;
   my @anchors;
   
   # --- now extract the property information for this page ---
   $printLogger->print("in ParseDisplayResponse:\n");
   $htmlSyntaxTree->printText();
   
   # return a list with just the anchor in it  
   return @emptyList;
   
}

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
   my $advertisedSaleProfiles = AdvertisedSaleProfiles::new($sqlClient);
   my $propertyTypes = PropertyTypes::new($sqlClient);
   
   return ($sqlClient, $advertisedSaleProfiles, $propertyTypes);
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

sub parseParameters
{   
   my $result = 0;
   
   my $createTables;
   my $startSession;
   my $continueSession;
   my $dropTables;
   my $maintenance;
   
   $createTables = param("create");
   
   $startSession = param("start");
     
   $continueSession = param("continue");
   
   $dropTables = param("drop");
   
   $maintenance = param("maintenance");
   
   $startLetter = param("startrange");
   $endLetter = param("endrange");
   $agent = param("agent");
   $statusPort = param("port");
   $state = param("state");
   $targetDatabase = param("database");
   
   if (($createTables) || ($startSession) || ($continueSession) || ($dropTables) || ($maintenance))
   {
      $result = 1;
   }
   
   return ($result, $createTables, $startSession, $continueSession, $dropTables, $maintenance);   
}

# -------------------------------------------------------------------------------------------------

sub doMaintenance
{   
   my $printLogger = shift;   
   my $sqlClient = SQLClient::new(); 
   my $advertisedSaleProfiles = AdvertisedSaleProfiles::new($sqlClient);
   my $propertyTypes = PropertyTypes::new($sqlClient);
   
   my $targetSQLClient = SQLClient::new($targetDatabase);
   my $targetAdvertisedSaleProfiles = AdvertisedSaleProfiles::new($targetSQLClient);
  
   $printLogger->print("---Performing Maintenance---\n");
   
   # 25 July 2004 - generate an instance ID based on current time and a random number.  The instance ID is 
   # used in the name of the logfile
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
   $year += 1900;
   $mon++;
   my $randNo = rand 1000;
   my $instanceID = sprintf("%s_%4i%02i%02i%02i%02i%02i_%04i", $agent, $year, $mon, $mday, $hour, $min, $sec, $randNo);

   #maintenance_ValidateContents($printLogger, $instanceID, $targetDatabase);
   maintenance_DeleteDuplicates($printLogger, $instanceID, $targetDatabase);
   
   $printLogger->print("---Finished Maintenance---\n");
   
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

sub maintenance_ValidateContents
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

sub maintenance_DeleteDuplicates
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
