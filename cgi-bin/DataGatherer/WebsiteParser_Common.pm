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
use PrintLogger;
use CGI qw(:standard);
use HTTPClient;
use HTMLSyntaxTree;
use SQLClient;
use SuburbProfiles;
#use URI::URL;
use DebugTools;
use DocumentReader;
use AdvertisedSaleProfiles;
use AdvertisedRentalProfiles;
use AgentStatusServer;
use PropertyTypes;

@ISA = qw(Exporter);

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
# validateProfile
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
sub validateProfile
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

