#!/usr/bin/perl
# 16 Oct 04 - derived from multiple sources
#  Contains parsers for the REIWA website to obtain advertised rental information
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
use SessionProgressTable;

@ISA = qw(Exporter);


# -------------------------------------------------------------------------------------------------
# extractREIWARentalProfile
# extracts property rental information from an HTML Syntax Tree
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
sub extractREIWARentalProfile
{
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;
   my $text;
   
   my %rentalProfile;   
   
   # --- set start constraint to the 3rd table (table 2) on the page - this is table
   # --- across the top that MAY contain a title and description            
   $htmlSyntaxTree->setSearchConstraintsByTable(2);
   $htmlSyntaxTree->setSearchEndConstraintByTag("td"); # until the next table
                    
   $IDSuburbPrice = $htmlSyntaxTree->getNextText();    # always set
   
   ($sourceID, $suburb, $priceLower, $priceHigher) = split /\-/, $IDSuburbPrice;
     
   $gumph = $htmlSyntaxTree->getNextText();            # sometimes undef
   # ---   
   #$htmlSyntaxTree->setSearchStartConstraintByTag("tr");  # next row of table
   $htmlSyntaxTree->setSearchStartConstraintByTag("tr");  # next row of table   
   $htmlSyntaxTree->setSearchEndConstraintByTag("table");    
   $title = $htmlSyntaxTree->getNextText();            # sometimes undef
   $description = $htmlSyntaxTree->getNextText();      # sometimes undef        

   # --- set start constraint to the 4th table on the page - this is table
   # --- to the right of the image that contains parameters for the property   
   $htmlSyntaxTree->setSearchConstraintsByTable(3);
   $htmlSyntaxTree->setSearchEndConstraintByTag("table"); # until the next table
   
   $type = $htmlSyntaxTree->getNextText();                # always set
   
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
   $sourceID =~ s/ //gi;     # remove spaces if exist
   
   # substitute trailing whitespace characters with blank
   # s/whitespace from end-of-line/all occurances
   # s/\s*$//g;      
   $suburb =~ s/\s*$//g;

   # substitute leading whitespace characters with blank
   # s/whitespace from start-of-line,multiple single characters/blank/all occurances
   #s/^\s*//g;    
   $suburb =~ s/^\s*//g;
   
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
       
   return %rentalProfile;  
}

# -------------------------------------------------------------------------------------------------
# parseREIWARentalsSearchDetails
# parses the htmlsyntaxtree to extract advertised rental information and insert it into the database
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
sub parseREIWARentalsSearchDetails

{	
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;
   my $instanceID = shift;
   my $transactionNo = shift;
   my $threadID = shift;
   my $parentLabel = shift;
   my $statusTable = $documentReader->getStatusTable();
   
   my $sqlClient = $documentReader->getSQLClient();
   my $tablesRef = $documentReader->getTableObjects();
   
   my $advertisedRentalProfiles = $$tablesRef{'advertisedRentalProfiles'};
   my $originatingHTML = $$tablesRef{'originatingHTML'};  # 22Dec04
   
   my %rentalProfiles;
   my $checksum;   
   my $sourceName = $documentReader->getGlobalParameter('source');
   my $printLogger = $documentReader->getGlobalParameter('printLogger');
   
   $printLogger->print("in parseSearchDetails ($parentLabel)\n");
   
   # --- now extract the property information for this page ---
                                       
   # parse the HTML Syntax tree to obtain the advertised rental information
   %rentalProfiles = extractREIWARentalProfile($documentReader, $htmlSyntaxTree, $url);                  
            
   tidyRecord($sqlClient, \%rentalProfiles);        # 27Nov04 - used to be called validateProfile
#print "ValidatedDesc: ", $rentalProfiles{'description'}, "\n";         
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
         # record in the log that it was encountered again
         $printLogger->print("   parseSearchDetails: record already encountered at $SOURCE_NAME.\n");
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
   	  
   
   
   # return an empty list
   return @emptyList;
}


