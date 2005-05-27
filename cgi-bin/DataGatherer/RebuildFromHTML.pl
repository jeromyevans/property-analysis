#!/usr/bin/perl
# 19 Apr 05
# Parses the directory of logged OriginatingHTML files reconstructs the raw AdvertisedPropertyProfiles table
#
# History:
#
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
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
use WebsiteParser_REIWA;
use WebsiteParser_Domain;
use WebsiteParser_RealEstate;
use DomainRegions;
use Validator_RegExSubstitutes;
use MasterPropertyTable;
use StatusTable;
use SuburbAnalysisTable;
use Time::Local;

# -------------------------------------------------------------------------------------------------    

# -------------------------------------------------------------------------------------------------    

($parseSuccess, %parameters) = parseParameters();

my $printLogger = PrintLogger::new("", "rebuildFromHTML.stdout", 1, 1, 0);
$printLogger->printHeader("Rebuilding AdvertisedPropertyProfiles from OriginatingHTML\n");

if ($parseSuccess)
{
  
   my $content;
        
   # initialise the objects for communicating with database tables
   ($sqlClient, $advertisedPropertyProfiles, $propertyTypes, $suburbProfiles, $domainRegions, 
         $originatingHTML, $validator_RegExSubstitutes, $masterPropertyTable) = initialiseTableObjects();
    
   my $originatingHTML = OriginatingHTML::new($sqlClient);
         
   $sqlClient->connect();          
      
   # hash of table objects - the key's are only significant to the local callback functions   
   $myTableObjects{'advertisedPropertyProfiles'} = $advertisedPropertyProfiles;
   $myTableObjects{'propertyTypes'} = $propertyTypes;
   $myTableObjects{'suburbProfiles'} = $suburbProfiles;
   $myTableObjects{'domainRegions'} = $domainRegions;
   $myTableObjects{'validator_RegExSubstitutes'} = $validator_RegExSubstitutes;
   $myTableObjects{'masterPropertyTable'} = $masterPropertyTable;
   
   # parsed into the parser functions
   $parameters{'printLogger'} = $printLogger;
      
   my %myParsers;
   
   my $myDocumentReader = DocumentReader::new($parameters{'agent'}, $parameters{'instanceID'}, $parameters{'url'}, $sqlClient, 
         \%myTableObjects, \%myParsers, $printLogger, $parameters{'thread'}, \%parameters);
      
   # read the list of log files...   
   
   $printLogger->print("Recursing into OriginatingHTML directory...\n");
  
   recurseDirectory($parameters{"ip"}."/", $printLogger, $advertisedPropertyProfiles, $myDocumentReader, \%parameters, 0);
  
   my $transactionNo = shift;
   $sqlClient->disconnect();
}
else
{
   print "Specify input path:\n";
   print "ip=$sourcePath\n";
}
   

$printLogger->printFooter("Finished\n");

exit 0;
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

