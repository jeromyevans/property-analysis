#!/usr/bin/perl
# Written by Jeromy Evans
# Started 16 May 2004
# 
# WBS: A.01.03.01 Developed On-line Database
# Version 0.0  
#
# Description:
#   Module that implements a TCP client to receive status information about an agent
#
# CONVENTIONS
# _ indicates a private variable or method
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
package AgentStatusClient;
require Exporter;
use IO::Socket;
use POSIX;

@ISA = qw(Exporter);

#@EXPORT = qw(&parseContent);

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
   
# Contructor for the AgentStatusClient - returns an instance of this object
sub new
{         
   my $port = shift;
   
   my $agentStatusClient = { 
      socketHandle => undef,      
      clientSocket => undef,
      localPort => $port,
      enabled => 1,
      statusHashRef => undef
   }; 
      
   bless $agentStatusClient;     
   
   return $agentStatusClient;   # return this
}

# -------------------------------------------------------------------------------------------------
# _connect
# initialise the TCP client on the specified port
# 
# Purpose:
#  setup server for reporting status
#
# Parameters:
#  integer port
#
# Returns:
#   TRUE (1) if successful, 0 otherwise
#
sub _connect

{  
   my $this = shift;
   my $localPort = $this->{'localPort'};
  
   my $socketHandle = new IO::Socket::INET (PeerAddr => 'localhost',
                              PeerPort => $localPort,
                              Proto    => 'tcp',
                              Timeout  => 0);
   

   #fcntl($socketHandle, F_SETFL(), O_NONBLOCK());
                           
   $this->{'socketHandle'} = $socketHandle;                                
}

# -------------------------------------------------------------------------------------------------
# closeConnection
# 
# Purpose:
#  setup server for reporting status
#
# Parameters:
#  nil
#
# Returns:
#   TRUE (1) if successful, 0 otherwise
#
sub closeConnection

{
   my $this = shift;      
   my $socketHandle = $this->{'socketHandle'};   
      
   if ($socketHandle)
   {   
      $socketHandle->close();    
      $this->{'enabled'} = 0;              
   }
}

# -------------------------------------------------------------------------------------------------
# getStatus
# 
# Purpose:
#  get hash of status parameters
#
# Parameters:
#  nil
#
# Returns:
#   TRUE (1) if successful, 0 otherwise
#
sub getStatus
{
   my $this = shift;           
   my %statusHash;
      
   #print "connecting...\n";
   $this->_connect();      
   #print "   exit\n";
   my $socketHandle = $this->{'socketHandle'};
   
   if (!$socketHandle)
   {        
      # set the field that the agent isn't running
      $statusHash{'reached'}=0;          
   }
   else
   {
      $statusHash{'reached'}=1;
      
      # read then close
      #print "reading...\n";
      $message = <$socketHandle>;
      #print "read\n";  
      #print "closing...\n";
      $this->closeConnection();
      #print "closed.\n";
      
      if ($message)
      {
         #print "message:", $message;
         
         # split message into pairs
         @pairs = split(/\n\r/, $message);
         
         foreach (@pairs)
         {
            chomp;
            # split message into keys and values
            ($key, $value)= split /=/;
                        
            if ($key) 
            {
               $statusHash{$key} = $value;
            }
         }
      }
   }
   
   return %statusHash;
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

