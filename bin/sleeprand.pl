#!/usr/bin/perl

my $sleepLimit = $ARGV[0];

if ((!$sleepLimit) || ($sleepLimit <= 0))
{ 
   $sleepLimit = 60;
}

$sleepTime = int(rand($sleepLimit)) + 1;

print "sleeping for $sleepTime seconds...\n";
sleep $sleepTime;

