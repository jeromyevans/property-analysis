#!/usr/bin/perl
# Written by Jeromy Evans
# Started 22 February 2004
#
# WBS: A.01.01.01 Developed HTTP Client
# Version 0.1 - 5 Apr 2004 - Added cookie jar support - parameter required in constructor 
#    now set set session name
# Version 0.11 - 8 Apr 2003 - Added support for POSTing form data and setting standard 
# http header information
#
# Description:
#   Module that encapsulates an LWP::UserAgent to setup an HTTP connection and receive
# the HTTP response.  Includes support for:
#   GET
#   Cookies
#   POST
#
# History:
#  25 July 2004 - added support for optional transactionNo stored in the log file
#  27 Sept 2004 - removed the autosave features for the cookies file.  This was deleting some cookies that I needed
#   to stay persistent between sessions even though discard was set (to allow a session to continue over multiple instances
#   of the application running)
#  2 Oct 2004 - disabled stripping out the parameters from referer for privacy - some servers depended on it
#  7 Oct 2004 - changed post to accept an encoded content string instead of a hash for the content
#  17 Oct 2004 - added retransmissions for 500 response code (internal server error)
#  26 Oct 2004 - added clearCookies function
#  31 Oct 20004 - added fetchDocument as a means to use a httpTransaction to get a document.  Previously it was upto the module
#    using this to determine which method to use
# 19 Feb 2005 - hardcoded absolute log directory temporarily
# CONVENTIONS
# _ indicates a private variable or method
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
package HTTPClient;
require Exporter;
use LWP::UserAgent;
use HTTP::Request; 
use HTTP::Request::Common;
use HTTP::Response; 
use HTTP::Cookies;
use URI::Escape;
use URI::URL;

@ISA = qw(Exporter);

#@EXPORT = qw(&parseContent);

my $LOG_TRANSACTIONS = 1;

# -------------------------------------------------------------------------------------------------
# PUBLIC enumerations
#
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

# Contructor for the HTTPClient - returns an instance of an HTTPClient object
# PUBLIC
sub new ($)
{   
   my $sessionName = shift;
   my $userAgent;   # LWP::UserAgent
   my $cookieJar;
   my @responseStack;
   
   my $httpClient = {         
      sessionName => $sessionName,
      agentName => "",
      referer => "",
      userAgentRef => undef,      
      requestRef => undef,
      responseRef => undef,
      responseStackRef => \@responseStack,
      cookieJarRef => undef,
      absoluteURL => undef,
      method => undef,
      httpTransaction => undef
   };  
   bless $httpClient;    # make it an object of this class      
   
   # instantiate the user agent for this HTTP client
   $userAgent = LWP::UserAgent->new(); 
   $httpClient->{'userAgentRef'} = $userAgent;
      
   $userAgent->agent($httpClient->{'agentName'}); 
   $userAgent->use_alarm(0);  # disable use of alarm on timeouts
   $userAgent->timeout(30);   # set 30 second timeout (instead of 3 mins)
   
   # create an object for automatically handling cookies for this
   # user agent.  
   # NOTE: ignore_discard needs to be set to true (in my experience so far)
   # because many sites don't clear the discard flag but still expect the cookie
   # to be saved.  Perhaps this is just my misunderstanding (5 Apr 2004)
   #print "HTTPClient:creating cookie jar: ", $sessionName, ".cookies\n";
   $logPath = "/projects/changeeffect/logs";
   $cookieJar = HTTP::Cookies->new( file => "$logPath/".$sessionName.".cookies", 
                                    autosave => 0,
                                    ignore_discard => 1);
#   print "   loading cookies logs/".$sessionName.".cookies...\n";
   $cookieJar->load();
   #print $cookieJar->as_string();
   # set the cookie jar handler
   $userAgent->cookie_jar($cookieJar);
      
   $httpClient->{'cookieJarRef'} = $cookieJar;
   
   return $httpClient;   # return it
}

# -------------------------------------------------------------------------------------------------
# setUserAgent
# sets the string to use as the agent name for this HTTP client
# agent name is an HTTP field 
# 
# Purpose:
#  Setting up HTTP client
#
# Parameters:
#  STRING agentName
#
# Constraints:
#  nil
#
# Updates:
#  this->{'agentName'}
#
# Returns:
#   Nil
#
sub setUserAgent
{
   $this = shift;
   $userAgent = shift;
   
   $this->{'agentName'} = $userAgent;
}

