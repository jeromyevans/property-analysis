#!/usr/bin/perl
# Written by Jeromy Evans
# Started 21 February 2004
# 
# WBS: A.01.01.02 Developed HTML Parser
# Version 0.1  22 February 2004 - almost complete except for handling of the 
#  callback function for traverse as the callback isn't instance-specific. It has to 
#  use a package global variable that will cause problems under concurrency.
# Verion 0.11  9 March 2004 - fixed a bug in getNextTextAfterTag that was attempting to use
#  textElementIndexRef for an element of type TAG (which is never set). 
#  also fixed a problem in the callback that replaced ALL non text characters (including
#  punctuation) instead of non-text/punctuation characters (eg. deleted percent, brackets etc.
#  Now just eliminates a range on non-text ascii.
#  Also added getNextText for getting the next text element after the last successful search
#   position.  Had to modify most functions that set lastFoundIndex to point to the corresponding
#   index of the next/previous text element (instead of the actual element where appropriate) to prevent
#   the same text element from being retreived again
# Version 0.12 14 March 2004 - Modified callback to strip leading and trailing whitespace from
#   text
# Version 0.13 31 March 2004 - Added new boolean key to the hash called startAtLastFoundIndex that
#   is set by the setStartSearchContraint methods after setting the lastFoundIndex.  All other 
#   functions that set lastFoundIndex must clear startAtLastFoundIndex.  The boolean flag is used
#   by methods that iterate from the lastFoundIndex.  Normally iteration starts at lastFound+1 except
#   when the flag is set, in which case iteration starts at lastFound.  Necessary to get the first
#   text after a constaint.
# Version 0.14 1 April 2004 - Added GetNextTextContainingPattern for extracting a text element
#   that contains the specified pattern.  
#                           - Added a method to set a search contraint to a table.  During paring the 
#   start and end index of each table is indexed 
#                           - Fixed bug in SetSearchStartConstraintByTag that attempted to directly
#   reference the text element list from a non text element.  Replaced with search iteration  
# already used in getNextTextAfterTag
#                           - Fixed bug in SetSearchEndConstraintByTag that attempted to directly
#   reference the text element list from a non text element. Replaced with search iteration  
# already used in getNextTextAfterTag (but backwards)
#
# Version 0.15 - added support for forms
#              - added support for frames
# Version 0.16 - modified so each element of the anchorlist is a hash containing
#                  elementIndex, textListLength, textListRef
#                   elementIndex is the index of the element in the SyntaxTree corresponding
#  to the anchor (as per earlief versions)
#              - added function getNextAnchorContainingPattern - examines the content of
#  a tag to see if it contains text matching the pattern and returns the URL if it does
#              - added function getAnchorSContainingPattern - returns a list of anchors
#  with text matching the specified pattern (or if no pattern specified, returns list of
#  anchors containing text (rather than images, etc))
#              - extended anchorlist so it includes a imgListLength and imgListRef for
#  images within the anchor
#              - added function getNextAnchorContainingImageSrc to obtain a list of
#  anchors containing an image matching the specified source
# Version 0.17 - added getAnchorsAndTextContainingPattern that's the same as 
#  GetAnchorsContainingPattern but returns the anchor and pattern in a hash list. Implemented
#  for extracting pertinent information from the link text rather than the URL.
# 23 May 2004 - if a checkbox is encountered in a form, it's now ignored unless
#   the selected attribute is set
#
# Description:
#   Module that accepts an HTTP::Response and runs a parser (HTTP:TreeBuilder)
# over it to generate a SyntaxTree object.  The SyntaxTree class is designed for 
# fast searching of the HTML content (text and tags).  
#
# CONVENTIONS
# _ indicates a private variable or method
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
package HTMLSyntaxTree;
require Exporter;
use HTML::TreeBuilder;
use HTMLForm;

@ISA = qw(Exporter);

#@EXPORT = qw(&parseContent);

# -------------------------------------------------------------------------------------------------
# PUBLIC enumerations
#
($TAG, $TEXT, $TOP)  = (0, 1, 2);

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

my ($currentInstance) = undef;

# -------------------------------------------------------------------------------------------------

# Contructor for the HTMLSyntaxTree - returns an instance of an HTMLSyntaxTree object
# PUBLIC
sub new
{     
   my $htmlSyntaxTree = {

      # list of all the elements in the HTMLSyntaxTree. Populated during parsing.
      # each node in the list is a reference to a HTMLElement hash
      elementListRef => undef,
      elementListLength => 0,

      # index pointing to the text-only elements in the HTMLSyntaxTree.  Populated during parsing, 
      # used to increase search speed.  Array of indexes into the @elementList
      #  string
      textElementIndexRef => undef,
      textElementIndexLength => 0,

      # index pointing to the ANCHOR elements in the HTMLSyntaxTree.  Populated during parsing, 
      # used to increase search speed (array of indexes into the @elementList)
      anchorElementIndexRef => undef,
      anchorElementIndexLength => 0,
      _insideAnchor => 0,
      
      # index pointing to the TABLE elements in the HTMLSyntaxTree.  Populated during parsing, 
      # used to increase search speed (array of indexes into the @elementList)
      tableElementIndexRef => undef,
      tableElementIndexLength => 0,

      # these integers are used to identify the constraints for performing searches in the
      # elementList.  A search will only start from this index.  
      # Controlled by the setSearchStartConstraint & setSearchEndConstraint methods
      searchStartIndex => 0,
      searchEndIndex => 0,
      lastFoundIndex => 0,
      startAtLastFoundIndex => 0,    
      
      # reference to list of HTMLForm objects
      htmlFormListLength => 0,
      htmlFormListRef => undef,
      
      # reference to a list of frame URLs
      frameListLength => 0,
      frameListRef => undef
   };  
   bless $htmlSyntaxTree;    # make it an object of this class
   
   _initialiseSyntaxTree($htmlSyntaxTree);
   
   return $htmlSyntaxTree;   # return it
}

# -------------------------------------------------------------------------------------------------

# instance method to initialise an object's instance
# creates the first element of the SyntaxTree with the name 'document'
# PRIVATE - used by the contructor
sub _initialiseSyntaxTree

{
   my $this = shift;
   my @frameList;
   my @formList;
   
   # initialise the first element of the elementList
   $this->{'elementListRef'}[0] = 
   {   
      type => $TOP,      
      tag => "", 
      string => "document",  # TEXT and TOP only
      elementRef => undef,   # TAG only - reference to HTML::Element
      listIndex => 0,
      href => undef          # ANCHOR TAG only
   }; 
   
   $this->{'elementListLength'}++;   
}

# -------------------------------------------------------------------------------------------------

