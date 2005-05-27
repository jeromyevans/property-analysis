#!/usr/bin/perl
# 11 Nov 04 - derived from multiple sources
#  Contains parsers for the RealEstate website to obtain advertised sales information
#
#  all parses must accept two parameters:
#   $documentReader
#   $htmlSyntaxTree
#
# The parsers can't access any other global variables, but can use functions in the WebsiteParser_Common module
#
# History:
#  5 December 2004 - adapted to use common AdvertisedPropertyProfiles instead of separate rentals and sales tables
# 22 January 2005  - added support for the StatusTable reporting of progress for the thread
# 23 January 2005  - added support for the SessionProgressTable reporting of progress of the thread
#                  - added check against SessionProgressTable to reject suburbs that appear 'completed' already
#  in the table.  Should prevent procesing of suburbs more than once if the server returns the same suburb under
#  multiple searches.  Note: completed indicates the propertylist has been parsed, not necessarily all the details.
#  25 April  2005   - modified parsing of search results to ignore 'related results' returned by the search engine
#  24 May 2005      - major change to support new AdvertisedPropertyProfiles table that combines rental and sale 
#  advertisements and perform less processing of the source data before entry

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
use StatusTable;
use SessionProgressTable;   # 23Jan05

@ISA = qw(Exporter);

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# parseRealEstateDisplayResponse
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
sub parseRealEstateDisplayResponse

{	
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;         
   my $instanceID = shift;   
   my $transactionNo = shift;
   my $threadID = shift;
   my $parentLabel = shift;
   
   my @anchors;
   my $printLogger = $documentReader->getGlobalParameter('printLogger');
   
   # --- now extract the property information for this page ---
   $printLogger->print("in ParseDisplayResponse:\n");
   $htmlSyntaxTree->printText();
   
   # return a list with just the anchor in it  
   return @emptyList;
   
}

