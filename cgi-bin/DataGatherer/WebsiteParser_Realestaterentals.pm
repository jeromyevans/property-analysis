#!/usr/bin/perl
# 22 Dec 04 
#  Contains parsers for the RealEstate website to obtain advertised rental information
#
#  all parses must accept two parameters:
#   $documentReader
#   $htmlSyntaxTree
#
# The parsers can't access any other global variables, but can use functions in the WebsiteParser_Common module
#
# History:
# 22 January 2005  - added support for the StatusTable reporting of progress for the thread
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
# extractRentalProfile
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
sub extractRealEstateRentalProfile
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

   my %rentalProfile;   
 #  print "   inExtractSaleProfile:\n";
   # --- set start contraint to Print to get the first line of text (id, suburb, price)
 
   # --- set start constraint to the 3rd table (table 2) on the page - this is table
   # --- across the top that MAY contain a title and description

   # a state machine is used for thie page as it's unstructured (it just flows)
   
   @splitLabel = split /\./, $parentLabel;
   $suburb = $splitLabel[$#splitLabel-1];  # extract the suburb name from the parent label   
#print "SUBURB=$suburb\n";         
   $htmlSyntaxTree->setSearchStartConstraintByText("Back to Search Results");
   $htmlSyntaxTree->setSearchEndConstraintByTag('hr'); # until the horizontal line
      
   $state = $SEEKING_START;
   $endOfRecord = 0;
   while (!$endOfRecord)
   {
      # state machine for processing the list of results
      $parsedThisLine = 0;
      $thisText = $htmlSyntaxTree->getNextText();
      if (!$thisText)
      {
         # not set - at the end of the list - exit the state machine
         $parsedThisLine = 1;
         $endOfRecord = 1;
      }
  #    print("START: state=$state: '$thisText' parsed=$parsedThisLine\n");
      
      if ((!$parsedThisLine) && ($state == $SEEKING_START))
      {
         if ($thisText =~ /\D/gi)   # if it contains a non-digit...
         {
            #print "'$thisText' contains non digit...\n";
            if ($thisText =~ /Next/i)
            {
               # still processing the stuff before the title
               #print "   ignoring '$thisText'\n";
               $parsedThisLine = 1;
               $state = $SEEKING_START;
            }
            else
            {
               #print "   this line is title '$thisText'\n";
               $state = $SEEKING_TITLE;  # line not parsed yet
            }
         }
         else
         {
            # bedrooms, bathrooms or carspaces
             #print "   ignoring number '$thisText'\n";
            $parsedThisLine = 1;
         }
      }
      
      if ((!$parsedThisLine) && ($state == $SEEKING_TITLE))
      {
         $title = $thisText;   # always set
 #        print "TITLE=$title\n";
         $state = $SEEKING_SUBTITLE;
         $parsedThisLine = 1;
      }
      
      if ((!$parsedThisLine) && ($state == $SEEKING_SUBTITLE))
      {
         # optionally set to the price, or AUCTION or UNDER OFFER or SOLD
         
         if ($thisText =~ /UNDER|SOLD/gi)
         {
            $state = $SEEKING_PRICE;
            $parsedThisLine = 1;
         }
         else
         {
            if ($thisText =~ /Auction/gi)
            {
               # price is not set for auctions
               $priceLower = undef;
               $state = $SEEKING_ADDRESS;
               $parsedThisLine = 1;
            }
            else
            { 
                $state = $SEEKING_PRICE;
                # don't set the parsed this line flag - keep processing
            }
         }
      }
        
      if ((!$parsedThisLine) && ($state == $SEEKING_PRICE))
      {
 #        print "priceString = $thisText\n";
         if ($thisText =~ /\$/gi)  # check if this line contains a price
         {
            ($priceLower, $priceUpper) = split(/-/, $thisText, 2);
            if ($priceLower)
            {
               $priceLower = $documentReader->parseNumberSomewhereInString($priceLower);  # may be set to undef
            }
            if ($priceUpper)
            {
               $priceUpper = $documentReader->parseNumberSomewhereInString($priceUpper);  # may be set to undef
            }
 #           print "priceLower = $priceLower\n";

            $state = $SEEKING_ADDRESS;
            $parsedThisLine = 1;
         }
         else
         {
            $priceLower = undef;
            $priceUpper = undef;
            # maybe there's no price and instead this line is the address - don't set parsedLine flag
            $state = $SEEKING_ADDRESS;
         }
      }
      
      if ((!$parsedThisLine) && ($state == $SEEKING_ADDRESS))
      {
         $addressString = $thisText;

         # the address always contains the suburb as the last word[s]
         $addressString =~ s/$suburb$//i;
#print "ADDRESSSTRING='$addressString'\n";         
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

         
         $state = $SEEKING_DESCRIPTION;
         $parsedThisLine = 1;
      }
      
      
      if ((!$parsedThisLine) && ($state == $SEEKING_DESCRIPTION))
      {
         $description = $thisText;
         
         $state = $APPENDING_DESCRIPTION;
         $parsedThisLine = 1;
      }
      
      if ((!$parsedThisLine) && ($state == $APPENDING_DESCRIPTION))
      {
         $description .= " ".$thisText;
         
         $state = $APPENDING_DESCRIPTION;
         $parsedThisLine = 1;
      }
            
      #print "  END: state=$state: '$thisText' parsed=$parsedThisLine\n";
   }

   $htmlSyntaxTree->resetSearchConstraints();
   $htmlSyntaxTree->setSearchStartConstraintByText("Property Overview");
   $htmlSyntaxTree->setSearchEndConstraintByTag("Show Visits"); # until the next table
   
   $type = $htmlSyntaxTree->getNextTextAfterPattern("Category:");             # always set
   $bedrooms = $htmlSyntaxTree->getNextTextAfterPattern("Bedrooms:");    # sometimes undef  
   $bathrooms = $htmlSyntaxTree->getNextTextAfterPattern("Bathrooms:");       # sometimes undef
   $land = $documentReader->strictNumber($htmlSyntaxTree->getNextTextAfterPattern("Land:"));      # sometimes undef
   $yearBuilt = $htmlSyntaxTree->getNextTextAfterPattern("Year:");      # sometimes undef
   $features = $htmlSyntaxTree->getNextTextAfterPattern("Features:");      # sometimes undef

   $htmlSyntaxTree->resetSearchConstraints();
   $htmlSyntaxTree->setSearchStartConstraintByText("Search Homes for Sale");
   $htmlSyntaxTree->setSearchEndConstraintByTag("Back to Search Results"); # until the next table
   $sourceIDString = $htmlSyntaxTree->getNextTextContainingPattern("Property No");     
   $sourceID = $documentReader->parseNumberSomewhereInString($sourceIDString);
   
   # ------ now parse the extracted values ----
         
   $rentalProfile{'SourceID'} = $sourceID;      
   
   if ($suburb) 
   {
      $rentalProfile{'SuburbName'} = $suburb;
   }
   
   if ($priceLower) 
   {
      $rentalProfile{'AdvertisedWeeklyRent'} = $documentReader->parseNumber($priceLower);
   }
      
   if ($type)
   {
      $rentalProfile{'Type'} = $type;
   }
   if ($bedrooms)
   {
      $rentalProfile{'Bedrooms'} = $documentReader->parseNumber($bedrooms);
   }
   if ($bathrooms)
   {
      $rentalProfile{'Bathrooms'} = $documentReader->parseNumber($bathrooms);
   }
   if ($land)
   {
      $rentalProfile{'Land'} = $documentReader->parseNumber($land);
   }
   if ($yearBuilt)
   {
      $rentalProfile{'YearBuilt'} = $documentReader->parseNumber($yearBuilt);
   }    
   
   if ($streetNumber)
   {
      $rentalProfile{'StreetNumber'} = $streetNumber;
   }
   if ($street)
   {
      $rentalProfile{'Street'} = $street;
   }
   
   if ($city)
   {
      $rentalProfile{'City'} = $city;
   }
   
   if ($zone)
   {
      $rentalProfile{'Council'} = $zone;
   }
   
   if ($description)
   {
      $rentalProfile{'Description'} = $description;
   }
   
   if ($features)
   {
      $rentalProfile{'Features'} = $features;
   }

   $rentalProfile{'State'} = $documentReader->getGlobalParameter('state');
   $rentalProfile{'City'} = $documentReader->getGlobalParameter('city');
     
  # DebugTools::printHash("SaleProfile", \%rentalProfile);
        
   return %rentalProfile;  
}

