#!/usr/bin/perl
# Written by Jeromy Evans
# Started 11 March 2004
# 
# WBS: A.01.03.01 Developed On-line Database
# Version 0.0  
#
# Description:
#   Module that encapsulates an SQL database
#
# History
#  22 May 2004 - added doSqlSelect for generic selection operations
#   6 Sep 2004 - added doSQLInsert for generic insert operations
#              - added option to new to specify database name
#  12 Sep 2004 - added support for logging SQL statements that write to the database
#  27 Nov 2004 - added function alterForeignKey() tha's used to change/set the value of a (non-strict) foreign key 
# for the specified table and primary key
#  8 Dec 2004  - modified quote to return 'null' for undef variables instead of the default of '';
# 11 Jan 2005  - BUGFIX - fixed quote so that variables that are SUPPOSED to be 0 are not set to null
# 19 Feb 2005 - hardcoded absolute log directory temporarily
# CONVENTIONS
# _ indicates a private variable or method
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#

package SQLClient;
require Exporter;

use DBI;

@ISA = qw(Exporter);

#@EXPORT = qw(&parseContent);

# -------------------------------------------------------------------------------------------------
# PUBLIC enumerations
#
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

# Contructor for the SQLClient - returns an instance of an HTTPClient object
# PUBLIC
sub new
{   
   
   my $databaseName = shift;
   
   if (!$databaseName)
   {
      $databaseName = "PropertyData";
   }
   
   my $sqlClient = {         
      dbiHandle => "instanceNotConnected",
      databaseName => $databaseName,
      loggingEnabled => 0,
      sessionName => undef
   }; 
      
   bless $sqlClient;     
   
   return $sqlClient;   # return this
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# enableLogging
# sets a flag so all write/update commands are logged to disk - need to specify a session name
# 
# Purpose:
#  Setting up the database interface
#
# Parameters:
#  string sessionName
#
# Constraints:
#  nil
#
# Updates:
#  this->{'sessionName'}
#
# Returns:
#   nil
#
sub enableLogging($)

{
   my $this = shift;
   my $sessionName = shift;
   
   $this->{'sessionName'} = $sessionName;
   $this->{'loggingEnabled'} = 1;
}

# -------------------------------------------------------------------------------------------------
# connect
# opens the connection to the SQL database
# 
# Purpose:
#  Setting up the database interface
#
# Parameters:
#  nil
#
# Constraints:
#  nil
#
# Updates:
#  this->{'dbiHandle'}
#
# Returns:
#   TRUE (1) if connected, 0 otherwise
#
sub connect

{
   my $this = shift;
   
   my $dbiHandle = DBI->connect("DBI:mysql:".$this->{'databaseName'}, "propagent", "propagent9");
   
   if ($dbiHandle)
   {
      $this->{'dbiHandle'} = $dbiHandle;
            
      return 1;
   }
   else
   {
      return 0;
   }
   
}

# -------------------------------------------------------------------------------------------------
# disconnect
# closes the connection to the SQL database
# 
# Purpose:
#  Setting up the database interface
#
# Parameters:
#  nil
#
# Constraints:
#  nil
#
# Updates:
#  this->{'dbiHandle'}
#
# Returns:
#   TRUE (1) if connected, 0 otherwise
#
sub disconnect

{
   my $this = shift;      
   my $dbiHandle;
   
   $dbiHandle = $this->{'dbiHandle'};   
   
   if ($dbiHandle)
   {
      $dbiHandle->disconnect();
      
      $this->{'dbiHandle'} = undef;
   }     
}

# -------------------------------------------------------------------------------------------------
# lastErrorString
# returns the last error string returned by the SQL database
# 
# Purpose:
#  Error handling
#
# Parameters:
#  nil
#
# Constraints:
#  nil
#
# Updates:
#  Nil
#
# Returns:
#   string
#
sub lastErrorString

{
   my $this = shift;   
   my $errorString;
   my $dbiHandle;
   
   $dbiHandle = $this->{'dbiHandle'};   
   
   if ($dbiHandle)
   {
      $errorString = $dbiHandle->errstr;
   }
   else
   {
      $errorString = "No database connection established.";
   }
      
   return $errorString;   
}

# -------------------------------------------------------------------------------------------------
# prepareStatement
# prepares a statement to issue to the SQL database
# 
# Purpose:
#  Database access
#
# Parameters:
#  STRING statement text 
#
# Constraints:
#  nil
#
# Updates:
#  $this->{'statementHandle'}

# Returns:
#   string
#
sub prepareStatement

{
   my $this = shift; 
   my $statementString = shift;
   my $statementHandle;
   my $dbiHandle;
   my $success = 0;
   
   $dbiHandle = $this->{'dbiHandle'};   
   
   if ($dbiHandle)
   {      
      if ($statementHandle = $dbiHandle->prepare($statementString))
      {
         $this->{'statementHandle'} = $statementHandle;
         $this->{'statementText'} = $statementString;
         $success = 1;
      }
   }
   
   return $success;   
}
# -------------------------------------------------------------------------------------------------
# executeStatement
# executes a previously prepared statement to the SQL database
# 
# Purpose:
#  Database access
#
# Parameters:
#  array of bind values for the statement (substitutions)
#
# Constraints:
#  nil
#
# Updates:
#  Nil
#
# Returns:
#   string
#
sub executeStatement

{
   my $this = shift;    
   my $bindValuesRef = shift;
   my $statementHandle;
   my $dbiHandle;
   my $success = 0;
   
   $dbiHandle = $this->{'dbiHandle'};   
   
   if ($dbiHandle)
   {
      $statementHandle = $this->{'statementHandle'};
      
      if ($statementHandle)
      {
         if ($statementHandle->execute(@$bindValues))
         {
            $success = 1;        
            if ($this->{'loggingEnabled'})
            {
               # if this is an update activity then log the statement
               if ($this->{'statementText'} =~ /^(delete|insert|replace|truncate|update|alter|create|drop|rename)/i)
               {
                  $this->saveSQLLog();
               }
            }
         }
         else
         {
             print "SQLClient->execute failed:\n", $this->{'statementText'}, "\n";  
         }
      }
   }
   
   return $success;   
}


# -------------------------------------------------------------------------------------------------
# fetchSingleColumnResult
# fetches the rows returned for the last executed statement assuming it was a single column
# the single column of data is returned as a list 
# 
# Purpose:
#  Database access
#
# Parameters:
#  nill
#
# Constraints:
#  nil
#
# Updates:
#  Nil
#
# Returns:
#   list of data
#
sub fetchSingleColumnResult

{
   my $this = shift;          
   my $dbiHandle;   
   my @singleColumnResult;
   my $index = 0;
   
   $dbiHandle = $this->{'dbiHandle'};   
   
   if ($dbiHandle)
   {
      $statementHandle = $this->{'statementHandle'};
      
      if ($statementHandle)
      {
         # loop through each row of the result
         while (@nextRow = $statementHandle->fetchrow_array())
         {
            # get the first element of the returned row and append to the result list
            $singleColumnResult[$index] = $nextRow[0];
         
            $index++;
         }                           
      }      
   }
   
   return @singleColumnResult;       
}

# -------------------------------------------------------------------------------------------------
# fetchResults
# fetches all the rows returned for the last executed statement assuming it was a single column
# returns a list of hashes
# 
# Purpose:
#  Database access
#
# Parameters:
#  nill
#
# Constraints:
#  nil
#
# Updates:
#  Nil
#
# Returns:
#   list of hashes of row data
#
sub fetchResults

{
   my $this = shift;          
   my $dbiHandle;   
   my @resultList;
   my $index = 0;
   
   $dbiHandle = $this->{'dbiHandle'};   
   
   if ($dbiHandle)
   {
      $statementHandle = $this->{'statementHandle'};
      
      if ($statementHandle)
      {
         # loop through each row of the result
         while ($nextRowRef = $statementHandle->fetchrow_hashref())
         {            
            # get the first element of the returned row and append to the result list
            $resultList[$index] = $nextRowRef;
         
            $index++;
         }                           
      }      
   }
   
   return @resultList;       
}

# -------------------------------------------------------------------------------------------------
# escapes a string for use in mysql
sub quote
{
   my $this = shift;
   my $string = shift;
   my $result;
   
   $dbiHandle = $this->{'dbiHandle'};
   
   if ($dbiHandle)
   {
      if ((($string) && ($string ne '')) || ($string eq '0'))
      {
         $result = $dbiHandle->quote($string);
      }
      else
      {         
         $result = 'null';
      }
      
   }
   
   return $result;  
}

# -------------------------------------------------------------------------------------------------
# doSQLSelect
# runs an sql select statement
#
# Purpose:
#  retreive database information
#
# Parameters:
#  string sqlStatementText - don't forget to QUOTE using sqlClient->quote()
#
# Updates:
#  Nil
#
# Returns:
#   nil
sub doSQLSelect
{   
   my $this = shift;      
   my $statementText = shift;
   my $statement;
   my $found = 0;
   my $noOfEntries = 0;
         
   $statement = $this->prepareStatement($statementText);
      
   if ($this->executeStatement($statement))
   {
      # get the array of rows from the table
      @selectResult = $this->fetchResults();                                                
   }                        
   
   return @selectResult;   
}  

# -------------------------------------------------------------------------------------------------
# performs a generic insert for the speicified table name and hash of parameters (column & value pairs)
sub doSQLInsert

{
   my $this = shift;
   my $tableName = shift;
   my $parametersRef = shift;
 
   my $success = 0;
   my $statementText;
   my $appendString = "";
   
   $statementText = "INSERT INTO $tableName (";
      
   @columnNames = keys %$parametersRef;
 
   $index = 0;
   foreach (@columnNames)
   {
      if ($index != 0)
      {
         $appendString = $appendString.", ";
      }
     
      $appendString = $appendString . $_;
      $index++;
   }      
   
   $statementText = $statementText.$appendString . ") VALUES (";

   # modify the statement to specify each column value to set 
   @columnValues = values %$parametersRef;
  
   $appendString = "";
   $index = 0;
   foreach (@columnValues)
   {
      if ($index != 0)
      {
         $appendString = $appendString.", ";
      }
     
      $appendString = $appendString.$this->quote($_);
      $index++;
   }
   $statementText = $statementText.$appendString . ")";
   
   $statement = $this->prepareStatement($statementText);
   if ($this->executeStatement($statement))
   {
      $success = 1;
   }
   
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------
# saveTransactionLog
#  saves to disk the request and response for a transaction (for debugging) 
# 
# Purpose:
#  Debugging
#
# Parametrs:
#  integer transactionNo (optional)
#
# Constraints:
#  nil
#
# Updates:
#  $this->{'requestRef'} 
#  $this->{'responseRef'}
#
# Returns:
#   nil
#
sub saveSQLLog()

{
   my $this = shift;
   my $sessionName = $this->{'sessionName'};
   my $sessionFileName = $sessionName.".sqlt";
   
  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
   $year += 1900;
   $mon++;
   $logPath = "/projects/changeeffect/logs";
   mkdir $logPath, 0755;       	      
   open(SESSION_FILE, ">>$logPath/$sessionFileName") || print "Can't open file: $!"; 
           
   print SESSION_FILE "\n<sql_transaction instance='$sessionName' year='$year' mon='$mon' mday='$mday' hour='$hour' min='$min' sec='$sec'>\n";
   print SESSION_FILE $this->{'statementText'};
   print SESSION_FILE "\n</sql_transaction>\n";   
      
   close(SESSION_FILE);      
}

# -------------------------------------------------------------------------------------------------

# alterForeignKey
# alters the table to change/set the value of a foreign key for the specified primary key
# 
# Purpose:
#  Updating relationships in a database
#
# Parameters:
#  string TableName
#  string PrimaryKeyName
#  integer PrimaryKeyValue
#  string ForeignKeyName
#  integer ForeignKeyValue

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
        
sub alterForeignKey

{
   my $this = shift;
   my $tableName = shift;
   my $primaryKeyName = shift;
   my $primaryKeyValue = shift;
   my $foreignKeyName = shift;
   my $foreignKeyValue = shift;
   
   my $success = 0;
 
   $quotedPrimaryKeyValue = $this->quote($primaryKeyValue);
   $quotedForeignKeyValue = $this->quote($foreignKeyValue);
   $statementText = "UPDATE $tableName SET $foreignKeyName = $quotedForeignKeyValue WHERE $primaryKeyName = $quotedPrimaryKeyValue";
         
   # prepare and execute the statement
   $statement = $this->prepareStatement($statementText);
   
   if ($this->executeStatement($statement))
   {
      $success = 1;
   }

   
   return $success;   
}

