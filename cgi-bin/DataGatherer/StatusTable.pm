#!/usr/bin/perl
# Written by Jeromy Evans
# Started 19 January 2005
# 
# WBS: A.01.03.01 Developed On-line Database
# Version 0.1  
#
# Description:
#   Module that encapsulate the StausTable database table.  The statusTable is used to show the progress of all
# the currently running and recently run PublishedMaterialScanner instances and is used for automatic recovery
# of a session.  Previously recover information was maintained in a text file and suffered to conditions where
# multiple different sessions could have the same ID (preventing correct recovery)
# 
# History:
#
# CONVENTIONS
# _ indicates a private variable or method
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
package StatusTable;
require Exporter;

use DBI;
use SQLClient;
use SessionProgressTable;
use SessionURLStack;

@ISA = qw(Exporter);

#@EXPORT = qw(&parseContent);

# -------------------------------------------------------------------------------------------------
# PUBLIC enumerations
#
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

# Contructor for the StatusTable - returns an instance of this object
# PUBLIC
sub new
{   
   my $sqlClient = shift;
   
   my $statusTable = { 
      sqlClient => $sqlClient,
      tableName => "StatusTable"
   }; 
      
   bless $statusTable;     
   
   return $statusTable;   # return this
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# createTable
# attempts to create the statusTable table in the database if it doesn't already exist - also
# populates the table with the default set of thread ID's.
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
   "ThreadID INTEGER PRIMARY KEY, ".
   "Created DATETIME, ".
   "LastActive DATETIME, ".
   "Allocated INTEGER, ".
   "InstanceID TEXT, ".
   "Restarts INTEGER, ".
   "RecordsEncountered INTEGER, ".
   "RecordsParsed INTEGER, ".
   "RecordsAdded INTEGER, ".
   "LastURL TEXT";
 
sub createTable

{
   my $this = shift;
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $tableName = $this->{'tableName'};
 
   my $SQL_CREATE_TABLE_PREFIX = "CREATE TABLE IF NOT EXISTS $tableName (";
   my $SQL_CREATE_TABLE_SUFFIX = ")";
   
   if ($sqlClient)
   {
      # append table prefix, original table body and table suffix
      $sqlStatement = $SQL_CREATE_TABLE_PREFIX.$SQL_CREATE_STATUS_TABLE.$SQL_CREATE_TABLE_SUFFIX;
      
      $statement = $sqlClient->prepareStatement($sqlStatement);
      
      if ($sqlClient->executeStatement($statement))
      {
         $success = 1;
         
         # populate the table with 127 default threads
         for ($threadID = 1; $threadID < 128; $threadID++)
         {
            
            $statementText = "INSERT INTO ".$this->{'tableName'}.
                             "(threadID, created, lastActive, allocated, instanceID, restarts, recordsEncountered, recordsParsed, recordsAdded, lastURL) VALUES ".
                             "($threadID, null, null, 0, null, 0, 0, 0, 0, null)";
            
            $statement = $sqlClient->prepareStatement($statementText);
      
            if ($sqlClient->executeStatement($statement))
            {
            }
         }
      }
   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------
# requestNewThread
# allocates one of the threads in the status table to a new session instance
#
# Purpose:
#  Storing information in the database
#
# Parameters:
#  string instanceID
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
sub requestNewThread

{
   my $this = shift;
   my $instanceID = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   my $tableName = $this->{'tableName'};
   my $localTime;
   my $threadID = 0;
   my $threadIDSet = 0;
   my $triedCleanup = 0;
   my $triedHardCleanup = 0;
      
   if ($sqlClient)
   {
      while (!$threadIDSet)
      {
         print "   StatusTable:requesting new threadID...";

         # select the threadID of the least-recently used unallocated thread
         $sqlStatement = "select threadID from $tableName where allocated=0 order by lastActive desc limit 1";
          
         @selectResults = $sqlClient->doSQLSelect($sqlStatement);
           
         # only zero or one result should be returned - if there's more than one, then we have a problem, to avoid it always take
         # the last entry in the list due to the 'order by' command
         $length = @selectResults;
         if ($length > 0)
         {
            $lastRecordHashRef = $selectResults[$#selectResults];
            $threadID = $$lastRecordHashRef{'threadID'};
            
            $quotedInstanceID = $sqlClient->quote($instanceID);
            $statementText = "UPDATE ".$this->{'tableName'}." ".
                             "set created=now(), lastActive=now(), allocated=1, instanceID=$quotedInstanceID, restarts=0, recordsEncountered=0, recordsParsed=0, recordsAdded=0, lastURL=null ".
                             "WHERE threadID = $threadID";
            
            $statement = $sqlClient->prepareStatement($statementText);
      
            if ($sqlClient->executeStatement($statement))
            {
               print "ok (new $threadID)\n";
               $threadIDSet = 1;
               # IMPORTANT - clear the session information for this previous use of this thread, if still defined
               # otherwise it might think it needs to recover from a previous position
               $sessionProgressTable = SessionProgressTable::new($sqlClient);
               $sessionProgressTable->releaseSession($threadID);
               
               # IMPORTANT - clear the URLstack previously used for this thread, if still defined
               # otherwise it might think it needs to recover from that position
               $sessionURLStack = SessionURLStack::new($sqlClient);
               $sessionURLStack->releaseSession($threadID);
            
            }
            else
            {
               print " initialisation for new thread $threadID failed\n";
               $threadIDSet = 1;
               $threadID = -1;
            }
         }
         else
         {
            if (!$triedCleanup)
            {
               print " cleaning up threads inactive more than 1 day...\n";
               # there's no unallocated threads - this is probably because they've all exited abnormally.  Clean up
               # the table instead
               $triedCleanup = 1;
               $statementText = "update $tableName set allocated=0 where lastActive < date_add(now(), interval -1 day)";
               
               $statement = $sqlClient->prepareStatement($statementText);
                     
               if ($sqlClient->executeStatement($statement))
               {       
                  $success = 1;
               }
            }
            else
            {
               if (!$triedHardCleanup)
               {
                  print " cleaning up threads inactive more than 1 hour...\n";
                  # there's no unallocated threads - this is probably because they've all exited abnormally.  Clean up
                  # the table instead
                  $triedHardCleanup = 1;
                  $statementText = "update $tableName set allocated=0 where lastActive < date_add(now(), interval -2 hour)";
                  
                  $statement = $sqlClient->prepareStatement($statementText);
                        
                  if ($sqlClient->executeStatement($statement))
                  {       
                     $success = 1;
                  }
               }
               else
               {
                  # abort - can't imagine it every getting here, but possible... the return a threadID of -1
                  # to indicate failure
                  print " failed again.  Aborting.\n";
                  $threadID = -1;
                  $threadIDSet = 1;
               }
            }
         }      
      }
   }
   
   return $threadID;   
}

# -------------------------------------------------------------------------------------------------
# continueThread
# re-allocates the specified thread in the status table to a new session instance
#
# Purpose:
#  Storing information in the database
#
# Parameters:
#  integer threadID
#  string instanceID
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
sub continueThread

{
   my $this = shift;
   my $threadID = shift;
   my $instanceID = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   my $tableName = $this->{'tableName'};
   my $localTime;
 
      
   if ($sqlClient)
   {

      $quotedInstanceID = $sqlClient->quote($instanceID);
      
      print "   StatusTable:requesting continuation of threadID $threadID...";
      $statementText = "update $tableName set allocated=1,instanceID=$quotedInstanceID,restarts=restarts+1 where threadID=$threadID";
               
      $statement = $sqlClient->prepareStatement($statementText);
            
      if ($sqlClient->executeStatement($statement))
      {       
         $success = 1;
         print "ok\n";
      }
      else
      {
         print "failed (update)\n";  
      }

   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------
# releaseThread
# releases allocation of the specified thread in the status table 
#
# Purpose:
#  Storing information in the database
#
# Parameters:
#  integer threadID
#  string instanceID
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
sub releaseThread

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
      print "   StatusTable:requesting release of threadID $threadID...";
      $statementText = "update $tableName set allocated=0 where threadID=$threadID";
               
      $statement = $sqlClient->prepareStatement($statementText);
            
      if ($sqlClient->executeStatement($statement))
      {       
         $success = 1;
         print "ok\n";
      }
      else
      {
         print "failed (update)\n";  
      }
   
   }
   
   return $success;   
}


# -------------------------------------------------------------------------------------------------
# lookupInstance
# returns the current instance name of the specified thread
#
# Purpose:
#  Storing information in the database
#
# Parameters:
#  string instanceID
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
sub lookupInstance

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
     
      print "   StatusTable:requesting last instance for thread $threadID...\n";

      # select the threadID of the least-recently used unallocated thread
      $sqlStatement = "select instanceID from $tableName where threadID=$threadID";
       
      @selectResults = $sqlClient->doSQLSelect($sqlStatement);
        
      # only zero or one result should be returned - if there's more than one, then we have a problem, to avoid it always take
      # the last entry in the list due to the 'order by' command
      $length = @selectResults;
      if ($length > 0)
      {
         $lastRecordHashRef = $selectResults[$#selectResults];
         $instanceID = $$lastRecordHashRef{'instanceID'};
      }
      
       print "               last instanceID was '$instanceID'.\n";
   }
   
   return $instanceID;
}        

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# addToRecordsEncountered
# increments the number of records encountered by this thread by the number specified
#
# Purpose:
#  Storing information in the database
#
# Parameters:
#  integer threadID
#  integer recordsEncountered
#  string lastURL
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
sub addToRecordsEncountered

{
   my $this = shift;
   my $threadID = shift;
   my $recordsAdded = shift;
   my $lastURL = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   my $tableName = $this->{'tableName'};
  
      
   if ($sqlClient)
   {
      # update the recordsEncounted value
      $triedCleanup = 1;
      $quotedURL = $sqlClient->quote($lastURL);
      $statementText = "update $tableName set lastActive=now(), recordsEncountered=recordsEncountered+$recordsAdded, lastURL=$quotedURL where threadID = $threadID";
      
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
# addToRecordsParsed
# increments the number of records parsed and records added by this thread by the numbers specified
#
# Purpose:
#  Storing information in the database
#
# Parameters:
#  integer threadID
#  integer recordsParsed
#  integer recordsAdded
#  string lastURL
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
sub addToRecordsParsed

{
   my $this = shift;
   my $threadID = shift;
   my $recordsParsed = shift;
   my $recordsAdded = shift;
   my $lastURL = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   my $tableName = $this->{'tableName'};
  
      
   if ($sqlClient)
   {
      # update the recordsParsed and Added values
      $triedCleanup = 1;
      $quotedURL = $sqlClient->quote($lastURL);
      $statementText = "update $tableName set lastActive=now(), recordsParsed=recordsParsed+$recordsParsed, recordsAdded=recordsAdded+$recordsAdded, lastURL=$quotedURL where threadID = $threadID";
      
      $statement = $sqlClient->prepareStatement($statementText);
            
      if ($sqlClient->executeStatement($statement))
      {       
         $success = 1;
      }
   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------
# dropTable
# attempts to drop the StatusTable table 
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

