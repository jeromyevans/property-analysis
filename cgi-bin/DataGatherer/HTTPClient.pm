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
#
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
   };  
   bless $httpClient;    # make it an object of this class      
   
   # instantiate the user agent for this HTTP client
   $userAgent = LWP::UserAgent->new(); 
   $httpClient->{'userAgentRef'} = $userAgent;
      
   $userAgent->agent($httpClient->{'agentName'}); 
   $userAgent->use_alarm(0);  # disable use of alarm on timeouts
   $userAgent->timeout(30);   # set 30 second timeout (instead of 3 mins)
   
   # create an object for automatically handling cookies for this
   # user agent.  Note cookies are written to the file sessionName.cookies
   # automatiicaly in this version.
   # NOTE: ignore_discard needs to be set to true (in my experience so far)
   # because many sites don't clear the discard flag but still expect the cookie
   # to be saved.  Perhaps this is just my misunderstanding (5 Apr 2004)
   #print "HTTPClient:creating cookie jar: ", $sessionName, ".cookies\n";
   $cookieJar = HTTP::Cookies->new( file => "logs/".$sessionName.".cookies", 
                                    autosave => 1,
                                    ignore_discard => 1);
   #print "   loading cookies...\n";
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
   
   ($this->{'referer'}, $dummy) = (split /\?/, $referer, 2);
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
   
   $request->push_header(Accept => 'text/plain,text/html,text/xml');
   $request->push_header('Accept-Charset' => 'ISO-8859-1,utf-8');
   $request->push_header('Accept-Language' => 'en,en-us');   
   
   if ($this->{'agentName'})
   {
      $request->push_header('User-Agent' => $this->{'agentName'});
   }
    
   if ($this->{'referer'})
   {      
      $request->push_header('Referer' => $this->{'referer'});
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
  
   # prepare HTTP request...
   $request = HTTP::Request->new(GET => $absoluteURL); 
#   $this->_initialiseHeader($request);      
   $this->{'requestRef'} = $request;      # update instance variable   
   $this->{'absoluteURL'} = $absoluteURL;  
   
   $this->_initialiseHeader($request);
   
   # 24 May 2004 - was missing call to prepare request to setup the header with
   # standard parameters.   
   $userAgent->prepare_request($request);
   # issue the request...get a response
   $response = $userAgent->request($request);
   $this->{'responseRef'} = $response;    # update instance variable

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
# opens the connection to the URI (posting form data with it) 
# post data is encoded and stored in the content part of the request
#
# Purpose:
#  Retreiving a document via HTTP
#
# Parameters:
#  STRING absoluteURL to get
#  reference to hash of POST parameters
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
   my $parametersRef = shift;
   my $transactionNo = shift;
  
   my $userAgent;  # LWP::UserAgent
   my $request;    # HTTP::Request
   my $response;   # HTTP::Response
   my $success = 1;       
   my $cookieJar = $this->{'cookieJarRef'};   
   my @postParameters;
                
   $userAgent = $this->{'userAgentRef'};  # get user agent for this instance
   
   $this->{'absoluteURL'} = $absoluteURL;   
   
   # parse the harsh into an array of post parameters
   while(($key, $value) = each(%$parametersRef)) 
   {
      # place the key and value into the post array     
     push @postParameters, $key;
     push @postParameters, $value;
   }
        
   # prepare HTTP request...
   $request = POST $absoluteURL, \@postParameters;
   
   $noOfParameters = @postParameters;
   if ($noOfParameters == 0)
   {      
      # if no parameters, then set the header value content-lenth = 0
      $request->push_header('Content-Length' => '0');
   }
   
   $this->_initialiseHeader($request);           
   $this->{'requestRef'} = $request;      # update instance variable      
   
   # 24 May 2004 - was missing call to prepare request to setup the header with
   # standard parameters.   
   $userAgent->prepare_request($request);
   
   #print "---[Request]---\n", $request->as_string(), "---[end]---\n";
   
   # issue the request...get a response
   $response = $userAgent->request($request);
   $this->{'responseRef'} = $response;    # update instance variable
   
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
   
   return $content;   
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
   
   mkdir "logs", 0755;       	      
   open(SESSION_FILE, ">>logs/$sessionFileName") || print "Can't open file: $!"; 
           
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
