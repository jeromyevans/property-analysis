#!/usr/bin/perl
# 12 April 2004
# Jeromy Evans
#
# Print logger - for logging progress information to multiple destinations including:
#   - file
#   - stdout (text)
#   - stdout via CGI (html)
#   - stdout via CGI (xml)

# Version 0.1 - Added escapeHTML for HTML output and substitution of /n with <br\>
# 
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
package PrintLogger;
require Exporter;
use CGI qw(:standard escapeHTML);

@ISA = qw(Exporter);

use DebugTools;

# -------------------------------------------------------------------------------------------------
# new
# contructor for the printLog
#
# Purpose:
#  initialisation of the logger
#
# Parameters:
#  string sessionName
#  string logfile name
#  BOOL logToFile
#  BOOL logToStdout
#  BOOL logToCGI 
#
# Returns:
#  PrintLogger object
#    
sub new
{
   my $sessionName = shift;
   my $logFileName = shift;
   my $logToFile = shift;
   my $logToStdout = shift;
   my $logToCGI = shift;
   
   mkdir "logs", 0755;    
   
   my $printLogger = { 
      sessionName => $sessionName,
      logFileName => "logs/".$logFileName,   
      logToFile => $logToFile,
      logToStdout => $logToStdout,
      logToCGI => $logToCGI
   };               
   
   bless $printLogger;     
   
   return $printLogger;   # return this
}


# -------------------------------------------------------------------------------------------------
# printHeader
# initialise the logger and write standard haedar
#
# Purpose:
#  data logging
#
# Parameters:
#  list of header parametrs
#
# Returns:
#  nil
# 
sub printHeader
{
   my $this = shift;
   my $logFileName = $this->{'logFileName'};   
   my $string;
   
   foreach (@_)
   {
      $string .= $_;
   }
   
   if ($this->{'logToFile'})
   {  
      if ($this->{'logToStdout'})
      {
         print "Logging to file : $logFileName\n";
      }
      open LOG_FILE, ">>$logFileName";      
      print LOG_FILE "---[StartLog]---\n";
      print LOG_FILE $string;            
      close LOG_FILE;
   }     

   if ($this->{'logToStdout'})
   {   
      print $string;      
   }   

   if ($this->{'logToCGI'})
   {      
      print header(), start_html($this->{'sessionName'});      
      print p($string);
   }         	                  
}


# -------------------------------------------------------------------------------------------------
# print
# write information to logger
#
# Purpose:
#  data logging
#
# Parameters:
#  list of parametrs
#
# Returns:
#  nil
# 
sub print
{
   my $this = shift;
   my $logFileName = $this->{'logFileName'};   
   my $string;

   foreach (@_)
   {
      $string .= $_;
   }
   if ($this->{'logToFile'})
   {
      open LOG_FILE, ">>$logFileName";           
      print LOG_FILE $string;            
      close LOG_FILE;
   }     

   if ($this->{'logToStdout'})
   {      
      print $string;     
   }

   if ($this->{'logToCGI'})
   {  
      $htmlString = escapeHTML($string);
      $htmlString =~ s/\n/<br\/>/gi;
      print $htmlString;      
   }                       	                  
}


# -------------------------------------------------------------------------------------------------
# printFooter
# closes the logger
#
# Purpose:
#  data logging
#
# Parameters:
#  list of footer parametrs
#
# Returns:
#  nil
# 
sub printFooter
{
   my $this = shift;
   my $logFileName = $this->{'logFileName'};   
   my $string;
   
   foreach (@_)
   {
      $string .= $_;
   }
   
   if ($this->{'logToFile'})
   {
      open LOG_FILE, ">>$logFileName";      
      print LOG_FILE $string;
      print LOG_FILE "---[EndLog]---\n";            
      close LOG_FILE;
   }     

   if ($this->{'logToStdout'})
   {      
      print $string;      
   }   

   if ($this->{'logToCGI'})
   {     
      print p($string);
      print end_html();      
   }         	                  
}
