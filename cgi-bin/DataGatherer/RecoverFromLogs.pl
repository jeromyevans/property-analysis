#!/usr/bin/perl
# 8 Sep 04
# Parses the logged HTTP files to recover a database automatically.
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
#use PropertyTypes;
use HTMLParser;
use Time::Local;

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

# -------------------------------------------------------------------------------------------------    

my $SOURCE_NAME = undef;

($parseSuccess, $recoverySec,$recoveryMin,$recoveryHour,$recoveryDay,$recoveryMonth,$recoveryYear, $agent, $SOURCE_NAME, $continueFromLast) = parseParameters();
   
# 2- generate an instance ID based on current time and a random number.  The instance ID is 
# used in the name of the logfile
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
$year += 1900;
$mon++;
my $randNo = rand 1000;
my $instanceID = sprintf("%s_%4i%02i%02i%02i%02i%02i_%04i", $agent, $year, $mon, $mday, $hour, $min, $sec, $randNo);

my $printLogger = PrintLogger::new($agent, "r_$instanceID.stdout", 1, 1, 0);

$printLogger->printHeader("Database Recovery Tool from HTTP Logs\n");

if ($parseSuccess)
{   
   $printLogger->print(sprintf("RecoveryTime: %04d-%02d-%02d %02d:%02d:%02d\n", $recoveryYear, $recoveryMonth, $recoveryDay, $recoveryHour, $recoveryMin, $recoverySec));
   ($sqlClient, $advertisedSaleProfiles, $advertisedRentalProfiles, $propertyTypes) = initialiseTableObjects();
  
   # enable logging to disk by the SQL client
   #$sqlClient->enableLogging("r_".$instanceID);
   $sqlClient->connect();          

   $advertisedSaleProfiles->createTable();
   $advertisedRentalProfiles->createTable();
  
   $myParsers{"searchdetails"} = \&parseSearchDetails;
   $myTableObjects{'advertisedSaleProfiles'} = $advertisedSaleProfiles;
   $myTableObjects{'advertisedRentalProfiles'} = $advertisedSaleProfiles;
   $myTableObjects{'propertyTypes'} = $propertyTypes;
  
   # read the list of log files...
   @filteredFileList = readLogFileList($printLogger, "d:/projects/changeeffect/propertyanalysis/bin/logs",
                                     $recoveryYear, $recoveryMonth, $recoveryDay, $recoveryHour, $recoveryMin, $recoverySec, $agent);
                              
   # create a stub document reader for the parsers (the parser's don't know the content has been read
   # from a log file rather than via an HTTP request)
  
   my $myDocumentReader = DocumentReader::new($agent, undef, undef, $sqlClient, \%myTableObjects, \%myParsers, $printLogger);
     
   recoverLogFiles($printLogger, $myDocumentReader, \@filteredFileList, \%myParsers, $continueFromLast);
   $sqlClient->disconnect();
}
else
{
   $printLogger->print("   parseParameters failed: Check parameters\n");
   $printLogger->print("   RecoveryDate: year=$recoveryYear mon=$recoveryMonth mday=$recoveryDay\n");
   $printLogger->print("   RecoveryTime: hour=$recoveryHour min=$recoveryMin sec=$recoverySec\n");
   $printLogger->print("   agent=$agent\n");
   $printLogger->print("   source=$SOURCE_NAME\n");
}

$printLogger->printFooter("Finished\n");

exit 0;

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
# saveRecoveryPoint
#  saves to disk the time current attribute (used for restart)
# 
# Purpose:
#  Debugging
#
# Parametrs:
#  integer transactionNo (optional)
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
sub saveRecoveryPoint

