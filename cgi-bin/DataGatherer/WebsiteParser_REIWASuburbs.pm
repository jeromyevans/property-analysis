#!/usr/bin/perl
# 17 Oct 04 - derived from multiple sources
#  Contains parsers for the REIWA website to obtain suburb profile information
#
#  all parses must accept two parameters:
#   $documentReader
#   $htmlSyntaxTree
#
# The parsers can't access any other global variables, but can use functions in the WebsiteParser_Common module
#
# History:
#  5 December 2004 - adapted to use common AdvertisedPropertyProfiles instead of separate rentals and sales tables
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
use AdvertisedPropertyProfiles;
use AgentStatusServer;
use PropertyTypes;
use WebsiteParser_Common;

@ISA = qw(Exporter);

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# parseREIWASuburbLetters
# extracts the list of anchors to all the pages listing suburbs (alphabetically) from the HTML
#  Syntax Tree
# assumes the HTML Syntax Tree is in a very specific format
#
# Purpose:
#  parsing document text
#
# Parameters:
#  HTMLSyntaxTree to parse
#
# Constraints:
#  nil
#
# Updates:
#  Nil
#
# Returns:
#   array containing the anchors on the page (within particular search constraints)
#      
# for a suburb.A|B|C|D|E|F...|X|Y|Z|SHOW ALL
sub parseREIWASuburbLetters

{
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;
   my $instanceID = shift;
   my $transactionNo = shift;
   my $threadID = shift;
   my $parentLabel = shift;
   my $printLogger = $documentReader->getGlobalParameter('printLogger');
   
   $printLogger->print("parseSuburbLetters($parentLabel))\n");
   if ($htmlSyntaxTree->containsTextPattern("Suburb Profile"))
   {  
              
      # parse the list of suburb letters across the top of the page
      if ($htmlSyntaxTree->setSearchStartConstraintByText("for a suburb."))
      {
         if ($htmlSyntaxTree->setSearchEndConstraintByText("SHOW ALL"))
         {                                         
            # get all anchors in the search constraints               
            if ($anchorsListRef = $htmlSyntaxTree->getAnchors())
            {                    
               $length = @$anchorsListRef;         
               $printLogger->print("   following $length anchors...\n");
            }
            else
            {
               $printLogger->print("   no anchors found!\n");
            }                              
         }
      }            
   }
   
   if ($anchorsListRef)
   {      
      return @$anchorsListRef;
   }
   else
   {
      return @emptyList;
   }
}

# -------------------------------------------------------------------------------------------------
# parseREIWASuburbNames
# extracts the list of suburb names in the current letter category
# assumes the HTML Syntax Tree is in a very specific format
#
# Purpose:
#  parsing document text
#
# Parameters:
#  HTMLSyntaxTree to parse
#
# Constraints:
#  nil
#
# Updates:
#  Nil
#
# Returns:
#   array containing the anchors on the page (within particular search constraints)
#      
sub parseREIWASuburbNames

{
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;
   my $instanceID = shift;
   my $transactionNo = shift;
   my $threadID = shift;
   my $parentLabel = shift;
   my $printLogger = $documentReader->getGlobalParameter('printLogger');
   
   $printLogger->print("parseSuburbNames(($parentLabel))\n");
   if ($htmlSyntaxTree->containsTextPattern("Suburb Profile"))
   {        
      # parse the main suburb anchors of this page
      if ($htmlSyntaxTree->setSearchStartConstraintByText("SHOW ALL"))
      {
         if ($htmlSyntaxTree->setSearchEndConstraintByText("Click here"))
        {        
            # get all anchors in the search constraints               
            if ($anchorsListRef = $htmlSyntaxTree->getAnchors())
            {                    
               $length = @$anchorsListRef;         
               $printLogger->print("   following $length anchors...\n");
            }
            else
            {
               $printLogger->print("   no anchors found!\n");
            }
        }      
      }      
   }
   
   if ($anchorsListRef)
   {      
      return @$anchorsListRef;
   }
   else
   {
      return @emptyList;
   }
}

