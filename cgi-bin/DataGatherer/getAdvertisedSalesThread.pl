#
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$

# -------------------------------------------------------------------------------------------------
# runs getAdvertisedSales in a loop continuing the thread until complete
$library_path="../cgi-bin/DataGatherer";

my $command = 'perl -I'.$library_path.' '.$library_path.'/GetAdvertisedSales.pl "start=1&'.$ARGV[0].'"';

$exitValue = 1;
  
print "\n> $command\n\n";
$exitValue = system($command);
$exitValue = $exitValue / 256;
print "Exited with value $exitValue\n";

if ($exitValue > 0)
{
   # continue the thread until complete
   my $command = 'perl -I'.$library_path.' '.$library_path.'/GetAdvertisedSales.pl "thread='.$exitValue.'&'.$ARGV[0].'"';
     
   $exitValue = 1;
   do{  
      print "\n> $command\n\n";
      $exitValue = system($command);
      $exitValue = $exitValue / 256;
      print "Exited with value $exitValue\n";
   } while ($exitValue > 0);
}

   
