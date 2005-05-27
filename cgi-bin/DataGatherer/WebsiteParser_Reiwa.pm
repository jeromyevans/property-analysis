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
# 23 January 2005  - added support for the SessionProgressTable reporting of progress of the thread
#                  - added check against SessionProgressTable to reject suburbs that appear 'completed' already
#  in the table.  Should prevent procesing of suburbs more than once if the server returns the same suburb under
#  multiple searches.  Note: completed indicates the propertylist has been parsed, not necessarily all the details.
# 25 May 2005      - REIWA website has undergone significant redesign
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
# extractREIWAProfile
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
sub extractREIWAProfile
{
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;
   my $parentLabel = shift;
   my $text;
   
   my %propertyProfile;  
   my $printLogger = $documentReader->getGlobalParameter('printLogger');

   my $tablesRef = $documentReader->getTableObjects();
   my $sqlClient = $documentReader->getSQLClient();
   
   my $saleOrRentalFlag = -1;
   my $sourceName = undef;
   my $state = undef;
   
   # first, locate the pattern that identifies the source of the record as RealEstate.com
   if ($htmlSyntaxTree->containsTextPattern("REIWA Online"))
   {
      $sourceName = 'REIWA';
   }
   
   if ($sourceName) 
   {
      $propertyProfile{'SourceName'} = $sourceName;
   }
   
   # second, locate the pattern that identifies this as a SALE record or RENT record
   # 26 May 2005 - there is a bug in the REIWA website that displays the title 'Property for Sale' even
   # for a rental listing - have to work around it by simply using the url
   if ($url =~ /Lst-ResSale/gi)
   {
      $saleOrRentalFlag = 0;
   }
   elsif ($url =~ /Lst-ResRent/gi)
   {
      $saleOrRentalFlag = 1;
   }
   
   $propertyProfile{'SaleOrRentalFlag'} = $saleOrRentalFlag;
   
   # third, locate the STATE for the property 
   # this is hardcoded
   $propertyProfile{'State'} = 'WA';
   
   # --- extract the sourceID ---
   
   $sourceID = $htmlSyntaxTree->getNextTextContainingPattern("Property For");
   $sourceID =~ s/\D//gi;  # remove non-digits
   
   if ($sourceID) 
   {
      $propertyProfile{'SourceID'} = $documentReader->trimWhitespace($sourceID);
   }
   
   # --- extract the price string ---
   
   $htmlSyntaxTree->setSearchStartConstraintByTagAndClass('td', 'lstv-price');
   $priceString = $htmlSyntaxTree->getNextText();
      
   if ($priceString) 
   {
      $propertyProfile{'AdvertisedPriceString'} = $documentReader->trimWhitespace($priceString);
   }
   
   # --- for REIWA.com.au the titleString is the priceString prefixed by Sold or Under Offer if applicable ---
   $htmlSyntaxTree->resetSearchConstraints();
   $htmlSyntaxTree->setSearchStartConstraintByTagAndClass('td', 'lstv-maincolumn', 1);
   $tagHash = $htmlSyntaxTree->getNextTagMatchingPattern('img');
   $htmlSyntaxTree->setSearchEndConstraintByTag('/td');
   $title = $$tagHash{'title'};
   if ($title =~ /Sold/gi)
   {
      $titleString = "Sold ".$documentReader->trimWhitespace($priceString);
   }
   elsif ($title =~ /Under/gi)
   {
      # use only the pricesString for the title
      $titleString = "Under Offer ".$documentReader->trimWhitespace($priceString);   
   }
   else
   {
      # use only the pricesString for the title
      $titleString = $priceString;
   }
   
   if ($titleString) 
   {
      $propertyProfile{'TitleString'} = $documentReader->trimWhitespace($titleString);
   }
   
   # --- extract suburb name --- 
   $htmlSyntaxTree->resetSearchConstraints();
   $htmlSyntaxTree->setSearchStartConstraintByTagAndClass('td', 'lstv-suburb');
   $suburb = $htmlSyntaxTree->getNextText();
   
   if ($suburb) 
   {
      $propertyProfile{'SuburbName'} = $documentReader->trimWhitespace($suburb);
   }     
   
   # --- extract address  --- 

   $htmlSyntaxTree->setSearchStartConstraintByTagAndClass('td', 'lstv-address');
   $addressString = $htmlSyntaxTree->getNextText();
   
   if ($addressString) 
   {
      $propertyProfile{'StreetAddress'} = $documentReader->trimWhitespace($addressString);
   }     
   
   
   # --- extract year built --- 
   
   $htmlSyntaxTree->setSearchStartConstraintByTagAndClass('td', 'lstv-featurecolumn');
   $yearBuilt = $htmlSyntaxTree->getNextTextAfterPattern('Year');
   
   if ($yearBuilt) 
   {
      $propertyProfile{'YearBuilt'} = $documentReader->trimWhitespace($yearBuilt);
   }     
  
   # --- extract type --- 
   
   $type = $htmlSyntaxTree->getNextTextAfterPattern('Type');
   
   if ($type) 
   {
      $propertyProfile{'Type'} = $documentReader->trimWhitespace($type);
   }     
   

   # --- extract bedrooms --- 
   
   $bedrooms = $htmlSyntaxTree->getNextTextAfterPattern('Bedrooms');
   
   if ($bedrooms) 
   {
      $propertyProfile{'Bedrooms'} = $documentReader->parseNumber($bedrooms);
   }   
   
   # --- extract bedrooms --- 
   
   $bathrooms = $htmlSyntaxTree->getNextTextAfterPattern('Bathrooms');
   
   if ($bathrooms) 
   {
      $propertyProfile{'Bathrooms'} = $documentReader->parseNumber($bathrooms);
   }   

   # --- extract features ---
   ################*********************##################*****************################****
   
   $htmlSyntaxTree->resetSearchConstraints();
   $htmlSyntaxTree->setSearchStartConstraintByTagAndClass('td', 'lstv-featurehead');
   $htmlSyntaxTree->setSearchStartConstraintByText('Features');
   $htmlSyntaxTree->setSearchEndConstraintByTagAndClass('td', 'lstv-contactcolumn');
   
   $features = "";
   
   # this processing of features is a little coarse - looks for an instance of three non-digit items
   # in a row to identify the start of the feature list
   # ie. the first couple of lines are bedrooms, 2, bathrooms 1, etc...
   # the $extractingFeatures flag is set once the start is found.
   $lastLine = undef;
   $secondLastLine = undef;
   $extractingFeatures = 0;
   while ($thisLine = $htmlSyntaxTree->getNextText())
   {
      #print "this:'$thisLine' (last='$lastLine') (secondLast='$secondLastLine')\n";
      if (!$extractingFeatures)
      {
         # if this line is a number...
         if ($thisLine =~ /\d/g)
         {
            # ignore this line
         }
         else
         {
            # if second last line and last line are non-digits, we're in)
            if (($secondLastLine) && ($lastLine))
            {
               if (($secondLastLine =~ /\D/g) && ($lastLine =~ /\D/g))
               {
                  # found the start of the feature list
                  $extractingFeatures = 1;
                  $features = $secondLastLine.", ".$lastLine.", ".$thisLine;
               }
            }
         }
      }
      else
      {
         # current extracting features - append this line
         
         $features = $features.", ".$thisLine;
      }
      #print "   features=$features\n";
      
      # cycle through the 3 element queue
      $secondLastLine = $lastLine;
      $lastLine = $thisLine;
   }
      
   if ($features)
   {
      $propertyProfile{'Features'} = $documentReader->trimWhitespace($features);
   }
   
      
   # --- extract description ---
   $htmlSyntaxTree->resetSearchConstraints();
   $htmlSyntaxTree->setSearchStartConstraintByTagAndClass('td', 'lstv-descr');
   $htmlSyntaxTree->setSearchEndConstraintByTag('/td');
   
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
     
   # --- extract agent details ---
   
   $htmlSyntaxTree->resetSearchConstraints();
   $htmlSyntaxTree->setSearchStartConstraintByTagAndClass('td', 'lstv-repname');
   $htmlSyntaxTree->setSearchEndConstraintByTag('/td');

   $contactName = $htmlSyntaxTree->getNextText();
   $mobilePhone = $htmlSyntaxTree->getNextText();
   if (!$mobilePhone)
   {
      $mobilePhone = $htmlSyntaxTree->getNextText();  
   }
   if ($contactName) 
   {
      $propertyProfile{'ContactName'} = $documentReader->trimWhitespace($contactName);
   }     
  
   if ($mobilePhone) 
   {
      $propertyProfile{'MobilePhone'} = $documentReader->trimWhitespace($mobilePhone);
   }
   
   # --- extract agency name ---

   $htmlSyntaxTree->resetSearchConstraints();
   $htmlSyntaxTree->setSearchStartConstraintByTagAndClass('td', 'lstv-agencyname');
   $htmlSyntaxTree->setSearchEndConstraintByTag('/td');

   $agencyName = $htmlSyntaxTree->getNextText();
   if ($agencyName) 
   {
      $propertyProfile{'AgencyName'} = $documentReader->trimWhitespace($agencyName);
   }     
     
   # --- extract agency phone number ---

   $htmlSyntaxTree->resetSearchConstraints();
   $htmlSyntaxTree->setSearchStartConstraintByTagAndClass('td', 'lstv-agencyphone');
   $htmlSyntaxTree->setSearchEndConstraintByTag('/td');

   $contactPhone = $htmlSyntaxTree->getNextText();
 
   if ($contactPhone) 
   {
      if ($salesOrRentalFlag == 0)
      {
         $propertyProfile{'SalesPhone'} = $documentReader->trimWhitespace($contactPhone);
      }
      elsif ($salesOrRentalFlag == 1)
      {
          $propertyProfile{'RentalsPhone'} = $documentReader->trimWhitespace($contactPhone);
      }
   }     
   
   # --- extract agency website ---

   $htmlSyntaxTree->resetSearchConstraints();
   $htmlSyntaxTree->setSearchStartConstraintByTagAndClass('td', 'lstv-agencyweb');
   $htmlSyntaxTree->setSearchEndConstraintByTag('/td');

   $website = $htmlSyntaxTree->getNextAnchorContainingPattern("Visit our Website");
   if ($website) 
   {
      $propertyProfile{'Website'} = $documentReader->trimWhitespace($website);
   }     
   
   populatePropertyProfileHash($sqlClient, $documentReader, \%propertyProfile);
   
   #DebugTools::printHash("PropertyProfile", \%propertyProfile);
   
   return \%propertyProfile;  
}


