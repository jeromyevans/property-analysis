#!/usr/bin/perl
# 22 Dec 04 - derived from multiple sources
#  Contains parsers for the Domain website to obtain advertised rentals information
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
use DomainRegions;
use OriginatingHTML;

@ISA = qw(Exporter);

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
sub extractDomainRentalProfile
{
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;
   my $text;
   
   my %rentalProfile;
   my $printLogger = $documentReader->getGlobalParameter('printLogger');
   my $state = $documentReader->getGlobalParameter('state');
   my $city = $documentReader->getGlobalParameter('city');

   my $tablesRef = $documentReader->getTableObjects();
   my $advertisedRentalProfiles = $$tablesRef{'advertisedRentalProfiles'};
   my $sqlClient = $documentReader->getSQLClient();
   
   
 
   # --- across the top that MAY contain a title and description
   $htmlSyntaxTree->setSearchStartConstraintByText("Property Details");
   $htmlSyntaxTree->setSearchEndConstraintByText("Agent Details"); 
   
   # get the suburb name out of the <h1> heading
   #first word(s) is suburb name, then price or 
   $htmlSyntaxTree->setSearchStartConstraintByTag("h1");
   $suburbAndPriceString = $htmlSyntaxTree->getNextText();
   
   # remove any price information from the string...
   ($suburbNameString, $crud) = split(/\$/, $suburbAndPriceString, 2);
   $suburbNameString = $documentReader->trimWhitespace($suburbNameString);
      
   # time to get clever - use the first to see if there's a defined matching suburb name
   @words = split(/ /, $suburbNameString);
   
   $suburb = $suburbNameString;  # start assuming the whole string is the suburb name (default)
   
   $matchedSuburb = 0;
   $tryNextWord = 0;
   $searchPattern = "";
   $firstRun = 1;
   # loop for all the words in the string
   foreach (@words)
   {
      if ($firstRun)
      {
         $suburbPattern .= $_;    # append this word to the search pattern
         $firstRun = 0;
      }
      else
      {
         $suburbPattern .= " ".$_;   # insert a space then this word
      }
      
      # see if this is a suburb name...
      %matchedSuburb = matchSuburbName($sqlClient, $suburbPattern, $state);
      if (%matchedSuburb)
      {
         # this word matched a suburb - try the next word as well in case this is just a subset
         $suburb = $matchedSuburb{'SuburbName'};
         $tryNextWord = 1;
      }
      else
      {
         # didn't match - use the last matched pattern instead (or default if this is first run)
         last;
      }
   }
        
   $htmlSyntaxTree->resetSearchConstraints();
   $htmlSyntaxTree->setSearchStartConstraintByTag("h1");
   
   $firstLine = $htmlSyntaxTree->getNextText();            # usually suburb and price string (used above)
   #$addressString = $htmlSyntaxTree->getNextText();        # not always set
   $addressString = $firstLine;
   
   # if the address contains the text bedrooms, bathrooms, car spaces or Add to Shortlist then reject it
   # if the address is blank, sometimes the next pattern is variable
   if ($addressString =~ /Bedrooms|Bathrooms|Car Spaces|Add to shortlist/i)
   {
      $addressString = undef;
   }
   
# Disabled next section 8 Nov 2004.  
#   # the last word(s) are ALWAYS the suburb name.  As this is known, drop it to leave just street & street number
#   # notes on the regular expression:
#   #  \b is used to match only the whole word
#   #  $ at the end of the expression ensures it matches only at the end of the pattern (this overcomes the case where the
#   #  suburb name is also in the street name
#   $addressString =~ s/\b$suburb\b$//i;
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

     
   $htmlSyntaxTree->resetSearchConstraints();
   $htmlSyntaxTree->setSearchStartConstraintByTag("h2");
   $htmlSyntaxTree->setSearchEndConstraintByText("Latest Auction"); 
   
   $priceString = $htmlSyntaxTree->getNextTextAfterPattern("Rent:");

   # price string is sometimes lower followed by a dash then price upper
   ($priceLowerString, $priceUpperString) = split(/-/, $priceString, 2);
   $priceLower = $documentReader->strictNumber($documentReader->parseNumberSomewhereInString($priceLowerString));
   $sourceID = $documentReader->trimWhitespace($htmlSyntaxTree->getNextTextAfterPattern("Property ID:"));
   
   $type = $documentReader->trimWhitespace($htmlSyntaxTree->getNextText());  # always set (contains at least TYPE)
   $type =~ s/\://gi;   
   
   $infoString = $documentReader->trimWhitespace($htmlSyntaxTree->getNextText());
   $bedroomsString = undef;
   $bathroomsString = undef;
   
   @wordList = split(/ /, $infoString);
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
   
   # 8 Nov 04 - concatenate description (same as done for features)
   $htmlSyntaxTree->resetSearchConstraints();
   if (($htmlSyntaxTree->setSearchStartConstraintByText("Description")) && ($htmlSyntaxTree->setSearchEndConstraintByText("Email Agent")))
   {
      # append all text in the features section
      $description = undef;
      while ($nextPara = $htmlSyntaxTree->getNextText())
      {
         if ($description)
         {
            $description .= " ";
         }
         
         $description .= $nextPara;
      }
      $description = $documentReader->trimWhitespace($description);   
   }
      
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

   $rentalProfile{'State'} = $state;
 
   #DebugTools::printHash("rentalProfile", \%rentalProfile);
        
   return %rentalProfile;  
}

