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
#              19 Jan 2005 - added support for the StatusTable to request and reuse threadID's in the constructor
#                          - replaced recovery process to use StatusTable instead of text file
#              22 Jan 2004 - added support for the SessionProgressTable to record the progress of each thread
#                          - extended timeout for parsing from 20seconds to 45 seconds as the low value was due to 
#   to memory leak error that's mainly now avoided.  On initial runs because of the size of the database the parser
#   ran take a long time.
#              19 Feb 2005 - hardcoded absolute log directory temporarily
#               2 Apr 2005 - added support for setting printLogger for HTTPClient (debug info)
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
use StatusTable;
use SessionProgressTable;
use SessionURLStack;

my $DEFAULT_USER_AGENT ="Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1)";

my ($printLogger) = undef;

my @refererStack;
my $ok = 1;
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
   my $lastInstanceID = undef;

   # access the statusTable
   $statusTable = StatusTable::new($sqlClient);
   $$tablesHashRef{'statusTable'} = $statusTable;
   
   # access the sessionProgressTable
   $sessionProgressTable = SessionProgressTable::new($sqlClient);
   $$tablesHashRef{'sessionProgressTable'} = $sessionProgressTable;
   
   # access the sessionURLStack
   $sessionURLStack = SessionURLStack::new($sqlClient);
   $$tablesHashRef{'sessionURLStack'} = $sessionURLStack;
   
   
   if ($threadID > 0)
   {
      # threadID has been specified - continue an existing session
      
      # recover the name of the last instance ID
      $lastInstanceID = recoverLastInstanceID($threadID, $statusTable);
      
      # take control of the threadID using the new instanceID
      $statusTable->continueThread($threadID, $instanceID);
   }
   else
   {
      # threadID is not set - request a new one from the status table
      $threadID = $statusTable->requestNewThread($instanceID);
   }
   
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
      httpClient => undef,
      lastInstanceID => $lastInstanceID,
      cookiePath => "/projects/changeeffect/logs"
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
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------  
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

sub regexEscape

