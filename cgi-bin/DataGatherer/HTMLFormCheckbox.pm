# Written by Jeromy Evans
# Started 11 July 2004
#
# Description:
#   Module that represents a form CHECKBOX in an HTMLSyntaxTree
#
# 2 Oct 2004 - now includes a value attribute for checkbox
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
   my $value = shift;
   my $textValue = shift;
   my $isSelected = shift;     
   
   my @optionList;
   
   my $htmlFormCheckbox = {     
      name => $name,         
      value => $value,
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
# getValue
#
# Purpose:
#  returns the value of this checkbox - use isSelected as well though
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
sub getValue
{
   my $this = shift;
                  
   return $this->{'value'};
}

# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# isSelected
#
# Purpose:
#  returns 1 if the value has been set for this input
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
sub isSelected
{
   my $this = shift;
 
   if ($this->{'isSelected'})
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
# setValue
#
# Purpose:
#  sets the current value for the checkbox (and selects it)
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
sub setValue
{
   my $this = shift;
      
   my $value = shift;          
              
   $this->{'value'} = $value; 
   $this->{'isSelected'} = 1;
}

# -------------------------------------------------------------------------------------------------


# -------------------------------------------------------------------------------------------------

# clearSelection
#
# Purpose:
#  clears the current value for the selection
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
sub clearSelection
{
   my $this = shift;
                    
   $this->{'isSelected'} = 0;
}

# -------------------------------------------------------------------------------------------------

