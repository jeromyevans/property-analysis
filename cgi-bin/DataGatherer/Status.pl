#!/usr/bin/perl
# Written by Jeromy Evans
# Started 9 May 2004
# 
# Description:
#   
#
# CONVENTIONS
# _ indicates a private variable or method
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
use LogTable;
#use URI::URL;
use DebugTools;
use DocumentReader;
use AdvertisedRentalProfiles;

# -------------------------------------------------------------------------------------------------
# loadTemplate
# loads a template html file and parses it for registered keywords.
# read it line by line
#
# Purpose:
#  returning an HTML page
#
# Parameters:
#  nil
#
#
# Updates:
#  nil
#
# Returns:
#  @sessionURLStack
#    
sub loadTemplate
{  
   my $filename = shift;  
   my $registeredCallbacks = shift;
   my $templateText;
   
   if (-e $filename)
   {       
      open(TEMPLATE_FILE, "<$filename") || print "Can't open template: $!"; 
               
      $index = 0;
      # loop through the content of the file
      while (<TEMPLATE_FILE>) # read a line into $_
      {
         $templateText .= $_;

         DebugTools::printHash("registeredCallbacks", $registeredCallbacks);
        
         # this substitute looks for a pattern inside %xxx%
         # if the pattern in is 
         if ($_ =~ /%%(.*?)%%/gi)
         {            
            print "match = '$1'\n";
            if ($registeredCallbacks->{$1})
            {
               print "callback2=", $registeredCallbacks->{$1};
               $callback = $registeredCallbacks->{$1};
               print "result=", &$callback(), "\n";
            }
         }
         
         #$_ =~ s{%%(.*?)%%}                 
         #       { exists( $registeredCallbacks->{$1} )
         #               ? "here"
         #               : ""
         #       }gsex;                                 	                        
      }
      
      close(TEMPLATE_FILE);
   }         
   
   return $templateText;
}

# -------------------------------------------------------------------------------------------------

sub testCallback
{     
   return "Hello dude";
}

print header();

$registeredCallbacks{"NoOfRentals"} = \&testCallback;

$html = loadTemplate("StatusTemplate.html", \%registeredCallbacks);      

print $html;      

# -------------------------------------------------------------------------------------------------

