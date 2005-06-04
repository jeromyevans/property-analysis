#!/usr/bin/perl
# 21 April 2005
# Parses the logged HTTP files to extact originatingHTML files - these can be used to rebuild the database later
#
# History:
# 13 March 2005 - disabled use of PropertyTypes table (typeIndex) as it's being re-written to better support 
#  analysis.  It actually performed no role here (the mapPropertyType function returned null in all cases).
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
use DomainRegions;
use Validator_RegExSubstitutes;
use MasterPropertyTable;
use StatusTable;
use SuburbAnalysisTable;
use Time::Local;
use HTMLParser;

# state machine for parsing log files
my $STATE_SEEKING_TRANSACTION_START = 0;
my $STATE_SEEKING_REQUEST_START = 1;
my $STATE_SEEKING_REQUEST_HEADER_END = 2;
my $STATE_SEEKING_REQUEST_END = 3;
my $STATE_SEEKING_RESPONSE_START = 4;
my $STATE_SEEKING_RESPONSE_HEADER_END = 5;
my $STATE_SEEKING_RESPONSE_END = 6;
my @stateNames = ('STATE_SEEKING_TRANSACTION_START',
'STATE_SEEKING_REQUEST_START',
'STATE_SEEKING_REQUEST_HEADER_END',
'STATE_SEEKING_REQUEST_END',
'STATE_SEEKING_RESPONSE_START',
'STATE_SEEKING_RESPONSE_HEADER_END',
'STATE_SEEKING_RESPONSE_END');

my @patternList = ('searchdetails', 'PropertyDetails', 'rsearch?a=o&'); 

# -------------------------------------------------------------------------------------------------    


my $recoveredIdentifier = 0;
my $originatingHTML = OriginatingHTML::new($sqlClient);

my $printLogger = PrintLogger::new($agent, "RecoverOriginatingHTML.stdout", 1, 1, 0);

$printLogger->printHeader("OriginatingHTML Recovery from HTTP Logs\n");
print "Supported patterns:\n";
foreach (@patternList)
{
   print "   $_\n";
}
$sourcePath = param("ip");
$outputPath = param("op");

$originatingHTML->overrideBasePath($outputPath);
$originatingHTML->useFlatPath();

if (($sourcePath) && ($outputPath))
{   
   $recoveredIdentifier = lookupLastIdentifier($printLogger, $outputPath);
   
   $printLogger->print("   starting at identifier $recoveredIdentifier\n");
   
   # read the list of log files...
   $filteredFileList = readLogFileList($printLogger, $sourcePath);
  
   recoverLogFiles($printLogger, $sourcePath, $filteredFileList);
}
else
{
   $printLogger->print("   parseParameters failed: Check parameters\n");
   $printLogger->print("   ip=$sourcePath\n");
   $printLogger->print("   op=$outputPath\n");
}

$printLogger->printFooter("Finished\n");

exit 0;

# -------------------------------------------------------------------------------------------------    
# -------------------------------------------------------------------------------------------------
# recoverLogFiles
# loops through the list of specified files and attempts to run a parser on each logged transaction if a parser
# is defined that matches the transaction's URL
# opens each file and runs a state machine to extract request and response components.  At the end of each
# transaction determines if a parser is defined for it - if there is, extracts the HTML file
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
   my $sourcePath = shift;
   my $filteredFileListRef = shift;
  
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
      $printLogger->print("(", $index+1, " of $totalFiles): $_\n");
          
      # open the recovery file for reading...
      open(RECOVERY_FILE, "<$sourcePath/$_") || print "Can't open file: $!"; 
      
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
         #chomp;
         
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
               
               $transactionEpoch = timelocal($transactionAttributes{'sec'}, $transactionAttributes{'min'}, $transactionAttributes{'hour'}, $transactionAttributes{'mday'}, $transactionAttributes{'mon'}-1, $transactionAttributes{'year'});
               #$printLogger->print(sprintf("   Transaction time: %04d-%02d-%02d %02d:%02d:%02d (%d)", $transactionAttributes{'year'}, $transactionAttributes{'mon'}, $transactionAttributes{'mday'}, $transactionAttributes{'hour'}, $transactionAttributes{'min'}, $transactionAttributes{'sec'}, $transactionEpoch));
              
               
               #print "   processing...\n";
               processRecoveredTransaction(\%transactionAttributes, \@requestHeader, \@responseBody, $transactions);
                           
            }
         }                     