# -------------------------------------------------------------------------------------------------
# setReferer
# sets the string to use as the referrer for this HTTP client
# 'referer' is an HTTP field (used to indicate where it came from)
# (note HTTP uses "referer", not "referrer")
# Note any parameter data after a ? is stripped out - this is inapproprate
#  to use in the referer because of privacy.
# 2 Oct 2004 - disabled above - parameters are kept
# 
# Purpose:
#  Setting up HTTP client
#
# Parameters:
#  STRING referer URL
#
# Constraints:
#  nil
#
# Updates:
#  this->{'referer'}
#
# Returns:
#   Nil
#
sub setReferer
{
   $this = shift;
   $referer = shift;
   
   #($this->{'referer'}, $dummy) = (split /\?/, $referer, 2);
   # 2 Oct 2004 - disabled stripping out the parameters - some servers depended on it
   $this->{'referer'} = $referer;
}

# -------------------------------------------------------------------------------------------------
# initialises the HTTP header with standard parameters for this user agent
# 
# Purpose:
#  Retreiving a document via HTTP
#
# Parameters:
#  HTTP::request being used
#
# Constraints:
#  nil
#
# Updates:
#  request
# 
# Returns:
#   ni;
#

sub _initialiseHeader
{   
   my $this = shift;
   my $request = shift;

   #$request->push_header(Accept => 'text/plain,text/html,text/xml');
   $request->push_header('Accept' => 'text/xml,application/xml,application/xhtml+xml,text/html;q=0.9,text/plain;q=0.8,image/png,*/*;q=0.5');
   $request->push_header('Accept-Charset' => 'ISO-8859-1,utf-8');
   $request->push_header('Accept-Language' => 'en-us, en');   
   
   if ($this->{'agentName'})
   {
      $request->push_header('User-Agent' => $this->{'agentName'});
   }

   if ($this->{'referer'})
   {      
      $referer = $this->{'referer'};
      
      #2Oct04: escape the ? in the referer path before using it (otherwise push_header's regular expression crashes) 
      $referer =~ s/\?/\?/gi;
 
      $request->push_header('Referer' => $referer);
   }

   

}

# -------------------------------------------------------------------------------------------------
# sets the proxy for the user agent 
# 
# Purpose:
#  Retreiving a document via HTTP
#
# Parameters:
#  STRING absoluteURL of the proxy
#
# Constraints:
#  nil
#
# Updates:

#
# Returns:
#  nil
#

sub setProxy
{
   my $this = shift;
   my $proxyURL = shift;
   my $userAgent = $this->{'userAgentRef'};  # get user agent for this instance
   
   $userAgent->proxy(['http'] => $proxyURL);  
   $userAgent->no_proxy('localhost', '127.0.0.1');
}

# -------------------------------------------------------------------------------------------------
# prepareRequestHeader
# sets fields for an HTTP request - for use prior to construction of the request object
#  cookies and content aren't set (only basic values) 
# 
# Purpose:
#  Retreiving a document via HTTP
#
# Parametrs:
#  STRING url associated with the request (used to get host name)
#
# Updates:
#  nil
#
# Returns:
#   header object
#
sub prepareRequestHeader

{
   my $this = shift;
   my $url = shift;   
   
   $header = HTTP::Headers->new();
   
   # extract host name from the URL (used in the header)
   $host = new URI::URL($url)->host();
   
   #$header->header(Accept => 'text/plain,text/html,text/xml');
   $header->header('Accept' => 'image/gif, image/x-xbitmap, image/jpeg, image/pjpeg, application/vnd.ms-excel, application/vnd.ms-powerpoint, application/msword, application/x-shockwave-flash, */*');
   $header->header('Accept-Language' => 'en-au');   
   $header->header('Host' => $host);
   #$header->header('Proxy-Connection' => 'Keep-Alive'); #4oct
   $header->header('Connection' => 'close');  #4oct
 
   if ($this->{'agentName'})
   {
      $header->header('User-Agent' => $this->{'agentName'});
   }

   if ($this->{'referer'})
   {      
      $referer = $this->{'referer'};
      
      #3Oct04: escape the ? in the referer path before using it (otherwise push_header's regular expression crashes) 
      $referer =~ s/\?/\?/gi;
 
      $header->header('Referer' => $referer);
   }
   return $header;
}

# -------------------------------------------------------------------------------------------------
# opens the connection to the URI 
# 
# Purpose:
#  Retreiving a document via HTTP
#
# Parametrs:
#  STRING absoluteURL to get
#  integer transaction number (optional, for logging)

