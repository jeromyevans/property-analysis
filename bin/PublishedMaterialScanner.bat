@echo off
REM $Revision$
REM $Id$

set library_path=..\cgi-bin\DataGatherer

REM run in foreground
REM echo Note: don't specify start or continue anymore - handled automatically
perl -I%library_path% %library_path%\PublishedMaterialScannerThread.pl %1 %2 %3 %4

