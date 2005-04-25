#!/usr/bin/perl
# 19 Apr 05
# Parses the directory of logged OriginatingHTML files and moves the files into sorted directories to reduce
# the time taken to load and parse directory (at the time of writing, all files are in a flat directory and it's 
# now too slow to manage)
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
use WebsiteParser_REIWASales;
use WebsiteParser_DomainSales;
use WebsiteParser_REIWARentals;
use WebsiteParser_REIWASuburbs;
use WebsiteParser_RealEstateSales;
use WebsiteParser_DomainRentals;
use WebsiteParser_RealEstateRentals;
use DomainRegions;
use Validator_RegExSubstitutes;
use MasterPropertyTable;
use StatusTable;
use SuburbAnalysisTable;
use Time::Local;

# -------------------------------------------------------------------------------------------------    

my $SOURCE_NAME = undef;


my $printLogger = PrintLogger::new("", "redistributeHTML.stdout", 1, 1, 0);

$printLogger->printHeader("OriginatingHTML directory reorganisation\n");

my $content;
     
# initialise the objects for communicating with database tables
($sqlClient, $advertisedSaleProfiles, $advertisedRentalProfiles, $propertyTypes, $suburbProfiles, $domainRegions, 
      $originatingHTML, $validator_RegExSubstitutes, $masterPropertyTable) = initialiseTableObjects();
 
my $originatingHTML = OriginatingHTML::new($sqlClient);
      
$sqlClient->connect();          

$sourcePath = param("ip");

if ($sourcePath)
{
   # read the list of log files...
   $filteredFileList = readFileList($printLogger, $sourcePath."/");
   
   foreach (@$filteredFileList)
   {
      # determine which directory this file belongs in...
      $fileName = $_;
      $identifier = $fileName;
      $identifier =~ s/\.html//gi;
      
      # read the source file
      $sourceFileName = "$sourcePath/$fileName";
      print "sourcefile: <$sourceFileName\n";
      open (SESSION_FILE, "<$sourceFileName") or print "Can't open file: $!";
      
      # initialise blank content
      $content = "";
                    
      while (<SESSION_FILE>) # read a line into $_
      {   
         # append to the content
         $content .= $_;
      }
        
      close(SESSION_FILE);
      
      # $content now contains the HTML content...
      
      # create new OriginatingHTML file in the destination directory...
      # (this is using the new method)
      $originatingHTML->saveHTMLContent($identifier, $content, undef, undef);
      
      $targetPath = $originatingHTML->targetPath($identifier);
      $targetFileName = $targetPath."/$identifier.html";
      
      # now - DELETE the original file only if the new file exists
      if (-e $targetFileName)
      {
         print "   $sourceFileName is a candidate for deleting\n";
         unlink ($sourceFileName);
      }
   }
}
else
{
   print "Specify input path:\n";
   print "ip=$sourcePath\n";
}

$sqlClient->disconnect();


$printLogger->printFooter("Finished\n");

exit 0;

# -------------------------------------------------------------------------------------------------
# readFileList
# gets the directory listing of files 
sub readFileList
{
   my $printLogger = shift;
   my $recoveryPath = shift;
   
   my $index;
   my $file;
   my @completeFileList;
   
   # fetch names of files in the recovery directory
   $printLogger->print("Reading OriginatingHTML directory...\n");
   opendir(DIR, $recoveryPath) or die "Can't open $recoveryPath: $!";
   
   $index = 0;
   while ( defined ($file = readdir DIR) ) 
   {
      next if $file =~ /^\.\.?$/;     # skip . and ..
      if ($file =~ /\.html$/i)        # is the extension .html...
      {
         # add this file...
         $completeFileList[$index] = $file;
         $index++;
      }
      else
      {
      }
   }
   closedir(BIN);
   $printLogger->print("   $index .html files total.\n");
   
   return \@completeFileList;
}


# -------------------------------------------------------------------------------------------------    
# -------------------------------------------------------------------------------------------------
# recoverLogFiles
# loops through the list of specified files and attempts to run a parser on each logged transaction if a parser
# is defined that matches the transaction's URL
# opens each file and runs a state machine to extract request and response components.  At the end of each
# transaction determines if a parser is defined for it - if there is, generates an htmlsyntaxtree from the 
# response body and calls the parser.
#
# Purpose:
#  database recovery
#
# Parameters:
#  $printLogger
#  reference to list of file names
#  reference to hash or parsers
#
# Returns:
#  nil
#   
sub recoverLogFiles

