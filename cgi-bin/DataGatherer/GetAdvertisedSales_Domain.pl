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
#
#  11 July 2004 - modified to support domain.com.au
#
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
   print "   Loading configuration file $filename\n";   
   if (-e $filename)
   {             
      open(PARAM_FILE, "<$filename") || $printLogger->print("   main: Can't open configuration file: $!"); 
                 
      # loop through the content of the file
      while (<PARAM_FILE>) # read a line into $_
      {
         # remove end of line marker from $_
         chomp;
         # split on 1st equals character
         ($key, $value) = split(/=/, $_, 2);	 	          
         $parameters{$key} = $value;                                    
      }
      
      close(PARAM_FILE);
   }
   else
   {
      print "   Configuration file not found.\n";
   }      
   
   return %parameters;
}

#  
# -------------------------------------------------------------------------------------------------    

my $SOURCE_NAME = "Domain";
my $useText = 0;
my $createTables = 0;
my $getSuburbProfiles = 0;
my $dropTables = 0;
my $continueSession = 0;
my $statusPort = undef;
my $state;

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
   $agent = "GetAdvertisedSales_Domain";
}

my $printLogger = PrintLogger::new($agent, $agent.".stdout", 1, $useText, $useHTML);
my $statusServer;

$printLogger->printHeader("$agent\n");


# load the configuration file
my %parameters = loadConfiguration($agent.".config", $printLogger);

if (!$parameters{'url'})
{
   $printLogger->print("   main: Configuration file not found\n");
}

