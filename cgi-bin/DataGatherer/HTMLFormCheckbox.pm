# Written by Jeromy Evans
# Started 11 July 2004
#
# Description:
#   Module that represents a form CHECKBOX in an HTMLSyntaxTree
#
# History:
#
# CONVENTIONS
# _ indicates a private variable or method
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
package HTMLFormCheckbox;
require Exporter;

@ISA = qw(Exporter);

use DebugTools;

# -------------------------------------------------------------------------------------------------

# Contructor for the HTMLFormCheckbox - returns an instance of an HTMLFormCheckbox object
# PUBLIC
#
# parameters:
# string name of the selection
sub new
{
   my $name = shift;
   my $textValue = shift;
   my $isSelected = shift;      
   
   my @optionList;
   
   my $htmlFormCheckbox = {     
      name => $name,            
      textValue => $textValue,
      isSelected => $isSelected
   };      
   bless $htmlFormCheckbox;    # make it an object of this class   
   
   return $htmlFormCheckbox;   # return it
}

# -------------------------------------------------------------------------------------------------
# getName
#
# Purpose:
#  returns the name of this selection
#
# Parameters:
#  nil
#
# Updates:
#  nil
#
# Returns:
#   nil
#
sub getName
{
   my $this = shift;
                  
   return $this->{'name'};      
}

# -------------------------------------------------------------------------------------------------


