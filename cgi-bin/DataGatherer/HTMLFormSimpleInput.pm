# Written by Jeromy Evans
# Started 5 October 2004
#
# Description:
#   Module that represents a simple form INPUT (name=value pair) in an HTMLSyntaxTree
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
package HTMLFormSimpleInput;
require Exporter;

@ISA = qw(Exporter);

use DebugTools;

# -------------------------------------------------------------------------------------------------

# Contructor for the HTMLFormSimpleInput - returns an instance of an HTMLFormSimpleInput object
# PUBLIC
#
# parameters:
# string name of the selection
sub new ($ $ $)
{
   my $name = shift;
   my $value = shift;
   my $valueSet = shift;
   
   my $htmlFormSimpleInput = {     
      name => $name,         
      value => $value,
      valueSet => $valueSet
   };      
   bless $htmlFormSimpleInput;    # make it an object of this class   
   
   return $htmlFormSimpleInput;   # return it
}

# -------------------------------------------------------------------------------------------------
# getName
#
# Purpose:
#  returns the name of this input
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
#  returns the value of this selection
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
                  
   if ($this->{'valueSet'})
   {
      return $this->{'value'};
   }
   else
   {
      return undef;
   }      
}

# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# isValueSet
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
sub isValueSet
{
   my $this = shift;
 
   if ($this->{'valueSet'})
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
#  sets the current value for the selection
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
   $this->{'valueSet'} = 1;               
}


# -------------------------------------------------------------------------------------------------
# clearValue
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
sub clearValue
{
   my $this = shift;
                    
   $this->{'valueSet'} = 0;               
}