{
   my $printLogger = shift;
   my $documentReader = shift;
   my $filteredFileListRef = shift;
   my $parserHashRef = shift;
   my $continueFromLast = shift;
   my $totalFiles;
   my $index;
   my @requestHeader;
   my @requestBody;
   my @responseHeader;
   my @responseBody;
   my %transactionAttributes;
   
   $totalFiles = @$filteredFileListRef;  
   $index = 0;                                
   foreach (@$filteredFileListRef)
   {
      $printLogger->print("(", $index+1, " of $totalFiles): $_");
          
      # open the recovery file for reading...
      open(RECOVERY_FILE, "<$_") || print "Can't open list: $!"; 
      
      @entries = stat(RECOVERY_FILE);
      $size = sprintf("%0.2lf", $entries[7]/(1024*1024));
      $printLogger->print(" (", $size, "Mb)\n");
      
      $transactions= 0;
      $parsedLine = 0;
      
      # clear arrays of lines for each section of the transaction
      @requestHeader = undef;
      @requestBody = undef;
      @responseHeader = undef;
      @responseBody = undef;
      %transactionAttributes = undef;
      
      if ($continueFromLast)
      {
         ($success, $year, $mon, $mday, $hour, $min, $sec) = getRecoveryPoint();
         if ($success)
         {
            $resumeEpoch = timelocal($sec, $min, $hour, $mday, $mon, $year);
            $printLogger->print(sprintf("   Resuming from: %04d-%02d-%02d %02d:%02d:%02d(%d)\n", $year, $mon, $mday, $hour, $min, $sec, $resumeEpoch));
         }
      }
      
      $recoveryState = $STATE_SEEKING_TRANSACTION_START;
      # loop through the content of the file
      while (<RECOVERY_FILE>) # read a line into $_
      {
         if ($parsedLine)
         {         
            # has been set if just changed state
            $lineNo = 0;
            $parsedLine = 0;
         }
         
         # remove end of line marker from $_
         chomp;
         
         # state machine...
         if (($recoveryState == $STATE_SEEKING_TRANSACTION_START) && (!$parsedLine))
         {
            # if the line starts with <transaction then the transaction start has been found
            if (/^<transaction/)
            {
               $recoveryState = $STATE_SEEKING_REQUEST_START;
               $parsedLine = 1;
               $transactions++;
               
               # extract transaction time and instance name from the <transaction> attributes
               %transactionAttributes = HTMLParser::decomposeHTMLTag($_);
            }
         }
         
         if (($recoveryState == $STATE_SEEKING_REQUEST_START) && (!$parsedLine))
         {
            # if the line starts with <transaction then the transaction start has been found
            if (/^<request/)
            {
               $recoveryState = $STATE_SEEKING_REQUEST_HEADER_END;
               $parsedLine = 1;
            }
         }         
         
         if (($recoveryState == $STATE_SEEKING_REQUEST_HEADER_END) && (!$parsedLine))
         {
            # if the line is blank...
            # check if the element is non-blank (contains at least one non-whitespace character)
            # TODO: This needs to be optimised - shouldn't have to do a substitution to 
            # work out if the string contains non-blanks
            $testForNonBlanks = $_;
            $testForNonBlanks =~ s/\s*//g;         
            if (!$testForNonBlanks)
            {
               $recoveryState = $STATE_SEEKING_REQUEST_END;
               $parsedLine = 1;
            }
            else
            {
               # add this line to the header section of the transaction
               $requestHeader[$lineNo] = $_;
               $lineNo++;
            }
         }
         
         if (($recoveryState == $STATE_SEEKING_REQUEST_END) && (!$parsedLine))
         {
            # if the line starts with <transaction then the transaction start has been found
            if (/^<\/request/)
            {
               $recoveryState = $STATE_SEEKING_RESPONSE_START;
               $parsedLine = 1;
            }
            else
            {
               # add this line to the header section of the transaction
               $requestBody[$lineNo] = $_;
               $lineNo++;
            }
         }    

         if (($recoveryState == $STATE_SEEKING_RESPONSE_START) && (!$parsedLine))
         {
            # if the line starts with <transaction then the transaction start has been found
            if (/^<response/)
            {
               $recoveryState = $STATE_SEEKING_RESPONSE_HEADER_END;
               $parsedLine = 1;
            }
         }
         
         if (($recoveryState == $STATE_SEEKING_RESPONSE_HEADER_END) && (!$parsedLine))
         {
            # if the line is blank...
            # check if the element is non-blank (contains at least one non-whitespace character)
            # TODO: This needs to be optimised - shouldn't have to do a substitution to 
            # work out if the string contains non-blanks
            $testForNonBlanks = $_;
            $testForNonBlanks =~ s/\s*//g;         
            if (!$testForNonBlanks)
            {
               $recoveryState = $STATE_SEEKING_RESPONSE_END;
               $parsedLine = 1;
            }
            else
            {
               # add this line to the header section of the transaction
               $responseHeader[$lineNo] = $_;
               $lineNo++;
            }
         }

         if (($recoveryState == $STATE_SEEKING_RESPONSE_END) && (!$parsedLine))
         {
            # if the line starts with <transaction then the transaction start has been found
            if (/^<\/response/)
            {
               $recoveryState = $STATE_SEEKING_TRANSACTION_END;
               $parsedLine = 1;
            }
            else
            {
               # add this line to the header section of the transaction
               $responseBody[$lineNo] = $_;
               $lineNo++;
            }
         }       
         
         if (($recoveryState == $STATE_SEEKING_TRANSACTION_END) && (!$parsedLine))
         {
            # if the line starts with <transaction then the transaction start has been found
            if (/^<\/transaction/)
            {
               $recoveryState = $STATE_SEEKING_TRANSACTION_START;
               $parsedLine = 1;
               
               # this little bit of code is needed to trim the quotes surrounding each of the attribute values
               # returned by HTMLParser::decodeHTMLTag
               foreach (keys %transactionAttributes)
               {
                  $transactionAttributes{$_} =~ s/'//g;
               }
               
               $transactionEpoch = timelocal($transactionAttributes{'sec'}, $transactionAttributes{'min'}, $transactionAttributes{'hour'}, $transactionAttributes{'mday'}, $transactionAttributes{'mon'}, $transactionAttributes{'year'});
                $printLogger->print(sprintf("   Transaction time: %04d-%02d-%02d %02d:%02d:%02d (%d)", $transactionAttributes{'year'}, $transactionAttributes{'mon'}, $transactionAttributes{'mday'}, $transactionAttributes{'hour'}, $transactionAttributes{'min'}, $transactionAttributes{'sec'}, $transactionEpoch));
               if ($transactionEpoch >= $resumeEpoch)
               {
                  print "   processing...\n";
                  processRecoveredTransaction($documentReader, \%transactionAttributes, \@requestHeader, \@responseBody, $parserHashRef, $transactions);
               }
               else
               {
                  print "   skipping\n";
               }
            }
         }                     

#         print $stateNames[$recoveryState],"\n";     
      }
         
      print "   $transactions found\n";
      close(RECOVERY_FILE); 
      $index++;     
   }
   # delete the recovery point file
   unlink("RecoveryPoint.last");
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
    
   my $advertisedRentalProfiles = AdvertisedPropertyProfiles::new($sqlClient, 'Rentals');
   my $advertisedSaleProfiles = AdvertisedPropertyProfiles::new($sqlClient, 'Sales');
   my $propertyTypes = PropertyTypes::new($sqlClient);
   my $suburbProfiles = SuburbProfiles::new($sqlClient);
   my $domainRegions = DomainRegions::new($sqlClient);
   my $originatingHTML = OriginatingHTML::new($sqlClient);
   my $validator_RegExSubstitutes = Validator_RegExSubstitutes::new($sqlClient);
   my $masterPropertyTable = MasterPropertyTable::new($sqlClient);

   return ($sqlClient, $advertisedSaleProfiles, $advertisedRentalProfiles, $propertyTypes, $suburbProfiles, $domainRegions, $originatingHTML, $validator_RegExSubstitutes, $masterPropertyTable);
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