#         print $stateNames[$recoveryState],"\n";     
      }
         
      print "   $transactions found\n";
      close(RECOVERY_FILE); 
      $index++;     
   }
   
}

# -------------------------------------------------------------------------------------------------
# lookupLastIdentifier
# gets the directory listing of outputs files and returns the last file number

# Purpose:
#  database recovery
#
# Parameters:
#  $printLogger
#  string recoveryPath
#  year,month,day,hour,min,sec
#  string agentname
#
# Returns:
#  list of matching log files
#
sub lookupLastIdentifier
{
   my $printLogger = shift;
   my $outputPath = shift;
   
   my $index;
   my $file;
   my @completeFileList;
   
   
   # fetch names of files in the recovery directory
   $printLogger->print("Reading output path...\n");
   opendir(DIR, $outputPath) or die "Can't open $sourcePath: $!";
   
   $index = 0;
   while ( defined ($file = readdir DIR) ) 
   {
      next if $file =~ /^\.\.?$/;     # skip . and ..
      if ($file =~ /\.html$/i)        # is the extension .http...
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
   $printLogger->print("   $index .http files total.\n");
   
   if ($index > 0)
   {
      @completeFileList = sort { $a <=> $b } @completeFileList;
      
      $lastFile = $completeFileList[$#completeFileList];
      ($identifier, $extension) = split /\./, $lastFile;
           
      $identifier++;
   }
   else
   {
      $identifier = 0;
   }
      
   return $identifier;
}


# -------------------------------------------------------------------------------------------------
# readLogFileList
# gets the directory listing of log files and filters filenames based on the recovery time
# and agent name

# Purpose:
#  database recovery
#
# Parameters:
#  $printLogger
#  string recoveryPath
#  year,month,day,hour,min,sec
#  string agentname
#
# Returns:
#  list of matching log files
#
sub readLogFileList
{
   my $printLogger = shift;
   my $sourcePath = shift;
   
   my $index;
   my $file;
   my @completeFileList;
   
   
   # fetch names of files in the recovery directory
   $printLogger->print("Reading source path...\n");
   opendir(DIR, $sourcePath) or die "Can't open $sourcePath: $!";
   
   $index = 0;
   while ( defined ($file = readdir DIR) ) 
   {
      next if $file =~ /^\.\.?$/;     # skip . and ..
      if ($file =~ /\.http$/i)        # is the extension .http...
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
   $printLogger->print("   $index .http files total.\n");
   
   @completeFileList = sort @completeFileList;
   
   return \@completeFileList;
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
   my $transactionAttributesRef = shift;
   my $requestHeaderRef = shift;
   my $responseBodyRef = shift;
   my $transactionNo = shift;

   my $url;
   my $htmlSyntaxTree;
   my $lines;
   my $content;

   #$htmlSyntaxTree = HTMLSyntaxTree->new();
   
   #print "   in ProcessRecoveredTransaction...\n";
   # this is the point to process the transaction
   if ($transactionAttributesRef)
   {
      $transactionEpoch = timelocal($$transactionAttributesRef{'sec'}, $$transactionAttributesRef{'min'}, $$transactionAttributesRef{'hour'}, $$transactionAttributesRef{'mday'}, $$transactionAttributesRef{'mon'}-1, $$transactionAttributesRef{'year'});
      
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
         ## determine if the URL matches a defined parser...
         if (($parserIndex = stringContainsPattern($url, \@patternList)) >= 0)
         {
            
            $lines = @$responseBodyRef;
            
            if ($lines > 8)
            {
               #print "   sourceURL=$url\n";
               #print "   unixtime=$transactionEpoch\n";
               #print "   body lines = $lines\n";
               
               ## a parser is defined.  Need to parse the response body into an html syntax tree
               $content = join '', @$responseBodyRef;
               
               #print "body2:\n";
               #print "$content\n";
               
               # create new OriginatingHTML file in the destination directory...
               # (this is using the new method)
               
               $originatingHTML->saveHTMLContent($recoveredIdentifier, $content, $url, $transactionEpoch);
               $recoveredIdentifier++;
            }            
         }
      }
   }
}
   
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

