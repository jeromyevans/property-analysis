#
# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$

# -------------------------------------------------------------------------------------------------
# runs publishedmaterialscanner in a loop continuing the thread until complete
$library_path="../cgi-bin/DataGatherer";

my $command = 'perl -I'.$library_path.' '.$library_path.'/PublishedMaterialScanner.pl "command=start&'.$ARGV[0].'"';

$exitValue = 1;
  
print "\n> $command\n\n";
$exitValue = system($command);
$exitValue = $exitValue / 256;
print "Exited with value $exitValue\n";

if (($exitValue > 0) && ($exitValue <= 128))
{
   # continue the thread until complete
   my $command = 'perl -I'.$library_path.' '.$library_path.'/PublishedMaterialScanner.pl "command=continue&thread='.$exitValue.'&'.$ARGV[0].'"';
     
   $exitValue = 1;
   do{  
      print "\n> $command\n\n";
      $exitValue = system($command);
      $exitValue = $exitValue / 256;
      print "Exited with value $exitValue\n";
   } while (($exitValue > 0) && ($exitValue <= 128));
}

   