# -------------------------------------------------------------------------------------------------
# extractLegacyREIWAProfile
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
sub extractLegacyREIWAProfile
{
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;
   my $text;
   
   my %propertyProfile;   
   
   # first, locate the pattern that identifies the source of the record as RealEstate.com
   if ($htmlSyntaxTree->containsTextPattern("1st Place ILS"))
   {
      $sourceName = 'REIWA';
   }
   
   if ($sourceName) 
   {
      $propertyProfile{'SourceName'} = $sourceName;
   }
   
   # second, locate the pattern that identifies this as a SALE record or RENT record
   if ($htmlSyntaxTree->containsTextPattern('Rent'))
   {
      $saleOrRentalFlag = 0;
   }
   else
   {
      $saleOrRentalFlag = 1;
   }
   
   $propertyProfile{'SaleOrRentalFlag'} = $saleOrRentalFlag;
   
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
  
   if ($description)
   {
      $propertyProfile{'Description'} = $description;
   }
  
   ($sourceID, $suburb, $priceString) = split(/\-/, $IDSuburbPrice, 3);
   
   if ($sourceID)
   {
      $propertyProfile{'SourceID'} = $documentReader->trimWhitespace($sourceID);
   }
   
   if ($suburb) 
   {
      $propertyProfile{'SuburbName'} = $suburb;
   }
     
   if ($priceString) 
   {
      $propertyProfile{'AdvertisedPriceString'} = $documentReader->trimWhitespace($priceString);
   }
   
   $titleString = $priceString;
   if ($titleString) 
   {
      $propertyProfile{'TitleString'} = $documentReader->trimWhitespace($titleString);
   }
   
   
   # --- set start constraint to the 4th table on the page - this is table
   # --- to the right of the image that contains parameters for the property   
   $htmlSyntaxTree->setSearchConstraintsByTable(3);
   $htmlSyntaxTree->setSearchEndConstraintByTag("table"); # until the next table
   
   $type = $htmlSyntaxTree->getNextText();             # always set
   
   if ($type)
   {
      $propertyProfile{'Type'} = $type;
   }
   
   $bedrooms = $htmlSyntaxTree->getNextTextContainingPattern("Bedrooms");    # sometimes undef     
   if ($bedrooms)
   {
      $propertyProfile{'Bedrooms'} = $documentReader->parseNumber($bedrooms);
   }
   
   $bathrooms = $htmlSyntaxTree->getNextTextContainingPattern("Bath");       # sometimes undef
   if ($bathrooms)
   {
      $propertyProfile{'Bathrooms'} = $documentReader->parseNumber($bathrooms);
   }
   
   $land = $htmlSyntaxTree->getNextTextContainingPattern("sqm");             # sometimes undef
   ($crud, $land) = split(/:/, $land);   
   if ($land)
   {
      $propertyProfile{'LandArea'} = $land;
   }
   
   $yearBuilt = $htmlSyntaxTree->getNextTextContainingPattern("Age:");      # sometimes undef
   ($crud, $yearBuilt) = split(/:/, $yearBuilt);
   
   if ($yearBuilt)
   {
      $propertyProfile{'YearBuilt'} = $yearBuilt;
   }
   
   # --- set the start constraint back to the top of the page and tje "for More info" label
   $htmlSyntaxTree->resetSearchConstraints();
            
   $addressString = $htmlSyntaxTree->getNextTextAfterPattern("Address:");
   
   if ($addressString)
   {
      $propertyProfile{'StreetAddress'} = $addressString;
   }
   
   # --- extract features ---
   $htmlSyntaxTree->setSearchStartConstraintByTag("blockquote");
   $htmlSyntaxTree->setSearchEndConstraintByText("For More Information");
   
   # may be multiple lines - get all text and append it   
     
   $features = "";
   $firstLine = 1;
   while ($nextLine = $htmlSyntaxTree->getNextText())
   {
      if (!$firstLine)
      {
          $features .= ", ";
      }
      else
      {
         $firstLine = 0;
      }
      $features .= $nextLine;
   }
      
   if ($features)
   {
      $propertyProfile{'Features'} = $documentReader->trimWhitespace($features);
   }

   $propertyProfile{'State'} = 'WA';  
   
    # --- set the start constraint back to the top of the page and tje "for More info" label
   $htmlSyntaxTree->resetSearchConstraints();
            
   $contactName = $htmlSyntaxTree->getNextTextAfterPattern("For More Information Contact:");
   $agencyName = $htmlSyntaxTree->getNextText();
   $phoneNumber = $htmlSyntaxTree->getNextText();
   $phoneNumber =~ s/\D//g;        # remove non-digits
   $mobileNumber = $htmlSyntaxTree->getNextText();
   $mobileNumber =~ s/\D//g;       # remove non-digits
   $email = $htmlSyntaxTree->getNextText();
   $website = $htmlSyntaxTree->getNextText();
   
   if ($contactName)
   {
      $propertyProfile{'ContactName'} = $contactName;
   }
   
   if ($agencyName)
   {
      $propertyProfile{'AgencyName'} = $agencyName;
   }
   
   if ($phoneNumber)
   {
      if ($saleOrRentalFlag == 1)
      {
         $propertyProfile{'RentalsPhone'} = $phoneNumber;
      }
      else
      {
         $propertyProfile{'SalesPhone'} = $phoneNumber;
      }
   }
   
   if ($mobileNumber)
   {
      $propertyProfile{'MobilePhone'} = $mobileNumber;
   }
   
   if ($website)
   {
      $propertyProfile{'Website'} = $website;
   }
   
   
   populatePropertyProfileHash($sqlClient, $documentReader, \%propertyProfile);
   DebugTools::printHash("PropertyProfile", \%propertyProfile);
        
   return \%propertyProfile;  
}


