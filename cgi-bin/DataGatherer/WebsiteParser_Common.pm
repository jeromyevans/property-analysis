#!/usr/bin/perl
# 28 Sep 04 - derived from multiple sources
#  Contains common website parser functions 
##
# The parsers can't access any other global variables, but can use functions in the WebsiteParser_Common module
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
# History:
#  27Nov04 - renamed validateProfile to tidyRecord - still performs the exact  function as the previously 
#   but renamed to reflect changed intent - better validation occurs later in the processing thread now
#   and all changes are tracked, but this original process couldn't be removed as it would have reset
#   all existing cached records (they'd all differ if not tidied up before creating the record, resulting in 
#   near duplicates)
#  28Nov04 - started developing the validateRecord function that performs some sophisticated validation 
#   of records.  It uses the Validator_RegExSubstitutions table that specifies regex patterns to apply
#   to different fields in the records, plus performs some brute-force suburb name look-ups.
#  5 December 2004 - adapted to use common AdvertisedPropertyProfiles instead of separate rentals and sales tables
# 23 January 2005 - added function isSuburbNameInRange as this bit of code was commonly used by all parses to 
#  determine if the suburbname was in the letter-range specified though parameters
use PrintLogger;
use CGI qw(:standard);
use HTTPClient;
use HTMLSyntaxTree;
use SQLClient;
use SuburbProfiles;
#use URI::URL;
use DebugTools;
use DocumentReader;
use AdvertisedPropertyProfiles;
use AgentStatusServer;
use PropertyTypes;

@ISA = qw(Exporter);


# -------------------------------------------------------------------------------------------------

# removes leading and trailing whitespace from parameter
# parameters:
#  string to trim
sub trimWhitespace
{
   my $string = shift;
   
   # --- remove leading and trailing whitespace ---
   # substitute trailing whitespace characters with blank
   # s/whitespace from end-of-line/all occurances
   # s/\s*$//g;      
   $string =~ s/\s*$//g;

   # substitute leading whitespace characters with blank
   # s/whitespace from start-of-line,multiple single characters/blank/all occurances
   #s/^\s*//g;    
   $string =~ s/^\s*//g;

   return $string;     
}


# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# change all characters to lowercase except the first character following a full stop, or the first character in the string
# if the allFirstUpper flag is set, then the first letter of all words is changed to uppercase, otherwise only the
# first letter of a sentance is changed to uppercase.
sub prettyPrint

