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
   
   my %inputHash;
   
   my $htmlForm = {     
      name => $name,      
      action => $action,      
      method => 'GET',
      inputHashRef => undef,
      
      # reference to a list of selection inputs
      selectionListLength => 0,
      selectionListRef => undef,
      
      # reference to a list of checkbox inputs
      checkboxListLength => 0,
      checkboxListRef => undef
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
     
   $this->{'method'} = 'GET';
}

# -------------------------------------------------------------------------------------------------
# setInputValue
#
# Purpose:
#  set a value to submit for a form
#
# Parameters:
#  string name
#  string value

# Updates:
#  method
#
# Returns:
#   nil
#
sub setInputValue
{
   my $this = shift;
   my $name = shift;
   my $value = shift;   
      
   $this->{'inputHashRef'}{$name} = $value;   
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
   print "name      : ", $this->{'name'}, "\n";
   print "action    : ", $this->{'action'}, "\n";
   print "method    : ", $this->{'method'}, "\n";
   #print "selections: ", $this->{'selectionListLength'}, "\n";
   my $inputHashRef = $this->{'inputHashRef'};     

   DebugTools::printHash("inputs", $inputHashRef);
   if ($this->{'selectionListLength'} > 0)
   {
      $selectionListRef = $this->{'selectionListRef'};
      foreach (@$selectionListRef)
      {
         print "selection: ", $_->getName();
         print " options: ", $this->{'selectionListLength'};
         if ($_->hasDefault())
         {
            print " default ='", $_->getDefaultValue(), "'";
         }
         
         print "\n";         
      }
   }
}

# -------------------------------------------------------------------------------------------------
# getPostParameters
#
# Purpose:
#  returns a hash containing the current set of parameters for the form
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
   my $inputHashRef = $this->{'inputHashRef'};     
   my $name;
   my $value;
   my %postParameters;
   
   # for each input that's defined in the form
   while(($name, $value) = each(%$inputHashRef)) 
   {     
      $postParameters{$name} = $value;            
   }
    
   # check if there's any SELECTions
   if ($this->{'selectionListLength'} > 0)
   {
      $selectionListRef = $this->{'selectionListRef'};
      
      # for each selection, get the name and default value    
      foreach (@$selectionListRef)
      {
         $name = $_->getName();
         $value = undef;         
         if ($_->hasDefault())
         {
            $value = $_->getDefaultValue();
         }   
         else
         {
            # 1 June 2004 - value is the first option in the list
            $value = $_->getFirstValue();
         }

         $postParameters{$name} = $value;            
      }
   }
           
   return %postParameters; 
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
#  string text value associated with the checkbox
#  boolean isSelected
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
   my $textValue = shift;
   my $isSelected = shift;
           
   #  add this checkbox to the list
   
   my $htmlFormCheckbox = HTMLFormCheckbox::new($name, $textValue, $isSelected);
   
    #  add this selection to the table element index
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
