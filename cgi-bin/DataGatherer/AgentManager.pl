#!/usr/bin/perl
# 16 Mar 04
# 
# Central application to start and stops agent applications 
#  forks to create a child for each instance so a PIPE can be established to 
# communication with each child.  This has the advantage of a the centreal 
# agent maintaining knowledge of the children so it can implement a
# real-time status function 
#
# To do:
#  - put GetAdvertisedRentals, GetAdvertisedSales & GetSuburbProfiles into a
#   common class and instantiate the agent from here based on the child parameter 
#
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
use PrintLogger;
use CGI qw(:standard);
use DebugTools;

#  
# -------------------------------------------------------------------------------------------------    
# fetch CGI parameters
my $agent = param('agent');
my $childAgent = param('child');
my $useHTML = param('html');

# -------------------------------------------------------------------------------------------------

if (!$useHTML)
{
   $useText = 1;   
}

if (!$agent)
{
   $agent = "AgentManager";
}

my $printLogger = PrintLogger::new($agent, $agent.".stdout", 1, $useText, $useHTML);
my $childPID;

$printLogger->printHeader("AgentManager\n");

$printLogger->print("   main: forking\n");
   
if (!defined($childPID = fork()))   
{
    $printLogger->print("   main: fork failed\n");
} 
elsif ($childPID) 
{       
    # This is the parent     
   $printLogger->print("   main: child started\n");        
   $printLogger->printFooter("main: Finished\n");
   
}
else
{    
   # this is the child - start agent
   $result = 1;
   print "childAgent = $childAgent\n";
   $printLogger->print("   chld: starting agent...\n");
   if ($childAgent eq 'salesAgent')
   {
      $printLogger->print("   chld: salesAgent\n");
   }
   elsif ($childAgent eq 'rentalAgent')
   {
      $printLogger->print("   chld: rentalAgent\n");  
   }         
   else
   {
      $printLogger->print("   chld: agent not recognised\n");
   }
   $printLogger->printFooter("chld: Finished\n");
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

