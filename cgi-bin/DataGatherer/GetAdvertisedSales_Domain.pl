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
#  25 July 2004 - added support for instanceID and transactionNo parameters in parser callbacks
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
my $city;

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

if (($parseSuccess) && ($parameters{'url'}) && ($state) && ($city))
{
   
   ($sqlClient, $advertisedSaleProfiles) = initialiseTableObjects();
   # hash of table objects - the key's are only significant to the local callback functions
 
   $myTableObjects{'advertisedSaleProfiles'} = $advertisedSaleProfiles;
   
   $myParsers{"ChooseState"} = \&parseChooseState;
   $myParsers{"ChooseRegions"} = \&parseChooseRegions;
   $myParsers{"ChooseSuburbs"} = \&parseChooseSuburbs;   
   $myParsers{"SearchResults"} = \&parseSearchResults;   
   $myParsers{"property="} = \&parsePropertyDetails;
  
   my $myDocumentReader = DocumentReader::new($agent, $instanceID, $parameters{'url'}, $sqlClient, 
      \%myTableObjects, \%myParsers, $printLogger);

   #$myDocumentReader->setProxy("http://localhost:8080");
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
               
   $htmlSyntaxTree->setSearchStartConstraintByText("E-mail me similar properties");
   $htmlSyntaxTree->setSearchEndConstraintByText("Agent Details"); 
   
   # extract the suburb name from the URL.  This is the easiest place to get it as it's used in the
   # path and has spaces replaced with an underscore.  
   @wordList = split(/\//, $url);   # split on /
   # second last word is always suburb name
   $length = @wordList;
   $suburb = $wordList[$length-2];
   # replace underscore(s) with space character
   $suburb =~ s/_/ /g;
   
   $sourceID =~ s/[^0-9]//gi;
                 
   $addressString = $htmlSyntaxTree->getNextText();    # always set, but may not contain the address (just the suburb/town)   
   
   # the last word(s) are ALWAYS the suburb name.  As this is known, drop it to leave just street & street number
   # notes on the regular expression:
   #  \b is used to match only the whole word
   #  $ at the end of the expression ensures it matches only at the end of the pattern (this overcomes the case where the
   #  suburb name is also in the street name
   $addressString =~ s/\b$suburb\b$//i;

   $street= undef;
   $streetNumber = undef;
   @wordList = split(/ /, $addressString);   # parse one word at a time 
   # the street number and street can be a variable number of words.  It's very annony to split.
   # best method seems to be to allocate all words LEFT of (and including) a numeral to the number, and the
   # balance to the street name
   # note: if no numerals are encountered, then the entire string is street name
   # TO DO: an improvement may be to look for recognised 'street types'
   $index = 0;
   $lastNumeralWord = -1;
   $length = @wordList;
   foreach (@wordList)
   {
      if ($_)
      {
         # if this word contains a numeral
         if ($_ =~ /[0-9]/)
         {
            $lastNumeralWord = $index;
         }
      }
      $index++;
      
   }
   #print "lastNumeralAt $lastNumeralWord\n";
   if ($lastNumeralWord >= 0)
   {
      for ($index = 0; $index <= $lastNumeralWord; $index++)
      {
         $streetNumber .= $wordList[$index]." ";
      }
      
      # place the balance of the word list into the street name
      for ($index = $lastNumeralWord+1; $index < $length; $index++)
      {
         $street .= $wordList[$index]." ";
      }
   }
   else
   {
      # no street number encountered - allocate entirely to street name
      $street = $addressString;
   }
   
   $streetNumber = $documentReader->trimWhitespace($streetNumber);
   $street = $documentReader->trimWhitespace($street);
   
   $priceString = $htmlSyntaxTree->getNextTextAfterPattern("Price:");
   # price string is sometimes lower followed by a dash then price upper
   ($priceLowerString, $priceUpperString) = split(/-/, $priceString, 2);
   #print "priceLowerString = $priceLowerString\n";
   #print "priceUpperString = $priceUpperString\n";
   $priceLower = $documentReader->strictNumber($documentReader->parseNumberSomewhereInString($priceLowerString));
   $priceUpper = $documentReader->strictNumber($documentReader->parseNumberSomewhereInString($priceUpperString));
   
   $infoString = $documentReader->trimWhitespace($htmlSyntaxTree->getNextTextAfterPattern("Property Details"));  # always set (contains at least TYPE)
   
   $bedroomsString = undef;
   $bathroomsString = undef;
   
   # type is the first word
   @wordList = split(/ /, $infoString);
   $type = $documentReader->trimWhitespace($wordList[0]);
   # 'x' bedrooms
   # 'y' bathrooms
   $index = 0;
   foreach (@wordList)
   {
      if ($_)
      {
         # if this is the bedrooms word, the preceeding word is the number of them
         if ($_ =~ /bedroom/i)
         {
            if ($index > 0)
            {              
               $bedroomsString = $wordList[$index-1];
            }
         }
         else
         {
            # if this is the bedrooms word, the preceeding word is the number of them
            if ($_ =~ /bathroom/i)
            {
               if ($index > 0)
               {
                  $bathroomsString = $wordList[$index-1];
               }
            }
         }
      }
      $index++;
   }
   
   $bedrooms = $documentReader->strictNumber($documentReader->parseNumber($bedroomsString));
   $bathrooms = $documentReader->strictNumber($documentReader->parseNumber($bathroomsString));
   
   $landArea = $htmlSyntaxTree->getNextTextAfterPattern("area:");  # optional
   $land = $documentReader->strictNumber($documentReader->parseNumber($landArea));
   
   $title = $htmlSyntaxTree->getNextTextAfterPattern("Description");
   $description = $documentReader->trimWhitespace($htmlSyntaxTree->getNextText());
   
   $htmlSyntaxTree->resetSearchConstraints();
   if (($htmlSyntaxTree->setSearchStartConstraintByText("Features")) && ($htmlSyntaxTree->setSearchEndConstraintByText("Description")))
   {
      # append all text in the features section
      $features = undef;
      while ($nextFeature = $htmlSyntaxTree->getNextText())
      {
         if ($features)
         {
            $features .= ", ";
         }
         
         $features .= $nextFeature;
      }
      $features = $documentReader->trimWhitespace($features);
      
   }
   
   # remove non-numeric characters from the string occuring before the question mark to get source ID
   ($sourceID, $crud) = split(/\?/, $url, 2);            
   $sourceID =~ s/[^0-9]//gi;
              
   $saleProfile{'SourceID'} = $sourceID;      
   
   if ($suburb) 
   {
      $saleProfile{'SuburbName'} = $suburb;
   }
   
   if ($priceUpper) 
   {
      $saleProfile{'AdvertisedPriceUpper'} = $documentReader->parseNumber($priceUpper);
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
# parsePropertyDetails
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
sub parsePropertyDetails

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
   $printLogger->print("in parsePropertyDetails\n");
   
   
   if ($htmlSyntaxTree->containsTextPattern("Property Details"))
   {
                                         
      # parse the HTML Syntax tree to obtain the advertised sale information
      %saleProfiles = extractSaleProfile($documentReader, $htmlSyntaxTree, $url);                  
            
      # calculate a checksum for the information - the checksum is used to approximately 
      # identify the uniqueness of the data
      $checksum = $documentReader->calculateChecksum(\%saleProfiles);
            
      $printLogger->print("   parsePropertyDetails: extracted checksum = ", $checksum, ". Checking log...\n");
             
      if ($sqlClient->connect())
      {		 	 
         # check if the log already contains this checksum - if it does, assume the tuple already exists                  
         if ($advertisedSaleProfiles->checkIfTupleExists($SOURCE_NAME, $saleProfiles{'SourceID'}, $checksum, $saleProfiles{'AdvertisedPriceLower'}))
         {
            # this tuple has been previously extracted - it can be dropped
            # record that it was encountered again
            $printLogger->print("   parsePropertyDetails: identical record already encountered at $SOURCE_NAME.\n");
            $advertisedSaleProfiles->addEncounterRecord($SOURCE_NAME, $saleProfiles{'SourceID'}, $checksum);
         }
         else
         {
            $printLogger->print("   parsePropertyDetails: unique checksum/url - adding new record.\n");
            # this tuple has never been extracted before - add it to the database
            $advertisedSaleProfiles->addRecord($SOURCE_NAME, \%saleProfiles, $url, $checksum, $instanceID, $transactionNo);         
         }
      }
      else
      {
         $printLogger->print("   parsePropertyDetails:", $sqlClient->lastErrorMessage(), "\n");
      }
   }
   else
   {
      $printLogger->print("   parsePropertyDetails:property details not found.\n");      
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
   my $instanceID = shift;
   my $transactionNo = shift;
   
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
         $actionURL = new URI::URL($htmlForm->getAction(), $parameters{'url'})->abs();
              
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
                  #($firstChar, $restOfString) = split(//, $_->{'text'});
                  #print $_->{'text'}, " FC=$firstChar ($startLetter, $endLetter) ";
                  $acceptSuburb = 1;
                  if ($startLetter)
                  {                              
                     # if the start letter is defined, use it to constrain the range of 
                     # suburbs processed
                     # if the first letter if less than the start then reject               
                     if ($_->{'text'} le $startLetter)
                     {
                        # out of range
                        $acceptSuburb = 0;
                   #     print "out of start range\n";
                     }                              
                  }
                             
                  if ($endLetter)
                  {               
                     # if the end letter is defined, use it to constrain the range of 
                     # suburbs processed
                     # if the first letter is greater than the end then reject       
                     if ($_->{'text'} ge $endLetter)
                     {
                        # out of range
                        $acceptSuburb = 0;
                   #     print "out of end range\n";
                     }               
                  }
                        
                  if ($acceptSuburb)
                  {         
                     my %newPostParameters;
                     
                     # 2 Aug 04 - I don't understand why this was necessary, but if the default post parameters
                     # hash was copied directly then 1Mb of memory per transaction is allocated.  Copying it 
                     # manually like this only allocates scalars.  Strange.
                     # create a duplicate of the default post parameters
                     #my %newPostParameters2 = %defaultPostParameters;                             
                     # and set the value to this option in the selection
                     #$newPostParameters2{'listboxSuburbs'} = $_->{'value'};
                     #DebugTools::printHash("oldPost", \%newPostParameters2);
                     
                     $newPostParameters{'txtKeywords'}=$defaultPostParameters{'txtKeywords'};
                     $newPostParameters{'dropPriceFromSale'}=$defaultPostParameters{'dropPriceFromSale'};
                     $newPostParameters{'listboxPropertyType'}=$defaultPostParameters{'listBoxPropertyType'};
                     $newPostParameters{'dropPriceToSale'}=$defaultPostParameters{'dropPriceToSale'};
                     $newPostParameters{'listboxBedrooms'}=$defaultPostParameters{'listboxBedrooms'};
                     $newPostParameters{'imgbtnSearch.x'}=$defaultPostParameters{'imgbtnSearch.x'};
                     $newPostParameters{'imgbtnSearch.y'}=$defaultPostParameters{'imgbtnSearch.y'};
                     $newPostParameters{'listboxSuburbs'} = $_->{'value'};
                     $newPostParameters{'__VIEWSTATE'} = $defaultPostParameters{'__VIEWSTATE'};
                     
                     #DebugTools::printHash("newPost", \%newPostParameters);
                                       #print "actionURL= $actionURL\n";
                                       #print "url=$url\n";
                     my $newHTTPTransaction = HTTPTransaction::new($actionURL, 'POST', \%newPostParameters, $url);
                     #print $_->{'value'},"\n";
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
   my $instanceID = shift;
   my $transactionNo = shift;
   my $htmlForm;
   my $actionURL;
   my $httpTransaction;
   my $anchor;
   my @transactionList;
   my $noOfTransactions = 0;
   
   
   $printLogger->print("in parseChooseRegions\n");
    
    
   if ($htmlSyntaxTree->containsTextPattern("Select Region"))
   {
      
      # if this page contains a form to select whether to proceed or not...
      $htmlForm = $htmlSyntaxTree->getHTMLForm();
           
      #$htmlSyntaxTree->printText();     
      if ($htmlForm)
      {       
         $actualAction = $htmlForm->getAction();
         $actionURL = new URI::URL($htmlForm->getAction(), $parameters{'url'})->abs();
          
         # get all of the checkboxes and set them
         $checkboxListRef = $htmlForm->getCheckboxes();
               
         foreach (@$checkboxListRef)
         {                 
            # $_ is a reference to an HTMLFormCheckbox
            # set this checkbox input to true
            $htmlForm->setInputValue($_->getName(), 'on');
            
            # create a transaction for only this checkbox selected
            my %postParameters = $htmlForm->getPostParameters();
            #DebugTools::printHash("$noOfTransactions", \%postParameters);
            my $newHTTPTransaction = HTTPTransaction::new($actionURL, 'POST', \%postParameters, $url);                                           
            # add this new transaction to the list to return for processing
            $transactionList[$noOfTransactions] = $newHTTPTransaction;
            $noOfTransactions++;
             
            # clear the checkbox value before the next post
            $htmlForm->clearInputValue($_->getName());
         }
         
         #$printLogger->print("   parseChooseRegions: returning a POST transaction for each checkbox...\n");
         
         #foreach (@$checkboxListRef)
         #{                 
         #   # $_ is a reference to an HTMLFormCheckbox
         #   # set this checkbox input to true
         #   $htmlForm->setInputValue($_->getName(), 'on');
         #}
        # 
        # # create a transaction for only this checkbox selected
        # my %postParameters = $htmlForm->getPostParameters();
        # 
        # my $newHTTPTransaction = HTTPTransaction::new($actionURL, 'POST', \%postParameters, $url);                                           
        # # add this new transaction to the list to return for processing
        # $transactionList[$noOfTransactions] = $newHTTPTransaction;
        # $noOfTransactions++;
             
         $printLogger->print("   parseChooseRegions: returning a POST transaction for setting every checkbox...\n");
         
            
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
       
            $transactionList[$noOfTransactions] = $httpTransaction;
            $noOfTransactions++;
         }
         
         #$htmlSyntaxTree->printText();
      }
   }
   
   if ($noOfTransactions > 0)
   {
      return @transactionList;
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
   my $instanceID = shift;
   my $transactionNo = shift;
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
   my $instanceID = shift;
   my $transactionNo = shift;
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
      $nextButton = $htmlSyntaxTree->getNextAnchorContainingPattern("Next Page");
                    
      if ($nextButton)
      {            
         $printLogger->print("   parseSearchResults: list includes a 'next' button anchor...\n");
         @anchorsList = (@urlList, $nextButton);
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
      $printLogger->print("   parseSearchResults: pattern not found\n");   
   }
   
   # return the list or anchors or empty list   
   if ($length > 0)
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
   $city = param("city");

   if (($createTables) || ($startSession) || ($continueSession) || ($dropTables))
   {
      $result = 1;
   }
   
   return ($result, $createTables, $startSession, $continueSession, $dropTables);   
}