# Constraints:
#  nil
#
# Updates:
#  $this->{'requestRef'} 
#  $this->{'responseRef'}
#
# Returns:
#   TRUE (1) if response received, FALSE (0) is not
#
sub get()

{
   my $this = shift;
   my $absoluteURL = shift;
   
   my $transactionNo = shift;
      
   my $userAgent;  # LWP::UserAgent
   my $request;    # HTTP::Request
   my $response;  # HTTP::Response
   
   my $success = 1;    
   my $cookieJar = $this->{'cookieJarRef'};
                   
                   
   $userAgent = $this->{'userAgentRef'};  # get user agent for this instance

   # 2 Oct 2004 - load cookies before every get/post (instead of the old auto-handling)
   #print "   loading cookies logs/".$this->{'sessionName'}.".cookies...\n";
   $cookieJar->load();
   # set the cookie jar handler
   $userAgent->cookie_jar($cookieJar);

   $header = $this->prepareRequestHeader($absoluteURL);

   
   #print "GET $absoluteURL\n";
   # prepare HTTP request...
   $request = HTTP::Request->new('GET', $absoluteURL, $header, undef);
   
   # set cookies in the header
   $cookieJar->add_cookie_header($request);
#print $cookieJar->as_string();
   $request->remove_header('Cookie2');   
   
   #print "---REQUEST\n";
   #print $request->as_string();
   #print "---\n";
   $this->{'requestRef'} = $request;      # update instance variable   
   $this->{'absoluteURL'} = $absoluteURL;  
   $this->{'method'} = 'GET';  

   # prepare to run in a loop if request fails with certain error types
   $requestAttempts = 0;
   $retryRequest = 1;
   while ($retryRequest)
   {
      $retryRequest = 0;
      if ($requestAttempts > 0)
      {
         print "   last HTTP status code $statusCode. Retrying...\n";
      }
      # issue the request...get a response
      $response = $userAgent->request($request);
      $this->{'responseRef'} = $response;    # update instance variable
      
      if ($LOG_TRANSACTIONS)
      {
         $this->saveTransactionLog($transactionNo);
      }
      
      if ($response->is_error())
      {         
         $statusCode = $response->code();
         if ($statusCode == 500)
         {
            # internal server error
            $requestAttempts++;
            if ($requestAttempts < 6)
            {
                # might be a temporary request failure - sleep a little bit and try again
               $retryRequest = 1;
               sleep 5;
            }
         }
      }
   }
   
   #23 May 2004 - get the updated cookie jar
   $cookieJar = $userAgent->cookie_jar();
   
   # search the response for any cookies in the header
   $cookieJar->extract_cookies($response);   
   
   #print "   saving cookies...\n";   
   #print $cookieJar->as_string();
   $cookieJar->save();
      
   # push the retreived response onto the response stack
   my $responseStackRef = $this->{'responseStackRef'};
   push @$responseStackRef, ($response);
   
   #print $response->as_string();
   
   if ($response->is_error()) 
   {
      # failed to get the page
      $success = 0;
   }
   return $success;
}


# -------------------------------------------------------------------------------------------------
# opens the connection to the URI (posting form data with it) 
# post data is encoded and stored in the content part of the request
#
# Purpose:
#  Retreiving a document via HTTP
#
# Parameters:
#  STRING absoluteURL to get
#  STRING encodedcontent
#  integer transaction number (optional, for logging)

#
# Constraints:
#  nil
#
# Updates:
#  $this->{'requestRef'} 
#  $this->{'responseRef'}
#
# Returns:
#   TRUE (1) if response received, FALSE (0) is not
#
sub post()

