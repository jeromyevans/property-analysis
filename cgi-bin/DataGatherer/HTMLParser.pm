#!/usr/bin/perl
# Written by Jeromy Evans
# Created 12 September 2004 from source developed in December 2003
# This module was originally used when constructing an HTML syntax tree but was 
# superceeded by the LWP module that did a better job.  It has been reinstated
# here as some functions are particularly useful, such as decomposing a tag into it's attributes
#
# Description:
# Module to parse an HTML file into tags with attributes and text
# History:
#  
#
# CONVENTIONS
# _ indicates a private variable or method
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
package HTMLParser;

require Exporter;

#@EXPORT = qw(parseFile);

# ------------------------------------------------------------------------------

#sub parseFile
#{
   #$input_file=shift;
#
   ## read the entire input file
   #@unparsed_lines = readFile($input_file);
#
   ## pass the reference to the unparsed lines array
   #@decommentedLines = removeComments(\@unparsed_lines);
#
   #@stringBuffer = preFilterWhitespace(\@decommentedLines);
#
   #$buffer = concatenateLines(\@stringBuffer);
#
   #@tagList = identifyTags($buffer);
#
   #@filteredLines = removeWhitespace(\@tagList);
#
   #@contentLines = assignUniqueIDs(\@filteredLines);
#
   #@decomposedTagList = decomposeTags(\@contentLines);
#
   #@document = identifyHierarchy(\@decomposedTagList);
#
   #return @document;
#}


# ------------------------------------------------------------------------------
#
#sub readFile
#{
   ## get the first parameter - the name of the file to read
   #my ($input_file) = shift;
   #my (@input_lines);
#
   ## if the input file exists
   #if (-e $input_file)
   #{
#
      ## open file for reading...
      #open(FILE,"<$input_file") || die "FILE: readFile can't open $input_file: $!";   
      ## read the entire file in...      
      #@input_lines = <FILE>;
#
      #close(FILE) || die "FILE: readFile can't close $input_file: $!";  
   #}
#
   #return @input_lines;
#}

# ------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# removeComments:
#
# Purpose:
#  removes comments from an array of unparsed HTML lines
# split the file into COMMENTS and CONTENT
#
# Updated 26 December 2003 for processing single line comments and multiple 
# comments on single line
# 
#
# Parameters:
#  ARRAY of HTML lines (eg. read from a file)
##
# Updates:
#  ni;
#
# Returns:
#   LIST of processed lines
#
sub removeComments
{
   my ($unparsed_lines) = shift;
   #note: $unparsed_lines is a reference to an array

   my (@content_lines);
   my ($inComment) = 0;   
   my (@split_line);
   my ($lineIndex) = 0;
   my ($stillProcessingCurrentLine);

   # note, current line is in $_ during each iteration of the loop
   foreach (@$unparsed_lines)
   {
      $stillProcessingCurrentLine = 1;
      # continue iterating on the current line after each successful match
      # in case mltiple occurances occur in the same line
      while ($stillProcessingCurrentLine)
      {
         
         # if currently in a comment, then searching for the end-of-comment token
         if ($inComment)
         {
            # split the current line on the end of comment token
            # split the current line on the token      
            (@split_line) = split(/-->/, $_, 2);      
            
            # if the second part of the split line contains anything, then the token was found
            if ($split_line[1])            
            {                  
               # clear the in-comment flag to control the state machine...
               $inComment = 0;
   
               #keep only the non-comment portion of the line for the content_line array
               # (the first part is discarded as it's comment)
               #$content_lines[$lineIndex++] = $split_line[1];

               # discard the comment portion of the line and continue processing
               
               $_ = $split_line[1];                             
            }            
            else
            {
               # finished processing this line - it's entirely inside comment
               $stillProcessingCurrentLine = 0;
            }
         }
         else
         {
            # if currently outside a comment, then searching for the start-of-comment token
         
            # split the current line on the token (next occurance only, otherwise results in multi-part
            # array for each occurance)
            (@split_line) = split(/<!--/, $_, 2);
   
            # if the second segment of the split line contains anything, then the token was found
            if ($split_line[1])
            {  
               # set the in-comment flag to control the state machine...
               $inComment = 1;
             
               #keep only the non-comment portion of the line for the content_line array
               # (the second part is discarded as it's comment)
               $content_lines[$lineIndex++] = $split_line[0];
               
               # keep processing the remainder of the line...
               $_ = $split_line[1];               
            }
            else
            {  
               # no start of comment token on this line, so add the entire line
               # to the content line array
               $content_lines[$lineIndex++] = $_;
               $stillProcessingCurrentLine = 0;
            }
         }
      }
   }
   return @content_lines;
}

# -------------------------------------------------------------------------------------------------
# preFilterWhitespace:
#
# Purpose:
# remove trailing and leading whitespace but retain one space at the end of the
# line.  This is used so lines of text separated by new-line characters
# have a space between them when concatenated (other excess whitespace is 
# removed later if necessary)
#
#
# Parameters:
#  ARRAY of HTML lines (eg. read from a file)
##
# Updates:
#  ni;
#
# Returns:
#   LIST of processed lines
#
sub preFilterWhitespace
{
   my ($unparsed_lines) = shift;
   #note: $unparsed_lines is a reference to an array
   my ($lineIndex) = 0;
   my (@content_lines);
   my (@segments);

   # note, current line is in $_ during each iteration of the loop
   foreach (@$unparsed_lines)
   {
      # remove leading and trailing whitespace

      # substitute trailing whitespace characters with blank
      # s/whitespace from end-of-line/all occurances
      s/\s*$//g;      
      # substitute leading whitespace characters with blank
      # s/whitespace from start-of-line,multiple single characters/blank/all occurances
      s/^\s*//g;        
      
      # determine if the line is blank or not...
      if ($_)
      {
         # keep this line.
         $content_lines[$lineIndex++] = $_ . " ";
      }
      
   }

   return @content_lines;
}

