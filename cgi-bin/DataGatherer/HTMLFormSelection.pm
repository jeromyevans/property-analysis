# Written by Jeromy Evans
# Started 9 April 2004
#
# Description:
#   Module that represents a form SELECTION in an HTMLSyntaxTree
#
# History:
#  1 June 2004 - added function to return the first option for the selection
#    that can be used in lieu of a default value

# CONVENTIONS
# _ indicates a private variable or method
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
package HTMLFormSelection;
require Exporter;

@ISA = qw(Exporter);

use DebugTools;

# -------------------------------------------------------------------------------------------------

# Contructor for the HTMLFormSelection - returns an instance of an HTMLFormSelection object
# PUBLIC
#
# parameters:
# string name of the selection
sub new
{
   my $name = shift;      
   
   my @optionList;
   
   my $htmlFormSelection = {     
      name => $name,            
      optionListLength => 0,
      optionListRef => undef,   # list of hashes (value, text)
      defaultIndex => -1,
      value => undef,
      valueSet => 0,
      defaultCleared => 0
   };      
   bless $htmlFormSelection;    # make it an object of this class   
   
   return $htmlFormSelection;   # return it
}

# -------------------------------------------------------------------------------------------------
# addOption
#
# Purpose:
#  defines an option for this selection in the form 
#
# Parameters:
#  string value for the option
#  string text value associated with this option (just displayed)
#  boolean isDefault
#
# Updates:
#  method
#
# Returns:
#   nil
#
sub addOption
{
   my $this = shift;
   my $value = shift;
   my $textValue = shift;
   my $isDefault = shift;
   
#print "addOption(", $this->{'name'}, ") val=$value text='$textValue'\n";             
   $this->{'optionListRef'}[$this->{'optionListLength'}]{'value'} = $value;
   $this->{'optionListRef'}[$this->{'optionListLength'}]{'text'} = $textValue;   
      
   # if this is the default value then record the index for the selection
   if ($isDefault)
   {
      #print $this->{'name'}, ".setting defaultIndex to ", $this->{'optionListLength'}, "($value:$textValue)\n";      
      $this->{'defaultIndex'} = $this->{'optionListLength'};
   }
   
   $this->{'optionListLength'}++;
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
# hasDefault
#
# Purpose:
#  returns true if this selection has a default value
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
sub hasDefault
{
   my $this = shift;
   my $defaultSet = 0;
    
   if ($this->{'defaultIndex'} >= 0)
   {      
      $defaultSet = 1;
   }
           
   return $defaultSet;      
}

# -------------------------------------------------------------------------------------------------
# getDefaultValue
#
# Purpose:
#  returns the default value for this selection if set (otherwise undef)
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
sub getDefaultValue
{
   my $this = shift;
   my $defaultIndex;   
   my $defaultValue = undef;
          
   $defaultIndex = $this->{'defaultIndex'};
   if ($defaultIndex >= 0)
   {            
      $defaultValue = $this->{'optionListRef'}[$defaultIndex]{'value'};            
   }
           
   return $defaultValue;      
}

# -------------------------------------------------------------------------------------------------
# getFirstValue
#
# Purpose:
#  returns the first value for this selection if set (otherwise undef)
#  (used when a default not available)
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
sub getFirstValue
{
   my $this = shift;
      
   my $firstValue = undef;          
              
   $firstValue = $this->{'optionListRef'}[0]{'value'};               
           
   return $firstValue;      
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# getOptionListRef
# returns a reference to the list of options for this selection
#
# Purpose:
#  parsing a form for posting
#
# Parameters:
#  nil
#
# Updates:
#  nil
#
# Returns:
#   reference to array of hashes
#
sub getOptionListRef
{
   my $this = shift;       
           
   return $this->{'optionListRef'};      
}

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
#   print "HTMLFormSelection::setValue(", $this->{'name'}, ") = $value\n";           
   $this->{'value'} = $value;  # should really be an index, but oh well....
   $this->{'valueSet'} = 1;               
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
   my $value = undef;
                  
#       print "HTMLFormSelection::getValue(", $this->{'name'}, ")...\n";           
              
   if ($this->{'valueSet'})
   {
      $value = $this->{'value'};
#      print "valueSet($value)\n";
   }
   else
   {
      # return the default
      if ($this->hasDefault())
      {
         # if the default hasn't been cleared
         if (!$this->{'defaultCleared'})
         {
            $value = $this->getDefaultValue();
            #         print "default($value)\n";
         }
      }   
   }      
   
   return $value;
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
   $this->{'defaultCleared'} = 1;  # clear the default value               
}

# -------------------------------------------------------------------------------------------------


# -------------------------------------------------------------------------------------------------
# isValueSet
#
# Purpose:
#  returns 1 if the value has been set for this input or the default value is still valid
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
   my $result = 0;
 
   if ($this->{'valueSet'})
   {
      $result = 1;
   }
   else
   {
      # check if a default value is set...
      if ($this->hasDefault())
      {
         # check if the default is still valid
         if (!$this->{'defaultCleared'})
         {
            # default hasn't been cleared - good
            $result = 1;
         }
      }
   }         

   return $result;           
}

