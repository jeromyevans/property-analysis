#!/usr/bin/perl
# 2 Oct 04 - derived from multiple sources
#  Contains parsers for the Domain website to obtain advertised sales information
#
#  all parses must accept two parameters:
#   $documentReader
#   $htmlSyntaxTree
#
# The parsers can't access any other global variables, but can use functions in the WebsiteParser_Common module
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
##################NEED TO HANDLE MULTIPLE CHECKBOXES WITH SAME NAME IN PARAMETERS
##################NEED TO ENSURE NAMELESS SUBMIT BUTTONS ARE NOT PROVIDED IN PARAMETERS

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

@ISA = qw(Exporter);

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
sub extractDomainSaleProfile
{
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;
   my $text;
   
   my %saleProfile;
   my $printLogger = $documentReader->getGlobalParameter('printLogger');
   my $state = $documentReader->getGlobalParameter('state');
   my $city = $documentReader->getGlobalParameter('city');
   
   # --- set start contraint to Print to get the first line of text (id, suburb, price)
   #$htmlSyntaxTree->setSearchStartConstraintByText("Print");
 
   # --- set start constraint to the 3rd table (table 2) on the page - this is table
   # --- across the top that MAY contain a title and description
   $htmlSyntaxTree->setSearchStartConstraintByText("Property Details");
   $htmlSyntaxTree->setSearchEndConstraintByText("Agent Details"); 
   
   $searchSourceURL = $htmlSyntaxTree->getNextAnchorContainingPattern("Back to Search Results");
   # extract the suburb name from the URL.  This is the easiest place to get it as it's used in the
   # path of a URL following sub=
   $searchSourceURL =~ s/sub\=(.*)\&page/$suburb=sprintf("$1")/egi;
   
   # replace + with space character
   $suburb =~ s/\+/ /g;
   
   $htmlSyntaxTree->resetSearchConstraints();
   $htmlSyntaxTree->setSearchStartConstraintByText("E-mail me similar properties");
   $htmlSyntaxTree->setSearchEndConstraintByText("Agent Details"); 
                 
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
   ($crud, $sourceID) = split(/\?/, $url, 2);            
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

   $saleProfile{'State'} = $state;
 
   #DebugTools::printHash("SaleProfile", \%saleProfile);
        
   return %saleProfile;  
}

# -------------------------------------------------------------------------------------------------
# parseDomainSalesPropertyDetails
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
sub parseDomainSalesPropertyDetails

