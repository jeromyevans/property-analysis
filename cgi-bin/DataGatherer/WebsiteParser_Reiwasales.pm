#!/usr/bin/perl
# 28 Sep 04 - derived from multiple sources
#  Contains parsers for the REIWA website to obtain advertised sales information
#
#  all parses must accept two parameters:
#   $documentReader
#   $htmlSyntaxTree
#
# The parsers can't access any other global variables, but can use functions in the WebsiteParser_Common module
# History:
#  5 December 2004 - adapted to use common AdvertisedPropertyProfiles instead of separate rentals and sales tables
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
sub extractREIWASaleProfile
{
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;
   my $text;
   
   my %saleProfile;   
 #  print "   inExtractSaleProfile:\n";
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

   $saleProfile{'State'} = $documentReader->getGlobalParameter('state');
     
  # DebugTools::printHash("SaleProfile", \%saleProfile);
        
   return %saleProfile;  
}

# -------------------------------------------------------------------------------------------------
# parseREIWASalesSearchDetails
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
sub parseREIWASalesSearchDetails

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
   my $statusTable = $documentReader->getStatusTable();

   my $advertisedSaleProfiles = $$tablesRef{'advertisedSaleProfiles'};
   my $originatingHTML = $$tablesRef{'originatingHTML'};  # 22Dec04

   my %saleProfiles;
   my $checksum;   
   my $sourceName = $documentReader->getGlobalParameter('source');
   my $printLogger = $documentReader->getGlobalParameter('printLogger');
   $printLogger->print("in parseSearchDetails ($parentLabel)\n");
   
   if ($htmlSyntaxTree->containsTextPattern("Property Details"))
   {
      # --- now extract the property information for this page ---
      #if ($htmlSyntaxTree->containsTextPattern("Suburb Profile"))
      #{
      # parse the HTML Syntax tree to obtain the advertised sale information
      %saleProfiles = extractREIWASaleProfile($documentReader, $htmlSyntaxTree, $url);

      tidyRecord($sqlClient, \%saleProfiles);        # 27Nov04 - used to be called validateProfile
#       DebugTools::printHash("sa;e", \%saleProfiles);
              
      # calculate a checksum for the information - the checksum is used to approximately 
      # identify the uniqueness of the data
      $checksum = $documentReader->calculateChecksum(\%saleProfiles);
            
      $printLogger->print("   parseSearchDetails: extracted checksum = ", $checksum, ". Checking log...\n");
             
      if ($sqlClient->connect())
      {		 	 
         # check if the log already contains this checksum - if it does, assume the tuple already exists                  
         if ($advertisedSaleProfiles->checkIfTupleExists($sourceName, $saleProfiles{'SourceID'}, $checksum, $saleProfiles{'AdvertisedPriceLower'}))
         {
            # this tuple has been previously extracted - it can be dropped
            # record that it was encountered again
            $printLogger->print("   parseSearchDetails: identical record already encountered at $sourceID.\n");
            $advertisedSaleProfiles->addEncounterRecord($sourceName, $saleProfiles{'SourceID'}, $checksum);
            $statusTable->addToRecordsParsed($threadID, 1, 0, $url);    
         }
         else
         {
            $printLogger->print("   parseSearchDetails: unique checksum/url - adding new record.\n");
            # this tuple has never been extracted before - add it to the database
            $identifier = $advertisedSaleProfiles->addRecord($sourceName, \%saleProfiles, $url, $checksum, $instanceID, $transactionNo);
            $statusTable->addToRecordsParsed($threadID, 1, 1, $url);    

            if ($identifier >= 0)
            {
               # 27Nov04: save the HTML file entry that created this record
               $htmlIdentifier = $originatingHTML->addRecord($identifier, $url, $htmlSyntaxTree, "advertisedSaleProfiles");
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
sub parseREIWASalesSearchForm

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
   
   my @metropolitanAreas = ('Armadale', 'Bassendean', 'Bayswater', 'Belmont', 'Cambridge', 'Canning', 'Chittering', 'Claremont', 'Cockburn', 'Cottesloe', 'East Fremantle', 'Fremantle', 'Gosnells', 'Joondalup', 'Kalamunda', 'Kwinana', 'Melville', 'Mosman Park', 'Mundaring', 'Nedlands', 'Peppermint Grove', 'Perth', 'Rockingham', 'Serpentine-Jarrahdale', 'South Perth', 'Stirling', 'Subiaco', 'Swan', 'Toodyah', 'Victoria Park', 'Vincent', 'Wanneroo');  
   my %subAreaHash;
      
   $printLogger->print("in parseSearchForm ($parentLabel)\n");
      
   # get the HTML Form instance
   $htmlForm = $htmlSyntaxTree->getHTMLForm("search");
    
   if ($htmlForm)
   {       
      $htmlForm->setInputValue('minprice', 1);                # minimum price of 0
               
      # --- Perth Metropolitan suburbs ---
      $htmlForm->setInputValue('MainArea', '1');
#      print "\nPerth Metropolitan (1):\n";
      
      # for all of the suburbs defined in the form, create a transaction to get it
      $optionsRef = $htmlForm->getSelectionOptions('subdivision');
      # parse through all those in the perth metropolitan area
      if ($optionsRef)
      {         
         foreach (@$optionsRef)
         {
            # create a duplicate of the default post parameters
            #my %newPostParameters = %defaultPostParameters;
            
            # and set the value to this option in the selection            
            
            #$newPostParameters{'subdivision'} = $_->{'value'};
            $htmlForm->setInputValue('subdivision', $_->{'value'});
 #           print $_->{'text'}, ", ";
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
               #my $newHTTPTransaction = HTTPTransaction::new($actionURL, 'POST', \%newPostParameters, $url);
               my $newHTTPTransaction = HTTPTransaction::new($htmlForm, $url, $parentLabel.".".$_->{'text'});
               #print $htmlForm->getEscapedParameters(), "\n";
            
               # add this new transaction to the list to return for processing
               $transactionList[$noOfTransactions] = $newHTTPTransaction;
               $noOfTransactions++;
            }
         }
         
         $printLogger->print("   ParseSearchForm:Created a transaction for $noOfTransactions metropolitan suburbs...\n");
      }  # end of metropolitan areas
               
      # now do the regional areas

      # construct the hash of subareas 
      $optionsRef = $htmlForm->getSelectionOptions('SubArea');
      if ($optionsRef)
      {         
         foreach (@$optionsRef)
         {  
            # get the value to this option in the selection            
            if ($_->{'value'} != 0)  # ignore [All]
            {           
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
                     #print "out of start range\n";
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
                  $subAreaHash{$_->{'text'}} = $_->{'value'};
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
# parseREIWASalesSearchQuery
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
sub parseREIWASalesSearchQuery

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
      
   $printLogger->print("in parseSearchQuery ($parentLabel)\n");
       
   # if this page contains a form to select whether to proceed or not...
   $htmlForm = $htmlSyntaxTree->getHTMLForm();
   if ($htmlForm)
   {       
      #$actionURL = new URI::URL($htmlForm->getAction(), $url)->abs();
           
      #%postParameters = $htmlForm->getPostParameters();
      $printLogger->print("   parseSearchQueury: returning POST transaction for continue form.\n");
      #$httpTransaction = HTTPTransaction::new($actionURL, 'POST', \%postParameters, $url);
      $httpTransaction = HTTPTransaction::new($htmlForm, $url, $parentLabel);            
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
# parseREIWASalesHomePage
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
sub parseREIWASalesHomePage

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
      my $newHTTPTransaction = HTTPTransaction::new($anchor, $url, $parentLabel."sales");

      return ($newHTTPTransaction);
   }
   else
   {
      return @emptyList;
   }
}

# -------------------------------------------------------------------------------------------------
# parseREIWASalesSearchList
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
sub parseREIWASalesSearchList

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
   
   my @urlList;        
   my $firstRun = 1;
   my $statusTable = $documentReader->getStatusTable();
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
         $printLogger->print("   parseSearchList: checking if unqiue ID exists...\n");
         if ($sqlClient->connect())
         {
            foreach (@$housesListRef)
            {
               $sourceID = $$_{'string'};
               $sourceURL = $$_{'href'};
              
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
               if (!$advertisedSaleProfiles->checkIfTupleExists($sourceName, $sourceID, undef, $priceLower, $priceHigher))                              
               {   
                  $printLogger->print("   parseSearchList: adding anchor id ", $sourceID, "...\n");
                  #$printLogger->print("   parseSearchList: url=", $sourceURL, "\n");          
                   my $httpTransaction = HTTPTransaction::new($sourceURL, $url, $parentLabel.".".$sourceID);                  
             
                   push @urlList, $httpTransaction;
            #      push @urlList, $sourceURL;
               }
               else
               {
                  $printLogger->print("   parseSearchList: id ", $sourceID , " in database. Updating last encountered field...\n");
                  $advertisedSaleProfiles->addEncounterRecord($sourceName, $sourceID, undef);
               }
               $recordsEncountered++;  # count records seen
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
# parseREIWASalesDisplayResponse
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
sub parseREIWASalesDisplayResponse

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