# -------------------------------------------------------------------------------------------------
# parseREIWARentalsSearchList
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
sub parseREIWARentalsSearchList

{	
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;    
   my $instanceID = shift;
   my $transactionNo = shift;
   my $threadID = shift;
   my $parentLabel = shift;
   
   my $printLogger = $documentReader->getGlobalParameter('printLogger');
   my $sourceName =  $documentReader->getGlobalParameter('source');
   my $tablesRef = $documentReader->getTableObjects();
   my $advertisedRentalProfiles = $$tablesRef{'advertisedRentalProfiles'};

   my @urlList;
   my $firstRun = 1;        
   my $statusTable = $documentReader->getStatusTable();
   my $sessionProgressTable = $documentReader->getSessionProgressTable();   # 23Jan05
   my $recordsEncountered = 0;

   # --- now extract the property information for this page ---
   $printLogger->print("inParseSearchList ($parentLabel):\n");

   #$htmlSyntaxTree->printText();
   if ($htmlSyntaxTree->containsTextPattern("matching listings"))
   {         
      # get all anchors containing any text
      if ($housesListRef = $htmlSyntaxTree->getAnchorsAndTextContainingPattern("\#"))
      {  
         # loop through all the entries in the log cache
         $printLogger->print("   parseSearchList: checking if unique IDs exist...\n");
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
               
               $priceString = $htmlSyntaxTree->getNextTextAfterPattern($sourceID);
               $price = $documentReader->strictNumber($documentReader->parseNumber($priceString, 1));
               if ($price)
               {
                  $printLogger->print("      printSearchList: checking if price changed (now '$price')\n");
               }
               # check if the cache already contains this unique id
               # $_ is a reference to a hash           

               if (!$advertisedRentalProfiles->checkIfTupleExists($sourceName, $sourceID, undef, $price))
               {   
                  $printLogger->print("      parseSearchList: adding anchor id ", $sourceID, "...\n");
                  #$printLogger->print("   parseSearchList: url=", $sourceURL, "\n");           
                  my $httpTransaction = HTTPTransaction::new($sourceURL, $url, $parentLabel.".".$sourceID);                  
             
                  push @urlList, $httpTransaction;
               }
               else
               {                 
                  $printLogger->print("      parseSearchList: id ", $sourceID , " in database.  Updating last encountered field...\n");
                  $advertisedRentalProfiles->addEncounterRecord($sourceName, $sourceID, undef);
               }
            
               $recordsEncountered++;  # count records seen
                # 23Jan05:save that this suburb has had some progress against it
               $sessionProgressTable->reportProgressAgainstSuburb($threadID, 1);
            }      
            $statusTable->addToRecordsEncountered($threadID, $recordsEncountered, $url);
            
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
            $httpTransaction = HTTPTransaction::new($$nextButtonListRef[0], $url, $parentLabel);                  

            @anchorsList = (@urlList, $httpTransaction);
         }
         else
         {            
            $printLogger->print("   parseSearchList: list has no 'next' button anchor...\n");
            @anchorsList = @urlList;
            # 23Jan05:save that this suburb has (almost) completed - just need to process the details
            $sessionProgressTable->reportSuburbCompletion($threadID);
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
      # 23Jan05:save that this suburb has (almost) completed - just need to process the details
      $sessionProgressTable->reportSuburbCompletion($threadID);
      $printLogger->print("   parseSearchList: returning empty anchor list.\n");
      return @emptyList;
   }   
     
}