{
   my $this = shift;
   my $absoluteURL = shift;
   my $content = shift;
   my $transactionNo = shift;
  
   my $userAgent;  # LWP::UserAgent
   my $request;    # HTTP::Request
   my $response;   # HTTP::Response
   
   my $success = 1;       
   my $cookieJar = $this->{'cookieJarRef'};   
   my @postParameters;
                
   $userAgent = $this->{'userAgentRef'};  # get user agent for this instance
   
   # 2 Oct 2004 - load cookies before every get/post (instead of the old auto-handling)
   #print "   loading cookies logs/".$this->{'sessionName'}.".cookies...\n";
   $cookieJar->load();
   # set the cookie jar handler
   $userAgent->cookie_jar($cookieJar);
#print $cookieJar->as_string();   
   $header = $this->prepareRequestHeader($absoluteURL);
   $header->header('Content-Type' => 'application/x-www-form-urlencoded');
   $header->header('Content-Length' => length $content);
   $header->header('Pragma' => 'no-cache');

   # prepare HTTP request...
   $request = HTTP::Request->new('POST', $absoluteURL, $header, $content);
   
   # set cookies in the header
   $cookieJar->add_cookie_header($request);
   $request->remove_header('Cookie2');

   #print "---REQUEST\n";
   #print $request->as_string();
   #print "---\n";
   
     
   $this->{'absoluteURL'} = $absoluteURL;              
   $this->{'requestRef'} = $request;      # update instance variable      
   $this->{'method'} = 'POST';  
   
 
   # prepare to run in a loop if request fails with certain error types
   $requestAttempts = 0;
   $retryRequest = 1;
   while ($retryRequest)
   {
      $retryRequest = 0;
      
      if ($requestAttempts > 0)
      {
         print "   last HTTP status code $statusCode. Retrying...\n";
      }
      
      # issue the request...get a response
      $response = $userAgent->request($request);
      $this->{'responseRef'} = $response;    # update instance variable
      
      if ($LOG_TRANSACTIONS)
      {
         $this->saveTransactionLog($transactionNo);
      }
      
      if ($response->is_error())
      {         
         $statusCode = $response->code();
         if ($statusCode == 500)
         {
            # internal server error
         
            $requestAttempts++;
            if ($requestAttempts < 6)
            {
                # might be a temporary request failure - sleep a little bit and try again
               $retryRequest = 1;
               sleep 5;
            }
         }
      }
   }
   
   if ($LOG_TRANSACTIONS)     
   {
      $this->saveTransactionLog($transactionNo);
   }   
   
   #23 May 2004 - get the updated cookie jar
   $cookieJar = $userAgent->cookie_jar();
   
   # search the response for any cookies in the header
   $cookieJar->extract_cookies($response); 
   
   #print "   saving cookies...\n";   
   #print $cookieJar->as_string();
   $cookieJar->save();
   
   # push the retreived response onto the response stack
   my $responseStackRef = $this->{'responseStackRef'};   
   push @$responseStackRef, ($response);
   
   #print $response->as_string();
   
   if ($response->is_error()) 
   {
      # failed to get the page
      $success = 0;
   }
   
   return $success;
}


# -------------------------------------------------------------------------------------------------
# returns as a STRING the content of the last request
# 
# Purpose:
#  Retreiving a document via HTTP
#
# Parameters:
#  nil
#
# Constraints:
#  nil
#
# Updates:
#  nil
#
# Returns:
#   STRING containing content, or undef
#
sub getResponseContent()

{
   my $this = shift;

   my $response = $this->{'responseRef'};
   my $content = $response->content();
   
   return $content;   
}

# -------------------------------------------------------------------------------------------------
# returns as a STRING the URL last accessed by this client
# 
# Purpose:
#  Retreiving a document via HTTP
#
# Parameters:
#  nil
#
# Constraints:
#  nil
#
# Updates:
#  nil
#
# Returns:
#   STRING containing url, or undef
#
sub getURL()

{
   my $this = shift;

   return $this->{'absoluteURL'};  
}

# -------------------------------------------------------------------------------------------------
# returns as a STRING the METHOD last used by this client
# 
# Purpose:
#  Retreiving a document via HTTP
#
# Parameters:
#  nil
#
# Constraints:
#  nil
#
# Updates:
#  nil
#
# Returns:
#   STRING containing url, or undef
#
sub getMethod()

{
   my $this = shift;

   return $this->{'method'};  
   
}

# -------------------------------------------------------------------------------------------------

sub back()

{
   # pop the last response from the response stack (drop back a level)
   my $this = shift;
   my $responseStackRef = $this->{'responseStackRef'};
   
   if (pop @$responseStackRef)
   {
      return 1;
   }
   else 
   {
      return 0;
   }  
}

# -------------------------------------------------------------------------------------------------

sub printURLStack()

{
   my $this = shift;
    # push the retreived response onto the response stack
   
   my $responseStackRef = $this->{'responseStackRef'};
   $length = @$responseStackRef;
   print "length=", $length, "\n";
   
   while ($response = pop @$responseStackRef)
   {
      print "base:", $response->base(), "\n";
   }    
}

# -------------------------------------------------------------------------------------------------

sub responseCode()

{
   my $this = shift;
   my $status;
   my $response = $this->{'responseRef'};
   
   if ($response)
   {
      $status = $response->code();
   }
    
   return $status;
}

# -------------------------------------------------------------------------------------------------
# saveTransactionLog
#  saves to disk the request and response for a transaction (for debugging) 
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
sub saveTransactionLog()