# -------------------------------------------------------------------------------------------------
# parseDomainRentalPropertyDetails
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
sub parseDomainRentalPropertyDetails

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
   my $printLogger = $documentReader->getGlobalParameter('printLogger');
   my $sourceName = $documentReader->getGlobalParameter('source');

   my $advertisedRentalProfiles = $$tablesRef{'advertisedRentalProfiles'};
   my $originatingHTML = $$tablesRef{'originatingHTML'};  # 27Nov04
   
   my %rentalProfiles;
   my $checksum;   
   $printLogger->print("in parsePropertyDetails ($parentLabel)\n");
   
   
   if ($htmlSyntaxTree->containsTextPattern("Property Details"))
   {
                                         
      # parse the HTML Syntax tree to obtain the advertised sale information
      %rentalProfiles = extractDomainRentalProfile($documentReader, $htmlSyntaxTree, $url);                  
      tidyRecord($sqlClient, \%rentalProfiles);        # 27Nov04 - used to be called validateProfile
      # calculate a checksum for the information - the checksum is used to approximately 
      # identify the uniqueness of the data
      $checksum = $documentReader->calculateChecksum(\%rentalProfiles);

      $printLogger->print("   parsePropertyDetails: extracted checksum = ", $checksum, ". Checking log...\n");
             
      if ($sqlClient->connect())
      {		 	 
         # check if the log already contains this checksum - if it does, assume the tuple already exists                  
         if ($advertisedRentalProfiles->checkIfTupleExists($sourceName, $rentalProfiles{'SourceID'}, $checksum, $rentalProfiles{'AdvertisedWeeklyRent'}))
         {
            # this tuple has been previously extracted - it can be dropped
            # record that it was encountered again
            $printLogger->print("   parsePropertyDetails: identical record already encountered at $sourceName.\n");
            $advertisedRentalProfiles->addEncounterRecord($sourceName, $rentalProfiles{'SourceID'}, $checksum);
         }
         else
         {
            $printLogger->print("   parsePropertyDetails: unique checksum/url - adding new record.\n");
            # this tuple has never been extracted before - add it to the database
            # 27Nov04 - addRecord returns the identifer (primaryKey) of the record created
            $identifier = $advertisedRentalProfiles->addRecord($sourceName, \%rentalProfiles, $url, $checksum, $instanceID, $transactionNo);
            
            if ($identifier >= 0)
            {
               # 27Nov04: save the HTML file entry that created this record
               $htmlIdentifier = $originatingHTML->addRecord($identifier, $url, $htmlSyntaxTree, "advertisedRentalProfiles");
            }
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

# global variable used for display purposes - indicates the current region being processed
my $currentRegion = 'Nil';

# -------------------------------------------------------------------------------------------------
# parseDomainRentalChooseSuburbs
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
sub parseDomainRentalChooseSuburbs
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
   my $printLogger = $documentReader->getGlobalParameter('printLogger');
   my $startLetter = $documentReader->getGlobalParameter('startrange');
   my $endLetter =  $documentReader->getGlobalParameter('endrange');
   my $state = $documentReader->getGlobalParameter('state');
      
   $printLogger->print("in parseChooseSuburbs ($parentLabel)\n");

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
         $optionsRef = $htmlForm->getSelectionOptions('_ctl0:listboxSuburbs');
         if ($optionsRef)
         {         
            # recover the state, region, suburb combination from the recovery file for this thread

            $lastSuburb = loadLastRentalSuburb($threadID);

            # if not already processing regions in this process instance check if 
            # continuing a thread or starting from scratch
           
            if ((!defined $lastSuburb) || ($lastSuburb eq 'Nil'))
            {
               # set flag to start at the first suburb
               $stillSeeking = 0;
               $useNextSuburb = 0;
               $lastSuburbDefined = 0;
            }
            else
            {
               # the last suburb is defined
               $stillSeeking = 1;
               $useNextSuburb = 0;   
               $lastSuburbDefined = 1;
            }
           
            # loop through the list of suburbs in the form...
            foreach (@$optionsRef)
            {  
               $value = $_->{'value'};   # this is the suburb name...
# print "'$value' useNextSuburb$useNextSuburb stillSeeking=$stillSeeking lastSubDef=$lastSuburbDefined lastSuburb=$lastSuburb\n";           
               # check if the last suburb has been encountered - if it has, then start processing from this point
               if ($useNextSuburb)
               {
                  $stillSeeking = 0;
               }
               else
               {
                  # seek forward to the last suburb processed
                  if ($lastSuburbDefined)
                  {
                     # check if this is the last suburb
                     if ($value =~ /$lastSuburb/i)
                     {
                        # this is the last suburb processed - set the flag to start from the next one
                        $useNextSuburb = 1;
                        $stillSeeking = 1;   
                     }
                  }
               }
                
               # only process the suburb once the stillSeeking flag has been cleared...
               if (!$stillSeeking)
               {
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
                           #print $_->{'text'}, " out of start range (start=$startLetter)\n";
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
                           #print "'", $_->{'text'}, "' out of end range (end='$endLetter')\n";
                        }               
                     }
                           
                     if ($acceptSuburb)
                     {         
                        
                        $printLogger->print("  $currentRegion:", $_->{'text'}, "\n");
   #                     my %domainRegion;
                        
   #                     $domainRegion{'region'} = $currentRegion;
   #                     $domainRegion{'suburb'} = $_->{'text'};
   #                     $domainRegion{'state'} = $state;
   #                     $domainRegions->addRecord(\%domainRegion);

                        # set the suburb name in the form
   
                        $htmlForm->setInputValue('_ctl0:listboxSuburbs', $_->{'value'});            
   
                        my $newHTTPTransaction = HTTPTransaction::new($htmlForm, $url, $parentLabel.".".$_->{'text'});
                  
               
                        #print $_->{'value'},"\n";
                        # add this new transaction to the list to return for processing
                        $transactionList[$noOfTransactions] = $newHTTPTransaction;
                        $noOfTransactions++;
   
                        $htmlForm->clearInputValue('_ctl0:listboxSuburbs');            
               
                     }
                  }
               }
            }
         }
         $printLogger->print("   ParseChooseSuburbs:Created a transaction for $noOfTransactions suburbs in '$currentRegion'...\n");                             
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
            
            $httpTransaction = HTTPTransaction::new($anchor, $url, $parentLabel);
            
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
# parseDomainRentalChooseRegions
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
sub parseDomainRentalChooseRegions

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
   my $anchor;
   my @transactionList;
   my $noOfTransactions = 0;
   my $printLogger = $documentReader->getGlobalParameter('printLogger');
   
   
   $printLogger->print("in parseChooseRegions ($parentLabel)\n");
    
    
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
    
         # 26 Oct 2004 - just process all the suburbs in the next region, then drop back to 
         # to the home page to start a new session with new cookies
         $startFirstRegion = 0;
         $restartLastRegion = 0;
         $continueNextRegion = 0;
        
         $lastRegion = loadLastRentalRegion($threadID);  # load the last region processed in this thread
         # if not already processing regions in this process instance check if 
         # continuing a thread or starting from scratch
         if ((!defined $currentRegion) || ($currentRegion =~ /Nil/i))
         {
            # the last region isn't defined for this thread - start from the beginning
            if ((!defined $lastRegion) || ($lastRegion =~ /Nil/i))
            {
               $startFirstRegion = 1;
            }
            else
            {
               # the last region is defined in the recovery file - continue processing that region
               # as isn't know if it terminated correctly
               $restartLastRegion = 1;
            }
         }
         else
         {
            # continue from the next region in the list (still in the same process)
            $continueNextRegion = 1;
         }

         #print "restartLastRegion:$restartLastRegion($lastRegion) startFirstRegion:$startFirstRegion continueNextRegion:$continueNextRegion (cr=$currentRegion)\n";

         # loop through all the regions defined in this page - the flags are used to determine 
         # which one to set for the transaction
         $regionAdded = 0;         
         $useNextRegion = 0;
         $useThisRegion = 0;
         foreach (@$checkboxListRef)
         {   
            
            if (!$useNextRegion)
            {       
               # if the lastRegion processed with the current checkbox then the next checkbox is the 
               # one to process this time
               if ($continueNextRegion)
               {            
                  # have previously processed a region - move onto the next one
                  if ($currentRegion eq $_->getValue())
                  {
                     # this is the last region processed - set a flag to use the next one instead
          #           print "   **setting useNextRegion to 1 as currentValue = ", $_->getValue(), "\n";
                     $useNextRegion = 1;

                  }
                  else
                  {
          #           print "   **seeking currentRegion ($currentRegion isn't ", $_->getValue(),")\n";
                  }
               }
               else
               {
                  if ($restartLastRegion)
                  {
                     # restart from the region in the recovery file
                     if ($lastRegion eq $_->getValue())
                     {
                        # this is it - start from here
                        $useThisRegion = 1;
                     }
                  }
                  else
                  {
                     # otherwise we're continuing from the start
           #          print "   **setting use this region ", $_->getValue(), "\n";

                     $useThisRegion = 1;
                  }
               }
            }
            else
            {
               # the $useNextRegion flag was set in the last iteration - now set useThisRegion flag
               # to processs this one
               $useThisRegion = 1;
            }
            
            #print "   ", $_->getValue(), ":useThisRegion:$useThisRegion useNextRegion:$useNextRegion\n";
            
            # if this flag has been set in the logic above, a transaction is used for this region
            if ($useThisRegion)
            {      
               # $_ is a reference to an HTMLFormCheckbox
               # set this checkbox input to true
               $htmlForm->setInputValue($_->getName(), $_->getValue());            
               
               # set global variable for display purposes only
               $currentRegion = $_->getValue();
               
               my $newHTTPTransaction = HTTPTransaction::new($htmlForm, $url, $parentLabel.".".$_->getValue());
               # add this new transaction to the list to return for processing
               $transactionList[$noOfTransactions] = $newHTTPTransaction;
               $noOfTransactions++;

               $htmlForm->clearInputValue($_->getName());
               
               # record which region was last processed in this thread
               saveLastRentalRegion($threadID, $_->getValue());
               saveLastRentalSuburb($threadID, 'Nil');          # reset to the first suburb in the region

               $regionAdded = 1;
               last;   # break out of the checkbox loop
            }
         } # end foreach

         if (!$regionAdded)
         {
            # no more regions to process - finished
            
            saveLastRentalRegion($threadID, 'Nil');
            saveLastRentalSuburb($threadID, 'Nil');          # reset to the first suburb in the region
         }
         else
         {
            # add the home directory as the second transaction to start a new session for the next region
            ##### NEED TO RESET COOKIES HERE?
            my $newHTTPTransaction = HTTPTransaction::new('http://www.domain.com.au/Public/advancedsearch.aspx?mode=buy', undef, 'base');
            
            # add this new transaction to the list to return for processing
            $transactionList[$noOfTransactions] = $newHTTPTransaction;
            $noOfTransactions++;
         }
         
         $printLogger->print("   parseChooseRegions: returning $noOfTransactions GET transactions (next region and home)...\n");
            
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
            $httpTransaction = HTTPTransaction::new($anchor, $url, $parentLabel);
       
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
# parseDomainRentalChooseState
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
sub parseDomainRentalChooseState

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
   
   # delete cookies to start a fresh session 
   $documentReader->deleteCookies();
   
   
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
sub parseDomainRentalSearchResults

