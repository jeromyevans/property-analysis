#!/usr/bin/perl
# 19 Apr 05
# Parses the specified directory of logged OriginatingHTML files and upgrades the localtime=<unixtime epoch>
# to the new time formate  'YYYY-MM-DD HH:MM:SS'
# rewrites the source files.
#
# History:
#
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
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
use AdvertisedPropertyProfiles;
use AgentStatusServer;
use PropertyTypes;
use WebsiteParser_Common;
use WebsiteParser_REIWA;
use WebsiteParser_Domain;
use WebsiteParser_RealEstate;
use DomainRegions;
use Validator_RegExSubstitutes;
use MasterPropertyTable;
use StatusTable;
use SuburbAnalysisTable;
use Time::Local;

# -------------------------------------------------------------------------------------------------    

# -------------------------------------------------------------------------------------------------    

($parseSuccess, %parameters) = parseParameters();

my $printLogger = PrintLogger::new("", "fixOriginatingHTMLTimestamp.stdout", 1, 1, 0);
$printLogger->printHeader("Fix OriginatingHTML timestamp...\n");

if ($parseSuccess)
{
  
   my $originatingHTML = OriginatingHTML::new(undef);
   # read the list of log files...   
   
   $printLogger->print("Recursing into specified OriginatingHTML directory...\n");
  
   recurseDirectory($parameters{"ip"}."/", $printLogger, $originatingHTML);
}
else
{
   print "Specify input path contining originatingHTML:\n";
   print "ip=$sourcePath\n";
}
   

$printLogger->printFooter("Finished\n");

exit 0;
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------

sub parseOriginatingHTMLFile
{
   my $path = shift;
   my $sourceFileName = shift;
   my $printLogger = shift;
   my $originatingHTML = shift;
 
   my $SEEKING_HEADER = 0;
   my $IN_HEADER = 1;
   my $FINISHED_HEADER = 2;

   my $content;
   my $lineNo;
   my $state;
   
   # read the source file
   $filename = $path.$sourceFileName;
   
   
   #IMPORTANT - ensure updates are written only to the SOURCE directory
   $originatingHTML->overrideBasePath($path);  
   #IMPORTANT - as the files are being parsed one-by-one, ensure they're written in the same directory
   # structure - turn on the flat path so new subdirectories are not created
   $originatingHTML->useFlatPath();
      
   # extract the identifier from the filename
   $identifier = $sourceFileName;
   $identifier =~ s/\.html//gi;
    
   # read the sourcefile content and header - the header is stripped from the content
   ($content, $sourceurl, $timestamp) = $originatingHTML->readHTMLContentWithHeader($identifier, 1);
   
   #---- check the format of the timestamp ----
   
   $rewriteLog = 1;   # this flag indicates that the file needs to be rewritten (updated timestamp)
   #check the format of the timestamp... is it only digits?
   if ($timestamp =~ /\D/g)
   {
      # contains a non-digit - it's probably the correct format - leave it alone
      $rewriteLog = 0; 
   }
   else
   {
      # contains only digits - it's probably the wrong format - decompose into elements
     ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($timestamp);
     
     $newTimestamp = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec);
   }
   
   # --- if the timestamp format is wrong, rewrite the record ----
   
   if ($rewriteLog)
   {
      $printLogger->print("   FIXING ID:$identifier ($sourceFileName) ($newTimestamp)\n");
      
      # write the content back again with the new timestamp format
      $originatingHTML->saveHTMLContent($identifier, $content, $sourceurl, $newTimestamp);
   }
   else
   {
      $printLogger->print("   ID:$identifier ($sourceFileName) timestamp is okay\n");
   }
}

# -------------------------------------------------------------------------------------------------
# this function:
#  reads the list of files in the specified directory
#  opens each file and calls a parser on it
#  recurses back into this function in each subdirectory
sub recurseDirectory
{
   my $path = shift;
   my $printLogger = shift;
   my $originatingHTML = shift;
   
   my @listing;
   my @subdirectory;
   print "Entering $path\n";
   opendir(DIR, $path) or die "Can't open $path: $!";
   
   $files = 0;
   $subdirectories = 0;
   while ( defined ($file = readdir DIR) ) 
   {
      next if $file =~ /^\.\.?$/;     # skip . and ..
      if ($file =~ /\.html$/i)        # is the extension .html...
      {
         # add this file...
         $listing[$files] = $file;
         $files++;
      }
      else
      {
         $subdirectory[$subdirectories] = $path.$file;
         $subdirectories++;
      }
   }
   closedir(BIN);
   print "   $files files, $subdirectories subdirectories\n";

   # --- source the listings ---
   # filenames are sorted numerically
   @listing = sort { $a <=> $b } @listing;
   @subdirectory = sort @subdirectory;
   
   # --- parse the files in this directory ---
   foreach (@listing)
   {
      $sourceFileName = $_;
      parseOriginatingHTMLFile($path."/", $sourceFileName, $printLogger, $originatingHTML);
      $transactionNo++;
   }

   # --- recurse into subdirectories ---
   foreach (@subdirectory)
   {
      @subdirectoryListing = recurseDirectory($_, $printLogger, $originatingHTML);
   }
   return @listing;
}

# -------------------------------------------------------------------------------------------------
# parses any specified command-line parameters

sub parseParameters
{      
   my %parameters;
   my $success = 0;

   $parameters{'ip'} = param('ip');
   
   if ($parameters{'ip'})
   {
      $success = 1;
   }
   # if successfully read the mandatory parameters, now get optional ones...
   if ($success)
   {
      
      $parameters{'agent'} = "FixOriginatingHTML";         
      
      # temporary hack so the useText command doesn't have to be explicit
      if (!$parameters{'useHTML'})
      {
         $parameters{'useText'} = 1;
      }
      
      # 25 July 2004 - generate an instance ID based on current time and a random number.  The instance ID is 
      # used in the name of the logfile
      my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
      $year += 1900;
      $mon++;
      my $randNo = rand 1000;
      my $instanceID = sprintf("%s_%4i%02i%02i%02i%02i%02i_%04i", $parameters{'agent'}, $year, $mon, $mday, $hour, $min, $sec, $randNo);
      $parameters{'instanceID'} = $instanceID;
     
   }
   
   return ($success, %parameters);   
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