# -------------------------------------------------------------------------------------------------
# removeWhitespace
#
# Purpose:
# remove trailing and leading whitespace and delete blank lines
# 23 Dec 03 - only operates on a HASH (containing member 'string').  Returns an 
# array of hashes.
#
# Parameters:
#  ARRAY of HTML lines (eg. read from a file)
##
# Updates:
#  ni;
#
# Returns:
#   LIST of processed lines
#
sub removeWhitespace
{
   my ($unparsed_lines) = shift;
   #note: $unparsed_lines is a reference to an array
   my ($lineIndex) = 0;
   my (@content_lines);
   my (@segments);

   # note, current line is in $_ during each iteration of the loop
   foreach (@$unparsed_lines)
   {
      # remove leading and trailing whitespace...

      # $_ is a reference to a HASH.  The string part of the hash needs to be
      # dereferenced.      

      # substitute trailing whitespace characters with blank
      # s/whitespace from end-of-line/all occurances
      # s/\s*$//g;      
      $$_{string} =~ s/\s*$//g;

      # substitute leading whitespace characters with blank
      # s/whitespace from start-of-line,multiple single characters/blank/all occurances
      #s/^\s*//g;    
      $$_{string} =~ s/^\s*//g;        

      # determine if the line is blank or not...
      if ($$_{string})
      {
         # keep this line.
         $content_lines[$lineIndex++] = \%$_;  # keep the original HASH (reference to it)
      }
   }

   return @content_lines;
}

# -------------------------------------------------------------------------------------------------
# concatenateLines
#
# Purpose:
# group all of the lines into a single buffer to aid tag identification (equiv to join)
# 
#
# Parameters:
#  ARRAY of HTML lines (eg. read from a file)
##
# Updates:
#  ni;
#
# Returns:
#  STRING concatenatedLine;
#
sub concatenateLines
{
   my ($unparsed_lines) = shift;
   #note: $unparsed_lines is a reference to an array

   my ($StringBuffer);

   # note, current line is in $_ during each iteration of the loop
   foreach (@$unparsed_lines)
   {
      $stringBuffer .= $_;
   }

   return $stringBuffer;
}

# -------------------------------------------------------------------------------------------------
# identifyTags
#
# Purpose:
# identify tags in the file (superceeded by HTMLSyntaxTree module)
# returns an array of hashes
#
# Parameters:
#  ARRAY of HTML lines (eg. read from a file)
##
# Updates:
#  ni;
#
# Returns:
#  hash of tages
#
sub identifyTags
{
   my ($currentSegment) = shift;

   my (@tag_list);
   my ($inTag) = 0;   
   my (@lineSegments);
   my ($tagIndex) = 0;
   my ($bufferEnd) = 0;   

   # 28 December 2003
   # create the top-level tag called 'doc'.  This is essential as in some document
   # formats there can be multiple tags that have no parent, so a pretend parent is required.
   # for a well-formed XML or HTML this would never be the base, but often special tags
   # can appear outside <html>
   $tag_list[$tagIndex] = {
               type => "tag",
               string => "document",
               tagName => "",
               attributesRef => undef,
               parentRef => undef,
               childrenListRef => undef,
               uniqueID => undef
            };
   $tagIndex++;
   
   # while still encountering tags
   while (!$bufferEnd)
   {
      # if currently in a tag, then searching for the end-of-tag token
      if ($inTag)
      {
         # if currently inside a tag, then searching for the end-of-tag token
         # split the current line on the token (maximum of two segments)     
         (@lineSegments) = split(/>/, $currentSegment, 2);  

         # if the second segment of the split buffer contains anything, then the token was found
         if ($lineSegments[1])
         {
            # clear the in-tag flag to control the state machine...
            $inTag = 0;

            # assign the text preceeding the tag to the current tag list item
            # (the second part is the start of the tag)
            $tag_list[$tagIndex] = {
               type => "tag",
               string => $lineSegments[0],
               tagName => "",
               attributesRef => undef,
               parentRef => undef,
               childrenListRef => undef,
               uniqueID => undef            
            };

            # start a new tag element
            $tagIndex++;
 
            # start processing from the second segment
            $currentSegment = $lineSegments[1];
         }
         else
         {  
            # tag end was not found - at the end of the buffer 
            # (most likely that the last character in the buffer is the 
            # end tag, or the buffer is incomplete.  Run chop in the last
            # segment to delete the last character)
          
            $bufferEnd = 1;         
            
            # keep the remaining segment text (except the last character)                 
            $tag_list[$tagIndex] = {
               type => "tag",
               string => $currentSegment,
               tagName => "",
               attributesRef => undef,
               parentRef => undef,
               childrenListRef => undef,
               uniqueID => undef
            };

            chop($tag_list[$tagIndex]{string});
            # Note: chop returns the last character, so have to use in a separate
            # statement so it operates in the actual string (ignoring result)


            $tagIndex++;
         }
      }
      else
      {
         # if currently outside a tag, then searching for the start-of-tag token
         # split the current line on the token (maximum of two segments)     
         (@lineSegments) = split(/</, $currentSegment, 2);  

         # if the second segment of the split buffer contains anything, then the token was found
         if ($lineSegments[1])
         {  
            # set the in-tag flag to control the state machine...
            $inTag = 1;

            # assign the text preceeding the tag to the current tag list item
            # (the second part is the start of the tag)
            $tag_list[$tagIndex] = {
                type => "text",
                string => "$lineSegments[0]",
                tagName => "",
                attributesRef => undef,
                parentRef => undef,
                childrenListRef => undef,
                uniqueID => undef
            };

            # start a new tag element
            $tagIndex++;
 
            # start processing from the second segment
            $currentSegment = $lineSegments[1];

         }
         else
         { 
            # tag start was not found - at the end of the buffer
            $bufferEnd = 1;         
            
            # keep the remaining segment text
            
            $tag_list[$tagIndex] = {
               type => "text",
               string => $currentSegment,
               tagName => "",
               attributesRef => undef,
               parentRef => undef,
               childrenListRef => undef,
               uniqueID => undef
            };

            $tagIndex++;
         }
      }   
   }
   return @tag_list;
}