# -------------------------------------------------------------------------------------------------

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
sub extractRealEstateProfile
{
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;
   my $parentLabel = shift;
   my $text;
   
   my $SEEKING_START         = 0;
   my $SEEKING_TITLE         = 3;
   my $SEEKING_SUBTITLE      = 4;
   my $SEEKING_PRICE         = 5;
   my $SEEKING_ADDRESS       = 6;
   my $SEEKING_DESCRIPTION   = 7;
   my $APPENDING_DESCRIPTION = 8;

   my %propertyProfile;  
   my $printLogger = $documentReader->getGlobalParameter('printLogger');

   my $tablesRef = $documentReader->getTableObjects();
   my $sqlClient = $documentReader->getSQLClient();
   
   my $saleOrRentalFlag = -1;
   my $sourceName = undef;
   my $state = undef;
   
   # first, locate the pattern that identifies the source of the record as RealEstate.com
   # 20 May 05
   if ($htmlSyntaxTree->containsTextPattern("realestate\.com\.au"))
   {
      $sourceName = 'RealEstate';
   }
   
   if ($sourceName) 
   {
      $propertyProfile{'SourceName'} = $sourceName;
   }
  
   $htmlSyntaxTree->setSearchStartConstraintByText("Search Results");
   $htmlSyntaxTree->setSearchEndConstraintByText("Property No"); 
   
   # second, locate the pattern that identifies this as a SALE record or RENT record
   # 20 May 05
   if ($htmlSyntaxTree->containsTextPattern("Homes For Sale"))
   {
      $saleOrRentalFlag = 0;
   }
   else
   {
      # locate the pattern that identifies this as a RENTAL record
      if ($htmlSyntaxTree->containsTextPattern("Homes For Rent"))
      {
         $saleOrRentalFlag = 1;
      }
   }
   
   $propertyProfile{'SaleOrRentalFlag'} = $saleOrRentalFlag;

   $htmlSyntaxTree->resetSearchConstraints();
   # third, locate the STATE for the property 
   # This needs to be obtained from one of the URLs in the page
   $anchorList = $htmlSyntaxTree->getAnchorsContainingPattern("Back to Search Results");
   $backURL = $$anchorList[0];
   if ($backURL)
   {
      # the state follows the state= parameter in the URL
      # matched pattern is returned in $1;
      $backURL =~ /\&s=(\w*)\&/gi;
      $stateName=$1;

      # convert to uppercase as it's used in an index in the database
      $stateName =~ tr/[a-z]/[A-Z]/;
   }
   
   if ($stateName)
   {
      $propertyProfile{'State'} = $stateName;
   }
   
   # --- extract the suburb name (cheat- use the parent label ---
   
   @splitLabel = split /\./, $parentLabel;
   $suburb = $splitLabel[$#splitLabel-1];  # extract the suburb name from the parent label

   if ($suburb) 
   {
      $propertyProfile{'SuburbName'} = $suburb;
   }     
   
   # --- extract the address string ---
   $htmlSyntaxTree->resetSearchConstraints();
   $htmlSyntaxTree->setSearchStartConstraintByTag("address");
   $htmlSyntaxTree->setSearchEndConstraintByTag('/address'); 
   $addressString = $htmlSyntaxTree->getNextText();
   
   # the address always contains the suburb as the last word[s]
   $addressString =~ s/$suburb$//i;
            
   if ($addressString) 
   {
      $propertyProfile{'StreetAddress'} = $addressString;
   }
   
   # --- extract the price string ---
   $htmlSyntaxTree->resetSearchConstraints();
   $htmlSyntaxTree->setSearchStartConstraintByTagAndClass("span", "lg-dppl-bold");
   $htmlSyntaxTree->setSearchEndConstraintByTag('/span'); 
   $priceString = $htmlSyntaxTree->getNextText();
   
   if ($priceString) 
   {
      $propertyProfile{'AdvertisedPriceString'} = $documentReader->trimWhitespace($priceString);
   }
   
   # --- for realestate.com.au the titleString is the same as the priceString --- 
   $titleString = $priceString;
   if ($titleString) 
   {
      $propertyProfile{'TitleString'} = $documentReader->trimWhitespace($titleString);
   }
   
   # --- extract the description ---
   $htmlSyntaxTree->resetSearchConstraints();
   $htmlSyntaxTree->setSearchStartConstraintByTagAndClass("div", "description");
   $htmlSyntaxTree->setSearchEndConstraintByTag('/div');
   
   # may be multiple lines - get all text and append it
   $description = "";
   while ($nextLine = $htmlSyntaxTree->getNextText())
   {
      $description = $description . " " . $nextLine;
   }
      
   if ($description)
   {
      $propertyProfile{'Description'} = $documentReader->trimWhitespace($description);
   }
   
   # --- extact other attributes ---
   $htmlSyntaxTree->resetSearchConstraints();
   $htmlSyntaxTree->setSearchStartConstraintByText("Property Overview");
   $htmlSyntaxTree->setSearchEndConstraintByTag("Show Visits"); # until the next table
   
   $type = $htmlSyntaxTree->getNextTextAfterPattern("Category:");             # always set
   $bedrooms = $htmlSyntaxTree->getNextTextAfterPattern("Bedrooms:");    # sometimes undef  
   $bathrooms = $htmlSyntaxTree->getNextTextAfterPattern("Bathrooms:");       # sometimes undef
   $land = $htmlSyntaxTree->getNextTextAfterPattern("Land:");      # sometimes undef
#   $yearBuilt = $htmlSyntaxTree->getNextTextAfterPattern("Year:");      # sometimes undef
   $features = $htmlSyntaxTree->getNextTextAfterPattern("Features:");      # sometimes undef

   $htmlSyntaxTree->resetSearchConstraints();
   $htmlSyntaxTree->setSearchStartConstraintByText("Search Homes for Sale");
   $htmlSyntaxTree->setSearchEndConstraintByTag("Back to Search Results"); # until the next table
   $sourceIDString = $htmlSyntaxTree->getNextTextContainingPattern("Property No");     
   $sourceID = $documentReader->parseNumberSomewhereInString($sourceIDString);
            
   if ($sourceID)
   {
      $propertyProfile{'SourceID'} = $sourceID;
   }      
   
   
   if ($type)
   {
      $propertyProfile{'Type'} = $type;
   }
   
   if ($bedrooms)
   {
      $propertyProfile{'Bedrooms'} = $documentReader->parseNumber($bedrooms);
   }
   
   if ($bathrooms)
   {
      $propertyProfile{'Bathrooms'} = $documentReader->parseNumber($bathrooms);
   }
   
   if ($land)
   {
      $propertyProfile{'LandArea'} = $land;
   }
   
   # --- extract building area ---

   if ($buidingArea)
   {
      $propertyProfile{'BuildingArea'} = $buildingArea;
   }
   
   if ($yearBuilt)
   {
      $propertyProfile{'YearBuilt'} = $yearBuilt;
   }    
   
   if ($features)
   {
      $propertyProfile{'Features'} = $features;
   }
   
   # --- extract agent details ---- 
   $htmlSyntaxTree->resetSearchConstraints();
   $htmlSyntaxTree->setSearchStartConstraintByTagAndID('div', 'agentCollapsed');
   $htmlSyntaxTree->setSearchEndConstraintByTag('/div');
   
   $fullURL = $htmlSyntaxTree->getNextAnchor();
   $website = $fullURL;
   $website =~ /to=(.*)/gi;
   $website = $1;
   $title = $htmlSyntaxTree->getNextText();
   $agencyName = $htmlSyntaxTree->getNextText();
   $contactNameAndNumber = $htmlSyntaxTree->getNextTextAfterPattern('Sales Person');
   
   ($contactName, $crud) = split /\d/, $contactNameAndNumber;
   $contactName = $documentReader->trimWhitespace($contactName);
   
   $mobilePhone = $contactNameAndNumber;
   # remove non-digits
   $mobilePhone =~ s/\D//gi;
   
   $fullURL =~ /AgentWebSiteClick-(.*)\&to/gi;
   $agencySourceID = $1;
   
   if ($agencySourceID)
   {
      $propertyProfile{'AgencySourceID'} = $agencySourceID;
   }
   
   if ($agencyName)
   {
      $propertyProfile{'AgencyName'} = $agencyName;
   }
    
   if ($contactName)
   {
      $propertyProfile{'ContactName'} = $contactName;
   }
   
   if ($mobilePhone)
   {
      $propertyProfile{'MobilePhone'} = $mobilePhone;
   }
   
   if ($website)
   {
      $propertyProfile{'Website'} = $website;
   }
   
   populatePropertyProfileHash($sqlClient, $documentReader, \%propertyProfile);
   
   #DebugTools::printHash("PropertyProfile", \%propertyProfile);
   
   return \%propertyProfile;  
}

# -------------------------------------------------------------------------------------------------
# parseRealEstateSearchDetails
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
sub parseRealEstateSearchDetails

{	
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;
   my $instanceID = shift;
   my $transactionNo = shift;
   my $threadID = shift;
   my $parentLabel = shift;
   
   my $sqlClient = $documentReader->getSQLClient();
   my $tablesRef = $documentReader->getTableObjects();
   
   my $advertisedPropertyProfiles = $$tablesRef{'advertisedPropertyProfiles'};
   my $originatingHTML = $$tablesRef{'originatingHTML'};  # 27Nov04

   my $sourceName = $documentReader->getGlobalParameter('source');
   my $printLogger = $documentReader->getGlobalParameter('printLogger');
   $statusTable = $documentReader->getStatusTable();

   $printLogger->print("in parseSearchDetails ($parentLabel)\n");
   
   if ($htmlSyntaxTree->containsTextPattern("Property No"))
   {
      # parse the HTML Syntax tree to obtain the advertised sale information
      $propertyProfile = extractRealEstateProfile($documentReader, $htmlSyntaxTree, $url, $parentLabel);

      if ($sqlClient->connect())
      {		 	 
         # check if the log already contains this checksum - if it does, assume the tuple already exists                  
         if ($advertisedPropertyProfiles->checkIfProfileExists($propertyProfile))
         {
            # this tuple has been previously extracted - it can be dropped
            # record that it was encountered again
            $printLogger->print("   parseSearchDetails: identical record already encountered at $sourceName.\n");
            $advertisedPropertyProfiles->addEncounterRecord($$propertyProfile{'SaleOrRentalFlag'}, $$propertyProfile{'SourceName'}, $$propertyProfile{'SourceID'}, $$propertyProfile{'Checksum'});
            $statusTable->addToRecordsParsed($threadID, 1, 0, $url);    
         }
         else
         {
            $printLogger->print("   parseSearchDetails: unique checksum/url - adding new record.\n");
            # this tuple has never been extracted before - add it to the database
            $identifier = $advertisedPropertyProfiles->addRecord($propertyProfile, $url, $htmlSyntaxTree);

            $statusTable->addToRecordsParsed($threadID, 1, 1, $url);    
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
# parseRealEstateSearchResults
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
sub parseRealEstateSearchResults

{	
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;    
   my $instanceID = shift;
   my $transactionNo = shift;
   my $threadID = shift;
   my $parentLabel = shift;
   my $SEEKING_FIRST_RESULT = 1;
   my $PARSING_RESULT_TITLE = 2;
   my $PARSING_SUB_LINE     = 3;
   my $PARSING_PRICE        = 4;
   my $PARSING_SOURCE_ID    = 5;
   my $SEEKING_NEXT_RESULT  = 6;
   
   my $printLogger = $documentReader->getGlobalParameter('printLogger');
   my $sourceName =  $documentReader->getGlobalParameter('source');
   my $length = 0;
   my @urlList;        
   my $firstRun = 1;
   my $statusTable = $documentReader->getStatusTable();
   my $recordsEncountered = 0;
   my $sessionProgressTable = $documentReader->getSessionProgressTable();   # 23Jan05
   my $ignoreNextButton = 0;
   my $sqlClient = $documentReader->getSQLClient();
   my $tablesRef = $documentReader->getTableObjects();
   my $advertisedPropertyProfiles = $$tablesRef{'advertisedPropertyProfiles'};
   my $saleOrRentalFlag = -1;
   
   # --- now extract the property information for this page ---
   $printLogger->print("inParseSearchResults ($parentLabel):\n");
   @splitLabel = split /\./, $parentLabel;
   $suburbName = $splitLabel[$#splitLabel];  # extract the suburb name from the parent label

   $sessionProgressTable->reportRegionOrSuburbChange($threadID, undef, $suburbName);    # 23Jan05 
   
   #$htmlSyntaxTree->printText();
   if ($htmlSyntaxTree->containsTextPattern("Displaying"))
   {         
      # if no exact matches are found the search engine sometimes returns related matches - these aren't wanted
      if (!$htmlSyntaxTree->containsTextPattern("No exact matches found"))
      {
         # determine if these are RENT or SALE results
         if ($htmlSyntaxTree->containsTextPattern("Homes for Sale"))
         {
            $saleOrRentalFlag = 0;
         }
         elsif (!$htmlSyntaxTree->containsTextPattern("Homes for Rent"))
         {
            $saleOrRentalFlag = 1;
         }
         
         $htmlSyntaxTree->setSearchStartConstraintByText("properties found");
         $htmlSyntaxTree->setSearchEndConstraintByText("Page:");
            
         $state = $SEEKING_FIRST_RESULT;
         $endOfList = 0;
         while (!$endOfList)
         {
            # state machine for processing the list of results
            $parsedThisLine = 0;
            $thisText = $htmlSyntaxTree->getNextText();
            if (!$thisText)
            {
               # not set - at the end of the list - exit the state machine
               $parsedThisLine = 1;
               $endOfList = 1;
            }
            #print "START: state=$state: '$thisText' parsed=$parsedThisLine\n";
            
            if ((!$parsedThisLine) && ($state == $SEEKING_FIRST_RESULT))
            {
               # if this text is the suburb name, we're in a new record
               if ($thisText =~ /$suburbName/i)
               {
                  $state = $PARSING_RESULT_TITLE;
               }
               $parsedThisLine = 1;
            }
            
            if ((!$parsedThisLine) && ($state == $PARSING_RESULT_TITLE))
            {
               $title = $thisText;   # always set
               $state = $PARSING_SUB_LINE;
               $parsedThisLine = 1;
            }
            
            if ((!$parsedThisLine) && ($state == $PARSING_SUB_LINE))
            {
               # optionally set to the price, or AUCTION or UNDER OFFER or SOLD
               
               if ($thisText =~ /UNDER|SOLD/gi)
               {
                  $state = $PARSING_PRICE;
                  $parsedThisLine = 1;
               }
               else
               {
                  if ($thisText =~ /Auction/gi)
                  {
                     # price is not set for auctions
                     $priceLower = undef;
                     $state = $PARSING_SOURCE_ID;
                     $parsedThisLine = 1;
                  }
                  else
                  { 
                      $state = $PARSING_PRICE;
                      # don't set the parsed this line flag - keep processing
                  }
               }
            }
              
            if ((!$parsedThisLine) && ($state == $PARSING_PRICE))
            {
               # the titleString for RealEstate.com is the line with the price on it
               $titleString = $thisText;
                           
               $state = $PARSING_SOURCE_ID;
               $parsedThisLine = 1;
            }
            
            if ((!$parsedThisLine) && ($state == $PARSING_SOURCE_ID))
            {
               $anchor = $htmlSyntaxTree->getNextAnchor();
               $temp=$anchor;
               $temp =~ s/id=(.\d*)&f/$sourceID = sprintf("$1")/ei;
   
               #print "$suburbName: '$title' \$$priceLower id=$sourceID\n";
               
               if (($sourceID) && ($anchor))
               {
                  # check if the cache already contains this unique id
                  # $_ is a reference to a hash
                  if (!$advertisedPropertyProfiles->checkIfResultExists($saleOrRentalFlag, $sourceName, $sourceID, $titleString))                              
                  {   
                     $printLogger->print("   parseSearchResults: adding anchor id ", $sourceID, "...\n");
                     #$printLogger->print("   parseSearchList: url=", $sourceURL, "\n");          
                     my $httpTransaction = HTTPTransaction::new($anchor, $url, $parentLabel.".".$sourceID);                  
                
                     push @urlList, $httpTransaction;
                  }
                  else
                  {
                     $printLogger->print("   parseSearchResults: id ", $sourceID , " in database. Updating last encountered field...\n");
                     $advertisedPropertyProfiles->addEncounterRecord($saleOrRentalFlag, $sourceName, $sourceID, undef);
                  }
               }
               
               $state = $SEEKING_NEXT_RESULT;
               $parsedThisLine = 1;
            }
            
            if ((!$parsedThisLine) && ($state == $SEEKING_NEXT_RESULT))
            {
               # searching for the start of the next result - possible outcomes are the
               # start of the next result is found or the start of an advertisement is found
               
               if ($thisText eq $suburbName)
               {
                  $state = $PARSING_RESULT_TITLE;
               }
               $parsedThisLine = 1;
            }
            
            #print "  END: state=$state: '$thisText' parsed=$parsedThisLine\n";
            $recordsEncountered++;  # count records seen
            # 23Jan05:save that this suburb has had some progress against it
            $sessionProgressTable->reportProgressAgainstSuburb($threadID, 1);
   
         }      
         $statusTable->addToRecordsEncountered($threadID, $recordsEncountered, $url);
      }
      else
      {
         $printLogger->print("   parseSearchResults: no exact matches found\n");
         $ignoreNextButton = 1;
      }
         
      # now get the anchor for the NEXT button if it's defined 
      
      $htmlSyntaxTree->resetSearchConstraints();
      $htmlSyntaxTree->setSearchStartConstraintByText("properties found");
      $htmlSyntaxTree->setSearchEndConstraintByText("property details");
      
      $anchor = $htmlSyntaxTree->getNextAnchorContainingPattern("Next");
           
      # ignore the next button if it's only for related results
      if (($anchor) && (!$ignoreNextButton))
      {            
         $printLogger->print("   parseSearchResults: list includes a 'next' button anchor...\n");
         $httpTransaction = HTTPTransaction::new($anchor, $url, $parentLabel);                  
         #print "   anchor=$anchor\n";
         @anchorsList = (@urlList, $httpTransaction);
      }
      else
      {            
         $printLogger->print("   parseSearchResults: list has no 'next' button anchor...\n");
         @anchorsList = @urlList;
         
         # 23Jan05:save that this suburb has (almost) completed - just need to process the details
         $sessionProgressTable->reportSuburbCompletion($threadID);
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
      # 23Jan05:save that this suburb has (almost) completed - just need to process the details
      $sessionProgressTable->reportSuburbCompletion($threadID);
      
      $printLogger->print("   parseSearchResults: returning empty anchor list.\n");
      return @emptyList;
   }   
     
}


# -------------------------------------------------------------------------------------------------
# parseRealEstateSearchForm
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
sub parseRealEstateSearchForm

{	
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;
   my $instanceID = shift;
   my $transactionNo = shift;
   my $threadID = shift;
   my $parentLabel = shift;
   
   my $htmlForm;
   my $actionURL;
   my $httpTransaction;
   my @transactionList;
   my $noOfTransactions = 0;
   my $startLetter = $documentReader->getGlobalParameter('startrange');
   my $endLetter =  $documentReader->getGlobalParameter('endrange');
   my $printLogger = $documentReader->getGlobalParameter('printLogger');
   my $sessionProgressTable = $documentReader->getSessionProgressTable();   # 23Jan05

   my %subAreaHash;
      
   $printLogger->print("in parseSearchForm ($parentLabel)\n");
      
   # get the HTML Form instance
   $htmlForm = $htmlSyntaxTree->getHTMLForm("n");
    
   if ($htmlForm)
   {       
      # for all of the suburbs defined in the form, create a transaction to get it
      $optionsRef = $htmlForm->getSelectionOptions('u');
      $htmlForm->clearInputValue('is');   # clear checkbox selecting surrounding suburbs
      $htmlForm->setInputValue('cat', '');   
      $htmlForm->setInputValue('o', 'def');   

      
      # parse through all those in the perth metropolitan area
      if ($optionsRef)
      {
         $sessionProgressTable->prepareSuburbStateMachine($threadID);     # 23Jan05
         
         foreach (@$optionsRef)
         {            
            $acceptSuburb = 0;

            # check if the last suburb has been encountered - if it has, then start processing from this point
            $useThisSuburb = $sessionProgressTable->isSuburbAcceptable($_->{'text'});  # 23Jan05
            
            if ($useThisSuburb)
            {
            
               if ($_->{'text'} =~ /\*\*\*/i)
               {
                   # ignore '*** show all suburbs ***' option
               }
               else
               {
                  $htmlForm->setInputValue('u', DocumentReader->trimWhitespace($_->{'text'}));
   
                  # determine if the suburbname is in the specific letter constraint
                  $acceptSuburb = isSuburbNameInRange($_->{'text'}, $startLetter, $endLetter);  # 23Jan05
               }
            }
                        
            if ($acceptSuburb)
            {
               # 23 Jan 05 - another check - see if the suburb has already been 'completed' in this thread
               # if it has been, then don't do it again (avoids special case where servers may return
               # the same suburb for multiple search variations)
               if (!$sessionProgressTable->hasSuburbBeenProcessed($threadID, $_->{'text'}))
               { 
                  
                  #print "accepted\n";               
                  my $newHTTPTransaction = HTTPTransaction::new($htmlForm, $url, $parentLabel.".".DocumentReader->trimWhitespace($_->{'text'}));
                  #print $htmlForm->getEscapedParameters(), "\n";
               
                  # add this new transaction to the list to return for processing
                  $transactionList[$noOfTransactions] = $newHTTPTransaction;
                  $noOfTransactions++;
               }   
               else
               {
                  $printLogger->print("   parseSearchForm:suburb ", $_->{'text'}, " previously processed in this thread.  Skipping...\n");
               }
            }
         }
         
         $printLogger->print("   ParseSearchForm:Created a transaction for $noOfTransactions suburbs...\n");
      }  # end of metropolitan areas
              
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
# parseRealEstateChooseState
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
sub parseRealEstateChooseState

{	
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;         
   my $instanceID = shift;
   my $transactionNo = shift;
   my $threadID = shift;
   my $parentLabel = shift;
   my @anchors;
   my $printLogger = $documentReader->getGlobalParameter('printLogger');
   my $state = $documentReader->getGlobalParameter('state');
   my @transactionList;
   
   # --- now extract the property information for this page ---
   $printLogger->print("inParseChooseState ($parentLabel):\n");
   if ($htmlSyntaxTree->containsTextPattern("Advanced Search"))
   { 
      $htmlSyntaxTree->setSearchStartConstraintByText("Browse by State");
      $htmlSyntaxTree->setSearchEndConstraintByText("Searching for Real Estate");                                    
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
      $httpTransaction = HTTPTransaction::new($anchor, $url, $parentLabel.".".$state);   # use the state in the label
       
      return ($httpTransaction);
   }
   else
   {
      return @emptyList;
   }
}


# -------------------------------------------------------------------------------------------------
# parseRealEstateSalesHomePage
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
sub parseRealEstateSalesHomePage

{	
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;         
   my $instanceID = shift;   
   my $transactionNo = shift;
   my $threadID = shift;
   my $parentLabel = shift;
   
   my $printLogger = $documentReader->getGlobalParameter('printLogger');
   my @anchors;
   
   # --- now extract the property information for this page ---
   $printLogger->print("inParseHomePage ($parentLabel):\n");
   if ($htmlSyntaxTree->containsTextPattern("Real Estate Institute of Western Australia"))
   {                                     
      $anchor = $htmlSyntaxTree->getNextAnchorContainingPattern("Homes For Sale");
      if ($anchor)
      {
         $printLogger->print("   following anchor 'Homes For Sale'...\n");
      }
      else
      {
         $printLogger->print("   anchor 'Homes For Sale' not found!\n");
      }
   }	  
   else 
   {
      $printLogger->print("parseHomePage: pattern not found\n");
   }
   
   # return a list with just the anchor in it
   if ($anchor)
   {
      my $newHTTPTransaction = HTTPTransaction::new($anchor, $url, $parentLabel."sales");

      return ($newHTTPTransaction);
   }
   else
   {
      return @emptyList;
   }
}


# -------------------------------------------------------------------------------------------------
# parseRealEstateRentalsHomePage
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
sub parseRealEstateRentalsHomePage

{	
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;         
   my $instanceID = shift;   
   my $transactionNo = shift;
   my $threadID = shift;
   my $parentLabel = shift;
   
   my $printLogger = $documentReader->getGlobalParameter('printLogger');
   my @anchors;
   
   # --- now extract the property information for this page ---
   $printLogger->print("inParseHomePage ($parentLabel):\n");
   if ($htmlSyntaxTree->containsTextPattern("Real Estate Institute of Western Australia"))
   {                                     
      $anchor = $htmlSyntaxTree->getNextAnchorContainingPattern("Rental Profiles");
      if ($anchor)
      {
         $printLogger->print("   following anchor 'Rental Profiles'...\n");
      }
      else
      {
         $printLogger->print("   anchor 'Rental Profiles' not found!\n");
      }
   }	  
   else 
   {
      $printLogger->print("parseHomePage: pattern not found\n");
   }
   
   # return a list with just the anchor in it
   if ($anchor)
   {
      my $newHTTPTransaction = HTTPTransaction::new($anchor, $url, $parentLabel."sales");

      return ($newHTTPTransaction);
   }
   else
   {
      return @emptyList;
   }
}


# -------------------------------------------------------------------------------------------------