# Instance method that accepts a string of content received in an HTTP response
# and constructs the SyntaxTree representing it
# PUBLIC
sub parseContent
{
   my $this = shift;     # get this object's instance (always the first parameter)
   my $content = shift;  # get the content of the HTTP response
   
   my $treeBuilder = HTML::TreeBuilder->new();   
   
   $treeBuilder->parse($content);
      
   # the currentInstance is used by the callback function as the callback
   # isn't within this object instance 
   # TODO 22/2/04 this will cause problems under multithreading - instead need
   # to create an instance of the callback for this object instance   
   $_currentInstance = $this;   

   # start traversing the tags in the document
   $treeBuilder->traverse(\&_treeBuilder_callBack, 0);
   
   #print "   TotalElements: ", $this->{'elementListLength'}, "\n";
   #print "   TextElements: ", $this->{'textElementIndexLength'}, "\n";
   #print "   AnchorElements: ", $this->{'anchorElementIndexLength'}, "\n";
   #print "   TotalFrames: ", $this->{'frameListLength'}, "\n";
   #print "   TotalForms:", $this->{'htmlFormListLength'}, "\n";
   
   # loop through all of the elements in the page
   # (note a forloop is used here instead of foreach because 
   # we don't need $_ to match the element in the list)
   #for ($listIndex = 0; $listIndex < $this->{'elementListLength'}; $listIndex++)
   #{      
   #   print $listIndex,":", $this->{'elementListRef'}[$listIndex]{'tag'},"\n";
   #}
   #print "Displaying forms...(", $this->{'htmlFormListLength'}, ")\n";
   #$htmlFormListRef = $this->{'htmlFormListRef'};
   #if ($htmlFormListRef)
   #{   
   #   for ($i = 0; $i < $this->{'htmlFormListLength'}; $i++)
   #   {
   #      $htmlForm = $this->{'htmlFormListRef'}[$i];       
   #      $htmlForm->printForm();
   #   }
   #}
   
   return 1;
}

# -------------------------------------------------------------------------------------------------
# call back function for the tree builder traverse operation.  This method is called once for
# each element in HTML content
# accepts an HTML::Element, boolean startFlag and a integer depth
# PRIVATE
sub _treeBuilder_callBack
{
   my $currentElement = shift;  # reference to HTML::Element, or just a string
   my $startFlag = shift;    # true if entering an element
   my $depth = shift;        # depth within the tree
   my $isTag = 1;
   my $traverseChildElements = 1;
   my $href = undef;         # set for anchors
   my $tagName;
   my $textIndex;
   
   # TODO 22/2/04 this will cause problems under multithreading - instead need
   # to create an instance of the callback for this object instance (this is sharing
   # a global variable for this package)
   my $this = $_currentInstance;

   # first thing to do is query the reference to determine if this
   # is a tag or text
   if (!ref($currentElement))
   {
      # this isn't an element reference - it's actual text
      $isTag = 0;      
   }
   
   if ($isTag)
   {
      # this element is a tag...
      #   record the tag name, a reference to the HTML::Element and the current index
      
      # special case handling:
      # - if the element is a SCRIPT, do not proceed into it's children
      if ($currentElement->tag() eq "script")
      {
         $traverseChildElements = 0;        # DO NOT traverse children
      }
      else
      {
         # special case handling:
         # - if this is an anchor, add it to the anchor list index
         # (only for the opening of the anchor, not the closing tag)
         if ($currentElement->tag() eq "a")
         {
            if ($startFlag)
            {
               # also add this element to the anchor element index
               $this->{'anchorElementIndexRef'}[$this->{'anchorElementIndexLength'}]{'elementIndex'} = $this->{'elementListLength'};
               # no text or image associated with this anchor yet...
               $this->{'anchorElementIndexRef'}[$this->{'anchorElementIndexLength'}]{'textListLength'} = 0;
               $this->{'anchorElementIndexRef'}[$this->{'anchorElementIndexLength'}]{'imgListLength'} = 0;                          
            
               $href = $currentElement->attr("href"); # used later
             
               $this->{'anchorElementIndexLength'}++;
             
               # the _insideAnchor flag is used for very basic tracking of the content
               # of a tag.  When the flag is set, all text encountered up
               # until the end of the tag is recording in the tag record
               # to increase speed searching for an anchor via the text
               # NOTE: NESTED TAGs will break this
               $this->{'_insideAnchor'} = 1;
               
            }
            else
            {
               # this is the end marker for a tag - clear the in tag flag
               $this->{'_insideAnchor'} = 0;
            }
         }
         else
         {
            # - if this is a table, add it to the table list index            
            if (($currentElement->tag() eq "table") && ($startFlag))
            {
               if ($startFlag)
               {                  
                  # this is the start position for a new table
                  #  add this element to the table element index
                  $this->{'tableElementIndexRef'}[$this->{'tableElementIndexLength'}] = $this->{'elementListLength'};                          
                                           
                  $this->{'tableElementIndexLength'}++;
               }              
            }
            
            # - if this is a form, create a form attached to this syntax tree
            if (($currentElement->tag() eq "form") && ($startFlag))
            {
               if ($startFlag)
               {           
                  # get the action attr for the target address
                  $action = $currentElement->attr('action');                  
                  $name = $currentElement->attr('name');
                  
                  #print "creating HTMLForm '$name'\n";
                  
                  $htmlForm = HTMLForm::new($name, $action);
                  
                  if ($method = $currentElement->attr('method'))
                  {
                     # check if the method is set to post
                     if ($method =~ /POST/i)
                     {
                        $htmlForm->setMethod_POST();
                     }
                  }  
                  
                  # add the HTML form to the end of the form list
                                                                                                                           
                  # add the frame address to the list                     
                  $this->{'htmlFormListRef'}[$this->{'htmlFormListLength'}] = $htmlForm;                   
                  $this->{'htmlFormListLength'}++;                                                                                    
                                                                                                                                                                                           
               }              
            }
            
            # if this is a form input, add it to the form attached to the
            # syntax tree
            if (($currentElement->tag() eq "input") && ($startFlag))
            {               
               if ($startFlag)
               {           
                  # check if the HTML form is defined            
                  if ($this->{'htmlFormListRef'})                  
                  {                                                                    
                     $type = $currentElement->attr('type');
                     $value = $currentElement->attr('value');
                     $name = $currentElement->attr('name');
                     
                     # if the type is submit ignore it
                     if ($type =~ /SUBMIT/i)
                     {
                        $name = undef;
                     }
                     # if the type is reset ignore it
                     if ($type =~ /RESET/i)
                     {
                        $name = undef;
                     }     
                     
                     # if the type is checkbox...
                     if ($type =~ /CHECKBOX/i)
                     {
                        # it it's not selected, ignore it
                        if (!defined $currentElement->attr('selected'))
                        {
                           $name = undef;
                        }
                     }     
                     
                     
                     # if the type is reset, then ignore it
                     
                     if ($name)
                     {
                        #print "input $name=$value\n";
                        $this->{'htmlFormListRef'}[$this->{'htmlFormListLength'}-1]->setInputValue($name, $value);
                     }
                  }                                                                                                                       
               }              
            }
            
            # if this is a form selection, add it to the form attached to the
            # syntax tree
            if (($currentElement->tag() eq "select") && ($startFlag))
            {               
               if ($startFlag)
               {           
                  # check if the HTML form is defined                                    
                  if ($this->{'htmlFormListRef'})                  
                  {                                                                                         
                     $name = $currentElement->attr('name');                                                               
                     
                     if ($name)
                     {
                        $this->{'htmlFormListRef'}[$this->{'htmlFormListLength'}-1]->addFormSelection($name);                     
                     }
                  }                                                                                                                       
               }              
            }
            
            # if this is a form option for a selection, add it to the form attached to the
            # syntax tree
            if (($currentElement->tag() eq "option") && ($startFlag))
            {               
               if ($startFlag)
               {           
                  # check if the HTML form is defined                                    
                  if ($this->{'htmlFormListRef'})                  
                  {    
                     # if the value attribute is set, use this
                     $value = $currentElement->attr('value');
                                          
                     # the next text element of this tag is the value                                                                                     
                     $tagContent = $currentElement->content();
                     $textValue = '';
                     foreach (@$tagContent)
                     {
                        # check if this is a reference to a structure
                        # (ie. a tag) or just text
                        if (!ref($_))
                        {
                           #this is text
                           $textValue = $_;
                        }
                     }
                     
                     $selected = $currentElement->attr('selected');
                     
                     if ($selected =~ /selected/i)
                     {
                        $isSelected = 1;
                     }
                     else
                     {
                        $isSelected = 0;
                     }
                      
                     #print "adding option '$value' isSelected='$isSelected'\n";                     
                     $this->{'htmlFormListRef'}[$this->{'htmlFormListLength'}-1]->addSelectionOption($value, $textValue, $isSelected);                                         
                  }                                                                                                                       
               }              
            }
            
            # if this is a frame, add it to the frame list
            if (($currentElement->tag() eq "frame") && ($startFlag))
            {               
               if ($startFlag)
               {                     
                  $frameListRef = $this->{'frameListRef'};        
                                                      
                  $source = $currentElement->attr('src');
                     
                  # add the frame address to the list                     
                  $this->{'frameListRef'}[$this->{'frameListLength'}] = $source;                   
                  $this->{'frameListLength'}++;                                                                                                                                                                                        
               }              
            }
            
            # if this is an image, check whether it's inside an anchor
            if (($currentElement->tag() eq "img") && ($startFlag))
            {     
               # save the URL to the image for this tag                              
               $href = $currentElement->attr("src"); # used later
                                          
               # if currently inside a tag, record this image element index against 
               # the tag element
               if ($this->{'_insideAnchor'})
               {           
                  # add this element to the anchor's text element list           
                  $imgListLength = $this->{'anchorElementIndexRef'}[$this->{'anchorElementIndexLength'}-1]{'imgListLength'};
                  $this->{'anchorElementIndexRef'}[$this->{'anchorElementIndexLength'}-1]{'imgListRef'}[$imgListLength] = $this->{'elementListLength'};
           
                  # and increase the length of the list of img elements associated with the anchor
                  $this->{'anchorElementIndexRef'}[$this->{'anchorElementIndexLength'}-1]{'imgListLength'}++;                                               
               }                                                                                                                                                                                                                              
            }
         }
      }         
       
      # if this is an end-tag, add the slash in front of it
      if ($startFlag)
      {
         $tagName = $currentElement->tag();
      }
      else
      {
         $tagName = "/".$currentElement->tag();         
      }
      
      # the a reference to the content of this tage                                                                                     
      $tagContent = $currentElement->content();
      
      # record the tag information used for searching
      $this->{'elementListRef'}[$this->{'elementListLength'}] = 
      {   
         type => $TAG,      
         tag => $tagName,
         elementRef => $currentElement, 
         href => $href,
         listIndex => $this->{'elementListLength'},
         content => $tagContent
      };                     
   }
   else
   {
      # this element is text...
       
      # replace non-text ASCII characters with white-space
      # (character 0 to 31, 128 to 255)
      #$currentElement =~ s/\W/ /g;
      $currentElement =~ s/[\x80-\xff\x00-\x1f]/ /g;
      
      # --- remove leading and trailing whitespace ---
      # substitute trailing whitespace characters with blank
      # s/whitespace from end-of-line/all occurances
      # s/\s*$//g;      
      $currentElement =~ s/\s*$//g;

      # substitute leading whitespace characters with blank
      # s/whitespace from start-of-line,multiple single characters/blank/all occurances
      #s/^\s*//g;    
      $currentElemnt =~ s/^\s*//g;   
      
      # check if the element is non-blank (contains at least one non-whitespace character)
      # TODO: This needs to be optimised - shouldn't have to do a substitution to 
      # work out if the string contains non-blanks
      $testForNonBlanks = $currentElement;
      $testForNonBlanks =~ s/\s*//g;         
      if ($testForNonBlanks)
      {
        # only add non-blank text elements to the text index
        $textIndex = $this->{'textElementIndexLength'};
        
        # also add this element to the text element index
        $this->{'textElementIndexRef'}[$this->{'textElementIndexLength'}] = $this->{'elementListLength'};           
        
        $this->{'textElementIndexLength'}++;

        # if currently inside a tag, record this text element index against 
        # the tag element
        if ($this->{'_insideAnchor'})
        {
           
           # also add this element to the anchor's text element list           
           $textListLength = $this->{'anchorElementIndexRef'}[$this->{'anchorElementIndexLength'}-1]{'textListLength'};
           $this->{'anchorElementIndexRef'}[$this->{'anchorElementIndexLength'}-1]{'textListRef'}[$textListLength] = $this->{'elementListLength'};
           
           # and increase the length of the list of text elements associated with the anchor
           $this->{'anchorElementIndexRef'}[$this->{'anchorElementIndexLength'}-1]{'textListLength'}++;
           #print "_insideAnchor: adding text '$currentElement' (anchor ", $this->{'anchorElementIndexLength'}-1, "listLen=",$this->{'anchorElementIndexRef'}[$this->{'anchorElementIndexLength'}-1]{'textListLength'}, ")\n";
        }
      }
      else
      {
         $textIndex = 0;
      }
      
      #  record the text, a reference to the HTML::Element and the current index
      # NOTE: the index in the textElementIndex is recorded to support jumping forward
      # and backwards one text element at a time
      $this->{'elementListRef'}[$this->{'elementListLength'}] = 
      {   
         type => $TEXT,      
         tag => undef,
         string => $currentElement,           
         listIndex => $this->{'elementListLength'},
         textElementIndex => $textIndex
      };                   
      
   }    
  
   # count the number of elements encountered
   $this->{'elementListLength'}++;
   # increment the search end index so the first search is unconstrained
   $this->{'searchEndIndex'}++;
     
   return $traverseChildElements;    
}


