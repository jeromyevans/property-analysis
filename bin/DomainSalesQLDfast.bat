REM parse at 4x
start "DomanSalesQLD:A-Ga" PublishedMaterialScanner "config=DomainSalesQLD&startrange=A&endrange=Ga";
perl sleeprand.pl 20
start "DomanSalesQLD:G-Na" PublishedMaterialScanner "config=DomainSalesQLD&startrange=G&endrange=Na";
perl sleeprand.pl 20
start "DomanSalesQLD:N-Ta" PublishedMaterialScanner "config=DomainSalesQLD&startrange=N&endrange=Ta";
perl sleeprand.pl 20
start "DomanSalesQLD:T-Zz" PublishedMaterialScanner "config=DomainSalesQLD&startrange=T&endrange=ZZ";

