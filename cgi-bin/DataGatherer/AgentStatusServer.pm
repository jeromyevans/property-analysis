#!/usr/bin/perl
# Written by Jeromy Evans
# Started 16 May 2004
# 
# WBS: A.01.03.01 Developed On-line Database
# Version 0.0  
#
# Description:
#   Module that implements a TCP server to send status information on the agent
#
# CONVENTIONS
# _ indicates a private variable or method
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
package AgentStatusServer;
require Exporter;
use IO::Socket;
use IO::Handle;

@ISA = qw(Exporter);

#@EXPORT = qw(&parseContent);

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
   
# Contructor for the AgentStatusServer - returns an instance of this object
sub new
{         
   my $port = shift;
 
#print "creating PIPE man\n";    
#  pipe(READER, WRITER);
#   WRITER->autoflush(1);
  
   my $agentStatusServer = { 
      socketHandle => undef,      
      clientSocket => undef,
      localPort => $port,
      enabled => 1,
      statusHashRef => undef   
   }; 
      
   bless $agentStatusServer;     
     
   return $agentStatusServer;   # return this
}

# -------------------------------------------------------------------------------------------------
# initialise
# initialise the TCP server on the specified port
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
sub _initialise

{  
   my $this = shift;
   my $localPort = $this->{'localPort'};
      
   my $socketHandle = new IO::Socket::INET (LocalAddr => 'localhost',
                              LocalPort => $localPort,
                              Proto     => 'tcp',
                              Listen    => 5);
                              
   $this->{'socketHandle'} = $socketHandle;                                
}

# -------------------------------------------------------------------------------------------------
# accept connection
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
sub _acceptConnections

{   
   my $this = shift;
   my $socketHandle = $this->{'socketHandle'};   
   my $newSocket;   
      
   if ($socketHandle)
   {   
      # block to accept connections on this socket
      $newSocket = $socketHandle->accept();
      
      if ($newSocket)
      {
         # add this client to the list
         #push @$clientSocketListRef, $newSocket;
         $this->{'clientSocket'} = $newSocket;         
         
         #print "connection accepted (peerHost=", $newSocket->peerhost(), ")\n";
         
         $this->multicast();
      }
   }
}

# -------------------------------------------------------------------------------------------------
# closeConnections
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
sub closeConnections

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
# statusMessage
# 
# Purpose:
#  generate a message to report status
#
# Parameters:
#  nul
#
# Returns:
#   TRUE (1) if successful, 0 otherwise
#
sub _statusMessage
{
   my $this = shift;
   my $message = "";
   my $statusHashRef = $this->{'statusHashRef'};         
   
   while(($key, $value) = each(%$statusHashRef)) 
   {      
      # add this pair to the status message      
      $message .= "$key=$value\r\n";
   }      
   
   return $message;
}

# -------------------------------------------------------------------------------------------------
# setStatus
# 
# Purpose:
#  set a status parameter
#
# Parameters:
#  string key
#  string value
#
# Returns:
#   TRUE (1) if successful, 0 otherwise
#
sub setStatus
{
   my $this = shift;
   my $key = shift;
   my $value = shift;
   
   # set hash key and value     
   $this->{'statusHashRef'}{$key} = $value;      
}


# -------------------------------------------------------------------------------------------------

sub multicast

{  
   my $this = shift;
         
   my $clientSocket = $this->{'clientSocket'};
            
   if ($clientSocket)
   {                 
      $clientSocket->send($this->_statusMessage());
      sleep(1);
      $clientSocket->close();
      $clientSocket = undef;                  
   }   
}

# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# start
# start the TCP server 
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
sub start

{
   my $this = shift;
      
   if (!defined($childPID = fork()))   
   {
       print "failed to start statusServer: fork failed\n";
   } 
   elsif ($childPID) 
   {       
       # This is the parent - start the server       
       $this->_initialise();      
       while ($this->{'enabled'})
       {          
          $this->_acceptConnections();          
       }   
   }
   else
   {    
      # this is the child - nothing to do
      $result = 1;
   }
   
   return $result;
}

# -------------------------------------------------------------------------------------------------

