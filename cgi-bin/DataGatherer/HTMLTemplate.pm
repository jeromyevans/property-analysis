#!/usr/bin/perl
# Written by Jeromy Evans
# Started 9 May 2004
# 
# Description:
#   Reads an HTML template file and when registered keywords are encoutered, 
# calls a corresponding callback function to insert replacement htm
#
# CONVENTIONS
# _ indicates a private variable or method
#
# HISTORY
#  20 March 2005 - modified to pass the matched parameter through to the callback function - use for parsing
# parameters from the HTML to the parser

# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#

package HTMLTemplate;

use PrintLogger;
use DebugTools;

require Exporter;
@ISA = qw(Exporter);

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
sub printTemplate
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
         # this substitute looks for a pattern inside %%xxx%%
         $firstPassOfLine = 1;
         $currentLine = "";         
         
         # this regular expression is in a while look so it can be iterated
         # over the line multiple times until the match failes
         # Regular expression: find any pattern inside %% %% - the brackets
         #  are used to store the result of that part of the match in $1         
         while ($_ =~ /%%(.*?)%%/gi)
         {                  
                                       
            # found a match on this line - call the callback if defined...                        
            $callback = $registeredCallbacks->{$1};
            if ($callback)
            {
               $callbackResponse = &$callback($1);
                  
               # check if the response is a scaler for direct insertion
               # or a list to insert over multiple lines
                                 
               if (!ref($callbackResponse))
               {
                  # and substitute the keyword with the response                                 
                  # append the text before the match to the current line, and insert
                  # the response from the callback
                  $currentLine .= $`.( $callbackResponse ? $callbackResponse : "" );                  
               }
               else
               {
                  #($firstPart, $secondPart) = split($1, $_);
                  $currentLine = "Not implemented";                  
               }
            }
            
            # process the remainder of the line... (this is contained in $')
            $_ = $';               
         }        
         
         # add the remainder of the line
         $currentLine .= $_;
         
         print $currentLine;         	                        
      }
      
      close(TEMPLATE_FILE);
   }  
   else
   {
      print "Template not found.\n";
   }       
   
   return $templateText;
}

# -------------------------------------------------------------------------------------------------    
# -------------------------------------------------------------------------------------------------

