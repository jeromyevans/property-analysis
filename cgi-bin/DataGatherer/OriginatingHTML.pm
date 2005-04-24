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
# 21 Apr 2005 - modified saveHTMLContent to prefix each file with a header that identifies the source and timestamp
#   This information is needed for reconstruction from the originatingHTML file
# 22 Apr 2005 - added override basepath function for setting where to output originatingHTML files (used for recovery)
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
      tableName => "OriginatingHTML",
      basePath => "/projects/changeeffect/OriginatingHTML", 
      useFlatPath => 0
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
            
            $timeStamp = time();
            
            # save the HTML content to disk using the primarykey as the filename
            $this->saveHTMLContent($identifier, $htmlSyntaxTree->getContent(), $url, $timestamp);
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
   
   return $this->{'basePath'};
}

# -------------------------------------------------------------------------------------------------
#
# returns the path to be used for the originating HTML with the specified identifier
sub targetPath
{
   my $this = shift;
   my $identifier = shift;
 
   if (!$this->{'useFlatPath'})
   {
      # this is the normal case - use subdirectories
      $targetDir = int($identifier / 1000);   
      $basePath = $this->basePath();
      $targetPath = $basePath."/$targetDir";
   }
   else
   {
      $basePath = $this->basePath();
      $targetPath = $basePath;
   }
   return $targetPath;
}


# -------------------------------------------------------------------------------------------------
#
#
sub overrideBasePath
{
   my $this = shift;
   my $newBasePath = shift;
   
   $this->{'basePath'} = $newBasePath; 
}


# -------------------------------------------------------------------------------------------------

sub useFlatPath
{
   my $this = shift;
   
   $this->{'useFlatPath'} = 1; 
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
sub saveHTMLContent ($ $ $ $)

{
   my $this = shift;
   my $identifier = shift;
   my $content = shift;
   my $sourceURL = shift;
   my $timeStamp = shift;
   
   my $sessionFileName = $identifier.".html";
   my $header;
   
   $logPath = $this->targetPath($identifier);
   
   $header = "<!---- OriginatingHTML -----\n".
             "sourceurl=$sourceURL\n".
             "localtime=$timeStamp\n".
             "--------------------------->\n";
   
   mkdir $basePath, 0755;       	      
   mkdir $logPath, 0755;       	      
   open(SESSION_FILE, ">$logPath/$sessionFileName") || print "Can't open file: $!";
   print SESSION_FILE $header;
   print SESSION_FILE $content;
   close(SESSION_FILE);      
}


# -------------------------------------------------------------------------------------------------
# readHTMLContent
#  reads from disk the html content for the specified record
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
#
# Returns:
#   content
#
sub readHTMLContent

{
   my $this = shift;
   my $identifier = shift;
   my $fileName = $identifier.".html";
   my @body;
   my $content = undef;
   
   $sourcePath = $this->targetPath($identifier);
   $lineNo = 0;
   
   if (open(SESSION_FILE, "<$sourcePath/$fileName"))
   {
      # read the content.
      while (<SESSION_FILE>)
      {
         # add this line to the header section of the transaction
         $body[$lineNo] = $_;
         $lineNo++;
      }
      
      if ($lineNo > 0)
      {
         $content = join '', @body;
      }
   }
   else
   {
      $content = undef;
   }
   
   close(SESSION_FILE);
   
   return $content;
}

# -------------------------------------------------------------------------------------------------