{	
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;    
   my $instanceID = shift;
   my $transactionNo = shift;
   my $threadID = shift;
   my $parentLabel = shift;
   
   my @urlList;        
   my $firstRun = 1;
   my $printLogger = $documentReader->getGlobalParameter('printLogger');
   my $sourceName = $documentReader->getGlobalParameter('source');
   my $state = $documentReader->getGlobalParameter('state');
   my $suburbName;
   
   # --- now extract the property information for this page ---
   $printLogger->print("inParseSearchResults ($parentLabel):\n");
   #$htmlSyntaxTree->printText();
   if ($htmlSyntaxTree->containsTextPattern("Search Results"))
   {         
      
      if ($sqlClient->connect())
      {
      
         $htmlSyntaxTree->setSearchStartConstraintByText("Your search for properties");
         $htmlSyntaxTree->setSearchEndConstraintByText("email me similar properties");
      
         # get the suburbname from the page - used to tracking progress...
         $trialSuburbName = $htmlSyntaxTree->getNextTextAfterPattern("suburbs:");
         $suburbName = matchSuburbName($sqlClient, $suburbName, $state);
         if (!$suburbName)
         {
            $suburbName = $trialSuburbName;
         }
         
         $htmlSyntaxTree->resetSearchConstraints();
         
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
            else
            {
               $priceLower = undef;
            }
            
            # remove non-numeric characters from the string occuring after the question mark
            ($crud, $sourceID) = split(/\?/, $sourceURL, 2);
            $sourceID =~ s/[^0-9]//gi;
            $sourceURL = new URI::URL($sourceURL, $url)->abs()->as_string();      # convert to absolute
           
            # check if the cache already contains this unique id            
            if (!$advertisedRentalProfiles->checkIfTupleExists($sourceName, $sourceID, undef, $priceLower, undef))                              
            {   
               $printLogger->print("   parseSearchResults: adding anchor id ", $sourceID, "...\n");
               #$printLogger->print("   parseSearchResults: url=", $sourceURL, "\n"); 
               my $httpTransaction = HTTPTransaction::new($sourceURL, $url, $parentLabel.".".$sourceID);                  
               #push @urlList, $sourceURL;
               push @urlList, $httpTransaction;
            }
            else
            {
               $printLogger->print("   parseSearchResults: id ", $sourceID , " in database. Updating last encountered field...\n");
               $advertisedRentalProfiles->addEncounterRecord($sourceName, $sourceID, undef);
            }
         }
         
         # save that this suburb has been processed (for tracking progress)
         saveLastRentalSuburb($threadID, $suburbName);
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
         $httpTransaction = HTTPTransaction::new($nextButton, $url, $parentLabel);                  
         @anchorsList = (@urlList, $httpTransaction);
      }
      else
      {            
         $printLogger->print("   parseSearchResults: list has no 'next' button anchor...\n");
         @anchorsList = @urlList;
      }                      
        
      $length = @anchorsList;         
      $printLogger->print("   parseSearchResults: following $length properties for '$currentRegion'...\n");               
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
sub parseDomainRentalDisplayResponse

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
   $printLogger->print("in ParseDisplayResponse ($parentLabel):\n");
   $htmlSyntaxTree->printText();
   
   # return a list with just the anchor in it  
   return @emptyList;
   
}


