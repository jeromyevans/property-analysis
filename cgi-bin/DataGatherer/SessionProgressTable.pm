#!/usr/bin/perl
# Written by Jeromy Evans
# Started 22 January 2005
# 
# WBS: A.01.03.01 Developed On-line Database
# Version 0.1  
#
# Description:
#   Module that encapsulate the SessionProgress database table.  The SessionProgress table is used to track
# which region/suburb a thread is currently in, as well as keeping a log of all the previously processed 
# suburbs for the thread.  It's purpose is for tracking and recovery
# 
# History:
# 2 April 2005 - added index to the table on threadid, region, suburb used to increase lookup speed
# 8 May 2005   - fixed typo in text adding the index above
#
# CONVENTIONS
# _ indicates a private variable or method
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
package SessionProgressTable;
require Exporter;

use DBI;
use SQLClient;

@ISA = qw(Exporter);

#@EXPORT = qw(&parseContent);

# -------------------------------------------------------------------------------------------------
# PUBLIC enumerations
#
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

# Contructor for the SessionProgressTable - returns an instance of this object
# PUBLIC
sub new
{   
   my $sqlClient = shift;
   
   my $sessionProgressTable = { 
      sqlClient => $sqlClient,
      tableName => "SessionProgressTable",
      restartLastRegion => 0,   # instance variables to control the recovery state machine
      continueNextRegion => 0,
      useNextRegion => 0,
      lastSuburbDefined => 0,
      useNextSuburb => 0,
      stillSeeking => 0
   }; 
      
   bless $sessionProgressTable;     
   
   return $sessionProgressTable;   # return this
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# createTable
# attempts to create the sessionProgressTable table in the database if it doesn't already exist 
#
# Purpose:
#  Initialising a new database
#
# Parameters:
#  nil
#
# Constraints:
#  nil
#
# Uses:
#  sqlClient
#
# Updates:
#  nil
#
# Returns:
#   TRUE (1) if successful, 0 otherwise
#

my $SQL_CREATE_STATUS_TABLE = 
   "ThreadID INTEGER, ".
   "SequenceNo BIGINT PRIMARY KEY AUTO_INCREMENT, ".
   "DateEntered DATETIME, ".
   "Region TEXT, ".
   "Suburb TEXT, ".
   "RecordsEncountered INTEGER DEFAULT 0, ".
   "Completed INTEGER DEFAULT 0";
 
sub createTable

{
   my $this = shift;
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $tableName = $this->{'tableName'};
 
   my $SQL_CREATE_TABLE_PREFIX = "CREATE TABLE IF NOT EXISTS $tableName (";
   my $SQL_CREATE_TABLE_SUFFIX = ", INDEX (ThreadID, Region(10), Suburb(10))";
   
   if ($sqlClient)
   {
      # append table prefix, original table body and table suffix
      $sqlStatement = $SQL_CREATE_TABLE_PREFIX.$SQL_CREATE_STATUS_TABLE.$SQL_CREATE_TABLE_SUFFIX;
      
      $statement = $sqlClient->prepareStatement($sqlStatement);
      
      if ($sqlClient->executeStatement($statement))
      {
         $success = 1;
      }
   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# reportRegionOrSuburbChange
# adds a record to the progressTable for the specified thread indicating that it's starting a
# new region or suburb
#
# Purpose:
#  Storing information in the database
#
# Parameters:
#  integer threadID
#  string region
#  string currentSuburb
#
# Constraints:
#  nil
#
# Uses:
#  sqlClient
#
# Updates:
#  nil
#
# Returns:
#   TRUE (1) if successful, 0 otherwise
#        
sub reportRegionOrSuburbChange

{
   my $this = shift;
   my $threadID = shift;
   my $region = shift;
   my $suburb = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   my $tableName = $this->{'tableName'};
  
   if ($sqlClient)
   {
      
      # lookup the last region and suburb
      ($lastRegion, $lastSuburb) = $this->getLastRegionAndSuburb($threadID);

      # if the region isn't specified, then look it up automatically...
      if (!$region)
      {
         $region = $lastRegion;
      }
      #print "lastRegion: $lastRegion, region=$region, lastSuburb=$lastSuburb, suburb=$suburb\n";
      #check if region and suburb match the last pair - if they do, then there's nothing to change
      if (($lastSuburb eq $suburb) && ($lastRegion eq $region))
      {
         # no update required - this is an okay state, for example if a parse is on the second page for the same suburb and region
         # it may not know that it isn't the first time the suburb has been processed
      }
      else
      {
      
         $quotedRegion = $sqlClient->quote($region);
         $quotedSuburb = $sqlClient->quote($suburb);
         
         $statementText = "insert into $tableName (threadID, dateEntered, region, suburb) VALUES ($threadID, now(), $quotedRegion, $quotedSuburb)";
         $statement = $sqlClient->prepareStatement($statementText);
               
         if ($sqlClient->executeStatement($statement))
         {       
            $success = 1;
         }
      }
   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------
# reportProgressAgainstSuburb
# updates the last record in the progressTable for the specified thread reporting progress against the current suburb
#   increments the number of records processed by the specified amount
#
# Purpose:
#  Storing information in the database
#
# Parameters:
#  integer threadID
#  integer additional recordsProcessed
#
# Constraints:
#  nil
#
# Uses:
#  sqlClient
#
# Updates:
#  nil
#
# Returns:
#   TRUE (1) if successful, 0 otherwise
#        
sub reportProgressAgainstSuburb

{
   my $this = shift;
   my $threadID = shift;
   my $recordsProcessed = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   my $tableName = $this->{'tableName'};
  
   if ($sqlClient)
   {
      ($region, $suburb) = $this->getLastRegionAndSuburb($threadID);
      
      if ($region)
      {
         $quotedRegionExpr = "region = ".$sqlClient->quote($region);
      }
      else
      {
         $quotedRegionExpr = "region is null"
      }
      
      $quotedSuburb = $sqlClient->quote($suburb);
      
      $statementText = "update $tableName ".
                       " set recordsEncountered=recordsEncountered+$recordsProcessed ".
                       " where threadID=$threadID and $quotedRegionExpr and suburb = $quotedSuburb";
      $statement = $sqlClient->prepareStatement($statementText);
            
      if ($sqlClient->executeStatement($statement))
      {       
         $success = 1;
      }
   }
   
   return $success;   
}


# -------------------------------------------------------------------------------------------------
# reportSuburbCompletion
# updates the last record in the progressTable for the specified thread reporting progress against the current suburb
#   increments the number of records processed by the specified amount
#
# Purpose:
#  Storing information in the database
#
# Parameters:
#  integer threadID
#  string suburbname [optional - uses last if not defined]
# Constraints:
#  nil
#
# Uses:
#  sqlClient
#
# Updates:
#  nil
#
# Returns:
#   TRUE (1) if successful, 0 otherwise
#        
sub reportSuburbCompletion

{
   my $this = shift;
   my $threadID = shift;
   my $suburb = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   my $tableName = $this->{'tableName'};
  
   if ($sqlClient)
   {
      ($region, $lastSuburb) = $this->getLastRegionAndSuburb($threadID);
      
      if ($region)
      {
         $quotedRegionExpr = "region = ".$sqlClient->quote($region);
      }
      else
      {
         $quotedRegionExpr = "region is null"
      }
      
      if (!$suburb)
      {
         $suburb = $lastSuburb;
      }
      
      $quotedSuburb = $sqlClient->quote($suburb);
      
      $statementText = "update $tableName ".
                       " set completed=1 ".
                       " where threadID=$threadID and $quotedRegionExpr and suburb = $quotedSuburb";
      $statement = $sqlClient->prepareStatement($statementText);
            
      if ($sqlClient->executeStatement($statement))
      {       
         $success = 1;
      }
   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------
# getLastRegion
# returns the current region name of the specified thread
#
# Purpose:
#  Storing information in the database
#
# Parameters:
#  string threadID
#  
#
# Constraints:
#  nil
#
# Uses:
#  sqlClient
#
# Updates:
#  nil
#
# Returns:
#   TRUE (1) if successful, 0 otherwise
#        
sub getLastRegion

{
   my $this = shift;
   my $threadID = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   my $tableName = $this->{'tableName'};
   my $localTime;
   my $instanceID = undef;
      
   if ($sqlClient)
   {
     
#      print "   SessionProgressTable:requesting last region for thread $threadID...\n";

      # select the last valid region for the thread 
      $sqlStatement = "select region from $tableName where threadID=$threadID and region is not null order by SequenceNo desc limit 1";
       
      @selectResults = $sqlClient->doSQLSelect($sqlStatement);
        
      # only zero or one result should be returned - if there's more than one, then we have a problem, to avoid it always take
      # the last entry in the list due to the 'order by' command
      $length = @selectResults;
      if ($length > 0)
      {
         $lastRecordHashRef = $selectResults[$#selectResults];
         $region = $$lastRecordHashRef{'region'};
      }
      
 #      print "               last region was '$region'.\n";
   }
   
   return $region;
}        

# -------------------------------------------------------------------------------------------------
# getLastSuburb
# returns the current suburb name of the specified thread
#
# Purpose:
#  Storing information in the database
#
# Parameters:
#  string threadID
#  
#
# Constraints:
#  nil
#
# Uses:
#  sqlClient
#
# Updates:
#  nil
#
# Returns:
#   TRUE (1) if successful, 0 otherwise
#        
sub getLastSuburb

{
   my $this = shift;
   my $threadID = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   my $tableName = $this->{'tableName'};
   my $localTime;
   my $instanceID = undef;
      
   if ($sqlClient)
   {
     
      #print "   SessionProgressTable:requesting last suburb for thread $threadID...\n";

      # select the last valid region for the thread 
      $sqlStatement = "select suburb from $tableName where threadID=$threadID and suburb is not null order by SequenceNo desc limit 1";
       
      @selectResults = $sqlClient->doSQLSelect($sqlStatement);
        
      # only zero or one result should be returned - if there's more than one, then we have a problem, to avoid it always take
      # the last entry in the list due to the 'order by' command
      $length = @selectResults;
      if ($length > 0)
      {
         $lastRecordHashRef = $selectResults[$#selectResults];
         $suburb = $$lastRecordHashRef{'suburb'};
      }
      
       #print "               last suburb was '$suburb'.\n";
   }
   
   return $suburb;
}        


# -------------------------------------------------------------------------------------------------
# getLastRegionAndSuburb
# returns the current region and suburb name of the specified thread
#
# Purpose:
#  Storing information in the database
#
# Parameters:
#  string threadID
#  
#
# Constraints:
#  nil
#
# Uses:
#  sqlClient
#
# Updates:
#  nil
#
# Returns:
#   TRUE (1) if successful, 0 otherwise
#        
sub getLastRegionAndSuburb

{
   my $this = shift;
   my $threadID = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   my $tableName = $this->{'tableName'};
   my $localTime;
   my $instanceID = undef;
      
   if ($sqlClient)
   {
      # select the last valid region for the thread 
      $sqlStatement = "select region, suburb from $tableName where threadID=$threadID order by SequenceNo desc limit 1";
      @selectResults = $sqlClient->doSQLSelect($sqlStatement);
        
      # IMPORTANT: zero or more results will be retuned, more thane one if multiple records have the same timestamp
      # only zero or one result should be returned - if there's more than one, then we have a problem, to avoid it always take
      # the last entry in the list due to the 'order by' command
      $length = @selectResults;
      if ($length > 0)
      {
         $lastRecordHashRef = $selectResults[$#selectResults];
         $region = $$lastRecordHashRef{'region'};
         $suburb = $$lastRecordHashRef{'suburb'};
      }      
   }
      
   return ($region, $suburb);
}        

# -------------------------------------------------------------------------------------------------
# releaseSession
# removes session information for the specified thread (no longer needed)
#
# Purpose:
#  Storing information in the database
#
# Parameters:
#  integer threadID
#  
#
# Constraints:
#  nil
#
# Uses:
#  sqlClient
#
# Updates:
#  nil
#
# Returns:
#   TRUE (1) if successful, 0 otherwise
#        
sub releaseSession

{
   my $this = shift;
   my $threadID = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   my $tableName = $this->{'tableName'};
   my $localTime;
 
      
   if ($sqlClient)
   {      
      print "   SessionProgressTable:releasing threadID $threadID session information...";
      $statementText = "delete from $tableName where threadID=$threadID";
               
      $statement = $sqlClient->prepareStatement($statementText);
            
      if ($sqlClient->executeStatement($statement))
      {       
         $success = 1;
         print "ok\n";
      }
      else
      {
         print "failed (delete from)\n";  
      }
   
   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------
# dropTable
# attempts to drop the SessionProgressTable table 
# 
# Purpose:
#  Initialising a new database
#
# Parameters:
#  nil
#
# Constraints:
#  nil
#
# Uses:
#  sqlClient
#
# Updates:
#  nil
#
# Returns:
#   TRUE (1) if successful, 0 otherwise
#
        
sub dropTable

{
   my $this = shift;
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $tableName = $this->{'tableName'};
   
   if ($sqlClient)
   {
      $statementText = "DROP TABLE $tableName";
      $statement = $sqlClient->prepareStatement($statementText);
      
      if ($sqlClient->executeStatement($statement))
      {
         $success = 1;
      }
   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------


   
# this method is used to check where to start processing regions
# can either process all regions from the first encountered, recover the last processed, or just keep
# processing the next one.  Depends on the information recorded for the lastRegion processed in this thread
# and the region last processed in this process INSTANCE
sub prepareRegionStateMachine
{
   my $this = shift;
   my $threadID = shift;
   my $currentRegion = shift;

   my $lastRegion = $this->getLastRegion($threadID);  # load the last region processed in this thread
   $this->{'lastRegion'} = $lastRegion;
   
   $this->{'continueNextRegion'} = 0;
   $this->{'useNextRegion'} = 0;
   $this->{'restartLastRegion'} = 0;
   
   # if not already processing regions in this process instance check if 
   # continuing a thread or starting from scratch
   if ((!defined $currentRegion) || ($currentRegion =~ /Nil/i))
   {
      # the last region isn't defined for this thread - start from the beginning
      if ((!defined $lastRegion) || ($lastRegion =~ /Nil/i))
      {
         $this->{'useNextRegion'} = 1;
       #        print "   use n   ext region\n";

      }
      else
      {
         # the last region is defined in the recovery file - continue processing that region
         # as isn't know if it terminated correctly
         $this->{'restartLastRegion'} = 1;
        #                print "   restart last region\n";

      }
   }
   else
   {
      #print "   continuing next region\n";

      # continue from the next region in the list (still in the same process)
      $this->{'continueNextRegion'} = 1;
   }   
}

# -------------------------------------------------------------------------------------------------

# this method checks the recovery state machine to determine whether this region should be processed - if it's still
# in a start-up mode it may be skipped
sub isRegionAcceptable

{
   my $this = shift;
   my $regionName = shift;
   my $currentRegion = shift;
   my $useThisRegion = 0;
   
   
   #print "UNR:", $this->{'useNextRegion'}, " CNR:", $this->{'continueNextRegion'}, " RLR:", $this->{'restartLastRegion'}, "\n";
   
   if (!$this->{'useNextRegion'})
   {       
      # if the lastRegion processed with the current checkbox then the next checkbox is the 
      # one to process this time
      if ($this->{'continueNextRegion'})
      {            
         # have previously processed a region - move onto the next one
         if ($currentRegion eq $regionName)
         {
            # this is the last region processed - set a flag to use the next one instead
            #print "   **setting useNextRegion to 1 as currentValue = ", $regionName, "\n";
            $this->{'useNextRegion'} = 1;

         }
         else
         {
           #print "   **seeking currentRegion ($currentRegion isn't ", $regionName,")\n";
         }
      }
      else
      {
         if ($this->{'restartLastRegion'})
         {
            # restart from the region in the recovery file
            if ($this->{'lastRegion'} eq $regionName)
            {
               # this is it - start from here
               $useThisRegion = 1;
            }
         }
         else
         {
            # otherwise we're continuing from the start
            #print "   **setting use this region ", $regionName, "\n";
            $useThisRegion = 1;
         }
      }
   }
   else
   {
      # the $useNextRegion flag was set in the last iteration - now set useThisRegion flag
      # to processs this one
      $useThisRegion = 1;
   }

   #print "SessionProgressTable:isRegionAcceptable($regionName) = $useThisRegion\n";
   
   return $useThisRegion;         
}

# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
 
# this method is used to check where to start processing suburbs
# can either process all suburbs in the region or recover the last one processed, or just keep
# processing the next one.  Depends on the information recorded for the lastSuburb processed in this thread
sub prepareSuburbStateMachine
{
   my $this = shift;
   my $threadID = shift;

   my $lastSuburb = $this->getLastSuburb($threadID);
   $this->{'lastSuburb'} = $lastSuburb;

   # if not already processing regions in this process instance check if 
   # continuing a thread or starting from scratch
  
   if ((!defined $lastSuburb) || ($lastSuburb eq 'Nil'))
   {
      # set flag to start at the first suburb
      $this->{'stillSeeking'} = 0;
      $this->{'useNextSuburb'} = 0;
      $this->{'lastSuburbDefined'} = 0;
   }
   else
   {
      # the last suburb is defined
      $this->{'stillSeeking'} = 1;
      $this->{'useNextSuburb'} = 0;
      $this->{'lastSuburbDefined'} = 1;
   }
}
        
# -------------------------------------------------------------------------------------------------


# this method checks the recovery state machine to determine whether this suburb should be processed - if it's still
# in a start-up mode it may be skipped
sub isSuburbAcceptable

{
   my $this = shift;
   my $suburbName = shift;
   my $acceptSuburb = 0;
   
   $lastSuburb = $this->{'lastSuburb'};
   
   if ($this->{'useNextSuburb'})
   {
      $this->{'stillSeeking'} = 0;
   }
   else
   {
      # seek forward to the last suburb processed
      if ($this->{'lastSuburbDefined'})
      {
         # check if this is the last suburb
         if ($suburbName =~ /$lastSuburb/i)
         {
            # this is the last suburb processed - set the flag to start from the next one
            $this->{'useNextSuburb'} = 1;
            $this->{'stillSeeking'} = 1;
         }
      }
      else
      {
         # starting at first suburb
         $this->{'stillSeeking'} = 0;
      }
   }
    
   # only process the suburb once the stillSeeking flag has been cleared...
   if ($this->{'stillSeeking'} == 0)
   {
      $acceptSuburb = 1;
   }
#   print "SessionProgressTable:isSuburbAcceptable($suburbName) = $acceptSuburb\n";
   
   return $acceptSuburb;         
}
           
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# hasSuburbBeenProcessed
# returns true if the specified suburb has already been proceed in this thread - used to avoid
# situations where a server may return the same suburb for multiple searches
#
# Purpose:
#  Storing information in the database
#
# Parameters:
#  string threadID
#  string suburbname
#
# Constraints:
#  nil
#
# Uses:
#  sqlClient
#
# Updates:
#  nil
#
# Returns:
#   TRUE (1) if successful, 0 otherwise
#        
sub hasSuburbBeenProcessed

{
   my $this = shift;
   my $threadID = shift;
   my $suburb = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   my $tableName = $this->{'tableName'};
   
   my $isComplete = 0;
      
   if ($sqlClient)
   {
     
#      print "   SessionProgressTable:checking if suburb '$suburb' already processed for thread $threadID...\n";

      # lookup the last region 
      $region = $this->getLastRegion($threadID);

      if ($region)
      {
         $quotedRegionExpr = "region = ".$sqlClient->quote($region);
      }
      else
      {
         $quotedRegionExpr = "region is null"
      }
      
      $quotedSuburb = $sqlClient->quote($suburb);
      
      
      # select the completed field for the thread and region/suburb combination
      $sqlStatement = "select completed from $tableName where threadID=$threadID and $quotedRegionExpr and suburb=$quotedSuburb";
       
      @selectResults = $sqlClient->doSQLSelect($sqlStatement);
        
      # only zero or one result should be returned - if there's more than one, then we have a problem, to avoid it always take
      # the last entry in the list due to the 'order by' command
      $length = @selectResults;
      if ($length > 0)
      {
         $lastRecordHashRef = $selectResults[$#selectResults];
         $isComplete = $$lastRecordHashRef{'complete'};
      }
    
   }
   
   return $isComplete;
}        

# -------------------------------------------------------------------------------------------------

