#!/usr/bin/perl
# Written by Jeromy Evans
# Started 27 November 2004
# 
# WBS: A.01.03.01 Developed On-line Database
# Version 0.0  
#
# Description:
#   Module that encapsulate the OriginatingHTMLTable database component
#
# History:
# 19 Feb 2005 - hardcoded absolute log directory temporarily 
# 19 Apr 2005 - modified storage path to stop using flat directory - it was getting too big (too many files) to manage
#   now sorts into directory (1000 files per directory)
#             - added basePath function that returns the base path used for OriginatingHTML files
#             - added targetPath function that returns the target path for a specified OriginatingHTML file
#
# CONVENTIONS
# _ indicates a private variable or method
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
package OriginatingHTML;
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

# Contructor for the OriginatingHTML - returns an instance of an OriginatingHTMLTable object
# PUBLIC
sub new
{   
   my $sqlClient = shift;
   
   my $originatingHTML = { 
      sqlClient => $sqlClient,
      tableName => "OriginatingHTML"
   }; 
      
   bless $originatingHTML;     
   
   return $originatingHTML;   # return this
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# createTable
# attempts to create the OriginatingHTML table in the database if it doesn't already exist
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
my $SQL_CREATE_TABLE_STATEMENT = "CREATE TABLE IF NOT EXISTS OriginatingHTML ".
   "(DateEntered DATETIME NOT NULL, ".
   "Identifier INTEGER ZEROFILL PRIMARY KEY AUTO_INCREMENT, ".
   "SourceURL TEXT, ".
   "CreatesRecord INTEGER ZEROFILL)";
      
sub createTable

{
   my $this = shift;
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   
   if ($sqlClient)
   {
      $statement = $sqlClient->prepareStatement($SQL_CREATE_TABLE_STATEMENT);
      
      if ($sqlClient->executeStatement($statement))
      {
	 $success = 1;
      }
   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------
# addRecord
# adds a record of data to the OriginatingHTML table
# also saves the content of the HTMLSyntaxTree to disk
# 
# Purpose:
#  Storing information in the database
#
# Parameters:
#  integer foreignIdentifier - foreign key to record that was created
#  string sourceURL   
#  HTMLSyntaxTree          - html content will be saved to disk
#  string foreignTableName - name of the table that contains the created record.  It will be altered with the this new key
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
      
sub addRecord

{
   my $this = shift;
   my $foreignIdentifier = shift;
   my $url = shift;
   my $htmlSyntaxTree = shift;
   my $foreignTableName = shift;
   
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   my $statementText;
   my $identifier = -1;
   
   if ($sqlClient)
   {
      $statementText = "INSERT INTO OriginatingHTML (";
            
      # modify the statement to specify each column value to set 
      $appendString = "DateEntered, identifier, sourceurl, CreatesRecord";
      
      $statementText = $statementText.$appendString . ") VALUES (";
      
      # modify the statement to specify each column value to set 
      $index = 0;
      $quotedUrl = $sqlClient->quote($url);
      $quotedForeignIdentifier = $sqlClient->quote($foreignIdentifier);
      $appendString = "localtime(), null, $quotedUrl, $quotedForeignIdentifier)";

      $statementText = $statementText.$appendString;
      
      # prepare and execute the statement
      $statement = $sqlClient->prepareStatement($statementText);         
      if ($sqlClient->executeStatement($statement))
      {
         $success = 1;
         
         # get the identifier of the record that was just created (the primary key)
         @selectResults = $sqlClient->doSQLSelect("select identifier from OriginatingHTML where CreatesRecord = $quotedForeignIdentifier");
         
         # only one result should be returned - if there's more than one, then we have a problem, to avoid it always take
         # the most recent entry which is the last in the list due to the 'order by' command
         $lastRecordHashRef = $selectResults[$#selectResults];
         $identifier = $$lastRecordHashRef{'identifier'};
         if ($identifier >= 0)
         {
            #print "altering foreign key in $foreignTableName identifier=$foreignIdentifier createdBy=$identifier\n";
            # alter the foreign record - add this primary key as the CreatedBy foreign key - completing the relationship
            # between the two tables (in both directions)
            $sqlClient->alterForeignKey($foreignTableName, 'identifier', $foreignIdentifier, 'createdBy', $identifier);
            
            # save the HTML content to disk using the primarykey as the filename
            $this->saveHTMLContent($identifier, $htmlSyntaxTree->getContent());
         }
      }
   }
   
   return $identifier;   
}

# -------------------------------------------------------------------------------------------------

# dropTable
# attempts to drop the OriginatingHTML table 
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
my $SQL_DROP_TABLE_STATEMENT = "DROP TABLE OriginatingHTML";
        
sub dropTable

{
   my $this = shift;
   my $success = 0;
   my $sqlClient = $this->{'sqlClient'};
   
   if ($sqlClient)
   {
      $statement = $sqlClient->prepareStatement($SQL_DROP_TABLE_STATEMENT);
      
      if ($sqlClient->executeStatement($statement))
      {
	      $success = 1;
      }
   }
   
   return $success;   
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
#
# returns the base path used for the originating HTML files
#
sub basePath
{
   my $this = shift;
   
   return "/projects/changeeffect/OriginatingHTML"; 
}

# -------------------------------------------------------------------------------------------------
#
# returns the path to be used for the originating HTML with the specified identifier
sub targetPath
{
   my $this = shift;
   my $identifier = shift;
 
   $targetDir = int($identifier / 1000);   
   $basePath = $this->basePath();
   $targetPath = $basePath."/$targetDir";
   
   return $targetPath;
}


# -------------------------------------------------------------------------------------------------



# -------------------------------------------------------------------------------------------------
# saveHTMLContent
#  saves to disk the html content for the specified record
# 
# Purpose:
#  Debugging
#
# Parameters:
#  integer identifier (primary key of the OriginatingHTML)
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
sub saveHTMLContent

{
   my $this = shift;
   my $identifier = shift;
   my $content = shift;
   
   my $sessionFileName = $identifier.".html";

   $logPath = $this->targetPath($identifier);
   
   mkdir $basePath, 0755;       	      
   mkdir $logPath, 0755;       	      
   open(SESSION_FILE, ">>$logPath/$sessionFileName") || print "Can't open file: $!";
   print SESSION_FILE $content;
   close(SESSION_FILE);      
}