# -------------------------------------------------------------------------------------------------
# saveLastRegion

#
# Purpose:
#  Debugging
#
# Parametrs:
#  nil
#
# Constraints:
#  nil
#
# Updates:
#  $this->{'requestRef'} 
#  $this->{'responseRef'}
#
# Returns:
#   nil
#
sub saveLastRentalRegion

{
   my $thisThreadID = shift;
   my $regionName = shift;
   my $recoveryPointFileName = "RecoverDomainRentalRegion.last";
   my %regionList;
   
   # load the cookie file name from the recovery file
   open(SESSION_FILE, "<$recoveryPointFileName") || print "   Can't open last domain region file: $!\n"; 
  
   $index = 0;
   # loop through the content of the file
   while (<SESSION_FILE>) # read a line into $_
   {
      # remove end of line marker from $_
      chomp;
      # split on null character
      ($threadID, $region) = split /=/;
    
      $regionList{$threadID} = $region;

      $index++;                    
   }
   
   close(SESSION_FILE);     
   
   # update this threadID
   $regionList{$thisThreadID} = $regionName;
   
   # save the new file with the thread removed  
   open(SESSION_FILE, ">$recoveryPointFileName") || print "Can't open file: $!"; 
   
   # loop through all of the elements (in reverse so they can be read into a stack)
   foreach (keys %regionList)      
   {        
      print SESSION_FILE $_."=".$regionList{$_}."\n";        
   }

#   print "savedLastRegion$thisThreadID=", $regionList{$thisThreadID}, "\n";
   
   close(SESSION_FILE);          
}

