# -------------------------------------------------------------------------------------------------
# runs recovery in a loop
my $command = 'perl RecoverFromLogs.pl "year=2004&mon=01&mday=01&hour=0&min=0&sec=0&agent=GetAdvertisedSales&source=REIWA&continue=1"';

$exitValue = 1;
do{  
   #perl RecoverFromLogs.pl "year=2004&mon=01&mday=01&hour=0&min=0&sec=0&agent=GetAdvertisedSales_Domain&source=Domain"";
   
   print "\n> $command\n\n";
   $exitValue = system($command);
   $exitValue = $exitValue / 256;
   print "exited with value $exitValue\n";
} while ($exitValue == 1);

print "now starting for DOMAIN\n";
my $command = 'perl RecoverFromLogs.pl "year=2004&mon=01&mday=01&hour=0&min=0&sec=0&agent=GetAdvertisedSales_Domain&source=Domain&continue=1"';

$exitValue = 1;
do{     
   print "\n> $command\n\n";
   $exitValue = system($command);
   $exitValue = $exitValue / 256;
   print "exited with value $exitValue\n";
} while ($exitValue == 1);