# ------------------------------------------------------------------------------

# assigns unique ID to each tag/text in the list (performed after 
# deleting blank text, etc
# 3 January 2004
sub assignUniqueIDs
{
   # $tag_list is a reference to an ARRAY of HASHes   
   my ($tag_list) = shift;
   my ($uniqueID) = 0;
   my ($tagIndex) = 0;
   
   foreach (@$tag_list)
   {      
      # $_ is a reference to a hash.  
      $$tag_list[$tagIndex]{'uniqueID'} = $uniqueID++;         
      
      $tagIndex++;
   }             

   return @$tag_list;
   
}

# -------------------------------------------------------------------------------------------------
# decomposeHTMLTag
#
# Purpose:
# 12 december 2003 - identifies tag attribute=value pairs in a tag string
#
# Parameters:
#  STRING html tag
#
# Updates:
#  ni;
#
# Returns:
#  hash of attributes
#
sub decomposeHTMLTag
{
   my $tagString = shift;
   my @splitTag;
   my $atEndOfTag = 0;
   my $currentSegment;
   my $tagIndex = 0;
   my %attributeList;
 
   # split on first whitespace (maximum 2 segments) 
   @splitTag = split(/\s/, $tagString, 2);
 
   # first segment of the split tag is the tag name (always)
   # $currentTag{'tagName'} = $splitTag[0];         
   $splitTag[0] =~ tr/A-Z/a-z/;     #convert tagName to lowercase (NOTE: locale insensitive)
   $splitTag[0] =~ s/<//g;   # remove leading < if provided       
   $attributeList{'TAG_NAME'} = $splitTag[0];
   
   # if the second segment exists, then the name is followed by
   # one or more attributes...
   if ($splitTag[1])
   {
      # loop in the state machine until the end of the tag is encountered
      $currentState = EXPECTING_ATTRIBUTE_NAME;
      $currentSegment = $splitTag[1];
      $atEndOfTag = 0;  
                 
      while (!$atEndOfTag)
      {
         #print $currentState.": $currentSegment\n";
         
         # substitute leading whitespace characters with blank
         # s/whitespace from start-of-line,multiple single characters/blank/all occurances                 
         $currentSegment =~ s/^\s*//g;
            
         if ($currentState eq EXPECTING_ATTRIBUTE_NAME)
         {
            # expecting an attribute name...
            #    attribute name is followed by either:
            #       equals or whitespace
            
            # look for first occurance of equals of whitespace
            if ($currentSegment =~ m/=|\s/g)
            {                  
               # attribute name is the substring from the start to the found position   
               # the matched position is returned by pos (actual it returns the position
               # of the next character, from which the next match will occur
               $attributeName = substr($currentSegment, 0, (pos $currentSegment)-1);
               $attributeName =~ tr/A-Z/a-z/;    #convert attributeName to lowercase (note: locale insensitive)
               # only process the remainder of the tag...
               $currentSegment = substr($currentSegment, (pos $currentSegment)-1);                      
            }
            else
            {
               $atEndOfTag = 1;               
            }                                                                                                                        
            
            # process the remainder of the tag...                  
            $currentState = EXPECTING_EQUALS;                                                      
         }
         else
         {               
            if ($currentState eq EXPECTING_EQUALS)
            {
               # expecting an [optional] equals...
               #    if an equals is found then expecting attribute value next, 
               #     other expecting attribute name next (current attribute
               #     has no value)
               #       equals or whitespace
               
               # if the first character in the substring is an equals...
               $nextChar = substr($currentSegment, 0, 1); 
               if ($nextChar eq "=")      
               {
                  # found an equals - now expecting attribute value
                  $currentState = EXPECTING_ATTRIBUTE_VALUE;
                  
                  # drop the equals - start processing from the next character
                  $currentSegment = substr($currentSegment, 1);
               }
               else
               {
                  # the next non-whitespace was not an equals - that 
                  # means the attribute was valueless.
                  # add the attribute without a value to the hash and 
                  # start looking for next attribute name.  Keep the current
                  # character as it may form part of the name
                  
                  # create the new hash element corresponding to this attribute name
                  $attributeList{$attributeName} = "";                        
                                                            
                  $currentState = EXPECTING_ATTRIBUTE_NAME;
               }
            } # end of EXPECTING_EQUALS
            else
            {                             
               if ($currentState eq EXPECTING_ATTRIBUTE_VALUE)
               {     
                  # remove any leading whitespace so the  next character is the 
                  # either the start of the attribute value (or next attribute name)
                  
                  # substitute leading whitespace characters with blank
                  # s/whitespace from start-of-line,multiple single characters/blank/all occurances                 
                  #$currentSegment =~ s/^\s*//g;
                  
                  # if the next character in the substring is a single or double quote...
                  $nextChar = substr($currentSegment, 0, 1);                                  
                  if ($nextChar eq "\"")      
                  {   
                     # if a double quote is found, attribute value is surrounded by
                     # by double quotes...                             
                     $currentState = IN_DOUBLE_QUOTED_ATTRIBUTE_VALUE;
                  }
                  else
                  {
                     if ($nextChar eq "\'")      
                     {
                        # if a single quote is found, attribute value is surrounded by
                        # by single quotes...                             
                        $currentState = IN_SINGLE_QUOTED_ATTRIBUTE_VALUE;
                     }
                     else
                     {                        
                        # otherwise the attribute value is unquoted...                  
                        $currentState = IN_UNQUOTED_ATTRIBUTE_VALUE;  
                     }
                  }
                                 
               } # end of EXPECTING_ATTRIBUTE_VALUE
               else
               {
                  if ($currentState eq IN_DOUBLE_QUOTED_ATTRIBUTE_VALUE)
                  {                  
                     # need to seek the terminating double quote and disregard nested quotes...
                     
                     # match the first quote (known to exist)
                     $currentSegment =~ m/\"/g;
                     $inQuote = 1;
                     
                     # look for next occurance of double quote
                     while (($currentSegment =~ m/\"/g) && ($inQuote))
                     {                  
                        # determine if this quote is escaped...
                        
                        # get the position of the matched character (this equates to the 
                        # length of the attribute value)
                        $length = (pos $currentSegment);
                        
                        # get the character preceeding the matched character
                        # (need to use minus 2 - pos points to the position after
                        # the match (==length)                     
                        $nextChar = substr($currentSegment, ($length)-2, 1);                                          
                        if ($nextChar eq "\\")
                        { 
                           # quotation is escaped - ignore
                        }
                        else
                        {
                           # closing quote found
                           $inQuote = 0;
                        }
                     }
                     
                     # extract the substring from quote-to-quote
                     $attributeValue = substr($currentSegment, 0, $length);                  
                     
                     #print "[DQ$attributeName=$attributeValue]";
                                                                          
                     # create the new hash element corresponding to this attribute name
                     $attributeList{$attributeName} = $attributeValue;
                      
                     $currentSegment = substr($currentSegment, $length);                    
                     
                     $currentState = EXPECTING_ATTRIBUTE_NAME;
                  } # end IN_DOUBLE_QUOTED                        
                  else
                  {
                     if (($currentState eq IN_SINGLE_QUOTED_ATTRIBUTE_VALUE) && (!$atEndOfTag))
                     {                  
                        # need to seek the terminating single quote and disregard nested quotes...
                        
                        # match the first quote (known to exist)
                        $currentSegment =~ m/\'/g;
                        $inQuote = 1;
                        
                        # look for next occurance of single quote
                        while (($currentSegment =~ m/\'/g) && ($inQuote))
                        {                  
                           # determine if this quote is escaped...
                           
                           # get the position of the matched character (this equates to the 
                           # length of the attribute value)
                           $length = (pos $currentSegment);
                           
                           # get the character preceeding the matched character
                           # (need to use minus 2 - pos points to the position after
                           # the match (==length)                     
                           $nextChar = substr($currentSegment, ($length)-2, 1);                                          
                           if ($nextChar eq "\\")
                           { 
                              # quotation is escaped - ignore
                           }
                           else
                           {
                              # closing quote found
                              $inQuote = 0;
                           }
                        }
                        
                        # extract the substring from quote-to-quote
                        $attributeValue = substr($currentSegment, 0, $length);                  
                        
                        #print "[SQ$attributeName=$attributeValue]";
                       
                        # create the new hash element corresponding to this attribute name
                        $attributeList{$attributeName} = $attributeValue;
                            
                        $currentSegment = substr($currentSegment, $length);                    
                                                         
                        $currentState = EXPECTING_ATTRIBUTE_NAME;
                     } # endif IN_SINGLE_QUOTED                          
                     else
                     {
                        if (($currentState == IN_UNQUOTED_ATTRIBUTE_VALUE) && (!$atEndOfTag))
                        {                  
                           # need to seek the terminating whitespace (or end of tag)...
                           (@splitTag)= split(/\s/, $currentSegment, 2);
                           $attributeValue = $splitTag[0];
                        
                           #print "UQ$attributeName=$attributeValue";
                       
                           # create the new hash element corresponding to this attribute name                                                                  
                           $attributeList{$attributeName} = $attributeValue;
                           
                           $currentSegment = $splitTag[1];
                           $currentState = EXPECTING_ATTRIBUTE_NAME;
                        }
                     }
                  }
               }
            }               
         }            
        
      } # while
      
      #print "[";
      #foreach (keys(%attributeList))
      #{
      #   print $_.", "; 
      #}
      #print "]\n";
   } # if
   else
   {
      # this tag has no attributes            
   }         
   
   return %attributeList;
}
# -------------------------------------------------------------------------------------------------
# decomposeTags
#
# Purpose:
# 24 december 2003 - identifies tag attribute=value pairs
#
# Parameters:
#  ARRAY of HTML lines (eg. read from a file)
##
# Updates:
#  ni;
#
# Returns:
#  array of tages
#
sub decomposeTags
{
   # $tag_list is a reference to an ARRAY of HASHes
   my ($tag_list) = shift;
   my ($tagString);
   my (@splitTag);
   my ($atEndOfTag) = 0;
   my ($currentSegment);
   my (%currentTag);
   my ($tagIndex) = 0;
 
   
   foreach (@$tag_list)
   {
      # $_ is a reference to a hash.  
      # if this element is a tag...
      if ($$_{'type'} eq "tag")
      {              
         # Get the tag's string member
         $tagString = $$_{'string'};

         # split on first whitespace (maximum 2 segments) 
         (@splitTag) = split(/\s/, $tagString, 2);
       
         # first segment of the split tag is the tag name (always)
         # $currentTag{'tagName'} = $splitTag[0];         
         $splitTag[0] =~ tr/A-Z/a-z/;     #convert tagName to lowercase (NOTE: locale insensitive)       
         $$tag_list[$tagIndex]{'tagName'} = $splitTag[0];
         
         # if the second segment exists, then the name is followed by
         # one or more attributes...
         if ($splitTag[1])
         {
            # loop in the state machine until the end of the tag is encountered
            $currentState = EXPECTING_ATTRIBUTE_NAME;
            $currentSegment = $splitTag[1];
            $atEndOfTag = 0;  
                       
            # reset the current hash list of attributes
            # (create a new memory space for it as it's persisent and referenced
            # by the attributeRef hash)
            my (%attributeList);
            while (!$atEndOfTag)
            {
               #print $currentState.": $currentSegment\n";
               
               # substitute leading whitespace characters with blank
               # s/whitespace from start-of-line,multiple single characters/blank/all occurances                 
               $currentSegment =~ s/^\s*//g;
                  
               if ($currentState eq EXPECTING_ATTRIBUTE_NAME)
               {
                  # expecting an attribute name...
                  #    attribute name is followed by either:
                  #       equals or whitespace
                  
                  # look for first occurance of equals of whitespace
                  if ($currentSegment =~ m/=|\s/g)
                  {                  
                     # attribute name is the substring from the start to the found position   
                     # the matched position is returned by pos (actual it returns the position
                     # of the next character, from which the next match will occur
                     $attributeName = substr($currentSegment, 0, (pos $currentSegment)-1);
                     $attributeName =~ tr/A-Z/a-z/;    #convert attributeName to lowercase (note: locale insensitive)
                     # only process the remainder of the tag...
                     $currentSegment = substr($currentSegment, (pos $currentSegment)-1);                      
                  }
                  else
                  {
                     $atEndOfTag = 1;               
                  }                                                                                                                        
                  
                  # process the remainder of the tag...                  
                  $currentState = EXPECTING_EQUALS;                                                      
               }
               else
               {               
                  if ($currentState eq EXPECTING_EQUALS)
                  {
                     # expecting an [optional] equals...
                     #    if an equals is found then expecting attribute value next, 
                     #     other expecting attribute name next (current attribute
                     #     has no value)
                     #       equals or whitespace
                     
                     # if the first character in the substring is an equals...
                     $nextChar = substr($currentSegment, 0, 1); 
                     if ($nextChar eq "=")      
                     {
                        # found an equals - now expecting attribute value
                        $currentState = EXPECTING_ATTRIBUTE_VALUE;
                        
                        # drop the equals - start processing from the next character
                        $currentSegment = substr($currentSegment, 1);
                     }
                     else
                     {
                        # the next non-whitespace was not an equals - that 
                        # means the attribute was valueless.
                        # add the attribute without a value to the hash and 
                        # start looking for next attribute name.  Keep the current
                        # character as it may form part of the name
                        
                        # create the new hash element corresponding to this attribute name
                        $attributeList{$attributeName} = "";                        
                                                                  
                        $currentState = EXPECTING_ATTRIBUTE_NAME;
                     }
                  } # end of EXPECTING_EQUALS
                  else
                  {                             
                     if ($currentState eq EXPECTING_ATTRIBUTE_VALUE)
                     {     
                        # remove any leading whitespace so the  next character is the 
                        # either the start of the attribute value (or next attribute name)
                        
                        # substitute leading whitespace characters with blank
                        # s/whitespace from start-of-line,multiple single characters/blank/all occurances                 
                        #$currentSegment =~ s/^\s*//g;
                        
                        # if the next character in the substring is a single or double quote...
                        $nextChar = substr($currentSegment, 0, 1);                                  
                        if ($nextChar eq "\"")      
                        {   
                           # if a double quote is found, attribute value is surrounded by
                           # by double quotes...                             
                           $currentState = IN_DOUBLE_QUOTED_ATTRIBUTE_VALUE;
                        }
                        else
                        {
                           if ($nextChar eq "\'")      
                           {
                              # if a single quote is found, attribute value is surrounded by
                              # by single quotes...                             
                              $currentState = IN_SINGLE_QUOTED_ATTRIBUTE_VALUE;
                           }
                           else
                           {                        
                              # otherwise the attribute value is unquoted...                  
                              $currentState = IN_UNQUOTED_ATTRIBUTE_VALUE;  
                           }
                        }
                                       
                     } # end of EXPECTING_ATTRIBUTE_VALUE
                     else
                     {
                        if ($currentState eq IN_DOUBLE_QUOTED_ATTRIBUTE_VALUE)
                        {                  
                           # need to seek the terminating double quote and disregard nested quotes...
                           
                           # match the first quote (known to exist)
                           $currentSegment =~ m/\"/g;
                           $inQuote = 1;
                           
                           # look for next occurance of double quote
                           while (($currentSegment =~ m/\"/g) && ($inQuote))
                           {                  
                              # determine if this quote is escaped...
                              
                              # get the position of the matched character (this equates to the 
                              # length of the attribute value)
                              $length = (pos $currentSegment);
                              
                              # get the character preceeding the matched character
                              # (need to use minus 2 - pos points to the position after
                              # the match (==length)                     
                              $nextChar = substr($currentSegment, ($length)-2, 1);                                          
                              if ($nextChar eq "\\")
                              { 
                                 # quotation is escaped - ignore
                              }
                              else
                              {
                                 # closing quote found
                                 $inQuote = 0;
                              }
                           }
                           
                           # extract the substring from quote-to-quote
                           $attributeValue = substr($currentSegment, 0, $length);                  
                           
                           #print "[DQ$attributeName=$attributeValue]";
                                                                                
                           # create the new hash element corresponding to this attribute name
                           $attributeList{$attributeName} = $attributeValue;
                            
                           $currentSegment = substr($currentSegment, $length);                    
                           
                           $currentState = EXPECTING_ATTRIBUTE_NAME;
                        } # end IN_DOUBLE_QUOTED                        
                        else
                        {
                           if (($currentState eq IN_SINGLE_QUOTED_ATTRIBUTE_VALUE) && (!$atEndOfTag))
                           {                  
                              # need to seek the terminating single quote and disregard nested quotes...
                              
                              # match the first quote (known to exist)
                              $currentSegment =~ m/\'/g;
                              $inQuote = 1;
                              
                              # look for next occurance of single quote
                              while (($currentSegment =~ m/\'/g) && ($inQuote))
                              {                  
                                 # determine if this quote is escaped...
                                 
                                 # get the position of the matched character (this equates to the 
                                 # length of the attribute value)
                                 $length = (pos $currentSegment);
                                 
                                 # get the character preceeding the matched character
                                 # (need to use minus 2 - pos points to the position after
                                 # the match (==length)                     
                                 $nextChar = substr($currentSegment, ($length)-2, 1);                                          
                                 if ($nextChar eq "\\")
                                 { 
                                    # quotation is escaped - ignore
                                 }
                                 else
                                 {
                                    # closing quote found
                                    $inQuote = 0;
                                 }
                              }
                              
                              # extract the substring from quote-to-quote
                              $attributeValue = substr($currentSegment, 0, $length);                  
                              
                              #print "[SQ$attributeName=$attributeValue]";
                             
                              # create the new hash element corresponding to this attribute name
                              $attributeList{$attributeName} = $attributeValue;
                                  
                              $currentSegment = substr($currentSegment, $length);                    
                                                               
                              $currentState = EXPECTING_ATTRIBUTE_NAME;
                           } # endif IN_SINGLE_QUOTED                          
                           else
                           {
                              if (($currentState == IN_UNQUOTED_ATTRIBUTE_VALUE) && (!$atEndOfTag))
                              {                  
                                 # need to seek the terminating whitespace (or end of tag)...
                                 (@splitTag)= split(/\s/, $currentSegment, 2);
                                 $attributeValue = $splitTag[0];
                              
                                 #print "UQ$attributeName=$attributeValue";
                             
                                 # create the new hash element corresponding to this attribute name                                                                  
                                 $attributeList{$attributeName} = $attributeValue;
                                 
                                 $currentSegment = $splitTag[1];
                                 $currentState = EXPECTING_ATTRIBUTE_NAME;
                              }
                           }
                        }
                     }
                  }               
               }            
              
            } # while
            
            # assign reference to the hash list to the attributesRef field
            
            $$tag_list[$tagIndex]{'attributesRef'} = \%attributeList;
            
            #print "[";
            #foreach (keys(%attributeList))
            #{
            #   print $_.", "; 
            #}
            #print "]\n";
         } # if
         else
         {
            # this tag has no attributes            
         }         
      }
      
      $tagIndex++;
   }
   
   return @$tag_list;
}

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
 

# 26 December 2003: this function is  complicated.  It's not clever, 
# but it's best to examine the flow diagram to understand it first.
# The function is recursive and the entry and termination states are significant
# (entry specifies the parent and termination specifies whether to go up or across next)
# creates a well-formed HTML Tree (from loose or strict HTML)
#
# 26 December 2003: may need to add support for XML-namespace
# (parentIndex, \@list of refs to hashes, depth)
sub recursiveParse 
{   
   # get the specified parent   
   my ($parentTagIndex) = shift;    # index into array
   my ($decomposedTagListRef) = shift; # reference to an array (of references to hashes)
   my ($currentDepth) = shift;       
   my ($lastChild) = 0;
   my ($currentTag);  
   my ($terminatedState) = 0;
   my ($seekTagName) = undef;
   
   my ($parentsChildListRef);  # \@ reference to a list
   
   my (%parentTag); 
   my ($currentTagIndex);
      
   $currentDepth++;
   while (!$lastChild)
   {  
      $recursiveTagIndex++;     
      
      $currentTagIndex = $recursiveTagIndex;                
      $currentTag = $$decomposedTagListRef[$recursiveTagIndex]; 
      # %$currentTag is a hash
      
      # set the parent tag to the one specified when first entering this recursive function
      $$currentTag{'parentRef'} = $$decomposedTagListRef[$parentTagIndex];
      $parentTagRef = $$decomposedTagListRef[$parentTagIndex];
      #print $parentTagRef, "\n";
      %parentTag = %$parentTagRef;
      # %parentTag is a hash
      
      if (($$currentTag{'type'}) && ($$currentTag{'type'} eq "tag"))
      {  
         # if the first character of the tag is a slash, then this is 
         # a terminating tag
         if (substr($$currentTag{'tagName'}, 0, 1) eq "/")
         {
            # if this tagname (excluding the first character) matches the parent's tagName then 
            # this is the terminating tag - (no more children) break out of this
            # layer (up to the parent)
            # NOTE: terminating tags are not added to the parent's list of children
            # (don't think they need to be referenced)
            $startTagName = substr($$currentTag{'tagName'}, 1);
            
            if ($startTagName eq $parentTag{'tagName'})
            {
               # it matches - terminate this tag      
               $lastChild = 1;
               $terminatedState = 1;  # drop back to parent (go to sibling)
            }
            else
            {
               # it doesn't match, which means the structure is slightly out of wack.  
               # implies this tag terminates a previous parent
               # eg. in a non-strict document, a /table can terminate all of the 
               # tags contained inside it.
               # RULES:
               #  /table, /tr and /td can terminate all children                                                   
               #  /ul and /li can terminate all it's children
               #  /dl, /dt cand /dd an terminate all it's children  
               #  /head /body /html
               #
               #note: the \b at the start of the expressions ensures the match is at a start of a
               # word boundary and the last \b ensures it also only matches on the end of a word
               # boundary.  This ensures, for example 'a' matches only to the word 'a', not 
               # a word starting with 'a', containing 'a', or ending in 'a'.
               $searchResult = grep /\b$startTagName\b/, ("table", "tr", "td", "ul", "li", "dl", "dt", "dd", "head", "body", "html");
               
               if ($searchResult > 0)                                   
               {
                  $found = 0;
                  $searchTag = $parentTag{'parentRef'};
                  while (!$found)
                  {                                         
                     if (!$searchTag)
                     {
                        # at the top of the tree - match failed
                        $found = 1;
                     }
                     else
                     {
                        
                        if ($$searchTag{"tagName"} eq $startTagName)
                        {
                           # this is the parent corresponding to this tag
                           # terminate current level all the way back up the tree 
                           # until the parent
                           $terminatedState = 2;   # drop back to matching pargent
                           $found = 1;
                           
                           # set the seek Tag name that's returned to the calling function 
                           # so it knows whether it's at the right level or not
                           $seekTagName = $startTagName;
                        }
                        else
                        {
                           # not matched - try next level up (set search level
                           # to current level's parent
                           $searchTag = $$searchTag{'parentRef'};
                        }
                     }
                  }
               }
               else
               {
                  # just ignore this terminating tag.  If it is actually associated with
                  # anything it's not a significant structure anyway
               }                              
               $lastChild = 1;
            }
print "5", "-" x $currentDepth, $$currentTag{'tagName'}, "\n";            
         }
         else
         {
            # if the last character of the tag is a slash then this is a childless tag         
            if ($$currentTag{'tagName'} =~ /\/$/)
            #if (substr($$currentTag{'tagName'}, ($$currentTag{'tagName'})-1, 1) eq "/")
            {
               # add this element to the children list of the parent...
               # get the parent's reference to it's children list
               $parentsChildListRef = $parentTag{'childrenListRef'};
               # if it exists...
               if ($parentsChildListRef)
               {
                  # print "ADDCHLD:";
                  # if the child list already exists, add to the end
                  push (@$parentsChildListRef, $$decomposedTagListRef[$recursiveTagIndex]);
               }
               else
               {
                  #print "NEWCHLD:";
                  # create a new children list for the parent and set the first element
                  # to the current tag
                  my (@parentsChildList) = ($$decomposedTagListRef[$recursiveTagIndex]);
                  # assign the reference in the parent to the new list's address
                  $$decomposedTagListRef[$parentTagIndex]{'childrenListRef'} = \@parentsChildList;
                  #$$parentTag{'childrenListRef'} = \@parentsChildList;
               }
print "3", "-" x $currentDepth, $$currentTag{'tagName'}, " childOf(", $parentTag{'tagName'},")\n";               
               # this tag is treated like text - it has no children, but may have siblings           
               $$currentTag{'childrenListRef'} = undef;
               $lastChild = 1;
            }
            else
            {
               # if the tag is a recognised childless tag (from non-strict HTML) then
               # it is not considered to have any children (structurelly) and it's 
               # corresponding end tag (if one does exist) is ignored.
               #
               # RULES:
               #   <br> instead of <br/> is acceptable
               #   <p> instead of <p></p> or <p/> is acceptable
               #   <div> instead of <div></div> or <div/> is acceptable
               #   <hr> instead of <hr/> is acceptable
               #   <meta> doesn't have children
               #   <input> doesn't have children               
               #   <link> doesn't have children
               #   <base> doesn't have children
               #   <area> doesn't have children
               #   <img> doesn't have children
               #   <font> appears to be used irregularly and is assumed to not contribute
               #       to interepration.  Ignored.
               #   <center> same treatment as <font>
               #   <!DOCTYPE or similar directives have no children (first char is !)
               #   <?xml or similar directives have no children (first char is ?)
               # NOTE: suspect DIV shouldn't be here...need to check it's purpose again
               #
               # NOTE: instead of ignoring the structure caused by some of this, 
               #  it may be better to insert the IMPLIED tag at the correct location.
               #  ie. assign parents normally and if a terminating tag is located - good, use it, 
               # otherwise is overriding terminating tag is located - insert implied tags
               # (may not be worth the added complication though)
                                               
                #note: the \b at the start of the expressions ensures the match is at a start of a
                # word boundary and the last \b ensures it also only matches on the end of a word
                # boundary.  This ensures, for example 'a' matches only to the word 'a', not 
                # a word starting with 'a', containing 'a', or ending in 'a'.                         
                #$result = grep /\b$tagName\b/, ("br", "p", "div", "hr", "meta", "link", "base", "area", "input", "img", "font", "center");
               $searchResult = grep /\b$$currentTag{'tagName'}\b/, ("br", "p", "div", "hr", "meta", "link", "base", "area", "input", "img", "font", "center", "param");
               
               if (($searchResult > 0) ||                 
                   ($$currentTag{'tagName'} =~ m/^\!/) ||
                   ($$currentTag{'tagName'} =~ m/^\?/))                   
               {
                  # this is a recognised childless tag.  It is treated the same was as a properly
                  # terminated childless tag
                  # add this element to the children list of the parent...
                  # get the parent's reference to it's children list
                  $parentsChildListRef = $parentTag{'childrenListRef'};
                  # if it exists...
                  if ($parentsChildListRef)
                  {
                     #print "ADDCHLD:";
                     # if the child list already exists, add to the end
                     push (@$parentsChildListRef, $$decomposedTagListRef[$recursiveTagIndex]);
                  }
                  else
                  {
                     #print "NEWCHLD:";
                     # create a new children list for the parent and set the first element
                     # to the current tag
                     my (@parentsChildList) = ($$decomposedTagListRef[$recursiveTagIndex]);
                     
                     # assign the reference in the parent to the new list's address
                     $$decomposedTagListRef[$parentTagIndex]{'childrenListRef'} = \@parentsChildList;
                     #$$parentTag{'childrenListRef'} = \@parentsChildList;
                  }
print "4", "-" x $currentDepth, $$currentTag{'tagName'}, " childOf(", $parentTag{'tagName'},")\n";                  
                  # this tag is treated like text - it has no children, but may have siblings           
                  $$currentTag{'childrenListRef'} = undef;
                  $lastChild = 1;
               }
               else               
               {    
                  # add this element to the children list of the parent...
                  # get the parent's reference to it's children list
                  $parentsChildListRef = $parentTag{'childrenListRef'};
                  # if it exists...
                  if ($parentsChildListRef)
                  {
                     # print "ADDCHLD:";
                     # if the child list already exists, add to the end
                     push (@$parentsChildListRef, $$decomposedTagListRef[$recursiveTagIndex]);
                  }
                  else
                  {
                     #print "NEWCHLD:";
                     # create a new children list for the parent and set the first element
                     # to the current tag
                     my (@parentsChildList) = ($$decomposedTagListRef[$recursiveTagIndex]);
                     # assign the reference in the parent to the new list's address
                     
                     $$decomposedTagListRef[$parentTagIndex]{'childrenListRef'} = \@parentsChildList;
                     #$$parentTag{'childrenListRef'} = \@parentsChildList;
                  }
                  
      print "1", "-" x $currentDepth, $$currentTag{'tagName'}, " childOf(", $parentTag{'tagName'},")\n";            
                  # this is a starting tag - it has children
                  # recurse down the chain passing this tag as the parent
                  # when it comes up, if it wasn't due to the terminating tag, pop down again
                  
                  $length = @$decomposedTagListRef;
                  $terminatedState = 0;
                  while (($terminatedState == 0) && ($recursiveTagIndex < $length))
                  {
                     ($terminatedState, $seekTagName, $recursiveTagIndex) = recursiveParse($currentTagIndex, $decomposedTagListRef, $currentDepth);                        
                  }         
                  
                  if ($terminatedState == 1)
                  {
                     # dropped out from recusive function.  Look for next child
                     # (sibling of this level)
                     # clear the terminated State flag so repetation at this
                     # parent continues
                     $terminatedState = 0;
                  }
                  else
                  {                     
                     if ($terminatedState == 2)
                     {
                        # dropped out from recursive function.  Abnormal termination caused
                        # by ending tag matching an ancestor (parent's parent) resulting
                        # in a jump up the tree.  This is the result of mulformed HTML
                        # where a tag hasn't been terminated correctly.  
                        
                        # will drop back multiple levels until the tag matching the terminating tag 
                        # is found (it definitely exists as the search was conducted where it
                        # was first detected)
                                                                        
                        if ($$currentTag{'tagName'} eq $seekTagName)
                        {
                           # found a match - this is the parent it corresponded to. 
                           # continue parsing from this level
                           # (clear the terminatedState flag to continue repetition from this level)
                           $terminatedState = 0;
                           $seekTagName = undef;
                        }  
                        else
                        {
                           # doesn't match so this isn't the parent.
                           # drop up another level retaining the terminatedState
                           $lastChild = 1;
                        }
                     }
                  }
                                         
               }
            }
         }
      }
      
      else
      {
         if (($$currentTag{'type'}) && ($$currentTag{'type'} eq "text"))
         {
            # add this element to the children list of the parent
            $parentsChildListRef = $parentTag{'childrenListRef'};
            if ($parentsChildListRef)
            {
               #print "ADDCHLD:";
               # if the child list already exists, add to the end
               push (@$parentsChildListRef, $$decomposedTagListRef[$recursiveTagIndex]);
            }
            else
            {
               #print "NEWCHLD:";
               # create the children list for the parent
               my (@parentsChildList) = ($$decomposedTagListRef[$recursiveTagIndex]);
               
               $$decomposedTagListRef[$parentTagIndex]{'childrenListRef'} = \@parentsChildList;
               #$$parentTag{'childrenListRef'} = \@parentsChildList;               
            }
            
print "2", "-" x $currentDepth, $$currentTag{'string'}, " childOf(", $parentTag{'tagName'},")\n";
            # text cannot have children
            $$currentTag{'childrenList'} = undef;            
               
            # no more children - break out of this layer (up to parent)
            $lastChild = 1;
         }
         else
         {
            #break out - end of list (early)
            $lastChild = 1;
         }
      }          
   }      
   
   return ($terminatedState, $seekTagName, $recursiveTagIndex);
}

# ------------------------------------------------------------------------------
# 24 december 2003 - identifies tag attribute=value pairs
sub identifyHierarchy
{
   # $tag_list is a reference to an ARRAY of HASHes
   my ($tag_list) = shift;
   my ($recursiveTagIndex) = 0;
   my ($terminatedState);
   my ($tagName);
      
   # the first tag has no parent 
   $length = @$tag_list;

   print $$tag_list[0]{'tagName'}, "\n";    

   # this while-loop is required at the absolute top level ("document") in case
   # the document has multiple top-level tags (a strict HTML or XML document
   # wouldn't, but it's known to happen). eg. tags outside <html></html>
   while ($recursiveTagIndex < $length)
   {    
      ($terminatedState, $tagName, $recursiveTagIndex) = recursiveParse(0, \@$tag_list, 0, $recursiveTagIndex);                        
   }       

   return @$tag_list;    
  
}
# ------------------------------------------------------------------------------

sub printList
{
   my ($length);

   print("Displaying...\n");
   foreach (@_)
   {       
      print "[$_]\n";
   } 

   $length = @_;
   print "\nDisplayed lines = $length\n";
}

# ------------------------------------------------------------------------------

# 23 Dec 03 - only operates on a HASH (containing member 'string')
sub printLines
{
   my ($length);

   print("Displaying...\n");
   foreach (@_)
   { 
      # $_ is a reference to a hash.  Defreference the hash member'string'
      print "[$$_{'string'}]\n";
   } 

   $length = @_;
   print "\nDisplayed lines = $length\n";
}

# ------------------------------------------------------------------------------

sub printTags
{
   my ($length);

   print("Displaying...\n");
   foreach (@_)
   { 
      # $_ is a reference to a hash.  Defreference the hash member'string'
      if ($$_{'type'} eq "text")
      {
         print "[TEXT($$_{'uniqueID'}):$$_{'string'}]\n";
      }
      else
      {
         print "[TAG($$_{'uniqueID'}) :$$_{'tagName'} attr:(";
         
         $attributesRef = $$_{'attributesRef'};
         foreach (keys(%$attributesRef))
         {
            print $_." ";           
         }
         print ") ";

         print "chld:<";
         #$parentRef = $$_{'parentRef'};
         #print $parentRef;
         $childrenRef = $$_{'childrenListRef'};
         #print $childrenRef;
         foreach (@$childrenRef)
         {
            if ($$_{'type'} eq "tag")
            {
               print $$_{'tagName'},", ";      
            }
            else
            {
               print "text, ";
            }
         }

         print ">]\n";       

        
      }
      #print "[$$_{'string'}]\n";
   } 

   $length = @_;
   print "\nDisplayed lines = $length\n";
}

# ------------------------------------------------------------------------------

