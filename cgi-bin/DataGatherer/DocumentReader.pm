#!/usr/bin/perl
# 28 March 2004
# Jeromy Evans
# Generic Document Reader Framework
# Turn-key solution for fetching and parsing HTML documents
#  assign a callback function to each URL (containing instructions to parse the documents and/or
# return a list of additional URLs to parse) 
# Version 0.2 31 March 2004 - removed concept of 'base' and 'normal' parser.  All normal
# 
# Version 0.21 8 April 2004 - added support for loading frames
#
# Version 0.22 9 April 2004 - added support for POST as well as GET.  Instead of 
#   maintaining a list of URL's to follow, maintains a hash containing Method, URL, 
#    reference to list of key=value pairs to submit (for post) (HTTPTransaction)
#                           - updated the format of the session file so it contains
#   the method and escaped key=value pairs for posting
#                           - updated the way frames are handled so they are all preloaded
#   prior to running the parses.  Had a situation previously where the ordering of URLs
#   would be corrupted by calling a parser for a frame before loading the rest of the
#   frames on the first page    
#              11 April 2004 - added support for referer & user-agent 
#                            - added full HTTP logging                  
#              29 April 2004 - added support for PrintLogger
#              10 July 2004 - added trimWhitespace function
#              15 July 2004 - added parseNumberSomewhereInString function.  This is same as parse number but returns the
#   first number encountered anywhere in the string rather than looking at a particular word offset.
#              25 July 2004 - changed initialisation so when using continue mode, if a session doesn't already exist then 
#   a new session is started
#                           - changed session filename to .session and removed unused first-line status information
#                           - changed logfile name to contain a value representing the instance id (time based identifier).  
#   The instanceID is stored in the database entries for tracking (with the unique transaction ID).  The two values provide
#   an index into the HTTP log.  IMPORTANT CHANGE: instanceID and transactionNo are passed to the parser callback functions.
#                           - added support for transaction number that's used to count the number of documents fetched
#   by the document reader in this instance.  The transaction number is now stored in the database and HTTP log file
#               1 Aug 2004 - fixed bug where multiple instances running concurrently would read and write to the same
#   session file, making them get mixed up and lose track if reading out of order.
#              26 Sep 2004 - added code to detect if the parser is running unusually slow, typically an artefact of 
#   running out of memory.  If this occurs, the transaction stack is saved.  The application then exits with exitcode 1.  
#   This allows the program to be executed in a loop that restarts it if memory isn't being flushed.  Admittedly  a bit 
#   of a hack, but needed to overcome current problem  handling very large number of transactions.  
#                           - When the program starts in continue mode it loads the name of the last instance and copies
#   the old cookie file into the new session's cookie file so the old cookies are loaded.  New ThreadID is used to indicate
#   which instance to continue
#              28 Sep 2004 - Include ThreadID as a parameter - used to continue an earlier session's sessionlog and cookies
#   in a new instance.  Allows multiple instances to run concurrently provided they don't use the same threadID.
#                          - modified run to specify a command to run instead of a list of booleans indicating the command
#                          - modified to accept extra parameters at construction that are passed into the callback functions.  Used
#   to pass global/instance variables into the parsers
#               7 Oct 2004 - constructor of HTTPTransaction changed to accept an HTML form in order to handle complex post
#   parameters better.  This class have been updated to use the new constructor.
#              26 Oct 2004 - added parameter to all parser callbacks specifying the threadID for this instance - it can be used
#   by the parsers to retain state information
#                          - added delete cookies function to start a fresh session
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
package DocumentReader;
require Exporter;

@ISA = qw(Exporter);

use HTTPClient;
use HTMLSyntaxTree;
use SQLClient;
use URI::URL;
use DebugTools;
use HTTPTransaction;
use PrintLogger;
use File::Copy;

my $DEFAULT_USER_AGENT ="Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1)";

my ($printLogger) = undef;

