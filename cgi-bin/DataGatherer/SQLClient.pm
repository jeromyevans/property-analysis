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
  
   my $sqlClient = {         
      dbiHandle => "instanceNotConnected"      
   }; 
      
   bless $sqlClient;     
   
   return $sqlClient;   # return this
}

# -------------------------------------------------------------------------------------------------
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
   
   my $dbiHandle = DBI->connect("DBI:mysql:test", undef, undef);
   
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
      $result = $dbiHandle->quote($string);
   }
   
   return $result;  
}
