#!/usr/bin/perl
# Written by Jeromy Evans
# Started 23 January 2005
# 
# WBS: A.01.03.01 Developed On-line Database
# Version 0.1  
#
# Description:
#   Module that encapsulate the SessionURLStack database table.  The SessionURLStack table is used to track
# URLs that have been queued for processing within a thread. THis module replaces an old method of using text
# files to track it.
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
package SessionURLStack;
require Exporter;

use DBI;
use SQLClient;
use HTTPTransaction;

@ISA = qw(Exporter);

#@EXPORT = qw(&parseContent);

# -------------------------------------------------------------------------------------------------
# PUBLIC enumerations
#
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

# Contructor for the SessionURLStack - returns an instance of this object
# PUBLIC
sub new
{   
   my $sqlClient = shift;
   
   my $sessionURLStack = { 
      sqlClient => $sqlClient,
      tableName => "SessionURLStack",
      restartLastRegion => 0,   # instance variables to control the recovery state machine
      continueNextRegion => 0,
      useNextRegion => 0,
      lastSuburbDefined => 0,
      useNextSuburb => 0,
      stillSeeking => 0
   }; 
      
   bless $sessionURLStack;     
   
   return $sessionURLStack;   # return this
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# createTable
# attempts to create the sessionURLStack table in the database if it doesn't already exist 
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
   "Method TEXT, ".
   "URL TEXT, ".
   "EscapedContent TEXT, ".
   "Label TEXT";
 
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
      }
   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# pushTransactionList
# adds a list of URLs to the end of the queue for processing by the thread  
#
# Purpose:
#  Storing information in the database
#
# Parameters:
#  integer threadID
#  reference to list of HTTPTransactions
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
sub pushTransactionList

{
   my $this = shift;
   my $threadID = shift;
   my $transactionListRef = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   my $tableName = $this->{'tableName'};
  
   if ($sqlClient)
   {
      # IMPORTANT: the list is processed IN REVERSE, ensure the sequence number is incremented in the reverse order that
      # we want to get them back again.  ie. the record with the highest sequence number will be the one we want next, always
      # - allows the list to be operated as a stack using max(sequenceno)
      @reverseList = reverse @$transactionListRef;
      
      foreach (@reverseList)
      {
         $url = $_->getURL();
         $method = $_->getMethod();
         if ($method =~ /POST/i)
         {
            $escapedContent = $_->getEscapedParameters();
         }
         else
         {
            $escapedContent = undef; 
         }
         $label = $_->getLabel();
         
         $quotedURL = $sqlClient->quote($url);
         $quotedMethod = $sqlClient->quote($method);
         $quotedContent = $sqlClient->quote($escapedContent);
         $quotedLabel = $sqlClient->quote($label);

         $statementText = "insert into $tableName (threadID, sequenceNo, dateEntered, url, method, escapedcontent, label) VALUES ".
                                                 "($threadID, null, now(), $quotedURL, $quotedMethod, $quotedContent, $quotedLabel)";
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
# popNextTransaction
# returns the next transaction in the stack for the specified thread and REMOVES it from the stack
#
# Purpose:
#
# Parameters:
#  integer threadID  
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
#   HTTPTransaction or undef if none left
#        
sub popNextTransaction

{
   my $this = shift;
   my $threadID = shift;
   my $parentSequenceNo = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   my $tableName = $this->{'tableName'};
   my $httpTransaction;
      
   if ($sqlClient)
   {     
      # select the next record - the sequenceNo is used to track this 
      $statementText = "select sequenceNo, url, method, escapedContent, label from $tableName where threadID=$threadID order by sequenceNo desc limit 1";
      @selectResults = $sqlClient->doSQLSelect($statementText);
      
      # only zero or one result should be returned - if there's more than one, then we have a problem, to avoid it always take
      # the last entry in the list due to the 'order by' command
      $length = @selectResults;
      if ($length > 0)
      {
         $lastRecordHashRef = $selectResults[$#selectResults];
         $sequenceNo = $$lastRecordHashRef{'sequenceNo'};
         $url = $$lastRecordHashRef{'url'};
         $method = $$lastRecordHashRef{'method'};
         $content = $$lastRecordHashRef{'escapedContent'};
         $label = $$lastRecordHashRef{'label'};

         if ($url)
         {
            $httpTransaction = HTTPTransaction::new($url, undef, $label);  # NOTE: referer is lost (wasn't saved)
        
            if ($content)
            {
               $httpTransaction->setEscapedParameters($content);
            }
            
            # remove the item from the URL queue
            $statementText = "delete from $tableName where threadID=$threadID and sequenceNo = $sequenceNo";
            $statement = $sqlClient->prepareStatement($statementText);
            if ($sqlClient->executeStatement($statement))
            {       
               $success = 1;
            }
         }
      }
   }
   
   return $httpTransaction;
}        

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

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
      print "   SessionURLStack:releasing threadID $threadID URLstack information...";
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