# -------------------------------------------------------------------------------------------------
# new
# contructor for the document reader
#
# Purpose:
#  initialisation of the agent
#
# Parameters:
#  string session name (used for logging)
#  string instance ID (used for logging)
#  string base URL
#  sqlClient - sql client to use
#  tables ref - reference to a list of database tables
#  parser Callback - reference to callback function for parsing main pages
#
# Constraints:
#  nil
#
# Updates:
#  Nil
#
# Returns:
#  DocumentReader object
#    
sub new ($ $ $ $ $ $ $ $ $)
{
   my $sessionName = shift;
   my $instanceID = shift;
   my $baseURL = shift;
   my $sqlClient = shift;   
   my $tablesHashRef = shift;   
   my $parserHashRef = shift;     
   my $localPrintLogger = shift;
   my $threadID = shift;
   my $parametersHashRef = shift;
   
   $printLogger = $localPrintLogger; 
   
   my $documentReader = { 
      sessionName => $sessionName,
      baseURL => $baseURL,
      sqlClient => $sqlClient,      
      tablesHashRef => $tablesHashRef,      
      parserHashRef => $parserHashRef,    
      proxy => undef,
      instanceID => $instanceID,
      transactionNo => 0,
      lowMemoryError => 0,
      threadID => $threadID,
      parametersHashRef => $parametersHashRef,
      httpClient => undef
   };               
   
   bless $documentReader;     
   
   return $documentReader;   # return this
}


# -------------------------------------------------------------------------------------------------
# parseNumber
# extracts a number from the string provided as the first parameter
# second parameter specifies the word number in the string (default is first word)
# (words separated by space)
# automatically strips of the following characters:
#   %, $, comma, ", ', (, ), :, |, ;
# note that it retains '.' (for decimal points)

# Purpose:
#  parsing document text
#
# Parameters:
#  array of bind values for the statement (substitutions)
#  word index - index of number to obtain (first by default)
#
# Constraints:
#  nil
#
# Updates:
#  Nil
#
# Returns:
#   string containing the matching number
#
sub parseNumber
{
   my $this = shift;
   
   my $stringToParse = shift;
   my $wordIndex = shift;

   @words = split (" ", $stringToParse);
  
   $words[$wordIndex] =~ s/,|\$|%|\(|\)|\:|\||\;//g;
  
   return $words[$wordIndex];
}

# -------------------------------------------------------------------------------------------------
# parseNumberSomewhereInString
# extracts a number from the string provided as the first parameter
# returns any number found in any word of the string
# USE THIS FUNCTION WHEN IT'S IMPOSSIBLE TO KNOW WHERE IN THE SENTANCE THE NUMBER SHOULD
# APPEAR (ie. not at a fixed word index)\

# Purpose:
#  parsing document text
#
# Parameters:
#  word to search
#
# Constraints:
#  nil
#
# Updates:
#  Nil
#
# Returns:
#   string containing the number
#
sub parseNumberSomewhereInString
{
   my $this = shift;
   my $stringToParse = shift;
   my $thisNumber = undef;
   my $result = undef;
   
   @words = split(/\s+/, $stringToParse);
   $length = @words;
  
   foreach (@words)
   {
      $thisNumber = $this->strictNumber($_);
      
      if ($thisNumber != '')
      {
         $result = $thisNumber;
         last;
      }
   }
   
   return $result;
}

# -------------------------------------------------------------------------------------------------
# strictNumber
# removes non-numeric characters (except .) from the string

# Purpose:
#  parsing document text
#
# Parameters:
#  string to modify
#
# Constraints:
#  nil
#
# Updates:
#  Nil
#
# Returns:
#   string with non-numeric characters removed
#
sub strictNumber
{
   my $this = shift;
   
   my $stringToParse = shift;

   $stringToParse =~ s/[^0-9.]//gi;
  
   return $stringToParse;
}

# -------------------------------------------------------------------------------------------------