# -------------------------------------------------------------------------------------------------
# extractREIWASuburbProfile
# extracts suburb information from an HTML Syntax Tree
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
sub extractREIWASuburbProfile
{
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;
   
   my %suburbProfile;   
      
   $htmlSyntaxTree->setSearchStartConstraintByText("SHOW ALL");   
   $htmlSyntaxTree->setSearchEndConstraintByText("Back to top");
      
   $suburbProfile{'suburbName'} = $documentReader->trimWhitespace($htmlSyntaxTree->getNextTextAfterTag("HR"));     
   $suburbProfile{'population'} = $documentReader->parseNumber($htmlSyntaxTree->getNextTextAfterPattern("Population:"));
   $suburbProfile{'medianAge'} = $documentReader->parseNumber($htmlSyntaxTree->getNextTextAfterPattern("Median Age of Residents"));
   $suburbProfile{'percentOver65'} = $documentReader->parseNumber($htmlSyntaxTree->getNextTextAfterPattern("Residents over 65"));
   $suburbProfile{'distanceToGPO'} = $documentReader->parseNumber($htmlSyntaxTree->getNextTextAfterPattern("Distance From Perth"));
      
   $suburbProfile{'noOfHomes'} = $documentReader->parseNumber($htmlSyntaxTree->getNextTextAfterPattern("Not Stated"));
   $suburbProfile{'percentOwned'} = $documentReader->parseNumber($htmlSyntaxTree->getNextText());
   $suburbProfile{'percentMortgaged'} = $documentReader->parseNumber($htmlSyntaxTree->getNextText());
   $suburbProfile{'percentRental'} = $documentReader->parseNumber($htmlSyntaxTree->getNextText());
   $suburbProfile{'percentNotStated'} = $documentReader->parseNumber($htmlSyntaxTree->getNextText());

      
   $suburbProfile{'medianPrice'} =  $documentReader->parseNumber($htmlSyntaxTree->getNextTextAfterPattern("Median House Sale Price"));
   $suburbProfile{'medianPercentChange12Months'} = $documentReader->parseNumber($htmlSyntaxTree->getNextTextAfterPattern("in Last 12 Months:"));
      
   $suburbProfile{'medianPercentChange5Years'} = $documentReader->parseNumber($htmlSyntaxTree->getNextTextAfterPattern("Annual Growth Rate:"));
   $suburbProfile{'highestSale'} = $documentReader->parseNumber($htmlSyntaxTree->getNextTextAfterPattern("Highest House"));
   $suburbProfile{'medianWeeklyRent'} = $documentReader->parseNumber($htmlSyntaxTree->getNextTextAfterPattern("Median Weekly Rent:"));
   $suburbProfile{'medianMonthlyLoan'} = $documentReader->parseNumber($htmlSyntaxTree->getNextTextAfterPattern("Monthly Loan Repayment:"));
   $suburbProfile{'medianWeeklyIncome'} = $documentReader->parseNumber($htmlSyntaxTree->getNextTextAfterPattern("Weekly Income:"));
   $suburbProfile{'schools'} = $documentReader->trimWhitespace($htmlSyntaxTree->getNextTextAfterPattern("Local Schools:"));
   $suburbProfile{'shops'} = $documentReader->trimWhitespace($htmlSyntaxTree->getNextTextAfterPattern("Shops:"));
   $suburbProfile{'trains'} = $documentReader->trimWhitespace($htmlSyntaxTree->getNextTextAfterPattern("Train Stations:"));
   $suburbProfile{'buses'} = $documentReader->trimWhitespace($htmlSyntaxTree->getNextTextAfterPattern("Bus Services:"));    
   
   return %suburbProfile;  
}

# -------------------------------------------------------------------------------------------------
# parseREIWASuburbProfilePage
# parses the htmlsyntaxtree to extract suburb information and insert it into the database
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
sub parseREIWASuburbProfilePage

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
   
   my $suburbProfiles = $$tablesRef{'suburbProfiles'};   
   
   my %suburbProfile;
   my $checksum;   
   my $sourceName = $documentReader->getGlobalParameter('source');
   my $printLogger = $documentReader->getGlobalParameter('printLogger');

   
   $printLogger->print("parseSuburbProfilePage($parentLabel)\n");
   # --- now extract the suburb information for this page ---
   if ($htmlSyntaxTree->containsTextPattern("Suburb Profile"))
   {
      
      # parse the HTML Syntax tree to obtain the suburb information
      %suburbProfile = extractREIWASuburbProfile($documentReader, $htmlSyntaxTree, $url);                  
            
      # calculate a checksum for the information - the checksum is used to approximately 
      # identify the uniqueness of the data
      $checksum = $documentReader->calculateChecksum(\%suburbProfile);
             
      #print "checksum=", $checksum, "\n";
            
      if ($sqlClient->connect())
      {                          
         # check if the log already contains this checksum - if it does, assume the tuple already exists                  
         if ($suburbProfiles->checkIfTupleExists($sourceName, $suburbProfile{'suburbName'}, $checksum))
         {
            # this tuple has been previously extracted - it can be dropped
            # record in the log that it was encountered again
            $printLogger->print("   parseSuburbProfile: identical record already encountered at $sourceName.\n");
	         $suburbProfiles->addEncounterRecord($sourceName, $suburbProfile{'suburbName'}, $checksum);            
         }
         else
         {
            $printLogger->print("   parseSuburbProfile: unique checksum/url - adding new record.\n");
            # this tuple has never been extracted before - add it to the database
            $suburbProfiles->addRecord($sourceName, \%suburbProfile, $url, $checksum)            
         }
      }
      else
      {
         $printLogger->print($sqlClient->lastErrorMessage(), "\n");
      }
   }          
   else 
   {
      $printLogger->print("pattern not found\n");
   }
   
   # return an empty list
   return @emptyList;
}

# -------------------------------------------------------------------------------------------------
# parseREIWAHomePage
# parses the htmlsyntaxtree to extract the link to the SuburbProfile
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
sub parseREIWASuburbsHomePage

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
   $printLogger->print("inParseHomePage($parentLabel):\n");
   if ($htmlSyntaxTree->containsTextPattern("Real Estate Institute of Western Australia"))
   {                                     
      $anchor = $htmlSyntaxTree->getNextAnchorContainingPattern("suburb profiles");
      if ($anchor)
      {
         $printLogger->print("   following anchor 'suburb profiles'...\n");
      }
      else
      {
         $printLogger->print("   anchor 'suburb profiles' not found!\n");
      }
   }          
   else 
   {
      $printLogger->print("parseHomePage: pattern not found\n");
   }
   
   # return a list with just the anchor in it
   if ($anchor)
   {
      $httpTransaction = HTTPTransaction::new($anchor, $url, $parentLabel.".suburbs");  
      return ($httpTransaction);
   }
   else
   {
      return @emptyList;
   }
}


# -------------------------------------------------------------------------------------------------