{	
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;
   my $instanceID = shift;
   my $transactionNo = shift;
   
   my $sqlClient = $documentReader->getSQLClient();
   my $tablesRef = $documentReader->getTableObjects();
   my $printLogger = $documentReader->getGlobalParameter('printLogger');
   my $sourceName = $documentReader->getGlobalParameter('source');

   my $advertisedSaleProfiles = $$tablesRef{'advertisedSaleProfiles'};
   
   my %saleProfiles;
   my $checksum;   
   $printLogger->print("in parsePropertyDetails\n");
   
   
   if ($htmlSyntaxTree->containsTextPattern("Property Details"))
   {
                                         
      # parse the HTML Syntax tree to obtain the advertised sale information
      %saleProfiles = extractDomainSaleProfile($documentReader, $htmlSyntaxTree, $url);                  
      validateProfile($sqlClient, \%saleProfiles);
      # calculate a checksum for the information - the checksum is used to approximately 
      # identify the uniqueness of the data
      $checksum = $documentReader->calculateChecksum(\%saleProfiles);

      $printLogger->print("   parsePropertyDetails: extracted checksum = ", $checksum, ". Checking log...\n");
             
      if ($sqlClient->connect())
      {		 	 
         # check if the log already contains this checksum - if it does, assume the tuple already exists                  
         if ($advertisedSaleProfiles->checkIfTupleExists($sourceName, $saleProfiles{'SourceID'}, $checksum, $saleProfiles{'AdvertisedPriceLower'}))
         {
            # this tuple has been previously extracted - it can be dropped
            # record that it was encountered again
            $printLogger->print("   parsePropertyDetails: identical record already encountered at $sourceName.\n");
            $advertisedSaleProfiles->addEncounterRecord($sourceName, $saleProfiles{'SourceID'}, $checksum);
         }
         else
         {
            $printLogger->print("   parsePropertyDetails: unique checksum/url - adding new record.\n");
            # this tuple has never been extracted before - add it to the database
            $advertisedSaleProfiles->addRecord($sourceName, \%saleProfiles, $url, $checksum, $instanceID, $transactionNo);         
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
# parseDomainSalesChooseSuburbs
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
sub parseDomainSalesChooseSuburbs
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
   my $printLogger = $documentReader->getGlobalParameter('printLogger');
   my $startLetter = $documentReader->getGlobalParameter('startrange');
   my $endLetter =  $documentReader->getGlobalParameter('endrange');
      
   $printLogger->print("in parseChooseSuburbs\n");

 #  parseDomainSalesDisplayResponse($documentReader, $htmlSyntaxTree, $url, $instanceID, $transactionNo);
 
   if ($htmlSyntaxTree->containsTextPattern("Advanced Search"))
   {
       
      # get the HTML Form instance
      $htmlForm = $htmlSyntaxTree->getHTMLForm();
       
      if ($htmlForm)
      {       
#         $actionURL = new URI::URL($htmlForm->getAction(), $parameters{'url'})->abs()->as_string();
#         @defaultPostParameters = $htmlForm->getPostParameters();
#print "DefaultPostParameters:\n";            
#         foreach (@defaultPostParameters)
#         {
#            print $$_{'name'}, "=", $$_{'value'},"\n";
#         }
         # for all of the suburbs defined in the form, create a transaction to get it
         if (($startLetter) || ($endLetter))
         {
            $printLogger->print("   parseChooseSuburbs: Filtering suburb names between $startLetter to $endLetter...\n");
         }
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
                     
                     # 2 Aug 04 - I don't understand why this was necessary, but if the default post parameters
                     # hash was copied directly then 1Mb of memory per transaction is allocated.  Copying it 
                     # manually like this only allocates scalars.  Strange.
                     # create a duplicate of the default post parameters
#                     my @newPostParameters;
#print "STROP STOP STOP STOP STOP STOP STO PSTOP STOP STOP STOP \n";                         
                     # and set the value to this option in the selection
 #                    $newPostParameters{'__VIEWSTATE'} = $defaultPostParameters{'__VIEWSTATE'};
 #                    $newPostParameters{'_ctl0:listboxSuburbs'} = $_->{'value'};
 #                    $newPostParameters{'_ctl0:dropPriceFromSale'}=$defaultPostParameters{'_ctl0:dropPriceFromSale'};
 #                    $newPostParameters{'_ctl0:dropPriceToSale'}=$defaultPostParameters{'_ctl0:dropPriceToSale'};
 #                    $newPostParameters{'_ctl0:txtKeywords'}=$defaultPostParameters{'_ctl0:txtKeywords'};
 #                    $newPostParameters{'_ctl0:imgbtnSearch'}=$defaultPostParameters{'_ctl0:imgbtnSearch'};
                     # next parameter is used internally only to keep original order of parameters.
 #                    $newPostParameters{'_internalPOSTOrder_'}=$defaultPostParameters{'_internalPOSTOrder_'};
                     $htmlForm->setInputValue('_ctl0:listboxSuburbs', $_->{'value'});

                     #DebugTools::printHash("newPost", \%newPostParameters);
                     #print "actionURL= $actionURL\n";
                     #print "url=$url\n";
         #print "   parseChooseSuburbs::creating transaction...\n";
                     
                     my $newHTTPTransaction = HTTPTransaction::new($htmlForm, $url);
                     #print $_->{'value'},"\n";
                     # add this new transaction to the list to return for processing
                     $transactionList[$noOfTransactions] = $newHTTPTransaction;
                     $noOfTransactions++;
                  }
               }
            }
         }
         
         $printLogger->print("   ParseChooseSuburbs:Created a transaction for $noOfTransactions suburbs...\n");                             
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
            $httpTransaction = HTTPTransaction::new($anchor, $url);
            
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
# parseDomainSalesChooseRegions
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
sub parseDomainSalesChooseRegions

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
   my $printLogger = $documentReader->getGlobalParameter('printLogger');
   
   
   $printLogger->print("in parseChooseRegions\n");
    
    
   if ($htmlSyntaxTree->containsTextPattern("Select Region"))
   {
      
      # if this page contains a form to select whether to proceed or not...
      $htmlForm = $htmlSyntaxTree->getHTMLForm();
           
      #$htmlSyntaxTree->printText();     
      if ($htmlForm)
      {       
         $actualAction = $htmlForm->getAction();
         $actionURL = new URI::URL($htmlForm->getAction(), $parameters{'url'})->abs()->as_string();
          
         # get all of the checkboxes and set them
         $checkboxListRef = $htmlForm->getCheckboxes();
               
 #        foreach (@$checkboxListRef)
 #        {                 
 #           # $_ is a reference to an HTMLFormCheckbox
 #           # set this checkbox input to true
 #           $htmlForm->setInputValue($_->getName(), $_->getValue());
 #           
 #           # create a transaction for only this checkbox selected
 #           my %formParameters = $htmlForm->getPostParameters();
 #           
 #           #DebugTools::printHash("$noOfTransactions", \%postParameters);
 #           my $newHTTPTransaction = HTTPTransaction::new($actionURL, 'GET', \%formParameters, $url);
 #                                                      
 #           # add this new transaction to the list to return for processing
 #           $transactionList[$noOfTransactions] = $newHTTPTransaction;
 #           $noOfTransactions++;
 #            
 #           # clear the checkbox value before the next post
 #           $htmlForm->clearInputValue($_->getName());
 #        }
         
         #$printLogger->print("   parseChooseRegions: returning a POST transaction for each checkbox...\n");
         
         foreach (@$checkboxListRef)
         {                 
            # $_ is a reference to an HTMLFormCheckbox
            # set this checkbox input to true
            $htmlForm->setInputValue($_->getName(), $_->getValue());            
         #$htmlForm->printForm();
            my $newHTTPTransaction = HTTPTransaction::new($htmlForm, $url);
            # add this new transaction to the list to return for processing
            $transactionList[$noOfTransactions] = $newHTTPTransaction;
#            $newHTTPTransaction->printTransaction();
            $noOfTransactions++;
            
            $htmlForm->clearInputValue($_->getName());
         }
             
         $printLogger->print("   parseChooseRegions: returning $noOfTransactions GET transaction for each checkbox...\n");
            
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
            $httpTransaction = HTTPTransaction::new($anchor, $url);
       
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
# parseDomainSalesChooseState
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
sub parseDomainSalesChooseState

{	
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;         
   my $instanceID = shift;
   my $transactionNo = shift;
   my @anchors;
   my $printLogger = $documentReader->getGlobalParameter('printLogger');
   my $state = $documentReader->getGlobalParameter('state');
   my @transactionList;
   
   # --- now extract the property information for this page ---
   $printLogger->print("inParseChooseState:\n");
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
sub parseDomainSalesSearchResults

{	
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;    
   my $instanceID = shift;
   my $transactionNo = shift;
   my @urlList;        
   my $firstRun = 1;
   my $printLogger = $documentReader->getGlobalParameter('printLogger');
   my $sourceName = $documentReader->getGlobalParameter('source');

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
         
         while ($htmlSyntaxTree->setSearchStartConstraintByTag('dl'))
         {
            
            $titleString = $htmlSyntaxTree->getNextText();
            $sourceURL = $htmlSyntaxTree->getNextAnchor();
            
            # not sure why this is needed - it shifts it onto the next property, otherwise it finds the same one twice. 
            $htmlSyntaxTree->setSearchStartConstraintByTag('dl');
            
            # --- extract values ---
            ($crud, $priceLowerString) = split(/\$/, $titleString, 2);
            if ($priceLowerString)
            {
               $priceLower = $documentReader->strictNumber($documentReader->parseNumber($priceLowerString));
            }
            
            # remove non-numeric characters from the string occuring after the question mark
            ($crud, $sourceID) = split(/\?/, $sourceURL, 2);
            $sourceID =~ s/[^0-9]//gi;
            $sourceURL = new URI::URL($sourceURL, $url)->abs()->as_string();      # convert to absolute
            
            # check if the cache already contains this unique id            
            if (!$advertisedSaleProfiles->checkIfTupleExists($sourceName, $sourceID, undef, $priceLower, undef))                              
            {   
               $printLogger->print("   parseSearchResults: adding anchor id ", $sourceID, "...\n");
               $printLogger->print("   parseSearchResults: url=", $sourceURL, "\n");                  
                push @urlList, $sourceURL;
            }
            else
            {
               $printLogger->print("   parseSearchResults: id ", $sourceID , " in database. Updating last encountered field...\n");
               $advertisedSaleProfiles->addEncounterRecord($sourceName, $sourceID, undef);
            }        
         }
      }
      else
      {
         $printLogger->print("   parseSearchResults:", $sqlClient->lastErrorMessage(), "\n");
      }         
         
      # now get the anchor for the NEXT button if it's defined 
      $nextButton = $htmlSyntaxTree->getNextAnchorContainingPattern("Next");
                    
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
# parseDomainSalesDisplayResponse
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
sub parseDomainSalesDisplayResponse

{	
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;         
   my $instanceID = shift;   
   my $transactionNo = shift;
   my @anchors;
   my $printLogger = $documentReader->getGlobalParameter('printLogger');
   
   # --- now extract the property information for this page ---
   $printLogger->print("in ParseDisplayResponse:\n");
   $htmlSyntaxTree->printText();
   
   # return a list with just the anchor in it  
   return @emptyList;
   
}