# -------------------------------------------------------------------------------------------------
# parseREIWARentalsSearchQuery
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
sub parseREIWARentalsSearchQuery

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
   my $printLogger = $documentReader->getGlobalParameter('printLogger');   
   my $sessionProgressTable = $documentReader->getSessionProgressTable();   # 23Jan05

   $printLogger->print("in parseSearchQuery ($parentLabel)\n");
       
   # report that a suburb has started being processed...
   $suburbName = extractOnlyParentName($parentLabel);
   $sessionProgressTable->reportRegionOrSuburbChange($threadID, undef, $suburbName);
   
   
   # if this page contains a form to select whether to proceed or not...
   $htmlForm = $htmlSyntaxTree->getHTMLForm();
            
   if ($htmlForm)
   {       
      #$actionURL = new URI::URL($htmlForm->getAction(), $url)->abs();
           
      #%postParameters = $htmlForm->getPostParameters();
      $printLogger->print("   parseSearchQueury: returning POST transaction for continue form.\n");
      #$httpTransaction = HTTPTransaction::new($actionURL, 'POST', \%postParameters, $url);
      $httpTransaction = HTTPTransaction::new($htmlForm, $url, "TBD");           
      my $newHTTPTransaction = HTTPTransaction::new($htmlForm, $url, $parentLabel.".continue");

   }	  
   else 
   {
      $printLogger->print("   parseSearchQuery: continue form not found\n");
      
      # there are no records in this suburb - it's already completed
      $sessionProgressTable->reportSuburbCompletion($threadID);
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
# -------------------------------------------------------------------------------------------------
# parseREIWARentalsSearchForm
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
sub parseREIWARentalsSearchForm

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

   my @metropolitanAreas = ('Armadale', 'Bassendean', 'Bayswater', 'Belmont', 'Cambridge', 'Canning', 'Chittering', 'Claremont', 'Cockburn', 'Cottesloe', 'East Fremantle', 'Fremantle', 'Gosnells', 'Joondalup', 'Kalamunda', 'Kwinana', 'Melville', 'Mosman Park', 'Mundaring', 'Nedlands', 'Peppermint Grove', 'Perth', 'Rockingham', 'Serpentine-Jarrahdale', 'South Perth', 'Stirling', 'Subiaco', 'Swan', 'Toodyah', 'Victoria Park', 'Vincent', 'Wanneroo');  
   my %subAreaHash;
   
   $printLogger->print("in parseSearchForm ($parentLabel)\n");
      
   # get the HTML Form instance
   $htmlForm = $htmlSyntaxTree->getHTMLForm("search");
    
   if ($htmlForm)
   {
      $htmlForm->setInputValue('ListingClass', '11');         # All property types             
      $htmlForm->setInputValue('MainArea', '1');              # Perth metropolitan suburbs
      
      # for all of the suburbs defined in the form, create a transaction to get it
      $optionsRef = $htmlForm->getSelectionOptions('subdivision');
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
               # set the value to this option in the selection
               $htmlForm->setInputValue('subdivision', $_->{'value'});

               # determine if the suburbname is in the specific letter constraint
               $acceptSuburb = isSuburbNameInRange($_->{'text'}, $startLetter, $endLetter);  # 23Jan05
            }
                  
            if ($acceptSuburb)
            {         
               # 23 Jan 05 - another check - see if the suburb has already been 'completed' in this thread
               # if it has been, then don't do it again (avoids special case where servers may return
               # the same suburb for multiple search variations)
               if (!$sessionProgressTable->hasSuburbBeenProcessed($threadID, $_->{'text'}))
               { 
               
                  #print "accepted\n";               
                  my $newHTTPTransaction = HTTPTransaction::new($htmlForm, $url, $parentLabel.".".$_->{'text'});
   
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
      }
      
      $printLogger->print("   ParseSearchForm:Created a transaction for $noOfTransactions metropolitan suburbs...\n");

      # now do the regional areas

      # construct the hash of subareas 
      $optionsRef = $htmlForm->getSelectionOptions('SubArea');
      if ($optionsRef)
      {
         
         $sessionProgressTable->prepareSuburbStateMachine($threadID);     # 23Jan05
         
         foreach (@$optionsRef)
         {  
            # get the value to this option in the selection            
            if ($_->{'value'} != 0)  # ignore [All]
            {
               $acceptSuburb = 0;

               # check if the last suburb has been encountered - if it has, then start processing from this point
               $useThisSuburb = $sessionProgressTable->isSuburbAcceptable($_->{'text'});  # 23Jan05
               
               if ($useThisSuburb)
               {
                  
                  # determine if the suburbname is in the specific letter constraint
                  $acceptSuburb = isSuburbNameInRange($_->{'text'}, $startLetter, $endLetter);  # 23Jan05
               }
       
               if ($acceptSuburb)
               {
                  # 23 Jan 05 - another check - see if the suburb has already been 'completed' in this thread
                  # if it has been, then don't do it again (avoids special case where servers may return
                  # the same suburb for multiple search variations)
                  if (!$sessionProgressTable->hasSuburbBeenProcessed($threadID, $_->{'text'}))
                  { 
                     $subAreaHash{$_->{'text'}} = $_->{'value'};
                  }
                  else
                  {
                     $printLogger->print("   parseSearchForm:suburb ", $_->{'text'}, " previously processed in this thread.  Skipping...\n");
                  }
               }
            }
         } # end foreach
         
         # remove the hardcoded metropolitan areas from the list of subareas - don't want to process them twice
         foreach (@metropolitanAreas)
         {
            delete $subAreaHash{$_};
         }
      } # end building hash of subareas
      
      # loop through all the main areas defined (Perth metropolitan and then regional areas) in alphabetical order
      foreach (sort(keys %subAreaHash))
      {      
         #print "regional area: $_ (", $subAreaHash{$_}, ")\n";
                     
         # get the list of subareas hardcoded for this mainarea
         $htmlForm->clearInputValue('subdivision');              # don't set subdivision                  
         $htmlForm->setInputValue('MainArea', 0);                # MainArea is [all] 
         $htmlForm->setInputValue('SubArea', $subAreaHash{$_});
         my $newHTTPTransaction = HTTPTransaction::new($htmlForm, $url, $parentLabel.".".$subAreaHash{$_});
         
         # add this new transaction to the list to return for processing
         $transactionList[$noOfTransactions] = $newHTTPTransaction;
         $noOfTransactions++;
      }      
      
      $printLogger->print("   ParseSearchForm:Creating a transaction for $noOfTransactions total areas...\n");                       
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
# parseREIWARentalsHomePage
# parses the htmlsyntaxtree to extract the link to the Advertised rental page
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
sub parseREIWARentalsHomePage

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
      $anchor = $htmlSyntaxTree->getNextAnchorContainingPattern("Homes for Rent");
      if ($anchor)
      {
         $printLogger->print("   following anchor 'Homes for Rent'...\n");
      }
      else
      {
         $printLogger->print("   anchor 'Homes for Rent' not found!\n");
      }
   }	  
   else 
   {
      $printLogger->print("parseHomePage: pattern not found\n");
   }
   
   # return a list with just the anchor in it
   if ($anchor)
   {
      $httpTransaction = HTTPTransaction::new($anchor, $url, $parentLabel.".rentals");   # use the state in the label

      return ($httpTransaction);
   }
   else
   {
      return @emptyList;
   }
}

# -------------------------------------------------------------------------------------------------
# parseREIWARentalsDisplayResponse
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
sub parseREIWARentalsDisplayResponse

{	
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;         
   my $instanceID = shift;   
   my $transactionNo = shift;
   my @anchors;
   my $printLogger = $documentReader->getGlobalParameter('printLogger');
   
   # --- now extract the property information for this page ---
   $printLogger->print("in ParseDisplayResponse ($parentLabel):\n");
   $htmlSyntaxTree->printText();
   
   # return a list with just the anchor in it  
   return @emptyList;
   
}

# -------------------------------------------------------------------------------------------------

