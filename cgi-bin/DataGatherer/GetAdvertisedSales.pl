#!/usr/bin/perl
# 31 Mar 04
# Parses the detailed real-estate sales information to extract fields
#
#
# To do:
#  - better logging instead of using stdout
#  - front page for monitoring progress
#  - support to run from a cron job or CGI
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
use LogTable;
#use URI::URL;
use DebugTools;
use DocumentReader;
use AdvertisedSaleProfiles;


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

my $startURL = "http://www.reiwa.com.au/content-home.cfm";
#my $startURL = "http://localhost/trial/content-home.htm";
#my $startURL = "http://localhost/trial/searchdetails4.htm";
#my $startURL = "http://localhost/cgi-bin/CookieTests.pl"; 

my $useText = 0;
my $createTables = 0;
my $getSuburbProfiles = 0;
my $dropTables = 0;
my $continueSession = 0;

# these two parameters are used to limit the letter range of suburbs processed
# by this instance of the application
my $startLetter;
my $endLetter;
my $agent;

my $useHTML = param('html');

($parseSuccess, $createTables, $startSession, $continueSession, $dropTables) = parseParameters();

if (!$useHTML)
{
   $useText = 1;  
}

if (!$agent)
{
   $agent = "GetAdvertisedSales";
}

my $printLogger = PrintLogger::new($agent, $agent.".stdout", 1, $useText, $useHTML);

$printLogger->printHeader("Advertised Sales\n");


# load the configuration file
my %parameters = loadConfiguration($agent.".config", $printLogger);

if (!$parameters{'url'})
{
   $printLogger->print("   main: Configuration file not found\n");
}

if (($parseSuccess) && ($parameters{'url'}))
{            
   ($sqlClient, $advertisedSaleProfiles, $logTable) = initialiseTableObjects();
   # hash of table objects - the key's are only significant to the local callback functions
 
   $myTableObjects{'advertisedSaleProfiles'} = $advertisedSaleProfiles;
   $myTableObjects{'logTable'} = $logTable;
   
   $myParsers{"searchdetails"} = \&parseSearchDetails;
   $myParsers{"search.cfm"} = \&parseSearchForm;
   $myParsers{"content-home"} = \&parseHomePage;
   $myParsers{"searchquery"} = \&parseSearchQuery;
   $myParsers{"searchlist"} = \&parseSearchList;
   $myParsers{"CGIPostTest"} = \&parseDisplayResponse;   
     
   my $myDocumentReader = DocumentReader::new($agent, $startURL, $sqlClient, 
      \%myTableObjects, \%myParsers, $printLogger);
   
   $myDocumentReader->setProxy("http://netcache.dsto.defence.gov.au:8080");
   $myDocumentReader->run($createTables, $startSession, $continueSession, $dropTables);
}
else
{
   $printLogger->print("   main: No action requested\n");
}