{
   my $string = shift;
   
   $string =~ s/\?/ /gi;
   $string =~ s/\[/ /gi;
   $string =~ s/\]/ /gi;
   $string =~ s/\(/ /gi;
   $string =~ s/\)/ /gi;
   $string =~ s/\*/ /gi;
   $string =~ s/\./ /gi;
   return $string;
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
   
   $string = regexEscape($string);
   # loop through the list of patterns
   foreach (@$patternListRef)
   {
      # check if the string contains the current pattern
      $comparitor = regexEscape($_);
      if ($string =~ /$comparitor/gi)
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
         
      #$printLogger->print("  Loading frames...\n"); 
      @frameList = $htmlSyntaxTree->getFrames();   

      # for each frame, load it's content but don't parse it yet (store content
      # in list)
      foreach (@frameList)
      {
	      $absoluteURL = new URI::URL($_, $url)->abs()->as_string();   
         # create new transaction.  set referer to the base url 
         # 2 Oct 2004 - bugfix to referer
         #$httpTransaction = HTTPTransaction::new($absoluteURL, 'GET', undef, $absoluteURL);
         $httpTransaction = HTTPTransaction::new($absoluteURL, $url, $nextTransaction->getLabel());
         # 30 Oct 2004 - referer is a transaction - useful for referer stack (for recovery)
         #$httpTransaction = HTTPTransaction::new($absoluteURL, $nextTransaction, $nextTransaction->getLabel());
         
         $frameHTTPClient = HTTPClient::new($this->{'instanceID'});      
         $frameHTTPClient->setProxy($this->{'proxy'});                  
         $frameHTTPClient->setUserAgent($DEFAULT_USER_AGENT);

         if ($frameHTTPClient->fetchDocument($httpTransaction, $url))
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
      $thisTransaction = $_->getHTTPTransaction();

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
      
      # determine if there's a parser defined for this url...
      if (($parserIndex = stringContainsPattern($url, \@parserPatternList)) >= 0)
   	{
         
         ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
         $year += 1900;
         $mon++;      
               
         $displayStr = sprintf("%02d:%02d:%02d  parsing...\n", $hour, $min, $sec);     
         $printLogger->print($displayStr);
         
	      # 26 September 2004 - measure how long the callback takes to run  
         $startTime = time;
         
	   	# get the value from the hash with the pattern matching the callback function
		   # the value in the cash is a code reference (to the callback function)		            
		   my $callbackFunction = $$parserHashRef{$parserPatternList[$parserIndex]};		  		  
         my @callbackTransactionStack = &$callbackFunction($this, $htmlSyntaxTree, $url, $this->{'instanceID'}, $this->{'transactionNo'}, $this->{'threadID'}, $nextTransaction->getLabel());
		
         $endTime = time;
         $runningTime = $endTime - $startTime;
           #print "Transaction $transactionNo took $runningTime seconds\n";
         if ($runningTime > 45)
         {
            $printLogger->print("Getting very slow...low memory....halting this instance (should automatically restart)\n");
            $this->{'lowMemoryError'} = 1;
         }
            
         # loop through the transactions to convert from URLs to transactions if necessary
         foreach (@callbackTransactionStack)
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
               $httpTransaction = HTTPTransaction::new($absoluteURL, $url, $nextTransaction->getLabel()."?");
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
   my @newTransactionStack;
   my $nextTransaction;
   
   my $maxURLsPerSession;
   my $currentIndex;
   my $urlValid;
   my $parserIndex;
   
   my $httpTransaction;
   my $recoveryCookies = undef;
   my $useRecoveryCookies = 0;
   my $sessionURLStack = $this->getSessionURLStack();
   
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

   
   if ($startSession)
   {
      $printLogger->print("--- starting new session - threadID=",$this->{'threadID'}, " ---\n");
   
      $httpClient = HTTPClient::new($this->{'instanceID'});      
      $httpClient->setProxy($this->{'proxy'});
      $httpClient->setUserAgent($DEFAULT_USER_AGENT);
      $httpClient->setPrintLogger($printLogger);
      $this->{'httpClient'} = $httpClient;      
      $nextTransaction = HTTPTransaction::new($startURL, undef, $this->getGlobalParameter('source'));  # no referer - this is first request
      
      if ($httpClient->fetchDocument($nextTransaction, $startURL))
      {
         @newTransactionStack = $this->_parseDocument($nextTransaction, $httpClient);
                    
         # 23Jan05 - let the database manage the transaction stack order for the thread
         $sessionURLStack->pushTransactionList($this->{'threadID'}, \@newTransactionStack);
      }
      
      # start processing off the top of the stack
      $continueSession = 1;
   }
   
   if ($continueSession)
   {   
      $printLogger->print("--- threadID=", $this->{'threadID'}, " ---\n");
      # get the URL stack remaining for the session
      #@sessionURLstack = $this->_loadSessionURLStack();    # load recovery point
      
      $httpClient = HTTPClient::new($this->{'instanceID'});
            
      $httpClient->setProxy($this->{'proxy'});
      $httpClient->setUserAgent($DEFAULT_USER_AGENT);
      $httpClient->setPrintLogger($printLogger);
      $this->{'httpClient'} = $httpClient;   
      
      $maxURLsPerSession = 0;
      $currentIndex = 0;
      $urlValid = 1;    
      while ((($currentIndex < $maxURLsPerSession) || ($maxURLsPerSession == 0)) && ($urlValid))
      {           
         # 23Jan05 - let the database manage the transaction stack order for the thread
         $nextTransaction = $sessionURLStack->popNextTransaction($this->{'threadID'});

         # if the next URL is defined...
         if ($nextTransaction)
         {
            if ($httpClient->fetchDocument($nextTransaction, $startURL))
            {
               # parse the document...
               @newTransactionStack = $this->_parseDocument($nextTransaction, $httpClient);
         
               # 23Jan05 - let the database manage the transaction stack for the thread
               $sessionURLStack->pushTransactionList($this->{'threadID'}, \@newTransactionStack);
                 
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
         }	       

         $currentIndex++;
      }      
      
      if (($currentIndex == $maxURLsPerSession) && ($maxURLsPerSession > 0))
      {
         # 27 Sep 04
         # if the session exits early because of the limit on number of transactions, then exit
         # with an exit code indicating the threadID.

         $printLogger->print("end-of-session - exiting with threadID".$this->{'threadID'}."\n");
         # exit and return the thread ID for restart
         exit $this->{'threadID'};  
      }
         
      # release this threadID - can't be continued as it's finished
      $this->releaseSessionHistory();
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
# releaseSessionHistory
#  release the threadID from the status table and all associated history as it's no longer 
# required (can't continue)
#
# Purpose:
#  start up, status reporting and recovery
#
# Parametrs:
#  nil
#
# Returns:
#   nil
#
sub releaseSessionHistory

{
   my $this = shift;
   my $tablesHashRef = $this->{'tablesHashRef'};      
   my $threadID = $this->{'threadID'};
   
   # get the status table
   $statusTable = $$tablesHashRef{'statusTable'};
   $sessionProgressTable = $$tablesHashRef{'sessionProgressTable'};
   $sessionURLStack = $$tablesHashRef{'sessionURLStack'};

   # update the status table releasing the threadID
   $statusTable->releaseThread($threadID);
   $sessionProgressTable->releaseSession($threadID);
   $sessionURLStack->releaseSession($threadID);
}


# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# recoverLastInstanceID
#  get the name of the instance ID last used for the thread from the status table on start-up (recovery)
# NOTE: this method is NOT inside the class.
# Purpose:
#  start up, status reporting and recovery
#
# Parametrs:
#  nil
#
# Returns:
#   nil
#
sub recoverLastInstanceID

{
   my $threadID = shift;
   my $statusTable = shift;    

   print "in recoverLastInstanceID(threadID=$threadID):\n";

   $instanceID = $statusTable->lookupInstance($threadID);
   
   return $instanceID
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
   
   $sessionName = $this->{'lastInstanceID'};
   $logpPath = $this->{'cookiePath'};

   if ($sessionName)
   {
      $printLogger->print("in recoverCookies (lastInstanceID=$sessionName, newInstanceID=$instanceID):\n");
      # copy the old file in place of the new one
      if (!copy("$logPath/".$sessionName.".cookies", "$logPath/".$instanceID.".cookies"))
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
   $logPath = $this->{'cookiePath'};

   if (!unlink("$logPath/".$instanceID.".cookies"))
   {
      print "Failed to delete cookie file\n";
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



# -------------------------------------------------------------------------------------------------

# gets the reference to the statusTable created for the DocumentReader
sub getStatusTable
{
   my $this = shift;
   my $tablesHashRef = $this->{'tablesHashRef'};      
   
   # get the status table
   $statusTable = $$tablesHashRef{'statusTable'};
   
   return $statusTable;
}


# -------------------------------------------------------------------------------------------------

# gets the reference to the sessionProgressTable created for the DocumentReader
sub getSessionProgressTable
{
   my $this = shift;
   my $tablesHashRef = $this->{'tablesHashRef'};      
   
   # get the status table
   $sessionProgressTable = $$tablesHashRef{'sessionProgressTable'};
   
   return $sessionProgressTable;
}


# -------------------------------------------------------------------------------------------------

# gets the reference to the sessionURLStack created for the DocumentReader
sub getSessionURLStack
{
   my $this = shift;
   my $tablesHashRef = $this->{'tablesHashRef'};      
   
   # get the table reference
   $sessionURLStack = $$tablesHashRef{'sessionURLStack'};
   
   return $sessionURLStack;
}

# -------------------------------------------------------------------------------------------------

sub getThreadID

{
   my $this = shift;
   return $this->{'threadID'};
}


# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

