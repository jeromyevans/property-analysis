REM parse at 4x
start "DomanSalesNSW:A-Ga" PublishedMaterialScanner "config=DomainSalesNSW&startrange=A&endrange=Ga";
perl sleeprand.pl 20
start "DomanSalesNSW:G-Na" PublishedMaterialScanner "config=DomainSalesNSW&startrange=G&endrange=Na";
perl sleeprand.pl 20
start "DomanSalesNSW:N-Ta" PublishedMaterialScanner "config=DomainSalesNSW&startrange=N&endrange=Ta";
perl sleeprand.pl 20
start "DomanSalesNSW:T-Zz" PublishedMaterialScanner "config=DomainSalesNSW&startrange=T&endrange=ZZ";