{
   my $this = shift;
   my $transactionNo = shift;
   
   my $requestRef = $this->{'requestRef'};
   my $responseRef = $this->{'responseRef'};
   my $sessionName = $this->{'sessionName'};
   my $sessionFileName = $sessionName.".http";
   
  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
   $year += 1900;
   $mon++;
   $logPath = "/projects/changeeffect/logs";
   mkdir $logPath, 0755;       	      
   open(SESSION_FILE, ">>$logPath/$sessionFileName") || print "Can't open file: $!"; 
           
   print SESSION_FILE "\n\n\n<!-------------- TRANSACTION START ------------------>\n";           
   print SESSION_FILE "\n<transaction instance='$sessionName' count='$transactionNo' year='$year' mon='$mon' mday='$mday' hour='$hour' min='$min' sec='$sec'>\n";
   print SESSION_FILE "<request>\n";   
   print SESSION_FILE $requestRef->as_string();
   print SESSION_FILE "</request>\n";
   print SESSION_FILE "\n<response>\n";
   print SESSION_FILE $responseRef->as_string();
   print SESSION_FILE "</response>\n";
   print SESSION_FILE "</transaction>\n";   
      
   close(SESSION_FILE);      
}
# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# clears the cookiejar associated with this client
# 
# Purpose:
#  Retreiving a document via HTTP
#
# Parameters:
#  nil
#
# Constraints:
#  nil
#
# Updates:
#  nil
#
# Returns:
#   STRING containing url, or undef
#
sub clearCookies()

{
   my $this = shift;

   $cookieJar = $this->{'cookieJarRef'};  
   if ($cookieJar)
   {
      $cookieJar->clear();
   }
}


# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

# fetchDocument
# loads a document in accordance with the specified HTTPTransaction

# Purpose:
#  loading a document via HTTP
#
# Parameters:
#  htmlTransaction to use
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
sub fetchDocument

{
   my $this = shift;
   my $nextTransaction = shift;
   my $startURL = shift;
   
   my $url;
   my $postParameters;
   my $processResponse = 0;
                        
   if ($nextTransaction->methodIsGet())
   {      
      $url = new URI::URL($nextTransaction->getURL(), $startURL)->abs()->as_string();
      
#      ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
#      $year += 1900;
#      $mon++;      
      
#      $displayStr = sprintf("%02d:%02d:%02d  GET: %s\n", $hour, $min, $sec, $url);     
#      $printLogger->print($displayStr);     
      
      $this->setReferer($nextTransaction->getReferer());
      
      if ($this->get($url, $this->{'transactionNo'}))
      {
         $processResponse = 1;
      }
#      else
#      {
#         $printLogger->print("failed ", $httpClient->responseCode(), "\n");
#      }

      # count the number of transactions performed this instance (this is used in the HTTP log)
      $this->{'transactionNo'}++;
      $this->{'httpTransaction'} = $nextTransaction;
      
#      $printLogger->print("HTTP (GET) Response Code: ", $httpClient->responseCode(), "\n");
   }
   else
   {
      if ($nextTransaction->methodIsPost())
      {                                  
         $url = new URI::URL($nextTransaction->getURL(), $startURL)->abs()->as_string();    
         
#         ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
#         $year += 1900;
#         $mon++;      
         
#         $displayStr = sprintf("%02d:%02d:%02d POST: %s\n", $hour, $min, $sec, $url);   
#         $printLogger->print($displayStr);     
                           
         $escapedParameters = $nextTransaction->getEscapedParameters();
         
         $this->setReferer($nextTransaction->getReferer());                 
               
         if ($this->post($url, $escapedParameters, $this->{'transactionNo'}))
         {
            $processResponse = 1;
         }
#         else
#         {
#            $printLogger->print("failed ", $httpClient->responseCode(), "\n");
#         }   
      
         # count the number of transactions performed this instance (this is used in the HTTP log)
         $this->{'transactionNo'}++;
         $this->{'httpTransaction'} = $nextTransaction;
         
#         $printLogger->print("HTTP (POST) Response Code: ", $httpClient->responseCode(), "\n");
      }
   }
   
   return $processResponse;
}
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# returns the httpTransaction last used
# 
# Purpose:
#  Retreiving a document via HTTP
#
# Parameters:
#  nil
#
# Constraints:
#  nil
#
# Updates:
#  nil
#
# Returns:
#   REFERENCE to a HTTPTransaction
#
sub getHTTPTransaction()

{
   my $this = shift;

   return $this->{'httpTransaction'};  
   
}

# -------------------------------------------------------------------------------------------------

