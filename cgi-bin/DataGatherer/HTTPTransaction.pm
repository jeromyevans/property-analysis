#!/usr/bin/perl
# 9 April 2004
# Jeromy Evans
#
# Represents a transaction to implement by the DocumentReader
#
# Version 0.0 
#
# History
#  2 Oct 2004 - modified getEscapedParameters so it so the function can be used without
# instantiating the object.  Needed to do this for forms that use GET - build the parameter hash, 
# escape the parameters and add to the end of the URL
#             - modified constructor to add escaped parameters to a GET URL if parameters have been 
# specified
#  4 Oct 2004 - The order of elements defined in a form is now tracked.  The list is used to
#  maintain the order that the inputs are defined which is consistent with other clients 
#  (don't appear to be mandatory but added while debugging to get exactly
#  the same).  The list order is used when generating the escaped parameters for a post.
#  6 Oct 2004 - changed post parameters to list of hashes instead of hash to allow multiple parameters
#   with the same name
#  7 Oct 2004 - changed constructor to accept either an HTML form or a simple URL
#  30 Oct 2004 - added a label to each transaction used to identify it (for recovery/logging purposes)
#              - allowed referer to be a string URL OR a reference to a HTTP Transaction.  The purpose of the latter option
#    allows the method and content to be retain, useful for recovery.

# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
package HTTPTransaction;
require Exporter;

@ISA = qw(Exporter);

use URI::URL;
use URI::Escape;
use DebugTools;

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# new
# contructor for the HTTP Transaction that accepts an HTML form
#
# Purpose:
#  parsing multiple documents
#
# Parameters:
#  htmlForm
#  string referer URL  or reference to referer HTTPTransaction 
#  string label - used to mark recovery point.  Any useful name

# Constraints:
#  nil
#
# Updates:
#  Nil
#
# Returns:
#  HTTPTransaction object
#    
sub new ($ $ $)
{
   my $htmlFormOrGetURL = shift;
   my $referer = shift;
   my $label = shift;   
   my $optionalPOSTContent = shift;
   my $escapedParameters = undef;                        
  
   if (ref($htmlFormOrGetURL))
   { 
      $htmlForm = $htmlFormOrGetURL;
      if (!ref($referer))
      {
         $url = new URI::URL($htmlForm->getAction(), $referer)->abs()->as_string();
      }
      else
      {
         $url = new URI::URL($htmlForm->getAction(), $referer->getURL())->abs()->as_string();
      }
      
      $method = $htmlForm->getMethod();
      $escapedParameters = $htmlForm->getEscapedParameters();
      #print "EscapedParameters:$escapedParameters\n";

      # 2 Oct 2004 - automatically add escaped parameters to GET url if parameters have been specified
      if (($method EQ 'GET') && ($escapedParameters))
      {
         # this is a GET transaction but parameters are specified - add the parameters to the URL
         # if the URL already contains a ? then just append parameters
         if ($url =~ /\?/)
         {
            $url = $url."&".$escapedParameters;
         }
         else
         {
            # append a ? on the URL
            $url = $url."?".$escapedParameters;
         }
      }
      #print "Transaction:$method $url\n";

   }
   else
   {
      # this is a URL for a simple GET transaction
      if (!ref($referer))
      {
         $url = new URI::URL($htmlFormOrGetURL, $referer)->abs()->as_string();
      }
      else
      {
         $url = new URI::URL($htmlForm->getAction(), $referer->getURL())->abs()->as_string();
      }
      $method = 'GET';
   }
   
   
   my $httpTransaction = { 
      url => $url,
      method => $method,      
      escapedParameters => $escapedParameters,
      referer => $referer, 
      label => $label
   };    
   bless $httpTransaction;     
   
   return $httpTransaction;   # return this
}

# -------------------------------------------------------------------------------------------------
# methodIsGet
#
# Purpose:
#  returns true if this transaction's method is GET
#
# Parameters:
#  nil
#
# Updates:
#  nil
#
# Returns:
#   true of false
#
sub methodIsGet
{
   my $this = shift;
   
   if ($this->{'method'} =~ /GET/i)
   {
      return 1;
   }
   else
   {
      return 0;
   }                  
}