$printLogger->printFooter("Finished");


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

     
   #DebugTools::printHash("SaleProfile", \%saleProfile);
        
   return %saleProfile;  
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
   
   my $sqlClient = $documentReader->getSQLClient();
   my $tablesRef = $documentReader->getTableObjects();
   
   my $advertisedSaleProfiles = $$tablesRef{'advertisedSaleProfiles'};
   my $logtable = $$tablesRef{'logTable'};
   
   my %saleProfiles;
   my $checksum;   
   $printLogger->print("in parseSearchDetails\n");
   
   # --- now extract the property information for this page ---
   if ($htmlSyntaxTree->containsTextPattern("Suburb Profile"))
   {                                    
      # parse the HTML Syntax tree to obtain the advertised sale information
      %saleProfiles = extractSaleProfile($documentReader, $htmlSyntaxTree, $url);                  
            
      # calculate a checksum for the information - the checksum is used to approximately 
      # identify the uniqueness of the data
      $checksum = $documentReader->calculateChecksum(\%saleProfiles);
         
      $printLogger->print("   parseSearchDetails: extracted checksum = ", $checksum, ". Checking log...\n");
          
      if ($sqlClient->connect())
      {		 	 
         # check if the log already contains this checksum - if it does, assume the tuple already exists                  
         if ($logTable->checkIfTupleExists($url, $checksum))
	      {
            # this tuple has been previously extracted - it can be dropped
            # record in the log that it was encountered again
            $printLogger->print("   parseSearchDetails: record already encountered at that URL.\n");
	         $logTable->addEncounterRecord($url, $checksum);
         }
         else
         {
            $printLogger->print("   parseSearchDetails: unique checksum/url - adding new record.\n");
            # this tuple has never been extracted before - add it to the database
            if ($advertisedSaleProfiles->addRecord(\%saleProfiles))
            {
               $printLogger->print("   parseSearchDetails: recording log for sourceID ", $saleProfiles{'SourceID'}, ".\n");
               # successfully added the tuple - log the checksum
               $logTable->addRecord($url, $saleProfiles{'SourceID'}, $checksum);
            }
         }
      }
      else
      {
         $printLogger->print("   parseSearchDetails:", $sqlClient->lastErrorMessage(), "\n");
      }
   }	  
   else 
   {
      $printLogger->print("parseSearchDetails: Identifier pattern not found.\n");
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
      
      # for all of the suburbs defined in the form, create a transaction to get it
      $optionsRef = $htmlForm->getSelectionOptions('subdivision');
      if ($optionsRef)
      {         
         foreach (@$optionsRef)
         {            
            # create a duplicate of the default post parameters
            my %newPostParameters = %defaultPostParameters;            
            # and set the value to this option in the selection
            
            $newPostParameters{'subdivision'} = $_->{'value'};
            ($firstChar, $restOfString) = split(//, $_->{'text'});
            #print $_->{'text'}, " FC=$firstChar ($startLetter, $endLetter) ";
            $acceptSuburb = 1;
            if ($startLetter)
            {                              
               # if the start letter is defined, use it to constrain the range of 
               # suburbs processed
               # if the first letter if less than the start then reject               
               if ($firstChar lt $startLetter)
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
               if ($firstChar gt $endLetter)
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
      
      $printLogger->print("   ParseSearchForm:Creating a transaction for $noOfTransactions suburbs...\n");                             
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
   my @urlList;        
   
   # --- now extract the property information for this page ---
   $printLogger->print("inParseSearchList:\n");
   #$htmlSyntaxTree->printText();
   if ($htmlSyntaxTree->containsTextPattern("matching listings"))
   {         
      # get all anchors containing any text
      if ($housesListRef = $htmlSyntaxTree->getAnchorsAndTextContainingPattern("\#"))
      {  
         # loop through all the entries in the log cache
         $printLogger->print("   parseSearchList: checking unqiue ID cache...\n");
         if ($sqlClient->connect())
         {
            foreach (@$housesListRef)
            {
               # check if the cache already contains this unique id
               # $_ is a reference to a hash                              
               if (!$logTable->checkIfUniqueIDExists($$_{'string'}))
               {   
                  $printLogger->print("   parseSearchList: adding anchor id ", $$_{'string'}, "...\n");
                  $printLogger->print("   parseSearchList: url=", $$_{'href'}, "\n");                  
                  push @urlList, $$_{'href'};
               }
               else
               {
                  $printLogger->print("   parseSearchList: id ", $$_{'string'} , " already in cache.  Ignoring anchor...\n");
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
   my $logTable = LogTable::new($sqlClient, "AdvertisedSaleProfilesLog");
 
   return ($sqlClient, $advertisedSaleProfiles, $logTable);
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
   
   $createTables = param("create");
   
   $startSession = param("start");
     
   $continueSession = param("continue");
   
   $dropTables = param("drop");
   
   $startLetter = param("startrange");
   $endLetter = param("endrange");
   $agent = param("agent");

   if (($createTables) || ($startSession) || ($continueSession) || ($dropTables))
   {
      $result = 1;
   }
   
   return ($result, $createTables, $startSession, $continueSession, $dropTables);   
}