{
   my $inputText = shift;
   my $allFirstUpper = shift;
   my $SEEKING_DOT = 0;
   my $SEEKING_NEXT_ALPHA = 1;
   my $SEEKING_FIRST_ALPHA = 2;
   my $state;
    
   if ($inputText)
   {
      # --- remove leading and trailing whitespace ---
      # substitute trailing whitespace characters with blank
      # s/whitespace from end-of-line/all occurances
      # s/\s*$//g;      
      $inputText =~ s/\s*$//g;
   
      # substitute leading whitespace characters and leading non-word characters with blank
      # s/whitespace from start-of-line,multiple single characters/blank/all occurances
      #s/^\s*//g;    
      $inputText =~ s/^[\s|\W]*//g; 
      
      # change all to lowercase
      $inputText =~ tr/[A-Z]/[a-z]/;
      
      
      # if the first upper flag has been set then the first alpha character of every word is to be uppercase
      if ($allFirstUpper)
      {
         # this expression works but it seems overly complicated
         # first it uses a substitution to match a single lowercase character at the start of each word (stored in $1)
         # then it evaluates the second expression which returns $1 in uppercase using sprintf
         # the ge modifiers ensure it's performed for every word and instructs the parser to evalutation the expression
        
         $inputText =~ s/(\b[a-z])/sprintf("\U$1")/ge;
         
         # note the above expression isn't perfect because the boundary of a word isn't just whitespace
         # for example, the above expresion would make isn't into Isn'T and i'm into I'M.
         # the expression below corrects for apostraphies.
         $inputText =~ s/(\'[A-Z])/sprintf("\L$1")/ge;
      }
      else
      {
         # --- change first character in a sentance to uppercase ---
         
         # a state machine is used to perform the special processing of the string.  This should be 
         # possible using a regular expression but I couldn't get it to work in every case.  
         # Instead the string is split into a list of characters...
         @charList = split //, $inputText;
      
         # then set the state machine to search for the next alpha character.  It sets this to uppercase
         # then searches for the next alphacharacter following a full-stop and sets that to uppercase, then 
         # repeats the search
         $state = $SEEKING_NEXT_ALPHA;
         $index = 0;
         foreach (@charList)
         {
           
            if ($state == $SEEKING_DOT)
            {
               if ($_ =~ m/[\.|\?|\!]/g)
               {
                  $state = $SEEKING_NEXT_ALPHA;
               }
            }
            else
            {
               if ($state == $SEEKING_NEXT_ALPHA)
               {
                  if ($_ =~ m/[a-z]/gi)
                  {
                     $_ =~ tr/[a-z]/[A-Z]/;
                     $charList[$index] = $_;
                     $state = $SEEKING_DOT;
                  }
               }
            }
          
            $index++;
         }
      
         # rejoin the array into a string
         $inputText = join '', @charList;
          
      }
     
      # special cases
      $inputText =~ s/(i\'m)/I\'m/gi;
      $inputText =~ s/(\si\s)/ I /gi;
      $inputText =~ s/(i\'ve)/I\'ve/gi;
      $inputText =~ s/(i\'d)/I\'d/gi;
         
      # remove multiple whitespaces
      $inputText =~ s/\s+/ /g;
   }
   
   return $inputText;
}

# -------------------------------------------------------------------------------------------------

# searches the postcode list for a suburb matching the name specified
sub matchSuburbName
{   
   my $sqlClient = shift;
   my $suburbName = shift;
   my $state = shift;
   my %matchedSuburb;
   
   if (($sqlClient) && ($suburbName))
   {       
      $quotedSuburbName = $sqlClient->quote($suburbName);
      $quotedState = $sqlClient->quote($state);
      $statementText = "SELECT locality, postcode, SuburbIndex FROM AusPostCodes WHERE locality like $quotedSuburbName and state like $quotedState order by postcode limit 1";
            
      @suburbList = $sqlClient->doSQLSelect($statementText);
      
      if ($suburbList[0])
      {
         $matchedSuburb{'SuburbName'} = $suburbList[0]{'locality'};
         $matchedSuburb{'postcode'} = $suburbList[0]{'postcode'};              
         $matchedSuburb{'SuburbIndex'} = $suburbList[0]{'SuburbIndex'};
      }                    
   }   
   return %matchedSuburb;
}  


# -------------------------------------------------------------------------------------------------
# tidyRecord
# validates the fields in the property record (for correctness)
#
# Purpose:
#  construction of the repositories
#
# Parameters:
#  saleProfile hash

# Updates:
#  database
#
# Returns:
#  validated sale profile
#    
sub tidyRecord
{
   my $sqlClient = shift;
   my $profileRef = shift; 
   
   # match the suburb name to a recognised suburb name
   %matchedSuburb = matchSuburbName($sqlClient, $$profileRef{'SuburbName'}, $$profileRef{'State'});
     
   if (%matchedSuburb)
   {
      $$profileRef{'SuburbIndex'} = $matchedSuburb{'SuburbIndex'};
      $$profileRef{'SuburbName'} = $matchedSuburb{'SuburbName'};
   }
   
   # validate property type
   $$profileRef{'TypeIndex'} = PropertyTypes::mapPropertyType($sqlClient, $$profileRef{'Type'});
   
   # validate number of bedrooms
   if (($$profileRef{'Bedrooms'} > 0) || (!defined $$profileRef{'Bedrooms'}))
   {
   }
   else
   {
       delete $$profileRef{'Bedrooms'};
   }

   # validate number of bathrooms
   if (($$profileRef{'Bathrooms'} > 0) || (!defined $$profileRef{'Bathrooms'}))
   {
   }
   else
   {
       delete $$profileRef{'Bathrooms'};
   }
   
   # validate land area
   if (($$profileRef{'Land'} > 0) || (!defined $$profileRef{'Land'}))
   {
   }
   else
   {
       delete $$profileRef{'Land'};
   }
      
   # validate advertised price lower
   if ((($$profileRef{'AdvertisedPriceLower'} > 0)) || (!defined $$profileRef{'AdvertisedPriceLower'}))
   {
   }
   else
   {
       delete $$profileRef{'AdvertisedPriceLower'};
   }
   
   # validate advertised price upper
   if ((($$profileRef{'AdvertisedPriceUpper'} > 0)) || (!defined $$profileRef{'AdvertisedPriceUpper'}))
   {
   }
   else
   {
       delete $$profileRef{'AdvertisedPriceUpper'};
   }
   
   # validate advertised weekly rent
   if ((($$profileRef{'AdvertisedWeeklyRent'} > 0)) || (!defined $$profileRef{'AdvertisedWeeklyRent'}))
   {
   }
   else
   {
       delete $$profileRef{'AdvertisedWeeklyRent'};
   }
   
   # ---
   # attempt to remove phone numbers and personal details from the description
   #  - a  phone number is 8 to 10 digits.  It may contain zero or more whitespaces between each digit, but nothing else
   $description = $$profileRef{'Description'};
   #if ($description =~ /0(\s*){8,10}/g)
   if ($description =~ /(\d(\s*)){8,10}/g)
   {
      # there is a phone number in the message - delete the entire sentance containing the phone number
      # split into sentances...
      @sentanceList = split /[\.|\?|\!\*]/, $$profileRef{'Description'};
      $index = 0;
      # loop through each sentance looking for the pattern
      foreach (@sentanceList)
      {
         # if this sentance contains a phone number...
         if ($_ =~ /(\d(\s*)){8,10}/g)
         {
            # reject this sentance as it contains the pattern
            #BUGFIX 13 September 2004 - need to escape the sentance before it's included in the
            # regular expression as some characters can break the expression
            # - escape regular expression characters
            $sentanceList[$index] =~ s/(\(|\)|\?|\.|\*|\+|\^|\{|\}|\[|\]|\|)/\\$1/g;
            
            $description =~ s/($sentanceList[$index])([\.|\?|\!\*]*)//g;
         }
         $index++;
      }         
   }
   $$profileRef{'Description'} = $description;
   
   # do another parse of the description to remove phone numbers if a sentance couldn't be identified - replace the number with a blank
   $$profileRef{'Description'} =~ s/(\d(\s*)){8,10}//g;
   
   #---
   # now, search the description for information not provided explicitly in the fields - look for landArea in sqm in the text
   if (!defined $$profileRef{'Land'})
   {
      # determine if the description contains 'sqm' or a variation of that
      #  look for 1 or more digits followed by 0 or more spaces then SQM
      if ($$profileRef{'Description'} =~ /\d+(\s*)sqm/i)
      {
         $description = $$profileRef{'Description'};
         # this expression extracts the sqm number out into $2 and assigns it to $landArea 
         # the 'e' modified ensures the second expresion is executed
         $description =~ s/((\d+)(\s*)sqm)/$landArea = sprintf("$2")/ei;         
      } 
      
      if ((defined $landArea) && ($landArea > 0))
      {
         # assign the land area specified in the description
         $$profileRef{'Land'} = $landArea;
      }
   }

   #---
   # now, search the description for information not provided explicitly in the fields - look for bedrooms in the text
   if (!defined $$profileRef{'Bedrooms'})
   {
      
      # determine if the description contains 'sqm' or a variation of that
      #  look for 1 or more digits followed by any space and charcters until bedrooms.  Note that a non-digit or 
      # non alpha character will break the pattern (for example, a comma implies the number may not be associated with bedrooms)
      # this is pretty rough but should work most of the time
      $description = $$_{'Description'};
      if ($description =~ /(\d+)([\w|\s]*)bedroom/i)
      {
         # this expression extracts the bedrooms number out into $1 and assigns it to $bedrooms 
         # the 'e' modified ensures the second expresion is executed
         $description =~ s/(\d+)([\w|\s]*)bedroom/$bedrooms = sprintf("$1")/ei;         
      } 
      
      if ((defined $bedrooms) && ($bedrooms > 0))
      {
         # assign the land area specified in the description
         $$profileRef{'Bedrooms'} = $bedrooms;
      }
   }
   
    #---
   # now, search the description for information not provided explicitly in the fields - look for bathrooms in the text
   if (!defined $$profileRef{'Bathrooms'})
   {      
      #  look for 1 or more digits followed by any space and charcters until bath.  Note that a non-digit or 
      # non alpha character will break the pattern (for example, a comma implies the number may not be associated with bath)
      # this is pretty rough but should work most of the time
      $description = $$_{'Description'};
      if ($description =~ /(\d+)([\w|\s]*)bath/i)
      {
         # this expression extracts the bedrooms number out into $1 and assigns it to $bedrooms 
         # the 'e' modified ensures the second expresion is executed
         $description =~ s/(\d+)([\w|\s]*)bath/$bathrooms = sprintf("$1")/ei;         
      } 
      
      if ((defined $bathrooms) && ($bathrooms > 0))
      {
         # assign the land area specified in the description
         $$profileRef{'Bathrooms'} = $bathrooms;
      }
   }
   
   # format the text using standard conventions to easy comparison later
   $$profileRef{'SuburbName'} = prettyPrint($$profileRef{'SuburbName'}, 1);

   if (defined $$profileRef{'StreetNumber'})
   {
      $$profileRef{'StreetNumber'} = prettyPrint($$profileRef{'StreetNumber'}, 1);
   }
   
   if (defined $$profileRef{'Street'})
   {
      $$profileRef{'Street'} = prettyPrint($$profileRef{'Street'}, 1);
   }

   if (defined $$profileRef{'City'})
   {
      $$profileRef{'City'} = prettyPrint($$profileRef{'City'}, 1);
   }

   if (defined $$profileRef{'Council'})
   {
      $$profileRef{'Council'} = prettyPrint($$profileRef{'Council'}, 1);
   }
   
   if (defined $$profileRef{'Description'})
   {
      $$profileRef{'Description'} = prettyPrint($$profileRef{'Description'}, 0);
   }

   if (defined $$profileRef{'Features'})
   {
      $$profileRef{'Features'} = prettyPrint($$profileRef{'Features'}, 0);
   }
}

# -------------------------------------------------------------------------------------------------

   my $badSuburbs = 0;
   my $fixedSuburbs = 0;
my $result = 1;

      
# repairSuburbName
# applies patterns to extact the correct suburbname from the parameter and lookup matched suburbIndex
#
# Purpose:
#  validation of the repositories
#
# Parameters:
#  reference to profile
#  reference to regEx substititions hash
#
# Returns:
#  list containing validated suburbname and suburb index
#    
sub repairSuburbName

{
   my $profileRef = shift;
   my $regExSubstitutionsRef = shift;
    
   my $suburbName = $$profileRef{'SuburbName'};
   
   #print "suburbName='$suburbName'";

   foreach (@$regExSubstitutionsRef)
   {
      if ($$_{'FieldName'} =~ /SuburbName/i)
      {
         $regEx = $$_{'RegEx'};
         $substitute = $$_{'Substitute'};
                  #print "regEx='$regEx', substitute='$substitute'\n";
   
         $suburbName =~ s/$regEx/$substitute/egi;
      }
   }
   
   # try to remove non-alpha characters (- and ' and whitespace are allowed)
   $suburbName =~ s/[^(\w|\-|\'|\s)]/ /gi;
   
   $suburbName = prettyPrint($suburbName, 1);
   
   if ($suburbName ne $$profileRef{'SuburbName'})
   {
      
      # match the suburb name to a recognised suburb name
      %matchedSuburb = matchSuburbName($sqlClient, $suburbName, $$profileRef{'State'});
        
      if (%matchedSuburb)
      {
         $changedSuburbName = prettyPrint($matchedSuburb{'SuburbName'}, 1);    # change the name
         $changedSuburbIndex = $matchedSuburb{'SuburbIndex'};
         #print "   NEW suburbIndex=", $changedProfile{'SuburbIndex'}, "\n";
         $fixedSuburbs++;
         $matched = 1;
         #print "BadSuburbs=$badSuburbs FixedSuburbs = $fixedSuburbs\n";
      }
   }
   
   if (!$matched)
   {
      # still haven't matched the suburb name - try searching for a close match on the assumption the suburbname is followed by crud
      @wordList = split(/ /, $suburbName);
      $noOfWords = @wordList;
      $currentWord = $noOfWords;
      $matched = 0;
      # loop through the series of words (from last to first)
      while ((!$matched) && ($currentWord > 0))
      {
         # concatenate the words of the string up to the current index
         $currentString = "";
         for ($index = 0; $index < $currentWord; $index++)
         {
            if ($index > 0)
            {
               $currentString .= " ";
            }  
            $currentString .= $wordList[$index];
         }
         
         # match the suburb name to a recognised suburb name
         
         %matchedSuburb = matchSuburbName($sqlClient, $currentString, $$profileRef{'State'});
     
         if (%matchedSuburb)
         {
            $changedSuburbName = prettyPrint($matchedSuburb{'SuburbName'}, 1);    # change the name
            $changedSuburbIndex = $matchedSuburb{'SuburbIndex'};
            #print "   OLD=", $$profileRef{'SuburbName'}, " NEW suburbName='", $changedProfile{'SuburbName'}, "'    NEW suburbIndex=", $changedProfile{'SuburbIndex'}, "\n";
            $matched = 1;
            $fixedSuburbs++;
         }
         else
         {
            # go back a word and try the series again
            $currentWord--;
         }
      }
   }
   
   if (!$matched)
   {
      #print "   OLD=", $$profileRef{'SuburbName'}, " NEW suburbName='$suburbName' STILL INVALID SUBURBNAME - UNCHANGED\n";
      
      
      # still haven't matched the suburb name - try searching for a close match on the assumption the suburbname is SOMEWHERE 
      # in the string
      @wordList = split(/ /, $suburbName);
      $noOfWords = @wordList;
      $currentWord = 0;
      $matched = 0;
      # loop through the series of words (from left to right)
      while ((!$matched) && ($currentWord < $noOfWords))
      {
         # match the suburb name to a recognised suburb name
         %matchedSuburb = matchSuburbName($sqlClient, $_, $$profileRef{'State'});
     
         if (%matchedSuburb)
         {
            $changedSuburbName = prettyPrint($matchedSuburb{'SuburbName'}, 1);    # change the name
            $changedSuburbIndex = $matchedSuburb{'SuburbIndex'};

            $matched = 1;
            $fixedSuburbs++;
            #print "   OLD=", $$profileRef{'SuburbName'}, " NEW suburbName='", $changedProfile{'SuburbName'}, "'    NEW suburbIndex=", $changedProfile{'SuburbIndex'}, "\n";
         }
         else
         {
            # try the next word in the list
            $currentWord++;
         }
      }      
   }
   if (!$matched)
   {
      #print "   OLD=", $$profileRef{'SuburbName'}, " NEW suburbName='", $suburbName, "' FAILED\n";
   }
   
   return ($changedSuburbName, $changedSuburbIndex);
}

# -------------------------------------------------------------------------------------------------

sub regexEscape

{
   my $string = shift;
   
   $string =~ s/\?/ /gi;
   $string =~ s/\[/ /gi;
   $string =~ s/\]/ /gi;
   $string =~ s/\(/ /gi;
   $string =~ s/\)/ /gi;
   $string =~ s/\*/ /gi;
   $string =~ s/\./ /gi;
   return $string;
}

# -------------------------------------------------------------------------------------------------   
# repairStreetName
# applies patterns to extract the correct street name and number from the profile 
#
# Purpose:
#  validation of the repositories
#
# Parameters:
#  reference to profile
#  reference to regEx substititions hash
#
# Returns:
#  list containing validated streetNumber and streetName
#    
sub repairStreetName

{
   my $profileRef = shift;
   my $regExSubstitutionsRef = shift;
    
   my $streetNumber = $$profileRef{'StreetNumber'};
   my $streetName = $$profileRef{'Street'};
   
   #print "suburbName='$suburbName'";
   
   # apply regular expression substitions to the street name
   foreach (@$regExSubstitutionsRef)
   {
      if ($$_{'FieldName'} =~ /Street$/i)
      {
         $regEx = $$_{'RegEx'};
         $substitute = $$_{'Substitute'};
                 # print "regEx='$regEx', substitute='$substitute'\n";
   
         $streetName =~ s/$regEx/$substitute/egi;
      }
      else
      {
         if ($$_{'FieldName'} =~ /StreetNumber/i)
         {
            $regEx = $$_{'RegEx'};
            $substitute = $$_{'Substitute'};
                   #  print "regEx='$regEx', substitute='$substitute'\n";
      
            $streetNumber =~ s/$regEx/$substitute/egi;
         }   
      }
   }
   if (($streetName ne $$profileRef{'Street'}) || ($streetNumber ne $$profileRef{'StreetNumber'}))
   {
      #print "Applied RegEx substitutions (", $$profileRef{'Street'}, ", ", $$profileRef{'StreetNumber'}, ")...\n";
      #print "   new StreetName = $streetName streetNumber = $streetNumber\n";
   }
      
   
   # if the street name contains any numbers, grab a copy of that subset of the street name - it may be
   # possible to transfer it into the street number instead
   
   if ($streetName =~ /\d/g)
   {
      #print "Extracting Numbers from street name ('$streetName', '$streetNumber')...\n";

      # extract numbers  - breakup word by word until the first number, get everything until the last number
      
      $prefix = "";
      $suffix = "";
      @wordList = split(/ /, $streetName);   # parse one word at a time (words are used as a valid number can include letters. eg. "21a / 14-24"

      $index = 0;
      $lastNumeralIndex = -1;
      $firstNumeralIndex = -1;
      $length = @wordList;
      $state = 0;  # searching for first number
      foreach (@wordList)
      {
         if ($_)
         {
            # if this word contains a numeral
            if ($_ =~ /\d/g)
            {
               if ($state == 0)
               {
                  # this is the first part of the number
                  $firstNumeralIndex = $index;
                  $lastNumeralIndex = $index;
                  $state = 1;  # searching for last number
               }
               else
               {
                  if ($state == 1)
                  {
                     # this is another part of the number - append it
                     $lastNumeralIndex = $index;
                  }
               }
            }
            else
            {
               # this word doesn't contain a numeral - keep searching right though
            }
         }
         $index++;
      }
      
      $number = undef;
      # at this point first and lastNumeralIndex specify the range of valid number data
      if ($lastNumeralIndex >= 0)
      {
         $number = "";
         for ($index = $firstNumeralIndex; $index <= $lastNumeralIndex; $index++)
         {
            $number .= $wordList[$index]." ";
            
            # important: the content of the streetname itself is used in part in a RegEx here.  Any characters in the
            # string that may break a regEx need to be erased or escaped before processing
            
            #print "wl[$index]: '", $wordList[$index], "'\n";
            
            $wordList[$index] = regexEscape($wordList[$index]);
            
            $streetName =~ s/$wordList[$index]/ /g;
         }
      }
      else
      {
         # no street number encountered - keep allocated entirely to street name
         $number = undef;
      }
      
      $number = trimWhitespace($number);
      $streetName = trimWhitespace($streetName);
      #print "   number='$number' streetName='$streetName'...\n";
      
      # now determine whether this number can actually be used for anything useful - check the content
      # of the current streetNumber
      if ($streetNumber =~ /\d/g)
      {
         # the street number already contains a number, can't resolve automatically.  Reject this number
         # pattern.
         $number = undef;
      }
      else
      {
         if ($number)
         {
            # the streetNumber contains no numbers - append this number to the end of it for processing
            $streetNumber .= " ".$number;
            #print "   interim streetNumber='$streetNumber' \n";
         }
      }
   }
   
   # remove anything after a comma
   if ($streetName =~ /\,/g)
   {
      #print "Removing post-comma text from street name ('$streetName', '$streetNumber')...\n";

      ($firstHalf, $rest) = split(/\,/, $streetName, 2);
      if ($firstHalf)
      {
         $streetName = $firstHalf;
      }
      #print "   StreetName='$streetName'\n";

   }
   
   # if the street name contains LOT by itself, extract it and apply to the street number instead.
   # not such a trivial task, surprisingly...
   if ($streetName =~ /^Lot(\s+)/gi)
   {      
      print "Extracting '^Lot(\s+)' from street name ('$streetName', '$streetNumber')...\n";
      $streetName =~ s/^Lot(\s+)/ /gi;
      # update the street number
      $streetNumber = "Lot ".$streetNumber;
         
      print "   StreetName='$streetName', streetNumber = '$streetNumber'\n";
   }
   else
   {
      if ($streetName =~ /\sLot(\s+)/gi)
      {
         print "Extracting '\sLot(\s+)' from street name ('$streetName', '$streetNumber')...\n";
         $streetName =~ s/\sLot(\s+)/ /gi;   
        
         # update the street number
         $streetNumber = "Lot ".$streetNumber;
         
         print "   StreetName='$streetName', streetNumber = '$streetNumber'\n";
      }
      else
      {
         if ($streetName eq 'Lot')
         {
            print "Extracting 'Lot' from street name ('$streetName', '$streetNumber')...\n";
            $streetName = "";   
           
            # update the street number
            $streetNumber = "Lot ".$streetNumber;
            
            print "   StreetName='$streetName', streetNumber = '$streetNumber'\n";            
         }
      }
   }
   
   # if the streetname contains numbers it's still invalid
   if ($streetName =~ /\d/g)
   {
      #print "Removing numbers from street name ('$streetName', '$streetNumber')...\n";

      $streetName =~ s/\d/ /g;
      #print "   StreetName='$streetName'\n";
   }
   
   
   # try to remove non-alpha characters (- and ' and whitespace are allowed) from street name
   $streetName =~ s/[^(\w|\-|\'|\s)]/ /gi;
   
   # apply regular expression substitions to the street name - AGAIN, now that the string has been repaired
   foreach (@$regExSubstitutionsRef)
   {
      if ($$_{'FieldName'} =~ /Street$/i)
      {
         $regEx = $$_{'RegEx'};
         $substitute = $$_{'Substitute'};
                 # print "regEx='$regEx', substitute='$substitute'\n";
   
         $streetName =~ s/$regEx/$substitute/egi;
      }
   }
   
   $streetNumber = prettyPrint($streetNumber, 1);
   $streetName = prettyPrint($streetName, 1);
      
   if (($streetNumber ne $$profileRef{'StreetNumber'}) || ($streetName ne $$profileRef{'Street'}))
   {
      #print "FINAL: (WAS:", $$profileRef{'Street'}, " IS:'$streetName', WAS ", $$profileRef{'StreetNumber'}, " IS '$streetNumber')\n";
      #print "FINAL: (NOW '$streetNumber' '$streetName')\n";
   }
   
   return ($streetNumber, $streetName);
}


# -------------------------------------------------------------------------------------------------   
# assessRecordValidity
# attempts to determine if the record is valid and returns a status flag indicating validity
# a value of 0 indicates it's valid, anything greater than 1 indicates invalidity (bin encoding)
# a value of 1 implies it hasn't been validated.
#
# Purpose:
#  validation of the repositories
#
# Parameters:
#  reference to profile
#
# Returns:
#  boolean
#    
sub assessRecordValidity

{
   my $profileRef = shift;
   my $validityCode = 0;
    
   my $streetName = $$profileRef{'Street'};
   
   # default is that the fields are invalid
   my $streetNumberInvalid = 1;
   my $streetNameInvalid = 1;
   my $suburbInvalid = 1;
   my $priceInvalid = 1;
   
   my @validStreetTypeList = ('Street', 'Road', 'Close', 'Avenue', 'Court', 'Place', 'The', 'Way', 
         'Highway', 'Drive', 'Circle', 'Parade', 'Crescent', 'Approach', 'Parkway', 'Turn', 'Elbow', 'Mews',
         'Retreat', 'Gardens', 'Loop', 'Circuit', 'Link', 'Terrace', 'Rise', 'View', 'Corner', 'Cove', 
         'Boulevard', 'Bypass', 'Square', 'Alley', 'Meander', 'Grove', 'Lane', 'Glade', 'Vista', 'Green',
         'Ramble', 'Glen', 'Promenade', 'Trail', 'Pass', 'Dale', 'Ridge', 'Chase', 'Entrance', 'Heights', 'Outlook',
         'Bend', 'Walk', 'Circus', 'Crest', 'Key', 'Terrace', 'Mall', 'Row');

   # --- assess whether the street number is valid - it needs to contain a number or Lot\s ---   
   $streetNumber = $$profileRef{'StreetNumber'};
   if (($streetNumber =~ /\d/g) || ($streetNumber =~ /Lot\s/gi))
   {
      $streetNumberInvalid = 0;
   }

   # --- assess whether the street name is valid - in needs to contain a valid street type ---   
   $string = regexEscape($streetName);
   $found = 0;
   # loop through the list of patterns
   foreach (@validStreetTypeList)
   {
      # check if the string contains the current pattern
      $comparitor = regexEscape($_);
      if ($string =~ /$comparitor/gi)
      {
         # pattern matched - break out of the loop 
         $found = 1;
         last;
      }
      else
      {
         $index++;
      }
   }
   
   if ($found)
   {
      $streetNameInvalid = 0;
   }
   
   # --- assess whether the suburb is valid - needs a suburbindex ---
   if ($$profileRef{'SuburbIndex'})
   {
      $suburbInvalid = 0;
   }
   
   
   # --- calculate the validity code -  binary encoding to show status --
  
   # zero implies it hasn't been validated at all - 1 means a validation has been performend and it's ok
   # anything greater than 1 implies valididity failed
   $validityCode =  ($streetNumberInvalid << 1) | ($streetNameInvalid << 2) | ($suburbInvalid << 3);
   
   if ($validityCode > 1)
   {
      #print $$profileRef{'Identifier'}, ": $validityCode '", $$profileRef{'StreetNumber'}, "' '", $$profileRef{'Street'}, "' ", $$profileRef{'SuburbName'}, "(", $$profileRef{'SuburbIndex'}, ") \n";
      
      if (($validityCode & 8) > 0)
      {
       #  print "   suburbInvalid\n";
      }
      if (($validityCode & 4) > 0)
      {
        # print "   streetInvalid\n";
      }
      if (($validityCode & 2) > 0)
      {
         #print "   streetNumberInvalid\n";
      }
   }
   
   return $validityCode;
}


# -------------------------------------------------------------------------------------------------
# mergeChanges
# merges the changes in the changedProfileHash into the original hash
#
# Purpose:
#  construction of the repositories
#
# Parameters:
#  changedProfileRef
#  originalProfileRef

# Updates:
#  database
#
# Returns:
#  validated sale profile
#    
sub mergeChanges
{
   my $changedProfileRef = shift;
   my $originalProfileRef = shift;
   
   %mergedProfile = %$originalProfileRef;
   
   while (($key, $value) =each(%$changedProfileRef))
   {
      # apply the change
      $mergedProfile{$key} = $value;
   }
   
   return %mergedProfile;
}

# -------------------------------------------------------------------------------------------------
# validateRecord
# validates the fields in the property record (for correctness) and returns changed values for
# the change log
# OPERATE ON THE WORKING VIEW
#
# Purpose:
#  construction of the repositories
#
# Parameters:
#  saleProfile hash

# Updates:
#  database
#
# Returns:
#  validated sale profile
#    
sub validateRecord
{
   my $sqlClient = shift;
   my $profileRef = shift;
   my $regExSubstitutionsRef = shift;
   my $advertisedSaleProfiles = shift;
   my $instanceID = shift;
   my $transactionNo = shift;
   my %changedProfile;
   my $changed = 0;
   my $success = 0;
   my $validityCode = 1;
   
   # if the suburbIndex isn't set then try to fix the suburb name
   if (!$$profileRef{'SuburbIndex'})
   {
      ($suburbName, $suburbIndex) = repairSuburbName($profileRef, $regExSubstitutionsRef);
      
      if (($suburbName) && ($suburbIndex))
      {
         $changedProfile{'SuburbName'} = $suburbName;
         $changedProfile{'SuburbIndex'} = $suburbIndex;
         $changed = 1;
      }
     
   }  
   
   # --- validate the street name ---
   # only proceed if the suburb is now recognised
   if (($$profileRef{'SuburbIndex'}) || ($changedProfile{'SuburbIndex'}))
   {
      ($streetNumber, $street) = repairStreetName($profileRef, $regExSubstitutionsRef);
      
      if ($streetNumber ne $$profileRef{'StreetNumber'})
      {
         $changedProfile{'streetNumber'} = $streetNumber;
         $changed = 1;
      }
      
      if ($street ne $$profileRef{'Street'})
      {
         $changedProfile{'street'} = $street;
         $changed = 1;
      }
   }
   
   # --------------------------------
   if ($changed)
   {
      # if a record was modified, add it to the database as a changed record
      $success = $advertisedSaleProfiles->changeRecord(\%changedProfile, $$profileRef{'sourceURL'}, $instanceID, $transactionNo, $$profileRef{'Identifier'}, "VAL");
      if ($success)
      {      
         # assess the validity of the changed record and add the validity code to the working view
         
         # --- validate the record with the changes incorporated ---
         %finalProfile = mergeChanges(\%changedProfile, $profileRef);
         $validityCode = assessRecordValidity(\%finalProfile);
                  
         # note the direct method is used as the validity isn't tracked in the changetable, otherwise every 
         # record would have at least one changed which is inappropriate
         $advertisedSaleProfiles->workingView_setSpecialField($$profileRef{'Identifier'}, 'ValidityCode', $validityCode);
      }
   }
   else
   {
      # assess the validiity of the unchanged record and add the validity to the working view
      
      $validityCode = assessRecordValidity($profileRef);
      
      # note the direct method is used as the validity isn't tracked in the changetable, otherwise every 
      # record would have at least one changed which is inappropriate
      $advertisedSaleProfiles->workingView_setSpecialField($$profileRef{'Identifier'}, 'ValidityCode', $validityCode);
         
   }
   
   return ($success, $validityCode);
}

# -------------------------------------------------------------------------------------------------

# this function compares the name to a range of letters and returns true if it's inside the range
# used when limiting the search to a letter-range
sub isSuburbNameInRange                     
{
   my $suburbName = shift;
   my $startLetter = shift;
   my $endLetter = shift;
   my $acceptSuburb = 1;
   
   #($firstChar, $restOfString) = split(//, $_->{'text'});
   #print $_->{'text'}, " FC=$firstChar ($startLetter, $endLetter) ";
   $acceptSuburb = 1;
   if ($startLetter)
   {                              
      # if the start letter is defined, use it to constrain the range of 
      # suburbs processed
      # if the first letter if less than the start then reject               
      if ($suburbName le $startLetter)
      {
         # out of range
         $acceptSuburb = 0;
         #print $_->{'text'}, " out of start range (start=$startLetter)\n";
      }                              
   }
              
   if ($endLetter)
   {               
      # if the end letter is defined, use it to constrain the range of 
      # suburbs processed
      # if the first letter is greater than the end then reject       
      if ($suburbName ge $endLetter)
      {
         # out of range
         $acceptSuburb = 0;
         #print "'", $_->{'text'}, "' out of end range (end='$endLetter')\n";
      }               
   }
   return $acceptSuburb;
}  
# -------------------------------------------------------------------------------------------------

# the parsers are given a string that represents its hierarchy in the processing chain
# this function returns the name of the parent only
sub extractOnlyParentName
{
   my $parentLabel = shift;
   my $parentName = undef;
   
   @splitLabel = split /\./, $parentLabel;
   $parentName = $splitLabel[$#splitLabel];  # extract the last name from the parent label

   return $parentName;
}
# -------------------------------------------------------------------------------------------------

