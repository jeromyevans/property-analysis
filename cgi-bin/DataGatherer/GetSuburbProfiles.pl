#!/usr/bin/perl
# 9 Mar 04
# Parses the detailed suburb information to extract fields
#  29 March 2004 - converted to use DocumentReader
#
# 16 May 04 - bugfix wasn't using parameters{'url'} as start URL
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
use LogTable;
#use URI::URL;
use DebugTools;
use DocumentReader;

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
#  
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
      
   if (-e $filename)
   {             
      open(PARAM_FILE, "<$filename") || $printLogger->print("   main: Can't open configuration file: $!"); 
                 
      # loop through the content of the file
      while (<PARAM_FILE>) # read a line into $_
      {
         # remove end of line marker from $_
         chomp;
	      # split on null character
         ($key, $value) = split /=/;	 	 
         $parameters{$key} = $value;                                    
      }
      
      close(PARAM_FILE);
   }      
   
   return %parameters;
}

# -------------------------------------------------------------------------------------------------    
 
my $SOURCE_NAME = "REIWA";
my $useText = 0;
$createTables = 0;
$getSuburbProfiles = 0;
$dropTables = 0;
$continueSession = 0;

my $useHTML = param('html');

($parseSuccess, $createTables, $startSession, $continueSession, $dropTables) = parseParameters();

if (!$useHTML)
{
   $useText = 1;  
}

if (!$agent)
{
   $agent = "GetSuburbProfiles";
}

my $printLogger = PrintLogger::new($agent, $agent.".stdout", 1, $useText, $useHTML);

$printLogger->printHeader("$agent\n");

# load the configuration file
my %parameters = loadConfiguration($agent.".config", $printLogger);

if (!$parameters{'url'})
{
   $printLogger->print("   main: Configuration file not found\n");
}

if (($parseSuccess) && ($parameters{'url'}))
{            
   ($sqlClient, $suburbProfiles) = initialiseTableObjects();
   # hash of table objects - the key's are only significant to the local callback functions
 
   $myTableObjects{'suburbProfiles'} = $suburbProfiles;     
   
   $myParsers{"content-home"} = \&parseHomePage;
   $myParsers{"content-suburb.cfm"} = \&parseSuburbLetters;
   $myParsers{"content-suburb-letter"} = \&parseSuburbNames;
   $myParsers{"content-suburb-detail"} = \&parseSuburbProfilePage;
   #DebugTools::printHash("myParsers", \%myParsers);
   my $myDocumentReader = DocumentReader::new("getSuburbProfiles", $parameters{'url'}, $sqlClient, 
      \%myTableObjects, \%myParsers, $printLogger);
   
   #$myDocumentReader->setProxy("http://netcache.dsto.defence.gov.au:8080");  
   $myDocumentReader->run($createTables, $startSession, $continueSession, $dropTables);
}
else
{
   $printLogger->print("   main: No action requested\n");
}

$printLogger->printFooter("Finished\n");

# -------------------------------------------------------------------------------------------------
# parseSuburbLetters
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
sub parseSuburbLetters

{
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;
   
   $printLogger->print("parseSuburbLetters()\n");
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
# parseSuburbNames
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
sub parseSuburbNames

{
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;
   
   $printLogger->print("parseSuburbNames()\n");
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
# extractSuburbProfile
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
sub extractSuburbProfile
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

      
   $suburbProfile{'medianPrice'} =  $documentReader->parseNumber($htmlSyntaxTree->getNextTextAfterPattern("Median House Price:"));
   $suburbProfile{'medianPercentChange12Months'} = $documentReader->parseNumber($htmlSyntaxTree->getNextTextAfterPattern("in Last 12 Months:"));
      
   $suburbProfile{'medianPercentChange5Years'} = $documentReader->parseNumber($htmlSyntaxTree->getNextTextAfterPattern("Annual Growth Rate:"));
   $suburbProfile{'highestSale'} = $documentReader->parseNumber($htmlSyntaxTree->getNextTextAfterPattern("Sale Price:"));
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
# parseSuburbProfilePage
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
sub parseSuburbProfilePage

{        
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;
   
   my $sqlClient = $documentReader->getSQLClient();
   my $tablesRef = $documentReader->getTableObjects();
   
   my $suburbProfiles = $$tablesRef{'suburbProfiles'};   
   
   my %suburbProfile;
   my $checksum;   
   
   $printLogger->print("parseSuburbProfilePage()\n");
   # --- now extract the suburb information for this page ---
   if ($htmlSyntaxTree->containsTextPattern("Suburb Profile"))
   {
      
      # parse the HTML Syntax tree to obtain the suburb information
      %suburbProfile = extractSuburbProfile($documentReader, $htmlSyntaxTree, $url);                  
            
      # calculate a checksum for the information - the checksum is used to approximately 
      # identify the uniqueness of the data
      $checksum = $documentReader->calculateChecksum(\%suburbProfile);
             
      #print "checksum=", $checksum, "\n";
            
      if ($sqlClient->connect())
      {                          
         # check if the log already contains this checksum - if it does, assume the tuple already exists                  
         if ($suburbProfiles->checkIfTupleExists($SOURCE_NAME, $suburbProfile{'suburbName'}, $checksum))
         {
            # this tuple has been previously extracted - it can be dropped
            # record in the log that it was encountered again
            $printLogger->print("   parseSuburbProfile: identical record already encountered at $SOURCE_NAME.\n");
	         $suburbProfiles->addEncounterRecord($SOURCE_NAME, $suburbProfile{'suburbName'}, $checksum);            
         }
         else
         {
            $printLogger->print("   parseSuburbProfile: unique checksum/url - adding new record.\n");
            # this tuple has never been extracted before - add it to the database
            $suburbProfiles->addRecord($SOURCE_NAME, \%suburbProfile, $url, $checksum)            
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
# parseHomePage
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
sub parseHomePage

{        
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;         
   my @anchors;
   
   # --- now extract the property information for this page ---
   $printLogger->print("inParseHomePage:\n");
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
      return ($anchor);
   }
   else
   {
      return @emptyList;
   }
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
#  ($sqlClient, $suburbProfiles)
#    
sub initialiseTableObjects
{
   my $sqlClient = SQLClient::new(); 
   my $suburbProfiles = SuburbProfiles::new($sqlClient);
 
   return ($sqlClient, $suburbProfiles);
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

   if (($createTables) || ($startSession) || ($continueSession) || ($dropTables))
   {
      $result = 1;
   }
   
   return ($result, $createTables, $startSession, $continueSession, $dropTables);   
}