# -------------------------------------------------------------------------------------------------
# searches the syntax tree for a string matching the specified search expression and
# returns TRUE if it's found.  Search is case insensitive
# 
# Purpose:
#  Quick document content validation (ie. contains text matching ...)
#
# Parameters:
#  STRING searchPattern
#
# Constraints:
#  $this->{'searchStartIndex'}
#  $this->{'searchEndIndex'}
#
# Updates:
#  $this->{'lastFoundIndex'} to the matching elementList index if FOUND
#
# Returns:
#   TRUE (1) if found, FALSE (0) is not found
#
 
sub containsTextPattern

{
   my $this = shift; # get this object's instance (always the first parameter)
   my $searchPattern = shift;   
   my $found = 0;
   my $textIndex;
         
   # loop through all of the text elements in the page      
   for ($textIndex = 0; $textIndex < $this->{'textElementIndexLength'}; $textIndex++)   
   {   
      # this is a bit of a hack because foreach couldn't be used on the
      # textElementIndexRef.  Get the current index into the elementList
      $_ = $this->{'textElementIndexRef'}[$textIndex];      
      
      # only search within the bounds of the search constraints
      if ($_ >= $this->{'searchStartIndex'})
      {
         if ($_ <= $this->{'searchEndIndex'})         
         {                    
            # check if this text element contains the search pattern...         
            if ($this->{'elementListRef'}[$_]{'string'} =~ /$searchPattern/gi)
            {         
               # found a match
               $found = 1;         
               $this->{'lastFoundIndex'} = $_;
               
               $this->{'startAtLastFoundIndex'} = 0;
               last;  # break out of the foreach loop
            }
         }
         else
         {
            # gone further than the end of the search constraint - break out now
            last;
         }
      }      
   }
   
   return $found;
}