sub parseOriginatingHTMLFile
{
   my $path = shift;
   my $sourceFileName = shift;
   my $printLogger = shift;
   my $advertisedPropertyProfiles = shift;
   my $documentReader = shift;
   my $parameters = shift;
   my $transactionNo = shift;
   
   my $htmlSyntaxTree;
   
   my $SEEKING_HEADER = 0;
   my $IN_HEADER = 1;
   my $FINISHED_HEADER = 2;

   my $content;
   my $lineNo;
   my $state;
   
   # read the source file
   $filename = $path.$sourceFileName;
   print "sourcefile: $filename\n";
   open (SESSION_FILE, "<$filename") or print "Can't open file: $!";
   
   # initialise blank content
   $content = "";
   $lineNo = 1;

   $state = $SEEKING_HEADER;
   while (<SESSION_FILE>) # read a line into $_
   {   
      # append to the content
      $content .= $_;
      
      # originating HTML header processing
      if (($lineNo < 10) && ($state != $FINISHED_HEADER))
      {
         $line = $_;
         chomp $line;
         if ($state == $SEEKING_HEADER)
         {
            if ($line =~ /OriginatingHTML/gi)
            {
               $state = $IN_HEADER;
            }
         }
         
         if ($state == $IN_HEADER)
         {
            if ($line =~ /sourceurl=/gi)
            {
               ($label, $sourceurl) = split(/=/, $line, 2);
               $sourceurl =~ s/\'//g;   # remove single quotes
            }
            elsif ($line =~ /localtime=/gi)
            {
               ($label, $timestamp) = split(/=/, $line, 2);
               $timestamp =~ s/\'//g;   # remove single quotes
               $state = $FINISHED_HEADER;
            }
         }
      }
      $lineNo++;
   }
     
   close(SESSION_FILE);
   
   print "   sourceurl = $sourceurl\n";
               
   # $content now contains the HTML content...

   $htmlSyntaxTree = HTMLSyntaxTree->new();   
   $htmlSyntaxTree->parseContent($content);
         
   # identify which parser to use...
   # REIWA...
   if ($htmlSyntaxTree->containsTextPattern("REIWA"))
   {
      # REIWA         
      $printLogger->print("$timestamp (REIWA)\n");
#      $advertisedPropertyProfiles->overrideDateEntered($timestamp);
#      parseREIWASearchDetails($documentReader, $htmlSyntaxTree, $sourceurl, $$parameters{'instanceID'}, $transactionNo, $documentReader->getThreadID(), undef);  
   }
   elsif ($htmlSyntaxTree->containsTextPattern("Domain\.com\.au"))
   {
      # domain
      $printLogger->print("$timestamp (Domain)\n");
#      $advertisedPropertyProfiles->overrideDateEntered($timestamp);
#      parseDomainPropertyDetails($documentReader, $htmlSyntaxTree, $sourceurl, $$parameters{'instanceID'}, $transactionNo, $documentReader->getThreadID(), undef);
   }
   elsif ($htmlSyntaxTree->containsTextPattern("realestate\.com\.au"))
   {
      # RealEstate
      $printLogger->print("$timestamp RealEstate\n");
      $advertisedPropertyProfiles->overrideDateEntered($timestamp);
      parseRealEstateSearchDetails($documentReader, $htmlSyntaxTree, $sourceurl, $$parameters{'instanceID'}, $transactionNo, $documentReader->getThreadID(), undef);
   }
   else
   {
   }
}

# -------------------------------------------------------------------------------------------------
# this function:
#  reads the list of files in the specified directory
#  opens each file and calls a parser on it
#  recurses back into this function in each subdirectory
sub recurseDirectory
{
   my $path = shift;
   my $printLogger = shift;
   my $advertisedPropertyProfiles = shift;
   my $documentReader = shift;
   my $parameters = shift;
   my $transactionNo = shift;
   
   my @listing;
   my @subdirectory;
   print "Entering $path\n";
   opendir(DIR, $path) or die "Can't open $path: $!";
   
   $files = 0;
   $subdirectories = 0;
   while ( defined ($file = readdir DIR) ) 
   {
      next if $file =~ /^\.\.?$/;     # skip . and ..
      if ($file =~ /\.html$/i)        # is the extension .html...
      {
         # add this file...
         $listing[$files] = $file;
         $files++;
      }
      else
      {
         $subdirectory[$subdirectories] = $path.$file;
         $subdirectories++;
      }
   }
   closedir(BIN);
   print "   $files files, $subdirectories subdirectories\n";

   # --- parse the files in this directory ---
   foreach (@listing)
   {
      $sourceFileName = $_;
      parseOriginatingHTMLFile($path."/", $sourceFileName, $printLogger, $advertisedPropertyProfiles, $documentReader, $parameters, $transactionNo);
      $transactionNo++;
   }

   # --- recurse into subdirectories ---
   foreach (@subdirectory)
   {
      @subdirectoryListing = recurseDirectory($_, $printLogger, $advertisedPropertyProfiles, $documentReader, $parameters, $transactionNo);
   }
   return @listing;
}

# -------------------------------------------------------------------------------------------------
# parses any specified command-line parameters

sub parseParameters
{      
   my %parameters;
   my $success = 0;

   $parameters{'ip'} = param('ip');
   
   if ($parameters{'ip'})
   {
      $success = 1;
   }
   # if successfully read the mandatory parameters, now get optional ones...
   if ($success)
   {
      
      $parameters{'agent'} = "RebuildFromHTML";         
      
      # temporary hack so the useText command doesn't have to be explicit
      if (!$parameters{'useHTML'})
      {
         $parameters{'useText'} = 1;
      }
      
      # 25 July 2004 - generate an instance ID based on current time and a random number.  The instance ID is 
      # used in the name of the logfile
      my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
      $year += 1900;
      $mon++;
      my $randNo = rand 1000;
      my $instanceID = sprintf("%s_%4i%02i%02i%02i%02i%02i_%04i", $parameters{'agent'}, $year, $mon, $mday, $hour, $min, $sec, $randNo);
      $parameters{'instanceID'} = $instanceID;
     
   }
   
   return ($success, %parameters);   
}