{
   my $transactionAttributesRef = shift;
   my $recoveryPointFileName = "RecoveryPoint.last";
   
   open(SESSION_FILE, ">$recoveryPointFileName") || print "Can't open file: $!"; 
     
   $timeStr = sprintf("%04d%02d%02d%02d%02d%02d", $$transactionAttributesRef{'year'}, $$transactionAttributesRef{'mon'}, $$transactionAttributesRef{'mday'},
                                                  $$transactionAttributesRef{'hour'}, $$transactionAttributesRef{'min'}, $$transactionAttributesRef{'sec'});
   print SESSION_FILE "$timeStr\n";
   close(SESSION_FILE);      
}

# -------------------------------------------------------------------------------------------------
# getRecoveryPoint
#  loads to disk the time of the last attribute
# 
# Purpose:
#  Debugging
#
# Parametrs:
#  integer transactionNo (optional)
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
sub getRecoveryPoint

{
   my $transactionAttributesRef;
   my $recoveryPointFileName = "RecoveryPoint.last";
   my $success = 0;
   
   open(SESSION_FILE, "<$recoveryPointFileName") || print "Can't open recovery point file: $!\n"; 
   
   $firstLine = <SESSION_FILE>;
   chomp;
   
   close(SESSION_FILE);     
   
   if ($firstLine)
   {
      # decode timestamp into time Stelements
      $year = substr($firstLine, 0, 4);
      $month = substr($firstLine, 4, 2);
      $day = substr($firstLine, 6, 2);
      $hour = substr($firstLine, 8, 2);
      $min = substr($firstLine, 10, 2);
      $sec = substr($firstLine, 12, 2);
      $success = 1;
   }   
   return ($success, $year, $month, $day, $hour, $min, $sec);
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
   my $recoveryPath = shift;
   my $recoveryYear = shift;
   my $recoveryMonth = shift;
   my $recoveryDay = shift;
   my $recoveryHour = shift;
   my $recoveryMin = shift;
   my $recoverySec = shift;
   my $agent = shift;
   
   my $index;
   my $file;
   my @completeFileList;
   my @filteredFileList;
   
   $recoveryEpoch = timelocal($recoverySec, $recoveryMin, $recoveryHour, $recoveryDay, $recoveryMonth, $recoveryYear);
   
   # fetch names of files in the recovery directory
   $printLogger->print("Reading recovery path...\n");
   opendir(DIR, $recoveryPath) or die "Can't open $recoveryPath: $!";
   
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
   
   $printLogger->print("Filtering log files by '$agent' and recovery time...\n");
   $index = 0;
   foreach (@completeFileList)
   {
      # decompose filename into its time component
      # check if this filename contains 14 numbers between underscores and the agent name...
      if ($_ =~ /(($agent)_(\d{14})_)/)
      {
         $filename = $_;
         # extract the timestamp into $timestamp
         $filename =~ s/(($agent)_(\d{14})_)/$timestamp = $3/e;

         # decode timestamp into time elements
         $year = substr($timestamp, 0, 4);
         $month = substr($timestamp, 4, 2);
         $day = substr($timestamp, 6, 2);
         $hour = substr($timestamp, 8, 2);
         $min = substr($timestamp, 10, 2);
         $sec = substr($timestamp, 12, 2);
   
         $fileEpoch = timelocal($sec, $min, $hour, $day, $month, $year);
         # compare the timestamp to the recovery time
         if ($fileEpoch >= $recoveryEpoch)
         {
            # accept this filename - add it to the list
            $filteredFileList[$index] = $recoveryPath."/".$_;
            $index++;
         }
      }
   }
   
   $printLogger->print("   $index matched files\n");
   
   @filteredFileList = sort @filteredFileList;
   
   return @filteredFileList;
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
   
   my $advertisedRentalProfiles = AdvertisedRentalProfiles::new($sqlClient);
   my $advertisedSaleProfiles = AdvertisedSaleProfiles::new($sqlClient);
   my $propertyTypes = PropertyTypes::new($sqlClient);
   
   return ($sqlClient, $advertisedSaleProfiles, $advertisedRentalProfiles, $propertyTypes);
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

sub parseParameters
{   
   my $result = 0;
   
   $sec = param("sec");
   $min = param("min");
   $hour = param("hour");
   $mday = param("mday");
   $mon = param("mon");
   $year = param("year");
   $agent = param("agent");
   $source = param("source");
   $continue = param("continue");
      
   if ((defined $sec) && (defined $min) && (defined $hour) && (defined $mday) && (defined $mon) && (defined $year) && (defined $agent) && (defined $source))
   {
      $result = 1;
   }
   
   return ($result, $sec,$min,$hour,$mday,$mon,$year, $agent, $source, $continue);   
}

# -------------------------------------------------------------------------------------------------

sub foundSearchDetails
{
   
   print "   found search details transaction!\n";
}


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
sub extractSaleProfile
{
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;
   my $text;
   
   my %saleProfile;   
   
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

   $saleProfile{'State'} = $state;
     
   #DebugTools::printHash("SaleProfile", \%saleProfile);
        
   return %saleProfile;  
}

# -------------------------------------------------------------------------------------------------
$PRETTY_PRINT_WORDS = 1;
$PRETTY_PRINT_SENTANCES = 0;
# ------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# validateProfile
# validates the fields in the property record (for correctness)
#
# Purpose:
#  construction of the repositories
#
# Parameters:
#  saleProfile hash

# Updates:
#  database
#
# Returns:
#  validated sale profile
#    
sub validateProfile
{
   my $sqlClient = shift;
   my $profileRef = shift; 
   
   # match the suburb name to a recognised suburb name
   %matchedSuburb = matchSuburbName($sqlClient, $$profileRef{'SuburbName'}, $$profileRef{'State'});
     
   if (%matchedSuburb)
   {
      $$profileRef{'SuburbIndex'} = $matchedSuburb{'SuburbIndex'};
      $$profileRef{'SuburbName'} = $matchedSuburb{'SuburbName'};
   }
   
   # validate property type
#   $$profileRef{'TypeIndex'} = PropertyTypes::mapPropertyType($$profileRef{'Type'});
   
   # validate number of bedrooms
   if (($$profileRef{'Bedrooms'} > 0) || (!defined $$profileRef{'Bedrooms'}))
   {
   }
   else
   {
       delete $$profileRef{'Bedrooms'};
   }

   # validate number of bathrooms
   if (($$profileRef{'Bathrooms'} > 0) || (!defined $$profileRef{'Bathrooms'}))
   {
   }
   else
   {
       delete $$profileRef{'Bathrooms'};
   }
   
   # validate land area
   if (($$profileRef{'Land'} > 0) || (!defined $$profileRef{'Land'}))
   {
   }
   else
   {
       delete $$profileRef{'Land'};
   }
      
   # validate advertised price lower
   if ((($$profileRef{'AdvertisedPriceLower'} > 0)) || (!defined $$profileRef{'AdvertisedPriceLower'}))
   {
   }
   else
   {
       delete $$profileRef{'AdvertisedPriceLower'};
   }
   
   # validate advertised price upper
   if ((($$profileRef{'AdvertisedPriceUpper'} > 0)) || (!defined $$profileRef{'AdvertisedPriceUpper'}))
   {
   }
   else
   {
       delete $$profileRef{'AdvertisedPriceUpper'};
   }
   
   # ---
   # attempt to remove phone numbers and personal details from the description
   #  - a  phone number is 8 to 10 digits.  It may contain zero or more whitespaces between each digit, but nothing else
   $description = $$profileRef{'Description'};
   #if ($description =~ /0(\s*){8,10}/g)
   if ($description =~ /(\d(\s*)){8,10}/g)
   {
      # there is a phone number in the message - delete the entire sentance containing the phone number
      # split into sentances...
      @sentanceList = split /[\.|\?|\!\*]/, $$profileRef{'Description'};
      $index = 0;
      # loop through each sentance looking for the pattern
      foreach (@sentanceList)
      {
         # if this sentance contains a phone number...
         if ($_ =~ /(\d(\s*)){8,10}/g)
         {
            # reject this sentance as it contains the pattern
            $description =~ s/($sentanceList[$index])([\.|\?|\!\*]*)//g;
         }
         $index++;
      }         
   }
   $$profileRef{'Description'} = $description;
   
   # do another parse of the description to remove phone numbers if a sentance couldn't be identified - replace the number with a blank
   $$profileRef{'Description'} =~ s/(\d(\s*)){8,10}//g;
   
   #---
   # now, search the description for information not provided explicitly in the fields - look for landArea in sqm in the text
   if (!defined $$profileRef{'Land'})
   {
      # determine if the description contains 'sqm' or a variation of that
      #  look for 1 or more digits followed by 0 or more spaces then SQM
      if ($$profileRef{'Description'} =~ /\d+(\s*)sqm/i)
      {
         $description = $$profileRef{'Description'};
         # this expression extracts the sqm number out into $2 and assigns it to $landArea 
         # the 'e' modified ensures the second expresion is executed
         $description =~ s/((\d+)(\s*)sqm)/$landArea = sprintf("$2")/ei;         
      } 
      
      if ((defined $landArea) && ($landArea > 0))
      {
         # assign the land area specified in the description
         $$profileRef{'Land'} = $landArea;
      }
   }

   #---
   # now, search the description for information not provided explicitly in the fields - look for bedrooms in the text
   if (!defined $$profileRef{'Bedrooms'})
   {
      
      # determine if the description contains 'sqm' or a variation of that
      #  look for 1 or more digits followed by any space and charcters until bedrooms.  Note that a non-digit or 
      # non alpha character will break the pattern (for example, a comma implies the number may not be associated with bedrooms)
      # this is pretty rough but should work most of the time
      $description = $$_{'Description'};
      if ($description =~ /(\d+)([\w|\s]*)bedroom/i)
      {
         # this expression extracts the bedrooms number out into $1 and assigns it to $bedrooms 
         # the 'e' modified ensures the second expresion is executed
         $description =~ s/(\d+)([\w|\s]*)bedroom/$bedrooms = sprintf("$1")/ei;         
      } 
      
      if ((defined $bedrooms) && ($bedrooms > 0))
      {
         # assign the land area specified in the description
         $$profileRef{'Bedrooms'} = $bedrooms;
      }
   }
   
    #---
   # now, search the description for information not provided explicitly in the fields - look for bathrooms in the text
   if (!defined $$profileRef{'Bathrooms'})
   {      
      #  look for 1 or more digits followed by any space and charcters until bath.  Note that a non-digit or 
      # non alpha character will break the pattern (for example, a comma implies the number may not be associated with bath)
      # this is pretty rough but should work most of the time
      $description = $$_{'Description'};
      if ($description =~ /(\d+)([\w|\s]*)bath/i)
      {
         # this expression extracts the bedrooms number out into $1 and assigns it to $bedrooms 
         # the 'e' modified ensures the second expresion is executed
         $description =~ s/(\d+)([\w|\s]*)bath/$bathrooms = sprintf("$1")/ei;         
      } 
      
      if ((defined $bathrooms) && ($bathrooms > 0))
      {
         # assign the land area specified in the description
         $$profileRef{'Bathrooms'} = $bathrooms;
      }
   }
   
   # format the text using standard conventions to easy comparison later
   $$profileRef{'SuburbName'} = prettyPrint($$profileRef{'SuburbName'}, 1);

   $$profileRef{'StreetNumber'} = prettyPrint($$profileRef{'StreetNumber'}, 1);

   $$profileRef{'Street'} = prettyPrint($$profileRef{'Street'}, 1);

   $$profileRef{'City'} = prettyPrint($$profileRef{'City'}, 1);

   $$profileRef{'Council'} = prettyPrint($$profileRef{'Council'}, 1);
   
   $$profileRef{'Description'} = prettyPrint($$profileRef{'Description'}, 0);

   $$profileRef{'Features'} = prettyPrint($$profileRef{'Features'}, 0);
}


# -------------------------------------------------------------------------------------------------
# change all characters to lowercase except the first character following a full stop, or the first character in the string
# if the allFirstUpper flag is set, then the first letter of all words is changed to uppercase, otherwise only the
# first letter of a sentance is changed to uppercase.
sub prettyPrint

{
   my $inputText = shift;
   my $allFirstUpper = shift;
   my $SEEKING_DOT = 0;
   my $SEEKING_NEXT_ALPHA = 1;
   my $SEEKING_FIRST_ALPHA = 2;
   my $state;
      
   # --- remove leading and trailing whitespace ---
   # substitute trailing whitespace characters with blank
   # s/whitespace from end-of-line/all occurances
   # s/\s*$//g;      
   $inputText =~ s/\s*$//g;

   # substitute leading whitespace characters and leading non-word characters with blank
   # s/whitespace from start-of-line,multiple single characters/blank/all occurances
   #s/^\s*//g;    
   $inputText =~ s/^[\s|\W]*//g; 
   
   # change all to lowercase
   $inputText =~ tr/[A-Z]/[a-z]/;
   
   
   # if the first upper flag has been set then the first alpha character of every word is to be uppercase
   if ($allFirstUpper)
   {
      # this expression works but it seems overly complicated
      # first it uses a substitution to match a single lowercase character at the start of each word (stored in $1)
      # then it evaluates the second expression which returns $1 in uppercase using sprintf
      # the ge modifiers ensure it's performed for every word and instructs the parser to evalutation the expression
     
      $inputText =~ s/(\b[a-z])/sprintf("\U$1")/ge;
      
      # note the above expression isn't perfect because the boundary of a word isn't just whitespace
      # for example, the above expresion would make isn't into Isn'T and i'm into I'M.
      # the expression below corrects for apostraphies.
      $inputText =~ s/(\'[A-Z])/sprintf("\L$1")/ge;
   }
   else
   {
      # --- change first character in a sentance to uppercase ---
      
      # a state machine is used to perform the special processing of the string.  This should be 
      # possible using a regular expression but I couldn't get it to work in every case.  
      # Instead the string is split into a list of characters...
      @charList = split //, $inputText;
   
      # then set the state machine to search for the next alpha character.  It sets this to uppercase
      # then searches for the next alphacharacter following a full-stop and sets that to uppercase, then 
      # repeats the search
      $state = $SEEKING_NEXT_ALPHA;
      $index = 0;
      foreach (@charList)
      {
        
         if ($state == $SEEKING_DOT)
         {
            if ($_ =~ m/[\.|\?|\!]/g)
            {
               $state = $SEEKING_NEXT_ALPHA;
            }
         }
         else
         {
            if ($state == $SEEKING_NEXT_ALPHA)
            {
               if ($_ =~ m/[a-z]/gi)
               {
                  $_ =~ tr/[a-z]/[A-Z]/;
                  $charList[$index] = $_;
                  $state = $SEEKING_DOT;
               }
            }
         }
       
         $index++;
      }
   
      # rejoin the array into a string
      $inputText = join '', @charList;
       
   }
  
   # special cases
   $inputText =~ s/(i\'m)/I\'m/gi;
   $inputText =~ s/(\si\s)/ I /gi;
   $inputText =~ s/(i\'ve)/I\'ve/gi;
   $inputText =~ s/(i\'d)/I\'d/gi;
      
   # remove multiple whitespaces
   $inputText =~ s/\s+/ /g;
   
   return $inputText;
}

# -------------------------------------------------------------------------------------------------

# searches the postcode list for a suburb matching the name specified
sub matchSuburbName
{   
   my $sqlClient = shift;
   my $suburbName = shift;
   my $state = shift;
   my %matchedSuburb;
   
   if (($sqlClient) && ($suburbName))
   {       
      $quotedSuburbName = $sqlClient->quote($suburbName);
      $quotedState = $sqlClient->quote($state);
      $statementText = "SELECT locality, postcode, SuburbIndex FROM AusPostCodes WHERE locality like $quotedSuburbName and state like $quotedState order by postcode limit 1";
            
      @suburbList = $sqlClient->doSQLSelect($statementText);
      
      if ($suburbList[0])
      {
         $matchedSuburb{'SuburbName'} = $suburbList[0]{'locality'};
         $matchedSuburb{'postcode'} = $suburbList[0]{'postcode'};              
         $matchedSuburb{'SuburbIndex'} = $suburbList[0]{'SuburbIndex'};
      }                    
   }   
   return %matchedSuburb;
}  


# -------------------------------------------------------------------------------------------------
# parseSearchDetails
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
sub parseSearchDetails

{	
   my $documentReader = shift;
   my $htmlSyntaxTree = shift;
   my $url = shift;
   my $instanceID = shift;
   my $transactionNo = shift;
   my $currentYear = shift;
   my $currentMonth = shift;
   my $currentDay = shift;
   my $currentHour = shift;
   my $currentMin = shift;
   my $currentSec = shift;
   
   my $sqlClient = $documentReader->getSQLClient();
   my $tablesRef = $documentReader->getTableObjects();
   
   my $advertisedSaleProfiles = $$tablesRef{'advertisedSaleProfiles'};
   
   my %saleProfiles;
   my $checksum;   
   #$printLogger->print("in parseSearchDetails\n");
   
   if ($htmlSyntaxTree->containsTextPattern("Property Details"))
   {
      # --- now extract the property information for this page ---
      #if ($htmlSyntaxTree->containsTextPattern("Suburb Profile"))
      #{                                    
      # parse the HTML Syntax tree to obtain the advertised sale information
      %saleProfiles = extractSaleProfile($documentReader, $htmlSyntaxTree, $url);  
      validateProfile($sqlClient, \%saleProfiles);
               
      # calculate a checksum for the information - the checksum is used to approximately 
      # identify the uniqueness of the data
      $checksum = $documentReader->calculateChecksum(\%saleProfiles);
            
      #$printLogger->print("   parseSearchDetails: extracted checksum = ", $checksum, ". Checking log...\n");
             
      if ($sqlClient->connect())
      {		 	 
         # check if the log already contains this checksum - if it does, assume the tuple already exists                  
         if ($advertisedSaleProfiles->checkIfTupleExists($SOURCE_NAME, $saleProfiles{'SourceID'}, $checksum, $saleProfiles{'AdvertisedPriceLower'}))
         {
            # this tuple has been previously extracted - it can be dropped
            # record that it was encountered again
            $printLogger->print("   parseSearchDetails: identical record already encountered at $SOURCE_NAME.\n");
            
            #**************
            $advertisedSaleProfiles->setDateEntered($currentYear, $currentMonth, $currentDay, $currentHour, $currentMin, $currentSec);
            #**************
            $advertisedSaleProfiles->addEncounterRecord($SOURCE_NAME, $saleProfiles{'SourceID'}, $checksum);
            
         }
         else
         {
            $printLogger->print("   parseSearchDetails: unique checksum/url - adding new record.\n");
            # this tuple has never been extracted before - add it to the database
            
            #**************
            #printf("%04d%02d%02d%02d%02d%02d\n", $currentYear, $currentMonth, $currentDay, $currentHour, $currentMin, $currentSec);
            $advertisedSaleProfiles->setDateEntered($currentYear, $currentMonth, $currentDay, $currentHour, $currentMin, $currentSec);
            #**************
            $advertisedSaleProfiles->addRecord($SOURCE_NAME, \%saleProfiles, $url, $checksum, $instanceID, $transactionNo);         
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
# -------------------------------------------------------------------------------------------------