# -------------------------------------------------------------------------------------------------
# sub setSearchStartConstraintbyText
# sets the search start constraint to start on the TEXT ELEMENT AFTER the element with text 
# matching the specified searchPattern
#
# returns TRUE if constraint element found.  Search is case insensitive
# 
# Purpose:
#  Preparation for search
#
# Parameters:
#  STRING searchPattern
#
# Constraints:
#  $this->{'searchStartIndex'}
#  $this->{'searchEndIndex'}
#
# Updates:
#  $this->{'searchStartIndex'} to the text element after the matching elementList index if FOUND
#  $this->{'lastFoundIndex'} to the matching elementList index if FOUND
#
# Returns:
#   TRUE (1) if found, FALSE (0) is not found
#
 
sub setSearchStartConstraintByText

{
   my $this = shift; # get this object's instance (always the first parameter)
   my $searchPattern = shift;   
   my $found = 0;   
   my $sourceTextIndex;
   my $nextTextIndex;
   my $textIndex;
         
   # loop through all of the text elements in the page      
   for ($textIndex = 0; $textIndex < $this->{'textElementIndexLength'}; $textIndex++)   
   {   
      # this is a bit of a hack because foreach couldn't be used on the
      # textElementIndexRef.  Get the current index into the elementList
      $_ = $this->{'textElementIndexRef'}[$textIndex];                  
      
      # only search within the bounds of the search constraints
      if ($_ >= $this->{'searchStartIndex'})
      {
         if ($_ <= $this->{'searchEndIndex'})         
         {      
            # check if this text element contains the search pattern...
            if ($this->{'elementListRef'}[$_]{'string'} =~ /$searchPattern/gi)
            {         
               # found a match
               $found = 1;         
               
               # need to set the searchStartIndex to the next TEXT element in 
               # the element list - this is found through the textElementIndex            
               # (get the index of this element in the textElementIndex, and obtain
               # the index of the next text element from there)                                              
               $sourceTextIndex = $this->{'elementListRef'}[$_]{'textElementIndex'};              
               $nextTextIndex = $this->{'textElementIndexRef'}[$sourceTextIndex+1];                 
               $this->{'searchStartIndex'} = $nextTextIndex;
               
               # record the index where this item was found
               $this->{'lastFoundIndex'} = $nextTextIndex;
               
               $this->{'startAtLastFoundIndex'} = 1;
   
               last;  # break out of the foreach loop               
            }
         }
         else
         {
            # gone further than the end of the search constraint - break out now
            last;
         }         
      }      
   }
   
   return $found;
}

# -------------------------------------------------------------------------------------------------
# sub setSearchEndConstraintbyText
# sets the search end constraint to end on the TEXT ELEMENT BEFORE the element with text 
# matching the specified searchPattern
# returns TRUE if constraint element found.  Search is case insensitive
# 
# Purpose:
#  Preparation for search
#
# Parameters:
#  STRING searchPattern
#
# Constraints:
#  $this->{'searchStartIndex'}
#  $this->{'searchEndIndex'}
#
# Updates:
#  $this->{'searchEndIndex'} to the text element before the matching elementList index if FOUND
#  $this->{'lastFoundIndex'} to the matching elementList index if FOUND
#
# Returns:
#   TRUE (1) if found, FALSE (0) is not found
#
 
sub setSearchEndConstraintByText

{
   my $this = shift; # get this object's instance (always the first parameter)
   my $searchPattern = shift;   
   my $found = 0;
   my $sourceTextIndex;
   my $previousTextIndex;
   my $textIndex;
         
   # loop through all of the text elements in the page      
   for ($textIndex = 0; $textIndex < $this->{'textElementIndexLength'}; $textIndex++)   
   {   
      # this is a bit of a hack because foreach couldn't be used on the
      # textElementIndexRef.  Get the current index into the elementList
      $_ = $this->{'textElementIndexRef'}[$textIndex];
      
      # only search within the bounds of the search constraints
      if ($_ >= $this->{'searchStartIndex'})
      {
         if ($_ <= $this->{'searchEndIndex'})         
         {         
            # check if this text element contains the search pattern...
            if ($this->{'elementListRef'}[$_]{'string'} =~ /$searchPattern/gi)
            {         
               # found a match
               $found = 1;         
               
               # need to set the searchEndIndex to the previous TEXT element in 
               # the element list - this is found through the textElementIndex            
               # (get the index of this element in the textElementIndex, and obtain
               # the index of the previous text element from there) 
               $sourceTextIndex = $this->{'elementListRef'}[$_]{'textElementIndex'};
               $previousTextIndex = $this->{'textElementIndexRef'}[$sourceTextIndex-1];               
               $this->{'searchEndIndex'} = $previousTextIndex;
                              
               # record the index where this item was found
               #$this->{'lastFoundIndex'} = $previousTextIndex;               
               last;  # break out of the foreach loop
            }
         }
         else
         {
            # gone further than the end of the search constraint - break out now
            last;
         }
      }
   }
   
   return $found;
}

# -------------------------------------------------------------------------------------------------
# sub resetSearchConstraints
# sets the search start and end constraints to the start and end of the document
# 
# Purpose:
#  Preparation for search
#
# Parameters:
#  nil
#
# Constraints:
#  nil
#
# Updates:
#  $this->{'searchStartIndex'} to zero
#  $this->{'searchEndIndex'} to last element in elementList
#
# Returns:
#   TRUE (1) 
#
 
sub resetSearchConstraints

{
   my $this = shift;
   
   $this->{'searchStartIndex'} = 0;
   $this->{'searchEndIndex'} = $this->{'elementListLength'}-1;
}


# -------------------------------------------------------------------------------------------------
# sub setSearchStartConstraintByTag
# sets the search start constraint to start on the TEXT ELEMENT AFTER the element with tag 
# matching the specified searchPattern
#
# returns TRUE if constraint element found.  Search is case insensitive
# 
# Purpose:
#  Preparation for search
#
# Parameters:
#  STRING searchPattern
#
# Constraints:
#  $this->{'searchStartIndex'}
#  $this->{'searchEndIndex'}
#
# Updates:
#  $this->{'searchStartIndex'} to the text element after the matching elementList index if FOUND
#  $this->{'lastFoundIndex'} to the matching elementList index if FOUND
#
# Returns:
#   TRUE (1) if found, FALSE (0) is not found
#
 
sub setSearchStartConstraintByTag

{
   my $this = shift; # get this object's instance (always the first parameter)
   my $searchPattern = shift;   
   my $found = 0;
   my $textIndex;
   my $nextTextIndex;
   my $textString;
   my $listIndex;
   my $getNextTextFlag = 0;
      
   # loop through all of the elements in the page
   # (note a forloop is used here instead of foreach because 
   # we don't need $_ to match the element in the list)
   for ($listIndex = 0; $listIndex < $this->{'elementListLength'}; $listIndex++)
   {      
      # only search within the bounds of the current search constraints
      if ($listIndex > $this->{'searchStartIndex'})
      {
         if ($listIndex <= $this->{'searchEndIndex'})         
         { 
            # the getNextTextFlag is used to control the search loop
            # whether it's looking for a tag or the text following it            
            if (!$getNextTextFlag)
            {
               # check if this tag element contains the search pattern...         
               if ($this->{'elementListRef'}[$listIndex]{'tag'} =~ /$searchPattern/gi)
               {         
                  # found a match
                  $found = 1;         
                       
                  # need to get the next TEXT element in 
                  # the element list - this is found by continuing the iteration until 
                  # the next text (as there's no index to the next element that's text)  
                  # NOTE: This algorithm could be optimised by recording an index to the 
                  # next text when constructing the syntaxTree
                  $getNextTextFlag = 1;                                                    
               }
            }
            else
            {        
               # check if this element is the next text...         
               if ($this->{'elementListRef'}[$listIndex]{'type'} == $TEXT)
               {         
                  # found a match
                  $found = 1;         
                
                  $this->{'searchStartIndex'} = $listIndex;               
                  $this->{'lastFoundIndex'} = $listIndex;
               
                  $this->{'startAtLastFoundIndex'} = 1;
                  last;  # break out of the foreach loop               
               }
            }                                
         }
         else
         {
            # gone further than the end of the search constraint - break out now
            last;
         }
      }      
   }
 
   return $found;      
}

