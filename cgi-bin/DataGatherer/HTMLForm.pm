#!/usr/bin/perl
# Written by Jeromy Evans
# Started 8 April 2004
#
# Description:
#   Module that accepts represents a form in an HTMLSyntaxTree
#
# History:
#  1 June 2004 - modified getPostParameters to return the first option in a selection
# if no default value is defined.  Discovered this is the convention through testing.
#
#  11 July 2004 - added checkbox list handling functions
#  18 July 2004 - added clearInputValue 
# 2 Oct 2004 - now sets the value attribute of checkboxs if defined.  Hadn't encountered this 
#   beung used previously (ie. each checkbox has the same name but different value instead of 
#   each checkbox having a different name) 
# 4 Oct 2004 - created a formelementlist that maintains the name of all inputs defined in the
#   form.  The list is used to maintain the order that the inputs are defined which is consistent
#   with other clients (don't appear to be mandatory but added while debugging to get exactly
#   the same).  The list order is provided in a hidden element in the post hash if requested.
# 5 Oct 2004 - added support for an HTMLFormSimpleInput that represents a basic name=value pair
#   in a form (eg. a text input) - used instead of a hash to track whether the value is set or not.  This
#   actually originated bedcause of the change at 2 Oct 2004 to handle multiple checkboxes with the same
#   name - it became apparant that even though they had the same name, every set checkbox with that
#   name has to be posted (ie name has multiple value) which required a change to the way the name=value
#   pairs for posting are stored in this object.
# 6 Oct 2004 - To support the above problem, also had to change postParameters to a list of hashes instead of a hash
#   as the keys have multiple instances in certain cases.  This may make the internal variable to maintain
#   order redundant, but not sure yet.
#
# CONVENTIONS
# _ indicates a private variable or method
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
package HTMLForm;
require Exporter;

use HTMLFormSelection;
use HTMLFormCheckbox;
use HTMLFormSimpleInput;
use URI::Escape;

@ISA = qw(Exporter);

use DebugTools;

# -------------------------------------------------------------------------------------------------