# -------------------------------------------------------------------------------------------------

# reads the name of the session corresponding to this thread from the recovery file
sub loadLastRentalRegion

{
   my $thisThreadID = shift;
   my $regionName;
   my $recoveryPointFileName = "RecoverDomainRentalRegion.last";
   my %regionList;
   
   # load the cookie file name from the recovery file
   open(SESSION_FILE, "<$recoveryPointFileName") || print "   Can't open last domain region file: $!\n"; 
  
   $index = 0;
   # loop through the content of the file
   while (<SESSION_FILE>) # read a line into $_
   {
      # remove end of line marker from $_
      chomp;
      # split on null character
      ($threadID, $regionName) = split /=/;
    
      $regionList{$threadID} = $regionName;

      $index++;                    
   }
   
   close(SESSION_FILE);     
#   print "loadedLastRegion:$thisThreadID=", $regionList{$thisThreadID}, "\n";
   
   return $regionList{$thisThreadID};
} 

# -------------------------------------------------------------------------------------------------


# -------------------------------------------------------------------------------------------------
# saveLastRentalSuburb

#
# Purpose:
#  Debugging
#
# Parametrs:
#  nil
#
# Constraints:
#  nil
#
# Updates:
#  $this->{'requestRef'} 
#  $this->{'responseRef'}
#
# Returns:
#   nil
#
sub saveLastRentalSuburb