# -------------------------------------------------------------------------------------------------
# sub setSearchEndConstraintByTag
# sets the search end constraint to end on the TEXT ELEMENT BEFORE the element with text 
# matching the specified searchPattern
# returns TRUE if constraint element found.  Search is case insensitive
# 
# Purpose:
#  Preparation for search
#
# Parameters:
#  STRING searchPattern
#
# Constraints:
#  $this->{'searchStartIndex'}
#  $this->{'searchEndIndex'}
#
# Updates:
#  $this->{'searchEndIndex'} to the text element before the matching elementList index if FOUND
#  $this->{'lastFoundIndex'} to the matching elementList index if FOUND
#
# Returns:
#   TRUE (1) if found, FALSE (0) is not found
#
sub setSearchEndConstraintByTag

{
   my $this = shift; # get this object's instance (always the first parameter)
   my $searchPattern = shift;   
   my $found = 0;
   my $textIndex;
   my $nextTextIndex;
   my $textString;
   my $listIndex = 0;
   my $getPreviousTextFlag = 0;
   my $foundIndex = 0;
      
   # loop through all of the elements in the page
   # (note a forloop is used here instead of foreach because 
   # we don't need $_ to match the element in the list)
   for ($listIndex = 0; $listIndex < $this->{'elementListLength'}; $listIndex++)
   {      
      # only search within the bounds of the current search constraints
      if ($listIndex >= $this->{'searchStartIndex'})
      {
         if ($listIndex <= $this->{'searchEndIndex'})         
         {                           
            # check if this text element contains the search pattern...         
            if ($this->{'elementListRef'}[$listIndex]{'tag'} =~ /$searchPattern/gi)
            {         
               # found a match                     
               $foundIndex = $listIndex;
                       
               # need to get the next TEXT element in 
               # the element list - this is found by continuing the iteration until 
               # the next text (as there's no index to the next element that's text)  
               # NOTE: This algorithm could be optimised by recording an index to the 
               # next text when constructing the syntaxTree
               $getPreviousTextFlag = 1;
               last;                                                                  
            }               
         }
         else
         {
            # gone further than the end of the search constraint - break out now
            last;
         }
      }      
   }
   
   if ($getPreviousTextFlag)
   {
      # loop through the elements of the page in reverse
      # (note a forloop is used here instead of foreach because 
      # we don't need $_ to match the element in the list)
      for ($listIndex = $foundIndex; $listIndex >= $this->{'searchStartIndex'}; $listIndex--)
      {      
           
         # check if this element is the previous TEXT...         
         if ($this->{'elementListRef'}[$listIndex]{'type'} == $TEXT)
         {         
            # found a match
            $found = 1;         
                             
            $this->{'searchEndIndex'} = $listIndex;
            #$this->{'lastFoundIndex'} = $previousTextIndex;
                  
            last;  # break out of the foreach loop            
         }
      }
   }
 
   return $found;      
}

# -------------------------------------------------------------------------------------------------
# sub setSearchConstraintsbyTable
# sets the search start (and end) constraints to boundary of the specified table number
# NOTE: haven't implemented end contraint yet - sets it to the last element in the page

# returns TRUE if table found.  
# 
# Purpose:
#  Preparation for search
#
# Parameters:
#  int TableNumber [0..n]
#
# Constraints:
#  $this->{'searchStartIndex'}
#  $this->{'searchEndIndex'}
#
# Updates:
#  $this->{'searchStartIndex'} to the text element after the matching elementList index if FOUND
#  $this->{'lastFoundIndex'} to the matching elementList index if FOUND
#
# Returns:
#   TRUE (1) if found, FALSE (0) is not found
#
 
sub setSearchConstraintsByTable

{
   my $this = shift; # get this object's instance (always the first parameter)
   my $tableNumber = shift;   
   $found = 0;
  
   if ($tableNumber < $this->{'tableElementIndexLength'})
   {
      $this->resetSearchConstraints();
      # point to next element after the start of the table
      $this->{'searchStartIndex'} = $this->{'tableElementIndexRef'}[$tableNumber]+1;      
      $this->{'lastFoundIndex'} = $this->{'searchStartIndex'};               
      $this->{'startAtLastFoundIndex'} = 0;
      $found = 1;
   }
   
   return $found;
}


# -------------------------------------------------------------------------------------------------
# sub getAnchors
# returns a list of anchors within the search constraints
# 
# Purpose:
#  Parsing file
#
# Parameters:
#  nil
#
# Constraints:
#  $this->{'searchStartIndex'}
#  $this->{'searchEndIndex'}
#
# Updates:
#  nil
#
# Returns:
#   reference to @anchorList of HREFs (href's) or UNDEF
#
 
sub getAnchors

{
   my $this = shift; # get this object's instance (always the first parameter)  
      
   my @anchorList = undef;
   my $anchorsFound = 0;   
   my $anchorIndex;
         
   # loop through all of the anchor elements in the page      
   for ($anchorIndex = 0; $anchorIndex < $this->{'anchorElementIndexLength'}; $anchorIndex++)   
   {   
      # this is a bit of a hack because foreach couldn't be used on the
      # anchorElementIndexRef.  Get the current index into the elementList
      $_ = $this->{'anchorElementIndexRef'}[$anchorIndex]{'elementIndex'};
                      
      # only search within the bounds of the search constraints
      if ($_ >= $this->{'searchStartIndex'}) 
      {
         if ($_ <= $this->{'searchEndIndex'})         
         {         
            # add this anchor to the anchor list
            $anchorList[$anchorsFound] = $this->{'elementListRef'}[$_]{'href'};                       
            $anchorsFound++;
         }
         else
         {
            # gone further than the end of the search constraint - break out now
            last;
         }
      }
   }              
   
   if ($anchorsFound > 0)
   {
      return \@anchorList;      
   }
   else
   {      
      return undef;
   }
}

# -------------------------------------------------------------------------------------------------
# sub getAnchorsContainingPattern
# returns a list of anchors within the search constraints that contain the pattern
#  (if pattern is undef, returns all anchors containing text)
# 
# Purpose:
#  Parsing file
#
# Parameters:
#  STRING searchPattern
#
# Constraints:
#  $this->{'searchStartIndex'}
#  $this->{'searchEndIndex'}
#
# Updates:
#  nil
#
# Returns:
#   reference to list of url's
#
 
sub getAnchorsContainingPattern

