@echo off
REM $Revision$
REM $Id$

set library_path=..\cgi-bin\DataGatherer

REM run in foreground

perl -I%library_path% %library_path%\GetAdvertisedSales.pl %1 %2 %3 %4