# removes leading and trailing whitespace from parameter
# parameters:
#  string to trim
sub trimWhitespace
{
   my $this = shift;
   my $string = shift;
   
   # --- remove leading and trailing whitespace ---
   # substitute trailing whitespace characters with blank
   # s/whitespace from end-of-line/all occurances
   # s/\s*$//g;      
   $string =~ s/\s*$//g;

   # substitute leading whitespace characters with blank
   # s/whitespace from start-of-line,multiple single characters/blank/all occurances
   #s/^\s*//g;    
   $string =~ s/^\s*//g;

   return $string;     
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# calculateChecksum
# calculates a checksum on a hash as a method to determine if the contents of this hash matches
# another.  Used for the case where only the checksum of the comparison hash is known (rather than
# keeping a complete copy of the original).
#
# Purpose:
#  parsing document text
#
# Parameters:
#  hash to parse (keys and values are all used)
#
# Constraints:
#  nil
#
# Updates:
#  Nil
#
# Returns:
#   a number representing the checksum
#      
sub calculateChecksum
{   
   my $this = shift;
   
   my $inputHashRef = shift;
   my $finalChecksum = 0;
   my $valueChecksum;
   
   while(($key, $value) = each(%$inputHashRef)) 
   {
      # do something with $key and $value
      
      $valueChecksum = 0;
      # calculate 16 bit checksum on the value
      foreach $ascval (unpack("%16C*", $value))
      {
	      $valueChecksum += $ascval;
      }      
      $valueChecksum %= (2 ** 16) - 1;
      
      $keyChecksum = 0;
      # calculate 16 bit checksum on the value
      foreach $ascval (unpack("%16C*", $key))
      {
	      $keyChecksum += $ascval;
      }      
      $keyChecksum %= (2 ** 16) - 1;
                  
      $finalChecksum+=$valueChecksum;
      $finalChecksum+=$keyChecksum;
   }        
   
   return $finalChecksum;
}

# -------------------------------------------------------------------------------------------------
# createTables
# creates all of the database tables
#
# Purpose:
#  construction of the repositories
#
# Uses:
#  sqlClient to use
#  tablesHashRef - hash of objects to execute dropTable on
#
# Constraints:
#  nil
#
# Updates:
#  Nil
#
# Returns:
#  nil
#    
sub _createTables
{   
   my $this = shift;
   my $sqlClient = $this->{'sqlClient'};
   my $tablesHashRef = $this->{'tablesHashRef'};
   my @listOfTables = values %$tablesHashRef;
   
   if ($sqlClient->connect())
   {	      
      foreach (@listOfTables)
      {
	      $_->createTable();
      }      
      
      $sqlClient->disconnect();
   }
   
}

# -------------------------------------------------------------------------------------------------
# dropTables
# drops all of the database tables
#
# Purpose:
#  construction of the repositories
#
# Parameters:
#  sqlclient to use
#  tablesHashRef - hash of objects to execute dropTable on
#
# Constraints:
#  nil
#
# Updates:
#  Nil
#
# Returns:
#  nil
#    
sub _dropTables
{   
   my $this = shift;
   my $sqlClient = $this->{'sqlClient'};
   my $tablesHashRef = $this->{'tablesHashRef'};
   
   my @listOfTables = values %$tablesHashRef; 
   
   if ($sqlClient->connect())
   {	      
      foreach (@listOfTables)
      {
	      $_->dropTable();
      }      
      
      $sqlClient->disconnect();
   }
}

# -------------------------------------------------------------------------------------------------
# loadSessionURLStack
# loads a text file that contains a list of URL's in a stack that are remaining in the 
# current session to be processed
#
# Purpose:
#  multi-session processing
#
# Parameters:
#  (optional) boolean useLast - set to use the last session file
#
# Constraints:
#  nil
#
# Updates:
#  nil
#
# Returns:
#  @sessionURLStack
#    
sub _loadSessionURLStack
{
   my $this = shift;
   my $useLast = shift;
   my @sessionURLstack;
   my $sessionFileName = $this->{'instanceID'}.".session";
   my $index = 0;
   my $httpTransaction;
   
   if ($useLast)
   {
      # 26 Sept 04 - if requested, load last used session file to continue from that one
      $this->recoverLastSession();
   }
   
   if (-e $sessionFileName)
   {       
      open(SESSION_FILE, "<$sessionFileName") || print "Can't open list: $!"; 
         
      # read the first line of the file (session ID and status)
      #$firstLine = <SESSION_FILE>;
      #chomp;
      #($sessionName, $sessionStatus) = split /\0/;
      
      $index = 0;
      # loop through the content of the file
      while (<SESSION_FILE>) # read a line into $_
      {
         # remove end of line marker from $_
         chomp;
	      # split on null character
         ($method, $url, $content) = split /\0/;
	 	 
         $httpTransaction = HTTPTransaction::new($url, undef);  # NOTE: referer is lost (wasn't saved)
         
         if ($content)
         {
            $httpTransaction->setEscapedParameters($content);
         }
         $sessionURLstack[$index] = $httpTransaction;

         $index++;                    
      }
      
      close(SESSION_FILE);
   }   

   $printLogger->print("$index URL's loaded into session stack\n");
   #DebugTools::printList("sessionURLstack", \@sessionURLstack);
   
   return @sessionURLstack;
}
  
# -------------------------------------------------------------------------------------------------
# saveSessionURLStack
# saves a text file that contains a list of URL's in a stack that are remaining in the 
# current session to be processed
#
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
sub _saveSessionURLStack
{
   my $this = shift;
   my $sessionURLstackRef = shift;         
   my $sessionFileName = $this->{'instanceID'}.".session";
   my $length;
   my $url;
   my $method;
              	      
   open(SESSION_FILE, ">$sessionFileName") || print "Can't open list: $!"; 
           
   #print SESSION_FILE "$sessionID\0$sessionStatus\n";
   
   # loop through all of the elements (in reverse so they can be read into a stack)
   foreach (@$sessionURLstackRef)      
   {        
      $url = $_->getURL();
      $method = $_->getMethod();
      $escapedContent = $_->getEscapedParameters();
      print SESSION_FILE "$method\0$url\0$escapedContent\n";        
   }
      
   close(SESSION_FILE);
   
   $length = @$sessionURLstackRef;
      
   $printLogger->print("$length URL's saved in session\n");       
}


# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------  
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
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

# _fetchDocument
# loads a document in accordance with the specified HTTPTransaction

# Purpose:
#  loading a document via HTTP
#
# Parameters:
#  htmlTransaction to use
#  httpclient to use
#  string base URL
#
# Constraints:
#  nil
#
# Updates:
#  nil
#
# Returns:
#  TRUE if the document should be parsed
#  
sub _fetchDocument

{
   my $this = shift;
   my $nextTransaction = shift;
   my $httpClient = shift;
   my $startURL = shift;
   
   my $url;
   my $postParameters;
   my $processResponse = 0;
                        
   if ($nextTransaction->methodIsGet())
   {      
      $url = new URI::URL($nextTransaction->getURL(), $startURL)->abs()->as_string();
      
      ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
      $year += 1900;
      $mon++;      
      
      $displayStr = sprintf("%02d:%02d:%02d  GET: %s\n", $hour, $min, $sec, $url);     
      $printLogger->print($displayStr);     
      
      $httpClient->setReferer($nextTransaction->getReferer());

      
      if ($httpClient->get($url, $this->{'transactionNo'}))
      {
         $processResponse = 1;
      }
      else
      {
         $printLogger->print("failed ", $httpClient->responseCode(), "\n");
      }

      # count the number of transactions performed this instance (this is used in the HTTP log)
      $this->{'transactionNo'}++;
      
      $printLogger->print("HTTP (GET) Response Code: ", $httpClient->responseCode(), "\n");
   }
   else
   {
      if ($nextTransaction->methodIsPost())
      {                                  
         $url = new URI::URL($nextTransaction->getURL(), $startURL)->abs()->as_string();    
         
         ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
         $year += 1900;
         $mon++;      
         
         $displayStr = sprintf("%02d:%02d:%02d POST: %s\n", $hour, $min, $sec, $url);   
         $printLogger->print($displayStr);     
                           
         $escapedParameters = $nextTransaction->getEscapedParameters();
         
         $httpClient->setReferer($nextTransaction->getReferer());                 
               
         if ($httpClient->post($url, $escapedParameters, $this->{'transactionNo'}))
         {
            $processResponse = 1;
         }
         else
         {
            $printLogger->print("failed ", $httpClient->responseCode(), "\n");
         }   
      
         # count the number of transactions performed this instance (this is used in the HTTP log)
         $this->{'transactionNo'}++;
      
         $printLogger->print("HTTP (POST) Response Code: ", $httpClient->responseCode(), "\n");
      }
   }
   
   return $processResponse;
}

# -------------------------------------------------------------------------------------------------

# _parseDocument
# parses a received document, calling local callback's if necessary and
# returns a new list of transactions to process

# Purpose:
#  loading a document via HTTP
#
# Parameters:
#  httpTransaction in progress
#  httpclient to use
#
# Constraints:
#  nil
#
# Updates:
#  nil
#
# Returns:
#  array of Http transactions
#  
sub _parseDocument
{
   my $this = shift;
   my $nextTransaction = shift;
   my $httpClient = shift;
   
   my $content;
   my $htmlSyntaxTree;
   my @frameList;
   my $absoluteURL;
   
   my @newTransactionStack;    
   my $httpTransaction;
       
   my $url;
   my @frameClientList;
   my $frameHTTPclient;
   my $noOfFrames = 0;
   my $inTopFrame = 1; 
   
   my $parserHashRef = $this->{'parserHashRef'};
   # get the list of pattterns for which a parser has been defined      
   my @parserPatternList = keys %$parserHashRef; 
   
   $url = $nextTransaction->getURL();   
   
   $content = $httpClient->getResponseContent();               
   $htmlSyntaxTree = HTMLSyntaxTree->new();   
   $htmlSyntaxTree->parseContent($content);   
   
   # store the top page as the first index in the frame list
   $frameClientList[0] = $httpClient;
   $noOfFrames++;
               
   # this is an opportunity to check if there's a frame to load for this page
   # if there's frames they all need to loaded before continuing processessing
   # to ensure the URL stack order is maintained
   if ($htmlSyntaxTree->containsFrames())           
   {
         
      $printLogger->print("  Loading frames...\n"); 
      @frameList = $htmlSyntaxTree->getFrames();   

      # for each frame, load it's content but don't parse it yet (store content
      # in list)
      foreach (@frameList)
      {
	      $absoluteURL = new URI::URL($_, $url)->abs()->as_string();   
         # create new transaction.  set referer to the base url 
         # 2 Oct 2004 - bugfix to referer
         #$httpTransaction = HTTPTransaction::new($absoluteURL, 'GET', undef, $absoluteURL);
         $httpTransaction = HTTPTransaction::new($absoluteURL, $url);
         
         $frameHTTPClient = HTTPClient::new($this->{'instanceID'});      
         $frameHTTPClient->setProxy($this->{'proxy'});                  
         $frameHTTPClient->setUserAgent($DEFAULT_USER_AGENT);

         if ($this->_fetchDocument($httpTransaction, $frameHTTPClient, $url))
         {
            $frameClientList[$noOfFrames] = $frameHTTPClient;
            $noOfFrames++;
         }		   	                                          
		}                  
   }
         	       
   # parse all of the loaded frames in series (including the top page)
   #   (run callback function to get list of URL's for the session)
   foreach (@frameClientList)
   {  
      $url = $_->getURL();
      #$printLogger->print("parsing document $url\n");
      
      # for the very first element (the top window) don't need to parse
      # the content again - it was done already to determine if there's 
      # any frames
      if (!$inTopFrame)
      {
         $content = $_->getResponseContent();               
         $htmlSyntaxTree = HTMLSyntaxTree->new();   
         $htmlSyntaxTree->parseContent($content);
      }
      else
      {
         # this was the first - clear the flag
         $inTopFrame = 0;
      }   
      
      if (($parserIndex = stringContainsPattern($url, \@parserPatternList)) >= 0)
   	{
	     # print "calling callback #$parserIndex...\n";
	      # 26 September 2004 - measure how long the callback takes to run  
         $startTime = time;
         
	   	# get the value from the hash with the pattern matching the callback function
		   # the value in the cash is a code reference (to the callback function)		            
		   my $callbackFunction = $$parserHashRef{$parserPatternList[$parserIndex]};		  		  
         my @callbackTransactionStack = &$callbackFunction($this, $htmlSyntaxTree, $url, $this->{'instanceID'}, $this->{'transactionNo'}, $this->{'threadID'});
		
         $endTime = time;
         $runningTime = $endTime - $startTime;
         #print "Transaction $transactionNo took $runningTime seconds\n";
         if ($runningTime > 20)
         {
            $printLogger->print("Getting very slow...low memory....halting this instance (should automatically restart)\n");
            $this->{'lowMemoryError'} = 1;
         }
            
         # loop through the transactions in reverse so when they're pushed onto 
         # the stack the order is maintained for popping.
         foreach (reverse @callbackTransactionStack)
         {
            
            # if this is a refence then it's an HTTPTransaction, otherwise
            #  it'ss a URL
            if (ref($_))
            {                        
               $httpTransaction = $_;
            }
            else
            {
               # this is a URL to GET - create a new transaction (use the base URL as referrer)
               $absoluteURL = new URI::URL($_, $url)->abs()->as_string();		               
               $httpTransaction = HTTPTransaction::new($absoluteURL, $url);
            }
                     	                                          
		      push @newTransactionStack, $httpTransaction;                                          
	      }
      }
	}
   
   return @newTransactionStack;
}

# -------------------------------------------------------------------------------------------------
# run
# Main process for the document reader
#
# Purpose:
# running document reader process

# Parameters:
#  bool createTables
#  bool startSession
#  bool continueSession
#  bool dropTables
#
# Constraints:
#  nil
#
# Updates:
#  Nil
#
# Returns:
#  Nil
#    
sub run ( $ )
{
   my $this = shift;
   my $command = shift;
   my $createTables = 0;
   my $startSession = 0;
   my $continueSession = 0;
   my $dropTables = 0;
   
   my $httpClient;
   my $startURL = $this->{'baseURL'};       
   my $parserHashRef = $this->{'parserHashRef'};
   
   my $content;
   my $htmlSyntaxTree;
   
   my $index;
   my $url;
   my $nextURL;
   my @sessionURLStack;
   my @reversedArray;
   my @newTransactionStack;
   my $nextTransaction;
   
   my $maxURLsPerSession;
   my $currentIndex;
   my $urlValid;
   my $parserIndex;
   
   my $httpTransaction;
   my $recoveryCookies = undef;
   my $useRecoveryCookies = 0;
   
    # get the list of pattterns for which a parser has been defined      
   my @parserPatternList = keys %$parserHashRef; 

   # parse the command specified
   if ($command =~ /start/i)
   {
      $startSession = 1;
   }
   else
   {
      if ($command =~ /continue/i)
      {
         $continueSession = 1;
      }
      else
      {
         if ($command =~ /create/i)
         {
            $createTables = 1;
         }
         else
         {
            if ($command =~ /drop/i)
            {
               $dropTables = 1;
            }
         }
      }
   }
   
   if ($createTables)
   {
      $this->_createTables();
   }

   # 25 July 2004 - start a new session in if continue is selected but a session doesn't exist
   if ($continueSession)
   {
      if (defined $this->{'threadID'})
      {
         # the threadID has been specified - continue that thread
         # 26 Sept 04 - attempt to load the last session file and last cookie file for this session
         @sessionURLstack = $this->_loadSessionURLStack(1);
         $this->recoverCookies();
         
         $stackSize = @sessionURLstack;
         if (($stackSize == 0) && ($continueSession))
         {
            # there's no session to continue - start a new session
            $startSession = 1;
         }
      }
   }
   
   if ($startSession)
   {
      # 27 Sept 04 - initialise a new threadID - used for continuing multi-part session
      $this->{'threadID'} = int(rand 128)+1;
      $printLogger->print("--- starting new session - threadID=",$this->{'threadID'}, " ---\n");
   
      $httpClient = HTTPClient::new($this->{'instanceID'});      
      $httpClient->setProxy($this->{'proxy'});
      $httpClient->setUserAgent($DEFAULT_USER_AGENT);
      $this->{'httpClient'} = $httpClient;      
      $nextTransaction = HTTPTransaction::new($startURL, undef);  # no referer - this is first request
      
      if ($this->_fetchDocument($nextTransaction, $httpClient, $startURL))
      {
         @newTransactionStack = $this->_parseDocument($nextTransaction, $httpClient);
               
         foreach (@newTransactionStack)
         {
            push @sessionURLstack, $_;
         }                                          
      }
      
      # save the list in reverse so it can be handled as a stack (pop off one at a time)  
      #@reversedArray = reverse @sessionURLstack;              
      $this->_saveSessionURLStack(\@sessionURLstack);
   
      # start processing off the top of the stack
      $continueSession = 1;
   }
   
   if ($continueSession)
   {   
      $printLogger->print("--- continuing session - threadID=", $this->{'threadID'}, " ---\n");
      # get the URL stack remaining for the session
      @sessionURLstack = $this->_loadSessionURLStack();
      
      $httpClient = HTTPClient::new($this->{'instanceID'});
            
      $httpClient->setProxy($this->{'proxy'});
      $httpClient->setUserAgent($DEFAULT_USER_AGENT);
      $this->{'httpClient'} = $httpClient;   
      
      $maxURLsPerSession = 0;
      $currentIndex = 0;
      $urlValid = 1;
      # 26 Sept 2004 - save the name of the current instance files, used for automatic recovery
      $this->saveRecoverySessionName();

      while ((($currentIndex < $maxURLsPerSession) || ($maxURLsPerSession == 0)) && ($urlValid))
      {  
         $nextTransaction = pop @sessionURLstack;   
         
         # if the next URL is defined...
         if ($nextTransaction)
         {
            if ($this->_fetchDocument($nextTransaction, $httpClient, $startURL))
            {
               @newTransactionStack = $this->_parseDocument($nextTransaction, $httpClient);
               
               foreach (@newTransactionStack)
               {
                  push @sessionURLstack, $_;
               }
               
               # save the status of the session in case it needs to be continued later
               $this->_saveSessionURLStack(\@sessionURLstack);
                  
               # 26 Sept 2004 - If parser took too long, drop out (use for automatic restart after memory flush)
               if ($this->{'lowMemoryError'})
               {
                  # exit and return the thread ID for restart
                  $printLogger->print("end-of-session - exiting with threadID".$this->{'threadID'}."\n");
                  exit $this->{'threadID'};
               }
               
	            $httpClient->back();
            }            
         } 
         else
         {
	         # this URL wasn't defined - could be at end of session            
	         $urlValid = 0;
            $this->_saveSessionURLStack(\@sessionURLstack);       
         }	       

         $currentIndex++;
      }      
      
      if (($currentIndex == $maxURLsPerSession) && ($maxURLsPerSession > 0))
      {
         # 27 Sep 04
         # if the session exits early because of the limit on number of transactions, then exit
         # with an exit code indicating the threadID.
         $this->_saveSessionURLStack(\@sessionURLstack);

         $printLogger->print("end-of-session - exiting with threadID".$this->{'threadID'}."\n");
         # exit and return the thread ID for restart
         exit $this->{'threadID'};  
      }
   
      $this->_saveSessionURLStack(\@sessionURLstack);
      
      # release this threadID - can't be continued as it's finished
      $this->endRecoveryThread();
      $printLogger->print("DocumentReader finished\n");
   }

   if ($dropTables)
   {
      $this->_dropTables();
   }
}

# -------------------------------------------------------------------------------------------------

sub getSQLClient

{
   my $this = shift;
   return $this->{'sqlClient'};
}

# -------------------------------------------------------------------------------------------------

sub setProxy

{
   my $this = shift;
   my $proxy = shift;
   
   $this->{'proxy'} = $proxy;
}

# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# getTableObjects
# returns the hash of table objects specifed when the DocumentReader was instantiated
# this is used by the local callback functions
#
# Purpose:
# accessing database tables in response to document parsing

# Parameters:
#  nil
#
# Updates:
#  Nil
#
# Returns:
#  Hash of table ojects
#    
sub getTableObjects

{
   my $this = shift;
   return $this->{'tablesHashRef'};
}

# -------------------------------------------------------------------------------------------------



# -------------------------------------------------------------------------------------------------
# saveRecoverySessionName
#  saves to disk the name of the file containing the name of this session and threadID - used for automatic restart from this position
# file is saved in the form"
#   theadID=instanceID\n
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
sub saveRecoverySessionName

{
   my $this = shift;
   my $recoveryPointFileName = "RecoverySessionName.last";
   my %threadList;
   
   # load the cookie file name from the recovery file
   open(SESSION_FILE, "<$recoveryPointFileName") || print "Can't open recovery point file: $!\n"; 
  
   $index = 0;
   # loop through the content of the file
   while (<SESSION_FILE>) # read a line into $_
   {
      # remove end of line marker from $_
      chomp;
      # split on null character
      ($threadID, $sessionName) = split /=/;
    
      $threadList{$threadID} = $sessionName;

      $index++;                    
   }
   
   close(SESSION_FILE);     
   
   
   # add this instanceID to the list of thread session names
   $threadList{$this->{'threadID'}} = $this->{'instanceID'};
   
   # save the new file with the thread added  
   open(SESSION_FILE, ">$recoveryPointFileName") || print "Can't open file: $!"; 
   
   # loop through all of the elements (in reverse so they can be read into a stack)
   foreach (keys %threadList)      
   {        
      print SESSION_FILE $_."=".$threadList{$_}."\n";        
   }
   
   close(SESSION_FILE);          
}

# -------------------------------------------------------------------------------------------------
# endRecoveryThread
#  remove theadID from the recovery file as the thread is now complete
# file is saved in the form:
#   theadID=instanceID\n
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
sub endRecoveryThread

{
   my $this = shift;
   my $recoveryPointFileName = "RecoverySessionName.last";
   my %threadList;
   
   # load the cookie file name from the recovery file
   open(SESSION_FILE, "<$recoveryPointFileName") || print "Can't open recovery point file: $!\n"; 
  
   $index = 0;
   # loop through the content of the file
   while (<SESSION_FILE>) # read a line into $_
   {
      # remove end of line marker from $_
      chomp;
      # split on null character
      ($threadID, $sessionName) = split /=/;
    
      $threadList{$threadID} = $sessionName;

      $index++;                    
   }
   
   close(SESSION_FILE);     
   
   # remove this threadID
   delete $threadList{$this->{'threadID'}};
   
   # save the new file with the thread removed  
   open(SESSION_FILE, ">$recoveryPointFileName") || print "Can't open file: $!"; 
   
   # loop through all of the elements (in reverse so they can be read into a stack)
   foreach (keys %threadList)      
   {        
      print SESSION_FILE $_."=".$threadList{$_}."\n";        
   }
   
   close(SESSION_FILE);          
}

# -------------------------------------------------------------------------------------------------

# reads the name of the session corresponding to this thread from the recovery file
sub recoverThreadSessionName

{
   my $this = shift;
   my $recoveryPointFileName = "RecoverySessionName.last";
   my %threadList;
   
   # load the cookie file name from the recovery file
   open(SESSION_FILE, "<$recoveryPointFileName") || print "Can't open recovery point file: $!\n"; 
  
   $index = 0;
   # loop through the content of the file
   while (<SESSION_FILE>) # read a line into $_
   {
      # remove end of line marker from $_
      chomp;
      # split on null character
      ($threadID, $sessionName) = split /=/;
    
      $threadList{$threadID} = $sessionName;

      $index++;                    
   }
   
   close(SESSION_FILE);     
   
   return $threadList{$this->{'threadID'}};
} 

# -------------------------------------------------------------------------------------------------
# recoverCookies
#  recovers cookies from disk by coping the recoverycookies into the new cookie file name - used for automatic restart from this position
# 
# Purpose:
#  Debugging
#
# Parametrs:
# nil

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
sub recoverCookies

{
   my $this = shift;
   
   my $instanceID = $this->{'instanceID'};
   
   $sessionName = $this->recoverThreadSessionName();
   if ($sessionName)
   {
      print "Using cookie file logs/".$sessionName.".cookies\n";
      # copy the old file in place of the new one
      if (!copy("logs/".$sessionName.".cookies", "logs/".$instanceID.".cookies"))
      {
         print "Failed to duplicate previous cookie file\n";
      }
   }      
}

# -------------------------------------------------------------------------------------------------
# deleteCookies
#  deletes cookies from disk - used to start a clean session
# 
# Purpose:
#
# Parametrs:
# nil

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
sub deleteCookies

{
   my $this = shift;
   
   my $instanceID = $this->{'instanceID'};
   my $httpClient = $this->{'httpClient'};
   
   $httpClient->clearCookies();
#   print "Deleting cookie file logs/".$instanceID.".cookies\n";
   # copy the old file in place of the new one
   if (!unlink("logs/".$instanceID.".cookies"))
   {
      print "Failed to delete cookie file\n";
   }
}

# -------------------------------------------------------------------------------------------------
# recoverLastSession
#  recovers last session file from from disk by coping the sessionfile into the new session file name - used for automatic restart from this position
# 
# Purpose:
#  Debugging
#
# Parametrs:
# nil

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
sub recoverLastSession

{
   my $this = shift;
   my $recoveryPointFileName = "RecoverySessionName.last";
   my $instanceID = $this->{'instanceID'};
   
   $sessionName = $this->recoverThreadSessionName();
   
   if ($sessionName)
   {
      # copy the old file in place of the new one
      copy($sessionName.".session", $instanceID.".session");
   }      
}

# -------------------------------------------------------------------------------------------------



# -------------------------------------------------------------------------------------------------

# gets the globalParameter specified
# used to pass global variables into the parsers
sub getGlobalParameter
{
   my $this = shift;
   my $key = shift;
   $parametersHashRef = $this->{'parametersHashRef'};
   
   return $$parametersHashRef{$key};
}