{
   my $thisThreadID = shift;
   my $suburbName = shift;
   
   my $recoveryPointFileName = "RecoverDomainRentalSuburb.last";
   my %suburbList;
   my $threadID;
   my $suburb;
   my $index;
   
   # load the cookie file name from the recovery file
   open(SESSION_FILE, "<$recoveryPointFileName") || print "   Can't open last domain suburb file: $!\n"; 
  
   $index = 0;
   # loop through the content of the file
   while (<SESSION_FILE>) # read a line into $_
   {
      # remove end of line marker from $_
      chomp;
      # split on null character
      ($threadID, $suburb) = split /=/;
   
      $suburbList{$threadID} = $suburb;

      $index++;                    
   }
   
   close(SESSION_FILE);     
   
   # update this threadID
   $suburbList{$thisThreadID} = $suburbName;
   
   # save the new file with the thread removed  
   open(SESSION_FILE, ">$recoveryPointFileName") || print "Can't open file: $!"; 
   
   # loop through all of the elements (in reverse so they can be read into a stack)
   foreach (keys %suburbList)      
   {        
      print SESSION_FILE $_."=".$suburbList{$_}."\n";        
   }

   close(SESSION_FILE);          

   print "savedLastSuburb $thisThreadID=", $suburbList{$thisThreadID}, "\n";
   
   return 1;
}

# -------------------------------------------------------------------------------------------------

# reads the name of the suburb corresponding to this thread from the recovery file
sub loadLastRentalSuburb

{
   my $thisThreadID = shift;
   my $suburbName;
   my $recoveryPointFileName = "RecoverDomainRentalSuburb.last";
   my %suburbList;
   
   # load the cookie file name from the recovery file
   open(SESSION_FILE, "<$recoveryPointFileName") || print "   Can't open last domain suburb file: $!\n"; 
  
   $index = 0;
   # loop through the content of the file
   while (<SESSION_FILE>) # read a line into $_
   {
      # remove end of line marker from $_
      chomp;
      # split on null character
      ($threadID, $suburbName) = split /=/;
    
      $suburbList{$threadID} = $suburbName;

      $index++;                    
   }
   
   close(SESSION_FILE);     
   print "loadedLastSuburb:$thisThreadID=", $suburbList{$thisThreadID}, "\n";
   
   return $suburbList{$thisThreadID};
} 

# -------------------------------------------------------------------------------------------------

