#!/usr/bin/perl
# 9 April 2004
# Jeromy Evans
#
# Represents a transaction to implement by the DocumentReader
#
# Version 0.0 
# 
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
# new
# contructor for the HTTP Transaction
#
# Purpose:
#  parsing multiple documents
#
# Parameters:
#  string URL
#  string method
#  reference to hash   
#  string referer URL

# Constraints:
#  nil
#
# Updates:
#  Nil
#
# Returns:
#  HTTPTransaction object
#    
sub new ($ $ $ $)
{
   my $url = shift;
   my $method = shift;
   my $postParametersRef = shift;
   my $referer = shift;         
   
   my $httpTransaction = { 
      url => $url,
      method => $method,      
      postParametersRef => $postParametersRef,
      referer => $referer            
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
   
   if ($this->{'method'} eq 'GET')
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
   
   if ($this->{'method'} eq 'POST')
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
# getPostParameters
#
# Purpose:
#  get's the reference to list of post parameters (ref to hash)
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
sub getPostParameters
{
   my $this = shift;
    
   return $this->{'postParametersRef'};                
}

# -------------------------------------------------------------------------------------------------
# getEscapedParameters
#
# Purpose:
#  get's the current parameters escaped into a string
#
# Parameters:
#  nil
#
# Updates:
#  nil
#
# Returns:
#   string containing escaped post parameters
#
sub getEscapedParameters
{
   my $this = shift;
   my $postParametersRef = $this->{'postParametersRef'};
   my $unescapedString;     
   my $escapedString = '';
   my $isFirst = 1;

   if ($this->methodIsPost())
   {     
      while(($key, $value) = each(%$postParametersRef)) 
      {
         # generate the string from the next hash pair
         $escapedKey = uri_escape($key)."=".uri_escape($value);
                 
         if (!$isFirst)
         {
            # insert an ampersand before the next string           
            $escapedString .= '&';            
         }
         else
         {
            $isFirst = 0;
         }                  
         
         $escapedString .= $escapedKey;                                    
      }      
   }
   return $escapedString;
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
   
   my %postParameters;
   
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
         
         $postParameters{$unescapedKey} = $unescapedValue;
      }                  
   }      
   
   $this->{'postParametersRef'} = \%postParameters;
   
   return $escapedString;
}