{
   my $this = shift; # get this object's instance (always the first parameter)
   my $searchPattern = shift;
         
   my $url = undef;       
   my $elementIndex;
   my @anchorList = undef;
   my $anchorsFound = 0;   
   my $anchorIndex;
   
   # loop through all of the anchor elements in the page      
   for ($anchorIndex = 0; $anchorIndex < $this->{'anchorElementIndexLength'}; $anchorIndex++)   
   {   
      # this is a bit of a hack because foreach couldn't be used on the
      # anchorElementIndexRef.  Get the current index into the elementList
      $_ = $this->{'anchorElementIndexRef'}[$anchorIndex]{'elementIndex'};
                      
      # only search within the bounds of the search constraints
      if ($_ >= $this->{'searchStartIndex'}) 
      {
         if ($_ <= $this->{'searchEndIndex'})         
         { 
            # this flag is used to indicate that it's not necessary to 
            # keep processing the content of this tag (because a match
            # has already been made)
            $finishedThisTag = 0;
            $elementIndex = $_;
            
            # check if this tag contains any text elements  
            $textListLength = $this->{'anchorElementIndexRef'}[$anchorIndex]{'textListLength'};
            if ($textListLength > 0)
            {              
               # loop for all of the text elements
               $listRef = $this->{'anchorElementIndexRef'}[$anchorIndex]{'textListRef'};
               #print "textListRef: $listRef\n"; 
               foreach (@$listRef)
               {
                  # $_ is a reference to a text element
                  if (!$finishedThisTag)
                  {                                                           
                     # see if this text it contains the pattern   
                     # $_ is the index of the text element in the element list
                     # this is text - see if it contains the pattern                        
                     if ($this->{'elementListRef'}[$_]{'string'} =~ /$searchPattern/gi)
                     {                   
                        # found a match - extract the URL and exit                                         
                        # add this anchor to the anchor list                                                       
                        $anchorList[$anchorsFound] = $this->{'elementListRef'}[$elementIndex]{'href'};                       
                        $anchorsFound++;  
                        $finishedThisTag = 1;                     
                     }                     
                  }
               }
            }                                                      
         }
         else
         {
            # gone further than the end of the search constraint - break out now
            last;
         }
      }
   }      
      
   if ($anchorsFound > 0)
   {            
      return \@anchorList;        
   }
   else
   {      
      return undef;
   }     
}

# -------------------------------------------------------------------------------------------------
# sub getAnchorsAndTextContainingPattern
# returns a list of anchors within the search constraints that contain the pattern
#  (if pattern is undef, returns all anchors containing text)
# returns the list as a list of hashes 'href', 'string'
# 
# Purpose:
#  Parsing file
#
# Parameters:
#  STRING searchPattern
#
# Constraints:
#  $this->{'searchStartIndex'}
#  $this->{'searchEndIndex'}
#
# Updates:
#  nil
#
# Returns:
#   reference to list of url's and the matched text
#
 
sub getAnchorsAndTextContainingPattern

{
   my $this = shift; # get this object's instance (always the first parameter)
   my $searchPattern = shift;
         
   my $url = undef;       
   my $elementIndex;
   my @anchorList = undef;
   my $anchorsFound = 0;   
   my $anchorIndex;
   
   # loop through all of the anchor elements in the page      
   for ($anchorIndex = 0; $anchorIndex < $this->{'anchorElementIndexLength'}; $anchorIndex++)   
   {   
      # this is a bit of a hack because foreach couldn't be used on the
      # anchorElementIndexRef.  Get the current index into the elementList
      $_ = $this->{'anchorElementIndexRef'}[$anchorIndex]{'elementIndex'};
                      
      # only search within the bounds of the search constraints
      if ($_ >= $this->{'searchStartIndex'}) 
      {
         if ($_ <= $this->{'searchEndIndex'})         
         { 
            # this flag is used to indicate that it's not necessary to 
            # keep processing the content of this tag (because a match
            # has already been made)
            $finishedThisTag = 0;
            $elementIndex = $_;
            
            # check if this tag contains any text elements  
            $textListLength = $this->{'anchorElementIndexRef'}[$anchorIndex]{'textListLength'};
            if ($textListLength > 0)
            {              
               # loop for all of the text elements
               $listRef = $this->{'anchorElementIndexRef'}[$anchorIndex]{'textListRef'};
               #print "textListRef: $listRef\n"; 
               foreach (@$listRef)
               {
                  # $_ is a reference to a text element
                  if (!$finishedThisTag)
                  {                                                           
                     # see if this text it contains the pattern   
                     # $_ is the index of the text element in the element list
                     # this is text - see if it contains the pattern                        
                     if ($this->{'elementListRef'}[$_]{'string'} =~ /$searchPattern/gi)
                     {                   
                        # found a match - extract the URL and exit                                         
                        # add this anchor to the anchor list                                                     
                        $anchorList[$anchorsFound]{'href'} = $this->{'elementListRef'}[$elementIndex]{'href'};
                        $anchorList[$anchorsFound]{'string'} = $this->{'elementListRef'}[$_]{'string'};
                        $anchorsFound++;  
                        $finishedThisTag = 1;                     
                     }                     
                  }
               }
            }                                                      
         }
         else
         {
            # gone further than the end of the search constraint - break out now
            last;
         }
      }
   }      
      
   if ($anchorsFound > 0)
   {            
      return \@anchorList;        
   }
   else
   {      
      return undef;
   }     
}


# -------------------------------------------------------------------------------------------------
# sub getNextAnchorContainingPattern
# returns an anchor URL containing the specified pattern
# 
# Purpose:
#  Parsing file
#
# Parameters:
#  STRING searchPattern
#
# Constraints:
#  $this->{'searchStartIndex'}
#  $this->{'searchEndIndex'}
#
# Updates:
#  nil
#
# Returns:
#   STRING url of anchor
#
 
sub getNextAnchorContainingPattern

{
   my $this = shift; # get this object's instance (always the first parameter)
   my $searchPattern = shift;
         
   my $url = undef;
   my $anchorsFound = 0;   
   my $anchorIndex;
   my $tagContent;   
   my $elementIndex;
   
   # loop through all of the anchor elements in the page      
   for ($anchorIndex = 0; $anchorIndex < $this->{'anchorElementIndexLength'}; $anchorIndex++)   
   {   
      # this is a bit of a hack because foreach couldn't be used on the
      # anchorElementIndexRef.  Get the current index into the elementList
      $_ = $this->{'anchorElementIndexRef'}[$anchorIndex]{'elementIndex'};
                      
      # only search within the bounds of the search constraints
      if ($_ >= $this->{'searchStartIndex'}) 
      {
         if ($_ <= $this->{'searchEndIndex'})         
         {
            $elementIndex = $_; 
            
            # check if this tag contains any text elements             
            $textListLength = $this->{'anchorElementIndexRef'}[$anchorIndex]{'textListLength'};                                          
                        
            if ($textListLength > 0)
            {              
               # loop for all of the text elements
               $listRef = $this->{'anchorElementIndexRef'}[$anchorIndex]{'textListRef'};
               #print "textListRef: $listRef\n"; 
               foreach (@$listRef)
               {                          
                  #print "   ", $this->{'elementListRef'}[$_]{'string'}, "\n";
                  # $_ is the index of the text element in the element list
                  # this is text - see if it contains the pattern                  
                  if ($this->{'elementListRef'}[$_]{'string'} =~ /$searchPattern/gi)
                  {                 
                     # found a match - extract the URL and exit
                     $url = $this->{'elementListRef'}[$elementIndex]{'href'};                     
                     last;                           
                  }
                  
               }               
            }                                                      
         }
         else
         {
            # gone further than the end of the search constraint - break out now
            last;
         }
      }
   }      
      
   return $url;     
}


# -------------------------------------------------------------------------------------------------
# sub getAnchorsContainingImageSrc
# returns a list of anchors within the search constraints that contain the image
# with source matching the specified pattern
#  (if pattern is undef, returns all anchors containing text)
# 
# Purpose:
#  Parsing file
#
# Parameters:
#  STRING searchPattern
#
# Constraints:
#  $this->{'searchStartIndex'}
#  $this->{'searchEndIndex'}
#
# Updates:
#  nil
#
# Returns:
#   reference to list of url's
#
 
sub getAnchorsContainingImageSrc

