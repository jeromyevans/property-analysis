#!/usr/bin/perl
# Written by Jeromy Evans
# Started 14 March 2004
# 
# Version 0.0  
#
# Description:
#   Generic debugging tools
#
# CONVENTIONS
# _ indicates a private variable or method
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
package DebugTools;
require Exporter;

@ISA = qw(Exporter);

#@EXPORT = qw(&parseContent);

# -------------------------------------------------------------------------------------------------
# printHash
# debugging tool to display the contents of a hash
#
# Purpose:
#  debug information
#
# Parameters:
#  $hashname (to display)
#  $hashToPrintReference  (reference to a hash)
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
sub printHash
{
   my $hashName = shift;
   my $hashToPrintRef = shift;
     
   print "---[start \%$hashName]---\n";
   while(($key, $value) = each(%$hashToPrintRef)) 
   {
      # do something with $key and $value
      print "   $key=$value\n";
   }
   print "---[end   \%$hashName]---\n";
}


# -------------------------------------------------------------------------------------------------
# printList
# debugging tool to display the contents of a list
#
# Purpose:
#  debug information
#
# Parameters:
#  $listname (to display)
#  $listToPrintReference  (reference to a list)
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
sub printList
{
   my $listName = shift;
   my $listToPrintRef = shift;
   my $first = 1;
     
   print "---[$listName][";
   foreach (@$listToPrintRef) 
   {
      # determine if a comma needs to preceed this element
      if (!$first)
      {
         print ", ";
      }
      else
      {
         $first = 0;
      }
      
      # do something with $key and $value
      print "$_";
   }
   print "]---\n";
}

# -------------------------------------------------------------------------------------------------