if (($parseSuccess) && ($parameters{'url'}) && ($state))
{
   
   ($sqlClient, $advertisedSaleProfiles) = initialiseTableObjects();
   # hash of table objects - the key's are only significant to the local callback functions
 
   $myTableObjects{'advertisedSaleProfiles'} = $advertisedSaleProfiles;
   
   $myParsers{"ChooseState"} = \&parseChooseState;
   $myParsers{"ChooseRegions"} = \&parseChooseRegions;
   $myParsers{"ChooseSuburbs"} = \&parseChooseSuburbs;
   
   $myParsers{"SearchResults"} = \&parseSearchResults;
   
   #$myParsers{"searchdetails"} = \&parseSearchDetails;
   
   #$myParsers{"searchquery"} = \&parseSearchQuery;
   #$myParsers{"searchlist"} = \&parseSearchList;
   #$myParsers{"CGIPostTest"} = \&parseDisplayResponse;   

   my $myDocumentReader = DocumentReader::new($agent, $parameters{'url'}, $sqlClient, 
      \%myTableObjects, \%myParsers, $printLogger);

   $myDocumentReader->setProxy("http://localhost:8080");
   $myDocumentReader->run($createTables, $startSession, $continueSession, $dropTables);
 
}
else
{
   if (!$state)
   {
      $printLogger->print("   main: state not specified\n");
   }
   $printLogger->print("   main: No action requested\n");
   
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
   
   my %saleProfiles;
   my $checksum;   
   $printLogger->print("in parseSearchDetails\n");
   
   # --- now extract the property information for this page ---
   #if ($htmlSyntaxTree->containsTextPattern("Suburb Profile"))
   #{                                    
   # parse the HTML Syntax tree to obtain the advertised sale information
   %saleProfiles = extractSaleProfile($documentReader, $htmlSyntaxTree, $url);                  
            
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
         $advertisedSaleProfiles->addRecord($SOURCE_NAME, \%saleProfiles, $url, $checksum);         
      }
   }
   else
   {
      $printLogger->print("   parseSearchDetails:", $sqlClient->lastErrorMessage(), "\n");
   }
   
   
   # return an empty list
   return @emptyList;
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# parseChooseSuburbs
# parses the htmlsyntaxtree to post form information to select suburbs
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
sub parseChooseSuburbs
{	
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;
   my $htmlForm;
   my $actionURL;
   my $httpTransaction;
   my @transactionList;
   my $noOfTransactions = 0;
      
   $printLogger->print("in parseChooseSuburbs\n");
   
 
   if ($htmlSyntaxTree->containsTextPattern("Property Search"))
   {
       
      # get the HTML Form instance
      $htmlForm = $htmlSyntaxTree->getHTMLForm("Form2");
       
      if ($htmlForm)
      {       
         $actionURL = new URI::URL($htmlForm->getAction(), $url)->abs();
              
         %defaultPostParameters = $htmlForm->getPostParameters();            
         
         # for all of the suburbs defined in the form, create a transaction to get it
         $optionsRef = $htmlForm->getSelectionOptions('listboxSuburbs');
         if ($optionsRef)
         {         
            foreach (@$optionsRef)
            {  
   
               $value = $_->{'value'};
               if ($value =~ /All Suburbs/i)
               {
                  # ignore 'all suburbs' option
               }
               else
               {
                  print $_->{'value'}, "\n";
                  # create a duplicate of the default post parameters
                  my %newPostParameters = %defaultPostParameters;            
                  # and set the value to this option in the selection
                  
                  $newPostParameters{'listboxSuburbs'} = $_->{'value'};
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
         
         $printLogger->print("   ParseChooseSuburbs:Creating a transaction for $noOfTransactions suburbs...\n");                             
      }	  
      else 
      
      {
         $printLogger->print("   parseChooseSuburbs:Search form not found.\n");
      }
   }
   else
   {
      # for some dodgy reason the action for the form above actually comes back to the same page, put returns
      # a STATUS 302 object has been moved message, pointing to an alternative page.  Seems like a hack
      # to overcome a problem with their server.  I don't know why they don't just post to a different address, but anyway,
      # this code detects the object not found message and follows the alternative URL
      if ($htmlSyntaxTree->containsTextPattern("Object moved"))
      {
         $printLogger->print("   parseChooseSuburbs: following object moved redirection...\n");
         $anchor = $htmlSyntaxTree->getNextAnchorContainingPattern("here");
         if ($anchor)
         {
            $printLogger->print("   following anchor 'here'\n");
            $httpTransaction = HTTPTransaction::new($anchor, 'GET', undef, $url);
            
            $transactionList[$noOfTransactions] = $httpTransaction;
            $noOfTransactions++;
         }
         
      }
      else
      {
         $printLogger->print("   parseChooseSuburbs: pattern not found\n");
      }
   }
   
   if ($noOfTransactions > 0)
   {      
      return @transactionList;
   }
   else
   {      
      $printLogger->print("   parseChooseSuburbs:returning zero transactions.\n");
      return @emptyList;
   }   
}

# -------------------------------------------------------------------------------------------------
# parseChooseRegions
# parses the htmlsyntaxtree to select the regions to follow
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
sub parseChooseRegions

{	
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;
   my $htmlForm;
   my $actionURL;
   my $httpTransaction;
   my $anchor;
      
   $printLogger->print("in parseChooseRegions\n");
    
    
   if ($htmlSyntaxTree->containsTextPattern("Select Region"))
   {
      
      # if this page contains a form to select whether to proceed or not...
      $htmlForm = $htmlSyntaxTree->getHTMLForm();
           
      #$htmlSyntaxTree->printText();     
      if ($htmlForm)
      {       
         $actionURL = new URI::URL($htmlForm->getAction(), $url)->abs();
         print "actionURL = $actionURL\n"; 
         # get all of the checkboxes and set them
         $checkboxListRef = $htmlForm->getCheckboxes();
        
         foreach (@$checkboxListRef)
         {     
            # $_ is a reference to an HTMLFormCheckbox
            # set this checkbox input to true
            $htmlForm->setInputValue($_->getName(), 'on');
         }
  
         %postParameters = $htmlForm->getPostParameters();
        
         #DebugTools::printHash("postParameters", \%postParameters);
         $printLogger->print("   parseChooseRegions: returning POST transaction selecting all checkboxes.\n");
         $httpTransaction = HTTPTransaction::new($actionURL, 'POST', \%postParameters, $url);            
      }	  
      else 
      {
         $printLogger->print("   parseChooseRegions: regions form not found\n");
      }
   }
   else
   {
      # for some dodgy reason the action for the form above actually comes back to the same page, put returns
      # a STATUS 302 object has been moved message, pointing to an alternative page.  Seems like a hack
      # to overcome a problem with their server.  I don't know why they don't just post to a different address, but anyway,
      # this code detects the object not found message and follows the alternative URL
      if ($htmlSyntaxTree->containsTextPattern("Object moved"))
      {
         $printLogger->print("   parseChooseRegions: following object moved redirection...\n");
         $anchor = $htmlSyntaxTree->getNextAnchorContainingPattern("here");
         if ($anchor)
         {
            $printLogger->print("   following anchor 'here'\n");
            $httpTransaction = HTTPTransaction::new($anchor, 'GET', undef, $url);
         }
         
         #$htmlSyntaxTree->printText();
      }
   }
   
   if ($httpTransaction)
   {
      return ($httpTransaction);
   }
   else
   {      
      $printLogger->print("   parseChooseRegions: returning empty list\n");
      return @emptyList;
   }   
}

# -------------------------------------------------------------------------------------------------
# parseChooseState
# parses the htmlsyntaxtree to extract the link to each of the specified state
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
sub parseChooseState

{	
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;         
   my @anchors;
   
   # --- now extract the property information for this page ---
   $printLogger->print("inParseChooseState:\n");
   
   if ($htmlSyntaxTree->containsTextPattern("State Search"))
   { 
      $htmlSyntaxTree->setSearchStartConstraintByText("search by region");
      $htmlSyntaxTree->setSearchEndConstraintByText("Quick Search");                                    
      $anchor = $htmlSyntaxTree->getNextAnchorContainingPattern($state);
      if ($anchor)
      {
         $printLogger->print("   following anchor '$state'\n");
      }
      else
      {
         $printLogger->print("   anchor '$state' not found!\n");
      }
   }	  
   else 
   {
      $printLogger->print("parseChooseState: pattern not found\n");
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
# parseSearchResults
# parses the htmlsyntaxtree that contains the list of properties generated in response 
# to to the search query
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
sub parseSearchResults

{	
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;    
   my @urlList;        
   my $firstRun = 1;
   
   # --- now extract the property information for this page ---
   $printLogger->print("inParseSearchResults:\n");
   #$htmlSyntaxTree->printText();
   if ($htmlSyntaxTree->containsTextPattern("Search Results"))
   {         
      
      if ($sqlClient->connect())
      {
      
         # loop through something...
         
         # each entry is in it's own table.
         # the suburb name and price are in an H4 tag
         # the next non-image anchor href attribute contains the unique ID
         
         while ($htmlSyntaxTree->setSearchStartConstraintByTag('h4'))
         {
            
            $titleString = $htmlSyntaxTree->getNextText();
            $sourceURL = $htmlSyntaxTree->getNextAnchor();
            
            # not sure why this is needed - it shifts it onto the next property, otherwise it finds the same one twice. 
            $htmlSyntaxTree->setSearchStartConstraintByTag('h4');
            
            # --- extract values ---
            ($crud, $priceLowerString) = split(/\$/, $titleString, 2);
            if ($priceLowerString)
            {
               $priceLower = $documentReader->strictNumber($documentReader->parseNumber($priceLowerString));
            }
            
            # remove non-numeric characters from the string occuring before the question mark
            ($sourceID, $crud) = split(/\?/, $sourceURL, 2);            
            $sourceID =~ s/[^0-9]//gi;
            
            #print "sourceID = $sourceID\n";
                    
            # check if the cache already contains this unique id
            
            if (!$advertisedSaleProfiles->checkIfTupleExists($SOURCE_NAME, $sourceID, undef, $priceLower, undef))                              
            {   
               $printLogger->print("   parseSearchResults: adding anchor id ", $sourceID, "...\n");
               $printLogger->print("   parseSearchResults: url=", $sourceURL, "\n");                  
                push @urlList, $sourceURL;
            }
            else
            {
               $printLogger->print("   parseSearchResults: id ", $sourceID , " in database. Updating last encountered field...\n");
               $advertisedSaleProfiles->addEncounterRecord($SOURCE_NAME, $sourceID, undef);
            }        
         }
      }
      else
      {
         $printLogger->print("   parseSearchResults:", $sqlClient->lastErrorMessage(), "\n");
      }         
         
      # now get the anchor for the NEXT button if it's defined 
      $nextButtonListRef = $htmlSyntaxTree->getNextAnchorContainingPattern("Next Page");
                    
      if ($nextButtonListRef)
      {            
         $printLogger->print("   parseSearchResults: list includes a 'next' button anchor...\n");
         @anchorsList = (@urlList, $$nextButtonListRef[0]);
      }
      else
      {            
         $printLogger->print("   parseSearchResults: list has no 'next' button anchor...\n");
         @anchorsList = @urlList;
      }                      
        
      $length = @anchorsList;         
      $printLogger->print("   parseSearchResults: following $length anchors...\n");               
   }	  
   else 
   {
      # for some dodgy reason the action for the form above actually comes back to the same page, put returns
      # a STATUS 302 object has been moved message, pointing to an alternative page.  Seems like a hack
      # to overcome a problem with their server.  I don't know why they don't just post to a different address, but anyway,
      # this code detects the object not found message and follows the alternative URL
      if ($htmlSyntaxTree->containsTextPattern("Object moved"))
      {
         $printLogger->print("   parseSearchResults: following object moved redirection...\n");
         $anchor = $htmlSyntaxTree->getNextAnchorContainingPattern("here");
         if ($anchor)
         {
            $printLogger->print("   following anchor 'here'\n");
            $httpTransaction = HTTPTransaction::new($anchor, 'GET', undef, $url);
         }
         
      }
      else
      {
         $printLogger->print("   parseSearchResults: pattern not found\n");
      }
   }
   
   # return the list or anchors or empty list   
   #if ($housesListRef)
   #{      
   #   return @anchorsList;
   #}
   #else
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
 
   return ($sqlClient, $advertisedSaleProfiles);
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
   $statusPort = param("port");
   $state = param("state");
   
   if (($createTables) || ($startSession) || ($continueSession) || ($dropTables))
   {
      $result = 1;
   }
   
   return ($result, $createTables, $startSession, $continueSession, $dropTables);   
}