{
   my $this = shift; # get this object's instance (always the first parameter)
   my $searchPattern = shift;
         
   my $url = undef;       
   my $elementIndex;
   my @anchorList = undef;
   my $anchorsFound = 0;   
   my $anchorIndex;
   
   # loop through all of the anchor elements in the page      
   for ($anchorIndex = 0; $anchorIndex < $this->{'anchorElementIndexLength'}; $anchorIndex++)   
   {   
      # this is a bit of a hack because foreach couldn't be used on the
      # anchorElementIndexRef.  Get the current index into the elementList
      $_ = $this->{'anchorElementIndexRef'}[$anchorIndex]{'elementIndex'};
                      
      # only search within the bounds of the search constraints
      if ($_ >= $this->{'searchStartIndex'}) 
      {
         if ($_ <= $this->{'searchEndIndex'})         
         { 
            # this flag is used to indicate that it's not necessary to 
            # keep processing the content of this tag (because a match
            # has already been made)
            $finishedThisTag = 0;
            $elementIndex = $_;
            
            # check if this tag contains any text elements  
            $imgListLength = $this->{'anchorElementIndexRef'}[$anchorIndex]{'imgListLength'};
            if ($imgListLength > 0)
            {              
               # loop for all of the text elements
               $listRef = $this->{'anchorElementIndexRef'}[$anchorIndex]{'imgListRef'};
               #print "imgListRef: $listRef (len=$imgListLength)\n";
               foreach (@$listRef)
               {                  
                  # $_ is a reference to a text element
                  if (!$finishedThisTag)
                  {
                     #print "img src='", $this->{'elementListRef'}[$_]{'href'}, "'\n";                                                           
                     # see if this img's source contains the pattern   
                     # $_ is the index of the img element in the element list                                             
                     if ($this->{'elementListRef'}[$_]{'href'} =~ /$searchPattern/gi)
                     {                   
                        # found a match - extract the URL and exit                                         
                        # add this anchor to the anchor list                                                       
                        $anchorList[$anchorsFound] = $this->{'elementListRef'}[$elementIndex]{'href'};                       
                        $anchorsFound++;  
                        $finishedThisTag = 1;                     
                     }                     
                  }
               }
            }                                                      
         }
         else
         {
            # gone further than the end of the search constraint - break out now
            last;
         }
      }
   }      
      
   if ($anchorsFound > 0)
   {            
      return \@anchorList;        
   }
   else
   {      
      return undef;
   }     
}

# -------------------------------------------------------------------------------------------------
# sub getNextTextAfterPattern

# returns the next text element following the element matching the specified pattern
# returns TRUE if it's found.  Search is case insensitive
# 
# Purpose:
#  Document parsing
#
# Parameters:
#  STRING searchPattern
#
# Constraints:
#  $this->{'searchStartIndex'}
#  $this->{'searchEndIndex'}
#
# Updates:
#  $this->{'lastFoundIndex'} to the matching elementList index if FOUND
#
# Returns:
#   STRING if found, undef if not
#
 
sub getNextTextAfterPattern

{
   my $this = shift; # get this object's instance (always the first parameter)
   my $searchPattern = shift;   
   my $found = 0;
   my $textIndex;
   my $nextTextIndex;
   my $textString;
   my $textIndex;
         
   # loop through all of the text elements in the page      
   for ($textIndex = 0; $textIndex < $this->{'textElementIndexLength'}; $textIndex++)   
   {   
      # this is a bit of a hack because foreach couldn't be used on the
      # textElementIndexRef.  Get the current index into the elementList
      $_ = $this->{'textElementIndexRef'}[$textIndex];
   
      # only search within the bounds of the search constraints
      if ($_ >= $this->{'searchStartIndex'})
      {
         if ($_ <= $this->{'searchEndIndex'})         
         {         
            # check if this text element contains the search pattern...         
            if ($this->{'elementListRef'}[$_]{'string'} =~ /$searchPattern/gi)
            {         
               # found a match
               $found = 1;         
                            
               # need to get the next TEXT element in 
               # the element list - this is found through the textElementIndex            
               # (get the index of this element in the textElementIndex, and obtain
               # the index of the next text element from there)                                              
               $textIndex = $this->{'elementListRef'}[$_]{'textElementIndex'};
               $nextTextIndex = $this->{'textElementIndexRef'}[$textIndex+1];                             
               
               $textString = $this->{'elementListRef'}[$nextTextIndex]{'string'};
               
               $this->{'lastFoundIndex'} = $nextTextIndex;               
               $this->{'startAtLastFoundIndex'} = 0;
               last;  # break out of the foreach loop
            }
         }
         else
         {
            # gone further than the end of the search constraint - break out now
            last;
         }
      }      
   }
   
   if ($found)
   {
      return $textString;
   }
   else
   {
      return undef;
   }   
}

# -------------------------------------------------------------------------------------------------
# sub getNextTextContainingPattern

# returns the text element containing the specified pattern
# returns TRUE if it's found.  Search is case insensitive
# 
# Purpose:
#  Document parsing
#
# Parameters:
#  STRING searchPattern
#
# Constraints:
#  $this->{'searchStartIndex'}
#  $this->{'searchEndIndex'}
#
# Updates:
#  $this->{'lastFoundIndex'} to the matching elementList index if FOUND
#
# Returns:
#   STRING if found, undef if not
#
 
sub getNextTextContainingPattern

{
   my $this = shift; # get this object's instance (always the first parameter)
   my $searchPattern = shift;   
   my $found = 0;
   my $textIndex;
   my $nextTextIndex;
   my $textString;   
         
   # loop through all of the text elements in the page      
   for ($textIndex = 0; $textIndex < $this->{'textElementIndexLength'}; $textIndex++)   
   {   
      # this is a bit of a hack because foreach couldn't be used on the
      # textElementIndexRef.  Get the current index into the elementList
      $_ = $this->{'textElementIndexRef'}[$textIndex];
   
      # only search within the bounds of the search constraints
      if ($_ >= $this->{'searchStartIndex'})
      {
         if ($_ <= $this->{'searchEndIndex'})         
         {         
            # check if this text element contains the search pattern...         
            if ($this->{'elementListRef'}[$_]{'string'} =~ /$searchPattern/gi)
            {                        
               # found a match
               $found = 1;         
                                        
               $textString = $this->{'elementListRef'}[$_]{'string'};                              
          
               $this->{'lastFoundIndex'} = $nextTextIndex;               
               $this->{'startAtLastFoundIndex'} = 0;
               last;  # break out of the foreach loop
            }
         }
         else
         {
            # gone further than the end of the search constraint - break out now
            last;
         }
      }      
   }
   
   if ($found)
   {
      return $textString;
   }
   else
   {
      return undef;
   }   
}


# -------------------------------------------------------------------------------------------------
# sub getNextTextAfterTag

# returns the next text element following the element matching the specified tag
# returns TRUE if it's found.  Search is case insensitive
# 
# Purpose:
#  Document parsing
#
# Parameters:
#  STRING tag
#
# Constraints:
#  $this->{'searchStartIndex'}
#  $this->{'searchEndIndex'}
#
# Updates:
#  $this->{'lastFoundIndex'} to the matching elementList index if FOUND
#
# Returns:
#   STRING if found, undef if not
#
 
sub getNextTextAfterTag