# -------------------------------------------------------------------------------------------------
# stringContainsPattern
# determines if the specified string contains a pattern from a list. If found, returns the
# index in the pattern list corresponding to the pattern matched, otherwise zero

# Purpose:
#  multi-session processing
#
# Parameters:
#  @sessionURLStacksqlclient to use
#
# Constraints:
#  nil
#
# Updates:
#  nil
#
# Returns:
#  nil
#    
sub stringContainsPattern

{
   my $string = shift;
   my $patternListRef = shift;
   my $index = 0;
   my $found = 0;
   
   # loop through the list of patterns
   foreach (@$patternListRef)
   {
      # check if the string contains the current pattern
      if ($string =~ /$_/gi)
      {
         # pattern matched - break out of the loop 
         $found = 1;
         last;
      }
      else
      {
         $index++;
      }
   }
   
   # return the index of the matching pattern (or -1)
   if ($found)
   {
      return $index;
   }
   else
   {
      return -1;
   }
}

# -------------------------------------------------------------------------------------------------

# for a transaction recovered from the logs, calls the appropriate parser if defined
sub processRecoveredTransaction
{
   my $documentReader = shift;
   my $transactionAttributesRef = shift;
   my $requestHeaderRef = shift;
   my $responseBodyRef = shift;
   my $parserHashRef = shift;
   my $transactionNo = shift;
   my $url;
   my $htmlSyntaxTree;
   my $lines;
   my $content;
   my @parserPatternList = keys %$parserHashRef; 
   $htmlSyntaxTree = HTMLSyntaxTree->new();
   
   #print "   in ProcessRecoveredTransaction...\n";
   # this is the point to process the transaction
   if ($transactionAttributesRef)
   {
      # extract the URL from the REQUEST HEADER to see if there's a parser associated with this webpage
      $url = undef;
      #print "   ProcessRecoveredTransaction:parsing request header...\n";
      foreach (@$requestHeaderRef)
      {
         # determine if this line is the GET or POST command specifying the URL
         # start of line is get or post followed by single white space, then arbitary number of characters
         if ($_ =~ /^(get|post)\s+(.*)/i)
         {
            # perform same operation but extract URL from $2
            $_ =~ s/^(get|post)\s+(.*)/$url=$2/ie;
            last;
         }
      }
      # if a URL was extracted from the request header...
      if ($url)
      {
         # determine if the URL matches a defined parser...
         if (($parserIndex = stringContainsPattern($url, \@parserPatternList)) >= 0)
         {
            $lines = @$responseBodyRef;
            #print "body lines = $lines\n";
            # a parser is defined.  Need to parse the response body into an html syntax tree
            $content = join '', @$responseBodyRef;         
            
            $htmlSyntaxTree->parseContent($content);
            
            saveRecoveryPoint($transactionAttributesRef);
            
            $startTime = time;
            # get the value from the hash with the pattern matching the callback function
            # the value in the hash is a code reference (to the callback function)		            
            my $callbackFunction = $$parserHashRef{$parserPatternList[$parserIndex]};	
            &$callbackFunction($documentReader, $htmlSyntaxTree, $url, $$transactionAttributesRef{'instance'}, $$transactionAttributesRef{'count'},
               $$transactionAttributesRef{'year'}, $$transactionAttributesRef{'mon'}, $$transactionAttributesRef{'mday'},
               $$transactionAttributesRef{'hour'}, $$transactionAttributesRef{'min'}, $$transactionAttributesRef{'sec'});
               
            $endTime = time;
            $runningTime = $endTime - $startTime;
            print "Transaction $transactionNo took $runningTime seconds\n";
            if ($runningTime > 20)
            {
               print "Getting very slow...low memory....halting this instance (should automatically restart)\n";
               exit 1;
            }
         }
      }
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
#  SQL client
#  list of tables
#    
sub initialiseTableObjects
{
   my $sqlClient = SQLClient::new(); 
    
   my $advertisedPropertyProfiles = AdvertisedPropertyProfiles::new($sqlClient);
   my $propertyTypes = PropertyTypes::new($sqlClient);
   my $suburbProfiles = SuburbProfiles::new($sqlClient);
   my $domainRegions = DomainRegions::new($sqlClient);
   my $originatingHTML = OriginatingHTML::new($sqlClient);
   my $validator_RegExSubstitutes = Validator_RegExSubstitutes::new($sqlClient);
   my $masterPropertyTable = MasterPropertyTable::new($sqlClient);

   return ($sqlClient, $advertisedPropertyProfiles, $propertyTypes, $suburbProfiles, $domainRegions, $originatingHTML, $validator_RegExSubstitutes, $masterPropertyTable);
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