# -------------------------------------------------------------------------------------------------
# parseRealEstateRentalsSearchDetails
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
sub parseRealEstateRentalsSearchDetails

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
   
   my $advertisedRentalProfiles = $$tablesRef{'advertisedRentalProfiles'};
   my $originatingHTML = $$tablesRef{'originatingHTML'};  # 22Dec04

   my %rentalProfiles;
   my $checksum;   
   my $sourceName = $documentReader->getGlobalParameter('source');
   my $printLogger = $documentReader->getGlobalParameter('printLogger');
   $statusTable = $documentReader->getStatusTable();

   $printLogger->print("in parseSearchDetails ($parentLabel)\n");
   
   if ($htmlSyntaxTree->containsTextPattern("Property No"))
   {
      # --- now extract the property information for this page ---
      #if ($htmlSyntaxTree->containsTextPattern("Suburb Profile"))
      #{
      # parse the HTML Syntax tree to obtain the advertised sale information
      %rentalProfiles = extractRealEstateRentalProfile($documentReader, $htmlSyntaxTree, $url, $parentLabel);

      tidyRecord($sqlClient, \%rentalProfiles);        # 27Nov04 - used to be called validateProfile
#       DebugTools::printHash("sale", \%rentalProfiles);
              
      # calculate a checksum for the information - the checksum is used to approximately 
      # identify the uniqueness of the data
      $checksum = $documentReader->calculateChecksum(\%rentalProfiles);
            
      $printLogger->print("   parseSearchDetails: extracted checksum = ", $checksum, ". Checking log...\n");
             
      if ($sqlClient->connect())
      {		 	 
         # check if the log already contains this checksum - if it does, assume the tuple already exists                  
         if ($advertisedRentalProfiles->checkIfTupleExists($sourceName, $rentalProfiles{'SourceID'}, $checksum, $rentalProfiles{'AdvertisedWeeklyRent'}))
         {
            # this tuple has been previously extracted - it can be dropped
            # record that it was encountered again
            $printLogger->print("   parseSearchDetails: identical record already encountered at $sourceID.\n");
            $advertisedRentalProfiles->addEncounterRecord($sourceName, $rentalProfiles{'SourceID'}, $checksum);
            $statusTable->addToRecordsParsed($threadID, 1, 0, $url);    

         }
         else
         {
            $printLogger->print("   parseSearchDetails: unique checksum/url - adding new record.\n");
            # this tuple has never been extracted before - add it to the database
            $identifier = $advertisedRentalProfiles->addRecord($sourceName, \%rentalProfiles, $url, $checksum, $instanceID, $transactionNo);
            $statusTable->addToRecordsParsed($threadID, 1, 1, $url);    

            if ($identifier >= 0)
            {
               # 27Nov04: save the HTML file entry that created this record
               $htmlIdentifier = $originatingHTML->addRecord($identifier, $url, $htmlSyntaxTree, "advertisedRentalProfiles");
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
      $printLogger->print("   parseSearchDetails: page identifier not found\n");
   }
   
   
   # return an empty list
   return @emptyList;
}


# -------------------------------------------------------------------------------------------------
# parseRealEstateRentalsSearchResults
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
sub parseRealEstateRentalsSearchResults

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

   # --- now extract the property information for this page ---
   $printLogger->print("inParseSearchResults ($parentLabel):\n");
   @splitLabel = split /\./, $parentLabel;
   $suburbName = $splitLabel[$#splitLabel];  # extract the suburb name from the parent label

   #$htmlSyntaxTree->printText();
   if ($htmlSyntaxTree->containsTextPattern("Displaying"))
   {         
            
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
            ($priceLower, $priceHiger) = split(/-/, $thisText, 2);
            if ($priceLower)
            {
               $priceLower = $documentReader->parseNumberSomewhereInString($priceLower);  # may be set to undef
            }
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
               if (!$advertisedRentalProfiles->checkIfTupleExists($sourceName, $sourceID, undef, $priceLower, undef))                              
               {   
                  $printLogger->print("   parseSearchResults: adding anchor id ", $sourceID, "...\n");
                  #$printLogger->print("   parseSearchList: url=", $sourceURL, "\n");          
                  my $httpTransaction = HTTPTransaction::new($anchor, $url, $parentLabel.".".$sourceID);                  
             
                  push @urlList, $httpTransaction;
               }
               else
               {
                  $printLogger->print("   parseSearchResults: id ", $sourceID , " in database. Updating last encountered field...\n");
                  $advertisedRentalProfiles->addEncounterRecord($sourceName, $sourceID, undef);
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

      }      
      $statusTable->addToRecordsEncountered($threadID, $recordsEncountered, $url);
      
      # now get the anchor for the NEXT button if it's defined 
      
      $htmlSyntaxTree->resetSearchConstraints();
      $htmlSyntaxTree->setSearchStartConstraintByText("properties found");
      $htmlSyntaxTree->setSearchEndConstraintByText("property details");
      
      $anchor = $htmlSyntaxTree->getNextAnchorContainingPattern("Next");
               
      if ($anchor)
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
      $printLogger->print("   parseSearchResults: returning empty anchor list.\n");
      return @emptyList;
   }   
     
}


# -------------------------------------------------------------------------------------------------
# parseRealEstateRentalsSearchForm
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
sub parseRealEstateRentalsSearchForm

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
         foreach (@$optionsRef)
         {            
            $acceptSuburb = 0;

            if ($_->{'text'} =~ /\*\*\*/i)
            {
                # ignore '*** show all suburbs ***' option
            }
            else
            {
               $htmlForm->setInputValue('u', DocumentReader->trimWhitespace($_->{'text'}));

               #print $_->{'text'}, ", ";
               

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
            }
                     
            if ($acceptSuburb)
            {         
               #print "accepted\n";               
               my $newHTTPTransaction = HTTPTransaction::new($htmlForm, $url, $parentLabel.".".DocumentReader->trimWhitespace($_->{'text'}));
               #print $htmlForm->getEscapedParameters(), "\n";
            
               # add this new transaction to the list to return for processing
               $transactionList[$noOfTransactions] = $newHTTPTransaction;
               $noOfTransactions++;
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
# parseRealEstateRentalsChooseState
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
sub parseRealEstateRentalsChooseState

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