{
   my $this = shift; # get this object's instance (always the first parameter)
   my $searchPattern = shift;   
   my $found = 0;
   my $textIndex;
   my $nextTextIndex;
   my $textString;
   my $listIndex = 0;
   my $getNextTextFlag = 0;
      
   # loop through all of the elements in the page
   # (note a forloop is used here instead of foreach because 
   # we don't need $_ to match the element in the list)
   for ($listIndex = 0; $listIndex < $this->{'elementListLength'}; $listIndex++)   
   {           
      # this is a bit of a hack because foreach couldn't be used on the
      # elementIndexRef.  Get the current index into the elementList
      #$_ = $this->{'elementListRef'}[$listIndex];
   
      # only search within the bounds of the search constraints
      if ($listIndex >= $this->{'searchStartIndex'})
      {
         if ($listIndex <= $this->{'searchEndIndex'})         
         { 
            # the getNextTextFlag is used to control the search loop
            # whether it's looking for a tag or the text following it
            
            if (!$getNextTextFlag)
            {
               # check if this text element contains the search pattern...         
               if ($this->{'elementListRef'}[$listIndex]{'tag'} =~ /$searchPattern/gi)
               {         
                  # found a match
                  $found = 1;         
                       
                  # need to get the next TEXT element in 
                  # the element list - this is found by continuing the iteration until 
                  # the next text (as there's no index to the next element that's text)  
                  # NOTE: This algorithm could be optimised by recording an index to the 
                  # next text when constructing the syntaxTree
                  $getNextTextFlag = 1;                                                    
               }
            }
            else
            {        
               # check if this text element contains the search pattern...         
               if ($this->{'elementListRef'}[$listIndex]{'type'} == $TEXT)
               {         
                  # found a match
                  $found = 1;         
                       
                  # get the text string for this element
                  $textString = $this->{'elementListRef'}[$listIndex]{'string'};
                  
                  $this->{'lastFoundIndex'} = $listIndex;                  
                  $this->{'startAtLastFoundIndex'} = 0;
                  last;  # break out of the foreach loop
               }
            }
         }
         else
         {
            # gone further than the end of the search constraint - break out now
            last;
         }                     
      }      
   }
   
   if ($found)
   {
      return $textString;
   }
   else
   {
      return undef;
   }   
}

# -------------------------------------------------------------------------------------------------
# sub getNextText

# returns the next text element following the last successful search
# returns TRUE if it's found.
# 
# Purpose:
#  Document parsing
#
# Parameters:
#  STRING tag
#
# Constraints:
#  $this->{'searchStartIndex'}
#  $this->{'searchEndIndex'}
#
# Updates:
#  $this->{'lastFoundIndex'} to the matching elementList index if FOUND
#
# Returns:
#   STRING if found, undef if not
#
 
sub getNextText

{
   my $this = shift; # get this object's instance (always the first parameter)      
   my $found = 0;
   my $textIndex;
   my $nextTextIndex;
   my $textString;
   my $listIndex = 0;
   my $getNextTextFlag = 0;
   my $offset = 1;
   
   # this global variable is set immediately after setting the start search 
   # contraint to overcome the special circumstance that the lastFoundIndex
   # is the position to start from
   if ($this->{'startAtLastFoundIndex'})
   {
      $offset = 0;
   }
      
   # loop through all of the elements in the page
   # (note a forloop is used here instead of foreach because 
   # we don't need $_ to match the element in the list)
   for ($listIndex = $this->{'lastFoundIndex'}+$offset; $listIndex < $this->{'elementListLength'}; $listIndex++)   
   {                    
      # only search within the bounds of the search constraints
      if ($listIndex >= $this->{'searchStartIndex'})
      {         
         if ($listIndex <= $this->{'searchEndIndex'})         
         {             
            # the getNextTextFlag is used to control the search loop
            # whether it's looking for a tag or the text following it
        
            # check if this text element contains the search pattern...         
            if ($this->{'elementListRef'}[$listIndex]{'type'} == $TEXT)
            {                  
               # get the text string for this element
               $textString = $this->{'elementListRef'}[$listIndex]{'string'};
               
               # only use non-blank
               if ($textString)
               {
                  # found a match
                  $found = 1;         
                                    
                  $this->{'lastFoundIndex'} = $listIndex;
                  $this->{'startAtLastFoundIndex'} = 0;
                  last;  # break out of the foreach loop
               }
            }
         }
         else
         {
            # gone further than the end of the search constraint - break out now
            last;            
         }                     
      }      
   }
   
   if ($found)
   {
      return $textString;
   }
   else
   {
      return undef;
   }   
}

# -------------------------------------------------------------------------------------------------
# sub getFrames
# returns a list of frames within the page
# 
# Purpose:
#  Parsing file
#
# Parameters:
#  nil
#
# Updates:
#  nil
#
# Returns:
#   @frameList of HREFs (href's) or UNDEF
# 
sub getFrames

{
   my $this = shift; # get this object's instance (always the first parameter)  
     
   my $frameListRef = $this->{'frameListRef'};      
   
   return @$frameListRef;
}

# -------------------------------------------------------------------------------------------------
# sub containsFrames
# returns TRUE if the page contains frames
# 
# Purpose:
#  Parsing file
#
# Parameters:
#  nil
#
# Updates:
#  nil
#
# Returns:
#   TRUE or FALSE
# 
sub containsFrames

{
   my $this = shift; # get this object's instance (always the first parameter)  
     
   if ($this->{'frameListLength'} > 0)
   {
      #print "containsFrames = true (len=", $this->{'frameListLength'}, "\n";
      return 1;
   }
   else
   {
      return 0;
   }
}
   
# -------------------------------------------------------------------------------------------------   
# -------------------------------------------------------------------------------------------------
# sub getHTMLForm
# returns the specified HTML form from the page or undef
#   if form name is not set this uses first defined form
#
# Purpose:
#  Preparing to POST
#
# Parameters:
#  form name
#
# Updates:
#  nil
#
# Returns:
#   reference to an HTML form, or undef
# 
sub getHTMLForm

{
   my $this = shift; # get this object's instance (always the first parameter)  
   my $formName = shift;
   my $htmlForm = undef;
   my $index = 0;
   my $found = 0;
   my $formListRef;
   
   if ($this->{'htmlFormListLength'} > 0)
   {
      
      if (!formName)
      {
         # if the form name isn't set get the first defined form         
         $found = 1;
      }
      else
      {
         # loop through all the forms defined on this page to see
         # if one has a matching name
         $formListRef = $this->{'htmlFormListRef'};
         foreach (@$formListRef)
         {            
            $thisFormName = $_->getName();           
            if ($thisFormName =~ /$formName/i)
            {
               # found a match
               $found = 1;
               last;
            }
            else
            {
               # try the next form
               $index++;
            }
         }
      }
      
      if ($found)
      {
         $htmlForm = $this->{'htmlFormListRef'}[$index];
      }
   }          
   
   return $htmlForm;
}
   
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

# Instance method that displays all of the text elements in the tree 
# PUBLIC
sub printText
{
   my $this = shift;     # get this object's instance (always the first parameter)
   
   my $textIndex;
         
   # loop through all of the text elements in the page      
   for ($textIndex = 0; $textIndex < $this->{'textElementIndexLength'}; $textIndex++)   
   {   
      # this is a bit of a hack because foreach couldn't be used on the
      # textElementIndexRef.  Get the current index into the elementList
      $_ = $this->{'textElementIndexRef'}[$textIndex];
       
      # only search within the bounds of the search constraints
      if ($_ >= $this->{'searchStartIndex'})
      {
         if ($_ <= $this->{'searchEndIndex'})         
         {      
            print "$_: ", $this->{'elementListRef'}[$_]{'string'}, "\n";
         }
         else
         {
            # gone further than the end of the search constraint - break out now
            last;
         }
      }
   }
   
   return 1;
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------


# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------