# -------------------------------------------------------------------------------------------------
# parseREIWASearchDetails
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
sub parseREIWASearchDetails

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
      
   if ($htmlSyntaxTree->containsTextPattern("Property Details"))
   {
      # --- now extract the property information for this page ---
      # parse the HTML Syntax tree to obtain the advertised sale information
      $propertyProfile = extractREIWAProfile($documentReader, $htmlSyntaxTree, $url, $parentLabel);
      
      # CRITICAL - if the sourceID isn't set, then it's probable that this is an LEGACY REIWA record
      # legacy records are encountered only when rebuilding from achieves - and support for them has
      # to be maintained (for now)
      if ((!$$propertyProfile{'SourceID'}) || (!$$propertyProfile{'SourceName'}))
      {
         $propertyProfile = extractLegacyREIWAProfile($documentReader, $htmlSyntaxTree, $url, $parentLabel);
      }

      if ($sqlClient->connect())
      {		 	 
         # check if the log already contains this checksum - if it does, assume the tuple already exists                  
         if ($advertisedPropertyProfiles->checkIfProfileExists($propertyProfile))
         {
            # this tuple has been previously extracted - it can be dropped
            # record that it was encountered again
            $printLogger->print("   parseSearchDetails: identical record already encountered at ", $$propertyProfile{'SourceName'}, ".\n");
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
# parseREIWASearchList
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
sub parseREIWASearchList

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
   my $sessionProgressTable = $documentReader->getSessionProgressTable();   # 23Jan05
   my $recordsEncountered = 0;
   
   my $sqlClient = $documentReader->getSQLClient();
   my $tablesRef = $documentReader->getTableObjects();
   my $advertisedPropertyProfiles = $$tablesRef{'advertisedPropertyProfiles'};
   my $saleOrRentalFlag = -1;
   my $length = 0;
   
   # --- now extract the property information for this page ---
   $printLogger->print("inParseSearchList ($parentLabel):\n");
   #$htmlSyntaxTree->printText();
   
   # note it's not necessary to report that the suburb is being processed in this function - it
   # was already called in the parseQuery function
   
   if ($htmlSyntaxTree->containsTextPattern("Results"))
   {         
      if ($htmlSyntaxTree->containsTextPattern("Residential Properties For Sale"))
      {
         $saleOrRentalFlag = 0;
      }
      elsif ($htmlSyntaxTree->containsTextPattern("Residential Properties For Rent"))
      {
         $saleOrRentalFlag = 1;
      }
   
      # loop through table data specifying the suburbname until no more properties can be found....
      while ($htmlSyntaxTree->setSearchStartConstraintByTagAndClass('table', 'lstl-container'))
      {
         $suburbName = $htmlSyntaxTree->getNextText(); 
         $nextString = $htmlSyntaxTree->getNextText();
         # if the substring includes the price, append it to the title string 
         if ($nextString =~ /\$/)
         {
            $titleString = $documentReader->trimWhitespace($nextString);
         }
         else
         {
            # instead of the price, there may be an image indicating it's sold or under offer
            # check the title of the next image...
            $tagHash = $htmlSyntaxTree->getNextTagMatchingPattern('img');
            $title = $$tagHash{'title'};
            if ($title =~ /Sold/gi)
            {
               $titleString = "Sold";
            }
            elsif ($title =~ /Under/gi)
            {
               # use only the pricesString for the title
               $titleString = "Under Offer";   
            }
            else
            {
               # use only the pricesString for the title
               $titleString = "";
            }
         }
         $sourceID = $htmlSyntaxTree->getNextTextContainingPattern("Listing No");
         $sourceID =~ s/\D//gi;    # remove non-digits;
         
         if ($sourceID)
         {
            # the page uses javascript to define the URL for each property - we have to implement the same function here
            if ($saleOrRentalFlag == 0)
            {
               $urlString = '../Lst/Lst-ResSale-View.cfm';
            }
            elsif ($saleOrRentalFlag == 1)
            {
               $urlString = '../Lst/Lst-ResRent-View.cfm';
            }
            $sourceURL = $urlString."?Id=$sourceID";
            
            # check if the cache already contains this unique id
            # $_ is a reference to a hash
            if (!$advertisedPropertyProfiles->checkIfResultExists($saleOrRentalFlag, $sourceName, $sourceID, $titleString))                              
            {   
               $printLogger->print("   parseSearchList: adding anchor id ", $sourceID, "...\n");
               #$printLogger->print("   parseSearchList: url=", $sourceURL, "\n");          
               my $httpTransaction = HTTPTransaction::new($sourceURL, $url, $parentLabel.".".$sourceID);                  
          
               push @urlList, $httpTransaction;
            }
            else
            {
               $printLogger->print("   parseSearchList: id ", $sourceID , " in database. Updating last encountered field...\n");
               $advertisedPropertyProfiles->addEncounterRecord($saleOrRentalFlag, $sourceName, $sourceID, undef);
            }
            $recordsEncountered++;  # count records seen
            # save that this suburb has had some progress against it
            $sessionProgressTable->reportProgressAgainstSuburb($threadID, 1);
         }
      }      
      
      $statusTable->addToRecordsEncountered($threadID, $recordsEncountered, $url);
            
      # now get the anchor for the NEXT button if it's defined 
      # this is an image with source 'right_btn'
      $htmlSyntaxTree->resetSearchConstraints();
      $nextButtonListRef = $htmlSyntaxTree->getAnchorsContainingPattern("Next");
               
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
      if ($length > 0)
      {
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
   if ($length > 0)
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
sub parseREIWASearchForm

{	
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;
   my $instanceID = shift;
   my $transactionNo = shift;
   my $threadID = shift;
   my $parentLabel = shift;
   
   # list of REIWA regions and suburbs:
   # this code extracted from: jscript-MainAreaSuburbs-Reset.js
   my @suburbMainAreas = (1, 10, 6, 11, 21, 5, 2, 7, 8, 3, 9, 4, 12);
   
   my @valueList1 = (3302,2169,3303,1871,2182,2179,121,237,3856,225,2180,685,5141,2410,2969,2847,2970,3011,694,3741,3042,226,2181,234,1323,1446,236,120,3012,2412,5061,693,3119,3330,3014,3013,239,3202,3863,692,1650,2170,674,2178,2419,2177,3040,2494,2176,3016,3328,3204,3326,2926,1874,1646,500,501,3325,2928,2983,3203,1649,3665,1875,3026,4201,2418,675,2982,496,684,691,3323,238,2967,3322,688,687,2981,2842,3132,838,3311,3008,3131,3022,3310,3010,2543,3909,3661,2417,3920,2980,2979,3919,3309,3761,1168,2703,2840,3206,227,3307,3306,3018,235,502,497,114,1647,1326,3039,3305,2411,2978,3319,2838,1641,1448,2416,3318,3035,2977,1645,2976,695,4301,3033,3317,2415,697,3032,2975,3030,1644,3232,3316,2837,1327,3681,3948,1872,3944,2414,1447,3315,2973,2972,3314,696,3028,2929,3312,3009,3321,2971,3953,1643,3320,2968,2171,2853,100,2545,3956,2992,106,2959,1449,240,2918,3043,2706,3265,3267,3266,3068,1861,1869,1870,3281,1453,3207,1868,494,2183,1651,3065,3064,649,504,1454,3781,2403,1655,3063,1867,2962,3280,2923,3279,3278,1455,3000,1866,2186,3002,3277,3062,3061,3060,3059,3276,3003,647,3988,3664,230,2310,2546,3234,2400,2999,110,2185,5081,646,3275,2399,2398,2922,698,2190,2187,1865,2547,3289,2998,2997,2996,1316,2189,3235,2708,3286,3142,1320,2921,3285,2457,1452,1864,2995,3284,2188,2396,505,1863,1652,3274,2680,2860,2707,3056,1654,1653,3273,2858,1862,506,3272,3053,242,3666,507,241,2857,104,511,2856,2961,1319,2394,2993,2855,2919,5062,508,3006,2854,3271,2851,3270,1317,3050,1660,699,2963,1451,701,509,3001,2404,3049,3007,700,3048,682,3268,4033,2405,1858,3046,1450,3144,2984,2986,3291,3069,3205,3075,2848,1657,1859,3301,1371,3300,2849,3298,2965,2990,3146,1658,703,1860,512,493,2991,2704,2705,3072,3148,109,2985,2924,1322,3070,3297,2191,515,514,2192,2850,2989,3296,2408,111,3293,705,2987);
   my @valueList10 = (2609,2608,1328,1340,2627,1330,1487,2626,1488,3883,1490,2623,612,3918,611,1499,610,2621,609,608,1494,3927,2620,2619,1498,1335,1497,1496,2618,2616,2615,2612,2610,1475,1484,2646,1345,614,1486,1483,1476,1482,1477,3987,1354,625,622,615,1481,4181,617,2655,1479,621,2654,1350,618,1461,1457,2648,1458,1348,1460,1347,1346,1459,1341,1472,1463,1471,1342,4058,1343,1469,634,1468,1467,1344,1465,2661,631,629);
   my @valueList6 = (81,63,64,80,79,86,77,82,75,72,83,2,3,4,5,8,6,11,12,13,14,15,89,16,17,4836,25,20,98,24,23,99,95,97,96,43,42,91,90,33,32,93,41,92,40,47,50,51,54,88,56);
   my @valueList11 = (2495,3865,3864,2033,2019,2031,2491,2029,2028,2490,2026,4881,2487,3931,2025,2486,2022,2021,2020,2484,2482,1999,2017,2013,2001,2451,2009,2452,3972,3997,3998,2460,2458,2003,2456,4012,2453,1995,1993,2475,2852,4034,1991,2473,2471);
   my @valueList21 = (3887,349,3908,1002,993,3922,1006,3923,991,990,1077,1073,363,3995,1063,1051,4023,361);
   my @valueList5 = (2890,1173,3885,2792,2433,2891,3521,676,2900,707,2899,2897,2895,2791,3535,5185,1314,3928,4737,2893,3185,5182,1182,3527,1514,2790,188,3513,5181,3966,2864,3506,3505,1315,2776,1211,2881,1547,2880,159,5183,2867,171,4738,4798,3483,1205,2879,4010,1202,167,3497,166,165,164,2868,2780,2877,2779,5184,4022,162,2872,1194,1191,4751,2784,2787,2883,2785,176,1197,138,2782,4062,2885,2887,148,3463,4070);
   my @valueList2 = (3859,1615,592,802,3880,1376,1617,1610,3881,3882,3862,602,3884,3889,538,599,934,933,537,3901,805,595,1385,1384,931,2936,1613,3189,4630,534,3934,1382,3939,806,917,3942,1378,2942,540,3951,1611,3801,4081,3964,1368,1364,816,3970,562,819,3994,580,3985,3980,574,2955,3981,4241,3986,3982,4008,3996,570,4009,1362,1622,4020,922,1361,4031,4032,2947,4057,2950,811,549,1370,558,4068,4067);
   my @valueList7 = (433,432,3893,431,430,428,4013,427,4042,4045,423);
   my @valueList8 = (435,436,455,441,438,442,3869,454,453,452,448,445,444,3935,457,461,460,458,459,462,468,467,465,464,479,478,476,4018,474,473,472,480,491,489,440,488,487,486,485,484,483,482,481);
   my @valueList3 = (345,212,708,1390,1109,412,1095,3108,3348,221,1608,1778,417,1744,2793,2560,3618,2070,1106,2799,3870,3246,3425,274,2356,2265,2327,1824,1607,1105,416,2800,2338,1825,1606,3451,313,264,837,2523,2336,2276,1604,3860,3617,273,3350,3223,2361,3360,3352,3877,1391,3861,1811,2529,980,3351,2697,1630,527,3448,311,220,1639,317,1107,346,402,3872,3874,3875,415,3866,1603,717,3878,836,3616,1140,835,3088,1880,2701,902,899,3432,939,3634,2579,4221,2236,2674,3431,3229,3894,2675,3252,2304,528,532,3230,2736,2503,2702,3362,316,2678,1814,1781,310,2569,2334,3384,3632,3254,716,3890,3891,2053,3615,3895,3392,866,1601,2273,3905,3358,3614,834,4786,217,3452,1746,841,943,271,868,3385,897,1102,1442,3916,2269,3633,3912,900,531,2797,942,4652,3357,2502,3087,2724,2050,216,982,983,2830,307,2044,1138,4726,1101,3627,1779,2280,3915,1110,869,3114,1848,1846,2533,1136,3356,3256,215,261,3430,4731,867,2040,941,1113,2677,530,2528,414,413,710,1747,940,2828,3932,222,2733,529,1828,842,2278,2330,1637,3610,524,3609,720,3936,3226,1100,2731,318,2060,3225,4787,1395,911,1437,2232,831,196,2574,323,3630,3933,1097,2306,3629,525,3333,195,3381,1600,3946,2730,978,4653,321,3943,2542,3947,1750,1112,2229,3945,2525,1850,2824,1431,1827,3950,2563,3608,1635,2499,3250,2068,2066,3952,1430,2562,2823,1634,915,1815,1849,830,912,320,1826,2358,1414,197,1760,2582,3636,1404,1775,2751,969,3954,1089,1795,3441,1831,3442,1423,2282,2295,3589,1116,1836,2247,972,3453,207,1124,292,1853,1838,2709,3960,821,3154,822,337,3153,1789,418,1883,2349,1884,3339,1894,1885,1887,4676,3083,2687,1591,3237,947,827,1088,1597,1410,3975,3639,3377,2346,2672,2097,1122,331,206,910,1762,287,3598,245,2688,291,297,893,2592,1125,3989,2245,2087,2286,3241,2262,3395,1121,1803,3217,2591,1840,205,3344,1764,3086,1119,2285,3597,1788,2716,2296,247,2085,1131,2761,1776,3263,3596,3637,3595,249,1890,3974,3594,2515,2348,730,2350,1087,2387,3976,1086,733,2816,2249,1802,2587,1595,1130,3454,340,2284,3999,2248,2263,2513,2516,1841,4004,4001,2772,2541,2537,1629,1889,3216,1888,394,202,1128,1085,2242,2538,3591,2096,4005,288,518,333,4006,2601,2094,909,2240,2673,1785,2093,965,4011,1406,1800,201,391,2807,1592,962,1084,961,2512,2091,519,2686,2767,390,3213,949,4297,3240,2384,1854,2711,1784,2300,1767,908,1405,859,2766,3346,3341,200,3261,2808,1796,1081,3643,2511,3396,2082,283,2811,4789,2756,1573,199,198,1417,2682,2283,4024,956,4790,4618,419,4656,728,2251,2803,4027,2522,1079,2597,3600,2598,4026,2739,4025,2102,521,2723,1792,4035,3084,3092,2378,1127,3398,2381,851,520,3101,4037,3379,952,2105,298,3370,1399,2288,862,3149,721,208,516,3082,3584,4044,1587,1090,1895,2518,3218,3334,3242,2292,3365,2115,2804,3258,324,3081,1586,4049,211,3338,3367,3368,1115,946,1585,2291,3244,2339,1583,945,4048,4741,253,3369,281,2507,2340,3374,4046,1092,974,3401,2373,325,210,2519,3372,1581,3099,1424,3444,2374,3445,4059,722,906,2596,279,3457,3220,3094,905,1093,3336,2260,2109,422,1579,3371,3150,2748,3586,3219,2536,3653,3095,864,326,2805,896);
   my @valueList9 = (1309,1307,1281,1303,1302,1301,1299,1298,1289,1284,1283,1282,1294,1293,1292,1276,1275,1274,4828,1251,1244,1261,1260,1243,1242,4829,1256,1272,1271,1270,1268,1236,1235);
   my @valueList4 = (2151,1932,870,1150,1916,875,779,2326,796,793,792,1928,1147,2225,1146,2224,787,874,873,2222,872,1145,784,1144,1935,1925,1142,2156,2219,3543,1942,773,2153,770,1950,734,2201,2128,744,1968,752,5161,1903,1951,1952,2311,1967,3968,1163,885,2131,2204,1965,740,3559,2212,2316,1912,2210,2209,2143,737,1959,2141,2208,3557,1155,2913,748,3568,2313,2135,2134,1159,887,2914,1970,2200,3564,1972,883,4043,2193,766,1976,763,3407,1983,3581,3577,2197,1980,2196,2911,2321,3578,1979,2195);
   my @valueLust12 = (1741,1739,1740,1706,1705,1700,1699,1698,3879,1697,1738,1713,1712,1711,1710,1709,1732,1731,1729,1723,1719,1716,1694,1693,1692,1691,1687,1686,1685,1682,1681,1680,1662,1668,1665,1664,1663,4028,1669,1670,4055,1671,1674,1675);
   
   my @suburbList1 = ("Alexander Heights","Alfred Cove","Alkimos","Anketell","Applecross","Ardross","Armadale","Ascot","Ashby","Ashfield","Attadale","Atwell","Aubin Grove","Bailup","Balcatta","Baldivis","Balga","Ballajura","Banjup","Banksia Grove","Baskerville","Bassendean","Bateman","Bayswater","Beaconsfield","Beckenham","Bedford","Bedfordale","Beechboro","Beechina","Beejording","Beeliar","Bejoording","Beldon","Belhus","Bellevue","Belmont","Bentley","Bertram","Bibra Lake","Bickley","Bicton","Bindoon","Booragoon","Boya","Brentwood","Brigadoon","Brookdale","Bull Creek","Bullsbrook","Burns Beach","Burswood","Butler","Byford","Calista","Canning Mills","Canning Vale","Cannington","Carabooda","Cardup","Carine","Carlisle","Carmel","Carramar","Casuarina","Caversham","Champion Lakes","Chidlow","Chittering","Churchlands","City Beach","Claremont","Clarence","Clarkson","Cloverdale","Como","Connolly","Coogee","Coolbellup","Coolbinia","Cooloongup","Coondle","Cottesloe","Craigie","Crawley","Culham","Cullacabardee","Currambine","Daglish","Dalkeith","Darch","Darling Downs","Darlington","Dewars Pool","Dianella","Doubleview","Dumbarton","Duncraig","East Cannington","East Fremantle","East Perth","East Rockingham","East Victoria Park","Eden Hill","Edgewater","Eglinton","Ellenbrook","Embleton","Ferndale","Floreat","Forrestdale","Forrestfield","Fremantle","Gidgegannup","Girrawheen","Glen Forrest","Glendalough","Gnangara","Golden Bay","Gooseberry Hill","Gosnells","Greenmount","Greenwood","Guildford","Gwelup","Hacketts Gully","Hamersley","Hamilton Hill","Hammond Park","Hazelmere","Heathridge","Helena Valley","Henderson","Henley Brook","Herdsman","Herne Hill","High Wycombe","Highgate","Hillarys","Hillman","Hilton","Hocking","Hoddys Well","Hope Valley","Hopeland","Hovea","Huntingdale","Iluka","Inglewood","Innaloo","Jandabup","Jandakot","Jane Brook","Jarrahdale","Jindalee","Jolimont","Joondalup","Joondanna","Julimar","Kalamunda","Kallaroo","Karawara","Kardinya","Karnup","Karragullen","Karrakatta","Karrakup","Karrinyup","Kelmscott","Kensington","Kenwick","Kewdale","Keysbrook","Kiara","Kings Park","Kingsley","Kinross","Koondoola","Koongamia","Kwinana","Kwinana Beach","Kwinana Town Centre","Landsdale","Langford","Lathlain","Leda","Leederville","Leeming","Lesmurdie","Lexia","Lockridge","Lower Chittering","Lynwood","Maddington","Madeley","Mahogany Creek","Maida Vale","Malaga","Mandogalup","Manning","Marangaroo","Mardella","Mariginiup","Marmion","Martin","Maylands","Medina","Melville","Menora","Merriwa","Middle Swan","Midland","Midvale","Millendon","Mindarie","Mirrabooka","Mooliabeenee","Moondyne","Morangup","Morley","Mosman Park","Mount Claremont","Mount Hawthorn","Mount Helena","Mount Lawley","Mount Nasura","Mount Pleasant","Mount Richon","Muchea","Mullaloo","Mundaring","Mundaring Weir","Mundijong","Munster","Murdoch","Myaree","Naval Base","Nedlands","Neerabup","Nollamara","Noranda","North Beach","North Fremantle","North Lake","North Perth","Northbridge","Nowergup","Nunile","O'Connor","Oakford","Ocean Reef","Oldbury","Orange Grove","Orelia","Osborne Park","Padbury","Palmyra","Parkerville","Parkwood","Parmelia","Paulls Valley","Pearsall","Peppermint Grove","Peron","Perth","Perth Airport","Pickering Brook","Piesse Brook","Pinjar","Port Kennedy","Postans","Queens Park","Quinns Rocks","Red Hill","Redcliffe","Ridgewood","Riverton","Rivervale","Rockingham","Roleystone","Rossmoyne","Safety Bay","Salter Point","Samson","Sawyers Valley","Scarborough","Secret Harbour","Serpentine","Seville Grove","Shelley","Shenton Park","Shoalwater","Sinagra","Singleton","Sorrento","South Fremantle","South Guildford","South Kalamunda","South Lake","South Perth","Southern River","Spearwood","St James","Stirling","Stoneville","Stratton","Subiaco","Success","Swan View","Swanbourne","Tamala Park","Tapping","The Lakes","The Spectacles","The Vines","Thornlie","Toodyay","Trigg","Tuart Hill","Two Rocks","Upper Swan","Victoria Park","Viveash","Waikiki","Walliston","Wandi","Wangara","Wannamal","Wanneroo","Warnbro","Warwick","Waterford","Watermans Bay","Wattening","Wattle Grove","Wattleup","Wellard","Welshpool","Wembley","Wembley Downs","West Leederville","West Perth","West Swan","West Toodyay","Westfield","Westminster","Whitby","White Gum Valley","Whiteman","Wilbinga","Willagee","Willetton","Wilson","Winthrop","Woodbridge","Woodlands","Woodvale","Wooroloo","Wungong","Yanchep","Yangebup","Yokine");
   my @suburbList10 = ("Ajana","Alma","Beachlands","Beresford","Binnu","Bluff Point","Bootenal","Bowes","Bringo","Burma Road","Cape Burney","Coolcalalaya","Dartmoor","Deepdale","Dindiloa","Drummond Cove","Durawah","East Bowes","East Chapman","East Yuna","Eradu","Eradu South","Eurardy","Galena","Georgina","Geraldton","Glenfield","Greenough","Gregory","Horrocks","Howatharra","Isseka","Kalbarri","Karloo","Kojarena","Lynton","Mahomets Flats","Marrah","Meru","Minnenooka","Moonyoonooka","Moresby","Mount Erin","Mount Hill","Mount Tarcoola","Nabawa","Nanson","Naraling","Narngulu","Narra Tarra","Nolba","Northampton","Northern Gully","Oakajee","Ogilvie","Rangeway","Rockwell","Rudds Gully","Sandsprings","Sandy Gully","South Greenough","Spalding","Strathalbyn","Sunset Beach","Tarcoola Beach","Tibradden","Utakarra","Waggrakine","Walkaway","Wandina","Webberton","West Binnu","West End","Westend","White Peak","Wicherina","Wicherina South","Wonthella","Woorree","Yallabatharra","Yetna","Yuna");
   my @suburbList6 = ("Albany","Bayonet Head","Big Grove","Bornholm","Cape Riche","Centennial Park","Collingwood Heights","Collingwood Park","Cuthbert","Elleker","Emu Point","Frenchman Bay","Gledhow","Gnowellen","Goode Beach","Green Range","Green Valley","Kalgan","King River","Kronkup","Lange","Little Grove","Lockyer","Lower King","Manypeaks","Marbelup","Mckail","Mettler","Middleton Beach","Millbrook","Milpara","Mira Mar","Mount Clarence","Mount Elphinstone","Mount Melville","Nanarup","Napier","Orana","Port Albany","Redmond","Robinson","Seppings","South Stirling","Spencer Park","Springfield","Torbay","Walmsley","Warrenup","Wellstead","Yakamia","Youngs Siding");
   my @suburbList11 = ("Barragup","Birchmont","Blythewood","Bouvard","Clifton","Coodanup","Coolup","Dawesville","Dudley Park","Dwellingup","Erskine","Estuary Park","Etmilyn","Fairbridge","Falcon","Furnissdale","Greenfields","Halls Head","Herron","Holyoake","Inglehope","Lakelands","Madora Bay","Mandurah","Mandurah East","Marrinup","Meadow Springs","Meelon","Myara","Nambeelup","Nirimba","North Dandalup","North Yunderup","Parklands","Pinjarra","Point Grey","Ravenswood","San Remo","Silver Sands","South Yunderup","Stake Hill","Teesdale","Wannanup","West Pinjarra","Yunderup");
   my @suburbList21 = ("Bilingurr","Broome","Cable Beach","Camballin","Cockatoo Island","Dampier Peninsula","Derby","Djugun","Ellendale","Fitzroy Crossing","Koolan","Koolan Island","Lagrange","Minyirr","Mornington","Paradise","Roebuck","Waterbank");
   my @suburbList5 = ("Balla Balla","Bamboo Creek","Baynton","Boodarie","Boolardy","Bulgarra","Cambridge Gulf","Christmas Island","Cleaverville","Cocos (Keeling) Islands","Cooya Pooya","Cossack","Dampier","De Grey","Drysdale River","Durack","Exmouth","Exmouth Gulf","Finucane","Gap Ridge","Gascoyne Junction","Gibb","Goldsworthy","Hall Point","Halls Creek","Indee","Juna Downs","Kalumburu","Kalumburu","Karijini","Karratha","Kununurra","Lake Argyle","Learmonth","Mallina","Marble Bar","Mardie","Mcbeath","Millars Well","Millstream","Mitchell Plateau","Mulataga","Mulga Downs","Mundabullangana","Murchison","Nembudding","Newman","Nickol","North West Cape","Nullagine","Onslow","Oombulgurri","Pannawonica","Paraburdoo","Peedamulla","Pegs Creek","Pippingarra","Point Samson","Port Hedland","Prince Regent River","Redbank","Rocklea","Roebourne","Roy Hill","Shay Gap","Sherlock","South Hedland","Spinifex Hill","Stove Hill","Strelley","Talandji","Telfer","Tom Price","Wallareenya","Wedgefield","Whim Creek","Wickham","Wittenoom","Wyndham","Yannarie");
   my @suburbList2 = ("Allanooka","Arrowsmith","Babbage Island","Badgingarra","Bambun","Beermullah","Bonniefield","Bookara","Boonanarring","Breera","Breton Bay","Brockman","Brown Range","Caraban","Carnamah","Carnarvon","Cataby","Cervantes","Coolimba","Coonabidgee","Coorow","Coral Bay","Cowalla","Cullalla","Dandaragan","Denham","Dongara","East Carnarvon","Eganu","Eneabba","Gabbadah","Gingin","Granville","Green Head","Grey","Greys Plain","Guilderton","Hamelin Pool","Illawong","Inggarda","Irwin","Jurien Bay","Karakin","Kingsford","Lancelin","Ledge Point","Leeman","Lennard Brook","Lyndon","Marchagee","Massey Bay","Mauds Landing","Milo","Mindarra","Minilya","Monkey Mia","Moondah","Morgantown","Mount Horner","Muckenburra","Neergabby","Nilgen","Ningaloo","North Plantations","Orange Springs","Port Denison","Red Gully","Regans Ford","Seabird","South Carnarvon","South Plantations","Useless Loop","Wanerie","Wannoo","Warradarge","Winchester","Woodridge","Wooramel","Yardarino","Yeal");
   my @suburbList7 = ("Bunbury","Carey Park","College Grove","Davenport","East Bunbury","Glen Iris","Pelican Point","South Bunbury","Usher","Vittoria","Withers");
   my @suburbList8 = ("Abba River","Abbey","Acton Park","Ambergate","Anniebrook","Boallia","Bovell","Broadwater","Busselton","Carbunup River","Chapman Hill","Dunsborough","Eagle Bay","Geographe","Hithergreen","Jarrahwood","Jindong","Kalgup","Kaloorup","Kealy","Ludlow","Marybrook","Metricup","Naturaliste","North Jindong","Quedjinup","Quindalup","Reinscourt","Ruabon","Sabina River","Siesta Park","Tutunup","Vasse","Walsall","West Busselton","Wilyabrup","Wonnerup","Yallingup","Yallingup Siding","Yalyalup","Yelverton","Yoganup","Yoongarillup");
   my @suburbList3 = ("Aldersyde","Alexandra Bridge","Allanson","Amelup","Amery","Ardath","Argyle","Arrino","Arthur River","Augusta","Australind","Baandee","Babakin","Badgebup","Badjaling","Bakers Hill","Baladjie","Balbarrup","Balingup","Balkuling","Balladong","Ballaying","Ballidu","Bannister","Barbalin","Barberton","Beacon","Beaufort River","Beela","Beelerup","Belka","Belmunging","Bencubbin","Bendering","Benger","Benjaberring","Benjinup","Beverley","Bilbarin","Billericay","Bimbijy","Bindi Bindi","Binningup","Bobalong","Bodallin","Boddington","Bokal","Bolgart","Bonnie Rock","Boodarockin","Boolading","Boraning","Borden","Borderdale","Boscabel","Boundain","Bow Bridge","Bowelling","Bowgada","Boxwood Hill","Boyanup","Boyerine","Boyup Brook","Bramley","Bremer Bay","Bridgetown","Brookhampton","Brookton","Broomehill","Broomehill East","Broomehill Village","Broomehill West","Bruce Rock","Brunswick","Brunswick Junction","Buckingham","Buckland","Bullaring","Bullfinch","Bullock Hills","Bulyee","Bungulla","Buniche","Bunjil","Bunketch","Buntine","Burakin","Burekup","Burges","Burlong","Burnside","Burracoppin","Burran Rock","Cadoux","Calingiri","Caljie","Campion","Cancanning","Canna","Capel","Capel River","Carani","Carbarup","Carlotta","Caron","Carrabin","Catterick","Chandler","Cherry Tree Pool","Chinocup","Chowerup","Clackline","Cleary","Codjatotine","Cold Harbour","Collanilling","Collie","Collie Burn","Collie Cardiff","Collins Siding","Colreavy","Commodine","Congelin","Contine","Cookernup","Coomberdale","Copley","Cordering","Corinthia","Corrigin","Courtenay","Cowaramup","Cowcowing","Coyrecup","Cranbrook","Crooked Brook","Crossman","Cuballing","Culbin","Cunderdin","Cundinup","Cunjardine","Daadenning Creek","Dalaroo","Dale","Daliak","Dalwallinu","Dalyellup","Dangin","Dardanup","Dardanup West","Darkan","Darradup","Dartnall","Dattening","Deanmill","Deepdene","Denbarker","Denmark","Desmond","Dinninup","Dixvale","Dongolocking","Donnelly River","Donnybrook","Doodenanning","Doodlakine","Dookaling","Doongin","Dowerin","Dryandra","Dudawa","Dudinin","Dukin","Dumberning","Dumbleyung","Duranillin","Dwarda","East Augusta","East Beverley","East Damboring","East Pingelly","East Popanyinning","Eastbrook","Eaton","Ejanding","Elabbin","Elgin","Emu Hill","Erikin","Eujinyn","Ewington","Ewlyamartup","Ferguson","Fitzgerald","Fitzgerald River","Forest Grove","Forest Hill","Forrest Beach","Forrestania","Frankland","Gabalong","Gabbin","Gairdner","Garratt","Gelorup","Ghooli","Gilfillan","Gilgering","Gillingarra","Glen Mervyn","Glencoe","Glenlynn","Glenoran","Glentromie","Gnarabup","Gnowangerup","Goodlands","Goomalling","Goomarin","Gorge Rock","Gracetown","Grass Valley","Greenbushes","Greenhills","Greenwoods Valley","Grimwade","Gutha","Gwambygine","Gwindinup","Hamel","Hamelin Bay","Harrismith","Harvey","Hastings","Hay","Hazelvale","Henty","Hester","Hester Brook","Highbury","Hillman River","Hillside","Hindmarsh","Hines Hill","Hoffman","Holleton","Holt Rock","Hopetoun","Hulongine","Hyden","Inkpen","Irishtown","Jackson","Jacup","Jalbarragup","Jaloran","Jardee","Jarrah Glen","Jelcobine","Jennacubbine","Jennapullin","Jerdacuttup","Jerramungup","Jibberding","Jingalup","Jitarning","Jubuk","Kalannie","Kangaroo Gully","Karlgarin","Karloning","Karranadgin","Karridale","Katanning","Katrine","Kauring","Kebaringup","Kellerberrin","Kendenup","Kentdale","Kingston","Kirup","Kojonup","Kokardine","Kondinin","Kondut","Konnongorring","Koojan","Koolanooka","Koolyanobbing","Koomberkine","Koorda","Korbel","Kordabup","Korrelocking","Kudardup","Kukerin","Kulikup","Kulin","Kulja","Kulyaling","Kundip","Kunjin","Kununoppin","Kurrenkutten","Kweda","Kwelkan","Kwobrup","Kwolyin","Lake Biddy","Lake Brown","Lake Camm","Lake Clifton","Lake Grace","Lake King","Lake Magenta","Lake Margarette","Lake Toolbrunup","Latham","Leschenault","Lime Lake","Linden","Lomos","Lowden","Lumeah","Magitup","Malabaine","Malebelling","Malyalling","Mandiga","Mangowine","Manjimup","Manmanning","Maranup","Margaret River","Marne","Marracoonda","Marradong","Marvel Loch","Mawson","Maya","Mayanup","Mcalinden","Meckering","Meenaar","Merilup","Merkanooka","Merredin","Middlesex","Miling","Minding","Mingenew","Minigin","Minnivale","Mobrup","Mogumber","Mokine","Mollerin","Molloy Island","Moodiarrup","Moojebing","Moonies Hill","Moonijin","Moora","Moorine Rock","Moornaming","Moorumbine","Morawa","Morbinning","Mordalup","Moulyinning","Mount Barker","Mount Caroline","Mount Cooke","Mount Hampton","Mount Hardey","Mount Jackson","Mount Kokeby","Mount Madden","Mount Observation","Mount Palmer","Mount Walker","Mouroubra","Muja","Mukinbudin","Mullalyup","Mullewa","Muluckine","Mumballup","Mungalup","Munglinup","Muntadgin","Muradup","Muresk","Myalup","Nairibin","Nalkain","Nalya","Namban","Nanga Brook","Nangeenan","Nangetty","Nannup","Narembeen","Narkal","Narrakine","Narraloggan","Narrikup","Narrogin","Narrogin Valley","Needilup","Neendaling","New Norcia","Newdegate","Newlands","Nillup","Nippering","Noggerup","Nokaning","Nomans Lake","Noongar","Nornalup","North Baandee","North Bannister","North Boyanup","North Greenbushes","North Kellerberrin","Northam","Northcliffe","Nugadong","Nukarni","Nungarin","Nyabing","Nyamup","Ocean Beach","Old Plains","Ongerup","Orchid Valley","Osmington","Pallinup","Pantapin","Parkfield","Parryville","Paynedale","Peaceful Bay","Peerabeelup","Pemberton","Peppermint Grove Beach","Perenjori","Perillup","Peringillup","Piawaning","Picton","Picton East","Piesseville","Pindar","Pingaring","Pingelly","Pingrup","Pintharuka","Pinwernying","Pithara","Pootenup","Popanyinning","Porongurup","Preston","Preston Beach","Prevelly","Pumphreys Bridge","Quairading","Qualeup","Queenwood","Quellington","Quigup","Quindanning","Quinninup","Ranford","Ravensthorpe","Redgate","Rocky Gully","Roelands","Rosa Brook","Rosa Glen","Rossmore","Rothsay","Round Hill","Schroeder","Scotsdale","Scott River","Scotts Brook","Shackleton","Shadforth","Shotts","South Burracoppin","South Caroling","South Doodlakine","South Kumminin","Southampton","Southern Brook","Southern Cross","Spencers Brook","St Ronans","St Werburghs","Stirling Estate","Strachan","Stratham","Stratherne","Sunnyside","Talbot","Tambellup","Tammin","Tardun","Tarin Rock","Tarwonga","Tenindewa","Tenterden","The Plains","Three Springs","Throssell","Tincurrin","Tingledale","Tone River Mill","Tonebridge","Toolibin","Toompup","Tootra","Townsendale","Trayning","Treesville","Treeton","Trigwell","Tunney","Turkey Hill","Ucarty","Uduc","Upper Capel","Varley","Wadderin","Waddington","Wagerup","Wagin","Walebing","Walgoolan","Walpole","Wamenusking","Wandering","Wandillup","Wansbrough","Warawarrup","Wardering","Warner Glen","Waroona","Warrachuppin","Warralakin","Watercarrin","Waterloo","Waterous","Watheroo","Wedgecarrup","Welbungin","Wellesley","Wellington Mill","West Popanyinning","West River","Westdale","Westonia","Westwood","Wheatley","Wialki","Wickepin","Wilberforce","Wilga","William Bay","Williams","Wilroy","Winnejup","Witchcliffe","Wogarl","Wogolin","Wokalup","Womarden","Wongamine","Wongan Hills","Wongoondy","Woodanilling","Woottating","Worsley","Wubin","Wundowie","Wuraming","Wyalkatchem","Wyening","Wyola","Xantippe","Yabberup","Yalup Brook","Yandanooka","Yanmah","Yarding","Yarloop","Yealering","Yelbeni","Yellanup","Yellowdine","Yerecoin","Yilliminning","York","Yorkrakine","Yornaning","Yornup","Yoting","Youndegin");
   my @suburbList9 = ("Buraminya","Cape Arid","Cape Le Grand","Cascade","Castletown","Chadwick","Condingup","Coomalbidgup","Dalyup","Dowak","East Munglinup","Esperance","Gibson","Ginginup","Grass Patch","Lort River","Malcolm","Merivale","Monjingup","Mount Ney","Myrup","Neridup","North Cascade","Nulsen","Oakley","Pink Lake","Red Lake","Salmon Gums","Scaddan","Shark Lake","Sinclair","West Beach","Wharton");
   my @suburbList4 = ("Abbotts","Agnew","Austin","Balladonia","Bandya","Big Bell","Bonnie Vale","Boogardie","Boorabbin","Bullabulling","Burbanks","Burtville","Caiguna","Callion","Cocklebiddy","Comet Vale","Coolgardie","Cuddingwarra","Cue","Davyhurst","Day Dawn","Dundas","Dunnsville","Eucla","Eulaminna","Euro","Fraser Range","Gabanintha","Goongarrie","Gullewa","Gwalia","Higginsville","Horseshoe","Kambalda","Kathleen","Kintore","Kookynie","Kumarina","Kunanalling","Kurrajong","Kurrawang","Lake Carnegie","Laverton","Lawlers","Leinster","Lennonville","Leonora","Londonderry","Madura","Mainland","Meekatharra","Menzies","Mertondale","Mount Burges","Mount Gibson","Mount Ida","Mount Magnet","Mount Margaret","Mulline","Mulwarrie","Mundiwindi","Mungari","Murrin Murrin","Nannine","Niagara","Noongal","Norseman","Nunngarra","Oldfield","Paynes Find","Paynesville","Peak Hill","Porlell","Princess Royal","Reedy","Sandstone","Sir Samuel","Tampa","Tardie","Teutonic","Tuckanarra","Ularring","Ullarring","Victory Heights","Vivien","Widgiemooltha","Wiluna","Woodarra","Wurarga","Yalgoo","Yarri","Yeelirrie","Yerilla","Youanmi","Yoweragabbie","Yuin","Yundamindera","Yunndaga");
   my @suburbList12 = ("Balagundi","Balgarri","Bardoc","Binduli","Black Flag","Boorara","Boulder","Broad Arrow","Broadwood","Brown Hill","Bulong","Emu Flat","Feysville","Fimiston","Forrest","Gindalbie","Golden Ridge","Gordon","Gudarra","Hannans","Kalgoorlie","Kanowna","Kundana","Kurnalpi","Lakewood","Lamington","Mulgarrie","Mullingar","Mundrabilla","Ora Banda","Parkeston","Piccadilly","Rawlinna","Reid","Siberia","Somerville","South Boulder","South Kalgoorlie","Trafalgar","West Kalgoorlie","West Lamington","Williamstown","Windanya","Zanthus");
   
   my $suburbValueHash = {
      1 =>  \@valueList1,
      10 => \@valueList10,
       6 => \@valueList6,
      11 => \@valueList11,
      21 => \@valueList21,
       5 => \@valueList5,
       2 => \@valueList2,
       7 => \@valueList7,
       8 => \@valueList8,
       3 => \@valueList3,
       9 => \@valueList9,
       4 => \@valueList4,
      12 => \@valueList12,
   };
  
   my $suburbNameHash = {
      1 =>  \@suburbList1,
      10 => \@suburbList10,
       6 => \@suburbList6,
      11 => \@suburbList11,
      21 => \@suburbList21,
       5 => \@suburbList5,
       2 => \@suburbList2,
       7 => \@suburbList7,
       8 => \@suburbList8,
       3 => \@suburbList3,
       9 => \@suburbList9,
       4 => \@suburbList4,
      12 => \@suburbList12,
   };
   
   my $htmlForm;
   my $actionURL;
   my $httpTransaction;
   my @transactionList;
   my $noOfTransactions = 0;
   my $startLetter = $documentReader->getGlobalParameter('startrange');
   my $endLetter =  $documentReader->getGlobalParameter('endrange');
   my $printLogger = $documentReader->getGlobalParameter('printLogger');
   my $sessionProgressTable = $documentReader->getSessionProgressTable();   # 23Jan05
      
   $printLogger->print("in parseSearchForm ($parentLabel)\n");
      
   # get the HTML Form instance
   $htmlForm = $htmlSyntaxTree->getHTMLForm("FormFilter\$");
    
   if ($htmlForm)
   {    
      # override the action for the from (it uses javascript to refine the result)
      $htmlForm->overrideAction($htmlForm->getAction()."?Action=SEARCH");

      # loop through all the hardcoded regions
      foreach (@suburbMainAreas)
      {
         $mainArea = $_;
         $htmlForm->setInputValue('Suburb_MainArea_Id', $mainArea);
      
         # loop through all the suburbs hardcoded for this region
         $valueList = $$suburbValueHash{$mainArea};
         $suburbList = $$suburbNameHash{$mainArea};
         
         $noOfSuburbs = @$valueList;
         
         for ($index = 0; $index < $noOfSuburbs; $index++)
         {
            $acceptSuburb = 0;
            $useThisSuburb = 0;
            $suburbValue = $$valueList[$index];
            $suburbName = $$suburbList[$index];
            
            $useThisSuburb = $sessionProgressTable->isSuburbAcceptable($suburbName);  # 23Jan05
               
            if ($useThisSuburb)
            {
               $htmlForm->setInputValue('Suburb_selected', $suburbValue);
               $htmlForm->setInputValue('Suburb_selected_options', $suburbValue);
               
               # determine if the suburbname is in the specific letter constraint
               $acceptSuburb = isSuburbNameInRange($suburbName, $startLetter, $endLetter);  # 23Jan05
            }
  
            if ($acceptSuburb)
            {         
               
               # 23 Jan 05 - another check - see if the suburb has already been 'completed' in this thread
               # if it has been, then don't do it again (avoids special case where servers may return
               # the same suburb for multiple search variations)
               if (!$sessionProgressTable->hasSuburbBeenProcessed($threadID, $suburbName))
               { 
                  
                  #print "accepted\n";               
                  my $newHTTPTransaction = HTTPTransaction::new($htmlForm, $url, $parentLabel.".".$suburbName);
               
                  # add this new transaction to the list to return for processing
                  $transactionList[$noOfTransactions] = $newHTTPTransaction;
                  $noOfTransactions++;
               }
               else
               {
                  $printLogger->print("   parseSearchForm:suburb ", $suburbName, " previously processed in this thread.  Skipping...\n");
               }
            }
         }
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
# parseREIWADisplayResponse
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
sub parseREIWADisplayResponse

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