# Contructor for the HTMLForm - returns an instance of an HTMLForm object
# PUBLIC
#
# parameters:
# string name
# string action URL
sub new
{
   my $name = shift;
   my $action = shift;   
      
   my $htmlForm = {     
      name => $name,      
      action => $action,      
      method => 'GET',   # default value
      
      # list of the unique names of inputs in the form - used to track order encountered for posting in same order
      formElementListRef => undef,
      formElementListLength => 0,
      
      # reference to a list of simple inputs (eg. text input) defined in the form
      simpleInputListRef => undef,
      simpleInputListLength => 0,
      
      # reference to a list of selection inputs defined in the form
      selectionListLength => 0,
      selectionListRef => undef,
      
      # reference to a list of checkbox inputs defined in the form
      checkboxListLength => 0,
      checkboxListRef => undef,
      
      # reference to a hash to catch other inputs with a value set explicitly
      otherInputsHashRef => undef
   };      
   bless $htmlForm;    # make it an object of this class   
   
   return $htmlForm;   # return it
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# setMethod_POST
# sets the method for the form to POST
# 
# Purpose:
#  parsing an HTML document containing a form
#
# Parameters:
#  nil

# Updates:
#  method
#
# Returns:
#   nil
#

sub setMethod_POST()
{
   my $this = shift;   
#print "HTMLForm::setMethodPOST\m";   
   $this->{'method'} = 'POST';
}

# -------------------------------------------------------------------------------------------------
# setMethod_GET
# sets the method for the form to GET
# 
# Purpose:
#  parsing an HTML document containing a form
#
# Parameters:
#  nil

# Updates:
#  method
#
# Returns:
#   nil
#
sub setMethod_GET()
{
   my $this = shift;
#print "HTMLForm::setMethodGET\m";   
     
   $this->{'method'} = 'GET';
}

# -------------------------------------------------------------------------------------------------
# getMethod
# gets the method used by the form
# 
# Purpose:
#  parsing an HTML document containing a form
#
# Parameters:
#  nil

# Updates:
#  method
#
# Returns:
#   nil
#
sub getMethod()
{
   my $this = shift;
   
   return $this->{'method'};
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

# maintains a list of form elements - a list is used instead of only a hash to maintain order
# that the form elements are defined - not sure if this is significant but browsers all
# seem to post using parameters in the order they're encountered
sub defineFormElement
{
   my $this = shift;
   my $name = shift;
   my $found = 0;
   
   # search the list for an element matching the name...
   if ($this->{'formElementListLength'} > 0)
   {      
      for ($index = 0; $index < $this->{'formElementListLength'}; $index++)
      {
         $key = $this->{'formElementListRef'}[$index]; 
         # check if this element is already defined
         if ($key eq $name)
         {
            # found a match - set the existing value in the input hash
            $found = 1;
            last;
         }
         else
         {
            $index++;
         }
      }
   }
     
   # doesn't already exist - add new form element
   if (!$found)
   {
      # add new input to end of list...
     # print "defining new input '$name'...\n";

      $this->{'formElementListRef'}[$this->{'formElementListLength'}] = $name;
      $this->{'formElementListLength'}++;      
   }   
}


# -------------------------------------------------------------------------------------------------
# addFormSelection
#
# Purpose:
#  defines an input of type SELECTION in the form
#  a selection can have a range of values attached to it
#
# Parameters:
#  string name

# Updates:
#  method
#
# Returns:
#   nil
#
sub addFormSelection
{
   my $this = shift;
   my $name = shift;   
        
   my $htmlFormSelection = HTMLFormSelection::new($name);
  
   # define the element in the form if not done so already... 
   $this->defineFormElement($name);   
#   print "   added form selection($name).\n";

   #  add this selection to the table element index
   $this->{'selectionListRef'}[$this->{'selectionListLength'}] = $htmlFormSelection;                                                                     
   $this->{'selectionListLength'}++;
}

# -------------------------------------------------------------------------------------------------
# addSelectionOption
#
# Purpose:
#  defines an option for the last created SELECTION in the form
#
# Parameters:
#  string value for the option
#  string text value associated with the option
#  boolean isSelected
# 
# Updates:
#  method
#
# Returns:
#   nil
#
sub addSelectionOption
{
   my $this = shift;
   my $value = shift;
   my $textValue = shift;
   my $isSelected = shift;
           
   #  add this selection to the table element index
   if ($this->{'selectionListRef'})
   {           
      if ($isSelected)
      {
 #        print "   selected$value\n";
      }
      $this->{'selectionListRef'}[$this->{'selectionListLength'}-1]->addOption($value, $textValue, $isSelected);
   }                                                                           
}

# -------------------------------------------------------------------------------------------------
# getName
#
# Purpose:
#  returns the name of this form
#
# Parameters:
#  nil
#
# Updates:
#  nil
#
# Returns:
#   string name
#
sub getName
{
   my $this = shift;
                  
   return $this->{'name'};      
}

# -------------------------------------------------------------------------------------------------
# getAction
#
# Purpose:
#  returns the action defined forthis form
#
# Parameters:
#  nil
#
# Updates:
#  nil
#
# Returns:
#   string name
#
sub getAction
{
   my $this = shift;
                  
   return $this->{'action'};      
}

# -------------------------------------------------------------------------------------------------

sub printForm
{
   my $this = shift;
   
   print "---start of form---\n";
   print "name      : ", $this->{'name'}, "\n";
   print "action    : ", $this->{'action'}, "\n";
   print "method    : ", $this->{'method'}, "\n";
   #print "selections: ", $this->{'selectionListLength'}, "\n";
   #my $inputHashRef = $this->{'inputHashRef'};     

   #DebugTools::printHash("inputs", $inputHashRef);
   
   if ($this->{'simpleInputListLength'} > 0)
   {
      $simpleInputListRef = $this->{'simpleInputListRef'};
   
      # loop for all of the defined simple inputs
      foreach (@$simpleInputListRef)
      {
         print "input: ", $_->getName(), "\n";
         print " value ='", $_->getValue(), "' (set=", $_->isValueSet(), ")\n";                 
      }
   }

   if ($this->{'selectionListLength'} > 0)
   {
      $selectionListRef = $this->{'selectionListRef'};
      foreach (@$selectionListRef)
      {
         print "selection: ", $_->getName(), "\n";
         print " options: ", $this->{'selectionListLength'}, "\n";
         print " value ='", $_->getValue(), "')\n";             
      }
   }
   
   # if the value still isn't set, try the checkboxes...
   if ($this->{'checkboxListLength'} > 0)
   {
      $checkboxListRef = $this->{'checkboxListRef'};
 
      # for each checkbox, get the name and default value    
      foreach (@$checkboxListRef)
      {
         print "checkbox: ", $_->getName(), "\n";
         print " value ='", $_->getValue(), "' (selected=", $_->isSelected(), ")\n";          
      }
   }
   $otherInputsHashRef = $this->{'otherInputsHashRef'};

   foreach (($key, $value) = each(%$otherInputsHashRef))
   {
      print "other: $key\n";
      print " value ='", $value, "'\n";
   }
   print "---end of form---\n";
   
   
}

# -------------------------------------------------------------------------------------------------
# getPostParameters
#
# Purpose:
#  returns a list of hashes containing the current set of parameters for the form
#  eg. hash of keys and default values
#
# Parameters:
#  nil
#
# Updates:
#  nil
#
# Returns:
#   string name
#
sub getPostParameters
{
   my $this = shift;            
   my $name;
   my $value;
   my @postParameters;
   my $index = 1;   #index zero is reserved for a a special variable - see below!
      
      
   if ($this->{'simpleInputListLength'} > 0)
   {
#      print "addingSimpleInputs\n";
      $simpleInputListRef = $this->{'simpleInputListRef'};
   
      # loop for all of the defined simple inputs
      foreach (@$simpleInputListRef)
      {
         $name = $_->getName();
         $value = undef;    
#print "   name = $name\n";         
         # only include this input if a value is set
         #if ($_->isValueSet())
         {
            $value = $_->getValue();
#            print "value=$value\n";
#         print "simpleInput[$index] $name=$value\n";
            $postParameters[$index]{'name'} = $name;
            $postParameters[$index]{'value'} = $value;
            $index++;
            
         }
      }
   }            
                       
   # check if there's any SELECTions
   if ($this->{'selectionListLength'} > 0)
   {
#      print "addingSelectionInputs\n";

      $selectionListRef = $this->{'selectionListRef'};
      
      # for each selection, get the name and default value    
      foreach (@$selectionListRef)
      {
         $name = $_->getName();
         if ($_->isValueSet())
         {
            $value = $_->getValue();
#         print "selection[$index] $name=$value\n";
         
         # selections are always added - either the value, the default (is set) or
         # the first item in the list
         
            $postParameters[$index]{'name'} = $name;
            $postParameters[$index]{'value'} = $value;
            $index++;
         }            
      }
   }
   
   # check if there's any CHECKBOXes
   if ($this->{'checkboxListLength'} > 0)
   {
#      print "addingCheckboxInputs\n";

      $checkboxListRef = $this->{'checkboxListRef'};
 
      # for each checkbox, get the name and default value    
      foreach (@$checkboxListRef)
      {
         $name = $_->getName();
      
         if ($_->isSelected())
         {
            $value = $_->getValue();         
            if (defined $value)
            {
#print "checkbox[$index] $name=$value\n";

               $postParameters[$index]{'name'} = $name;
               $postParameters[$index]{'value'} = $value;
               $index++;
            }
         }            
      }
   }
   
   # check if there's other inputs...
   $otherInputsHashRef = $this->{'otherInputsHashRef'};
   while(($key, $value) = each(%$otherInputsHashRef)) 
   {
      # return this key and value parameter
      if ((defined $key) && (defined $value))
      {
#         print "OtherInput[$index] $name=$value\n";
         
         $postParameters[$index]{'name'} = $name;
         $postParameters[$index]{'value'} = $value;
         $index++;
      }
   }

   $postParameters[0]{'name'} = '_internalPOSTOrder_';
   $postParameters[0]{'value'} = '';
   
   # 4 Oct 2004 - special - add parameter defining post order
   for ($index = 0; $index < $this->{'formElementListLength'}; $index++)
   {
      if ($index > 0)
      {
         $postParameters[0]{'value'} .= ",";
      }
      
      $name = $this->{'formElementListRef'}[$index];
      $postParameters[0]{'value'} .= $name;
   }

#print "STARTpostParameters:\n";  
#$index=0; 
#   foreach (@postParameters)
#   {      
#      print "$_\n";
#      print $index, " ", $$_{'name'}, "=", $$_{'value'}, "\n";
#      $index++;
#   }
#print "  ENDpostParameters:\n";   
        
   return @postParameters; 
}

# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# getSelectionOptions
# returns a list of options available for a form selection
#  retuns an array of hashes
# Purpose:
#  POSTing data to a form
#
# Parameters:
#  string search pattern for selection name
# 
# Updates:
#  method
#
# Returns:
#   reference to a list of hashes of options {value, textValue, isSelected}
#
sub getSelectionOptions
{
   my $this = shift;
   my $searchPattern = shift;
   my $foundSelection = 0;
   my $selectionIndex = 0;
      
   if ($this->{'selectionListLength'} > 0)
   {
      $selectionListRef = $this->{'selectionListRef'};
      
      # loop through all the selections in the form to check the name    
      foreach (@$selectionListRef)
      {      
         $selectionName = $_->getName();
         if ($selectionName =~ /$searchPattern/gi)
         {
            $foundSelection = 1;
            
            # get a reference to the list of options for this FormSelection
            $optionsListRef = $_->getOptionListRef();
            
            last;   
         }
         else
         {
            #try the next selection
            $selectionIndex++;
         }
      }
   }       
      
   if ($foundSelection)
   {
      return $optionsListRef;
   }
   else
   {
      return undef;
   }                                                                              
}

# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# addCheckbox
#
# Purpose:
#  defines a checkbox in the form
#
# Parameters:
#  string name for the checkbox
#  string value attribtute for the checkbox if defined
#  string text value associated with the checkbox
#  boolean isSelected
#  boolean isValueSet
# 
# Updates:
#  list of checkboxes
#
# Returns:
#   nil
#
sub addCheckbox
{
   my $this = shift;
   my $name = shift;
   my $value = shift;
   my $textValue = shift;
   my $isSelected = shift;
           
   #  add this checkbox to the list
   
   my $htmlFormCheckbox = HTMLFormCheckbox::new($name, $value, $textValue, $isSelected);
   
   # define the element in the form if not done so already... 
   $this->defineFormElement($name);   
#   print "   added checkbox($name)=$value, textValue=$textValue ($isSelected).\n";
   
   #  add this checkbox to the table element index
   $this->{'checkboxListRef'}[$this->{'checkboxListLength'}] = $htmlFormCheckbox;                                                                     
   $this->{'checkboxListLength'}++;
}


# -------------------------------------------------------------------------------------------------
# getCheckboxes
# returns a list of checkboxes available for a form
#  retuns an array of hashes
# Purpose:
#  POSTing data to a form
#
# Parameters:
#  nil
# 
# Updates:
#  method
#
# Returns:
#   reference to a list of hashes of checkboxes {name, textValue, isSelected}
#
sub getCheckboxes
{
   my $this = shift;
     
   if ($this->{'checkboxListLength'} > 0)
   {
      return $this->{'checkboxListRef'};
   }       
   else
   {
      return undef;  
   }                                                                              
}

# -------------------------------------------------------------------------------------------------
# addSimpleInput
#
# Purpose:
#  defines a simple input (eg text input) in the form
#
# Parameters:
#  string name
#  string value
#  bool isValueSet

# Updates:
#  
#
# Returns:
#   nil
#
sub addSimpleInput
{
   my $this = shift;
   my $name = shift;   
   my $value = shift;
   my $isValueSet = shift;
        
   my $htmlFormSimpleInput = HTMLFormSimpleInput::new($name, $value, $isValueSet);
  
   # define the element in the form if not done so already... 
   $this->defineFormElement($name);   
#    print "   added simple input($name)=$value ($isValueSet).\n";

   #  add this input to the simple input list
   $this->{'simpleInputListRef'}[$this->{'simpleInputListLength'}] = $htmlFormSimpleInput;                                                                     
   $this->{'simpleInputListLength'}++;
}

# -------------------------------------------------------------------------------------------------
# setInputValue
#
# Purpose:
#  sets the value of one of the form inputs
#
# Parameters:
#  string name
#  string value
#  bool isValueSet

# Updates:
#  
#
# Returns:
#   nil
#
sub setInputValue
{
   my $this = shift;
   my $name = shift;
   my $value = shift;
   my $valueSet = 0;
#print "setInputValue($name)=$value\n";
   # check if this is a simple input
   
   if ($this->{'simpleInputListLength'} > 0)
   {
      $simpleInputListRef = $this->{'simpleInputListRef'};
   
      # loop for all of the defined simple inputs
      foreach (@$simpleInputListRef)
      {
         if ($_->getName() eq $name)
         {
            $_->setValue($value);
#            print "setSimpleInput($name) = $value\n";
            $valueSet = 1;
            last;
         }
      }
   }

   # if it isn't a simple input, try the selections...
   if ((!$valueSet) && ($this->{'selectionListLength'} > 0))
   {
      $selectionListRef = $this->{'selectionListRef'};
      
      # for each selection, get the name and default value    
      foreach (@$selectionListRef)
      {
         if ($_->getName() eq $name)
         {
 #           print "setSelectionInput($name) = $value\n";
            $_->setValue($value);
            $valueSet = 1;
            last;
         }
      }
   }
   
   # if the value still isn't set, try the checkboxes...
   if ((!$valueSet) && ($this->{'checkboxListLength'} > 0))
   {
      $checkboxListRef = $this->{'checkboxListRef'};
 
      # for each checkbox, get the name and default value    
      foreach (@$checkboxListRef)
      {
         # important: both name and value must match to determine which specific checkbox 
         # should be 'selected';
         if (($_->getName() eq $name) && ($_->getValue() eq $value))
         {
            $_->setValue($value);
#            print "setCheckboxInput($name) = $value\n";
            $valueSet = 1;
            last;
         }            
      }
   }
   
   if (!$valueSet)
   {
      # this is some other value - add it to the hash
      $this->defineFormElement($name);   
      $this->{'otherInputsHashRef'}{$name} = $value;
#      print "setOtherInput($name) = $value\n";
   }
   
   return $valueSet;
}


# -------------------------------------------------------------------------------------------------
# clearInputValue
# Purpose:
#  clears a value so it's not submitted for a form 
#
# Parameters:
#  string name

# Updates:
#  inputhashref
#
# Returns:
#   nil
#
sub clearInputValue
{
   my $this = shift;
   my $name = shift;
      
#print "clearInputValue($name)\n";
   # check if this is a simple input
   
   if ($this->{'simpleInputListLength'} > 0)
   {
      $simpleInputListRef = $this->{'simpleInputListRef'};
   
      # loop for all of the defined simple inputs
      foreach (@$simpleInputListRef)
      {
         if ($_->getName() eq $name)
         {
            $_->clearValue();
#            print "clearSimpleInput($name)\n";
            $valueSet = 1;
            
         }
      }
   }

   # if it isn't a simple input, try the selections...
   if ($this->{'selectionListLength'} > 0)
   {
      $selectionListRef = $this->{'selectionListRef'};
      
      # for each selection, get the name and default value    
      foreach (@$selectionListRef)
      {
         if ($_->getName() eq $name)
         {
#            print "clearSelectionInput($name)\n";
            $_->clearValue();
            $valueSet = 1;
            
         }
      }
   }
   
   # if the value still isn't set, try the checkboxes...
   if ($this->{'checkboxListLength'} > 0)
   {
      $checkboxListRef = $this->{'checkboxListRef'};
 
      # for each checkbox, get the name and default value    
      foreach (@$checkboxListRef)
      {
         # important: both name and value must match to determine which specific checkbox 
         # should be 'selected';
         if (($_->getName() eq $name))
         {
            $_->clearSelection();
#            print "clearCheckboxInput($name)\n";
            $valueSet = 1;
            
         }            
      }
   }
   
   if (!$valueSet)
   {
      # this is some other value - add it to the hash
      delete $this->{'otherInputsHashRef'}{$name};
#      print "clearOtherInput($name)\n";
   }
   
   return $valueSet;   
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
   my @postParameters = $this->getPostParameters();
   my $unescapedString;     
   my $escapedString = '';
   my $isFirst = 1;
   
   $escapedString = escapeParameters(\@postParameters);
    
   return $escapedString;
}


# -------------------------------------------------------------------------------------------------
# escapeParameters
#
# Purpose:
#  get's the specified parameter hash into an escaped string
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
sub escapeParameters
{
   my $postParametersRef = shift;
   my $unescapedString;     
   my $escapedString = '';
   my $isFirst = 1;

   # check if the order for posting has been defined
   if ($$postParametersRef[0]{'name'} eq '_internalPOSTOrder_')
   {
      #print "**** ORDER IS DEFINED: ", $$postParametersRef[0]{'value'}, "\n";
      @postOrder = split(/\,/, $$postParametersRef[0]{'value'});  # get order list
      # iterate in the defined order
      foreach (@postOrder)
      {
         $name = $_;
         $value = undef;
         #print "name = $name\n";
         # determine if this name is defined in the post parameters (slow loop)...
         foreach (@$postParametersRef)
         {
            #print "   checking ", $$_{'name'}, "\n";
            if ($$_{'name'} eq $name)
            {
               
               $value = $$_{'value'};
#               print "X      ", $$_{'name'}, "=", $$_{'value'}, "\n";

               
               # generate the string from the value in the hash
               $escapedKey = uri_escape($name)."=".uri_escape($value);
                       
               #3Oct2004 - This is a special hack - replace %20 with + instead
               $escapedKey =~ s/\%20/+/gi;
                       
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
        
      }
   }
   else
   { 
     #print "**** ORDER IS NOT DEFINED\n";
   
      # determine if this name is defined in the post parameters (slow loop)...
      foreach (@$postParametersRef)
      {
         # generate the string from the next hash pair
         $escapedKey = uri_escape($$_{'name'})."=".uri_escape($$_{'value'});
         #3Oct2004 - This is a special hack - replace %20 with + instead
         $escapedKey =~ s/\%20/+/gi;   
                 
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
   
   #print "escapedString = $escapedString\n";
   return $escapedString;
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