# -------------------------------------------------------------------------------------------------
# methodIsPost
#
# Purpose:
#  returns true if this transaction's method is POST
#
# Parameters:
#  nil
#
# Updates:
#  nil
#
# Returns:
#   true or false
#
sub methodIsPost
{
   my $this = shift;
   
   if ($this->{'method'} =~ /POST/i)
   {
      return 1;
   }
   else
   {
      return 0;
   }                  
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# getURL
#
# Purpose:
#  get's the URL associated with this transaction
#
# Parameters:
#  nil
#
# Updates:
#  nil
#
# Returns:
#   string url
#
sub getURL
{
   my $this = shift;
    
   return $this->{'url'};                
}

# -------------------------------------------------------------------------------------------------
# getMethod
#
# Purpose:
#  get's the METHOD associated with this transaction
#
# Parameters:
#  nil
#
# Updates:
#  nil
#
# Returns:
#   string method string
#
sub getMethod
{
   my $this = shift;
    
   return $this->{'method'};                
}

# -------------------------------------------------------------------------------------------------
# getReferer
#
# Purpose:
#  get's the Referer associated with this transaction
#
# Parameters:
#  nil
#
# Updates:
#  nil
#
# Returns:
#   string url
#
sub getReferer
{
   my $this = shift;
    
   return $this->{'referer'};                
}

# -------------------------------------------------------------------------------------------------
# getEscapedParameters
#
# Purpose:
#  get's the post parameters for the transaction
#
# Parameters:
#  nil
#
# Updates:
#  nil
#
# Returns:
#   string url
#
sub getEscapedParameters
{
   my $this = shift;
    
   return $this->{'escapedParameters'};                
}

# -------------------------------------------------------------------------------------------------
# setEscapedParameters
#
# Purpose:
#  set's the post parameters for the transaction
#
# Parameters:
#  nil
#
# Updates:
#  nil
#
# Returns:
#   string url
#
sub setEscapedParameters
{
   my $this = shift;
   my $escapedParameters = shift;
    
   $this->{'escapedParameters'} = $escapedParameters;
   $this->{'method'} = 'POST';                
}

# -------------------------------------------------------------------------------------------------
# unescapedParameters
#
# Purpose:
#  converts a string of escaped parameters into a hash for posting
#
# Parameters:
#  string of parameters
#
# Updates:
#  postParametersRef
#
# Returns:
#   string containing escaped post parameters
#
sub unescapeParameters
{
   my $this = shift;
   my $escapedString = shift;
   
   my @postParameters;
   my $index = 1;
   
   $postParameters[0]{'name'} = '_internalPOSTOrder_';
   
   # split into pairs on the ampersand
   @pairs = split /\&/, $escapedString;
   
   foreach (@pairs)
   {
      #split on the equals
      ($key, $value) = split /=/, $_;
      
      if ($key)
      {
         $unescapedKey = uri_unescape($key);
         $unescapedValue = uri_unescape($value);
         
         $postParameters[$index]{'name'} = $unescapedKey;
         $postParameters[$index]{'value'} = $unescapedValue;
         
         # append to the internal order variable 
         if ($index > 1)
         {
            $postParameters[0]{'value'} .= ",";
         }
         $postParameters[0]{'value'} .= $unescapedValue;
         
         $index++;
      }                  
   }      
   
   return @postParameters;
}

# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# printTransaction
#
# Purpose:
#  prints information about the transaction
#
# Parameters:
#  nil
#
# Updates:
#  nil
#
# Returns:
#   string url
#
sub printTransaction
{
   my $this = shift;
    
   print $this->{'method'}, " ", $this->{'url'}, "\n";                
}

# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# getLabel
#
# Purpose:
#  get's the label associated with the transaction
#
# Parameters:
#  nil
#
# Updates:
#  nil
#
# Returns:
#   string url
#
sub getLabel
{
   my $this = shift;
    
   return $this->{'label'};                
}


