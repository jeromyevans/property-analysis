REM parse at 4x
start "DomanSalesVIC:A-Ga" PublishedMaterialScanner "config=DomainSalesVIC&startrange=A&endrange=Ga";
perl sleeprand.pl 20
start "DomanSalesVIC:G-Na" PublishedMaterialScanner "config=DomainSalesVIC&startrange=G&endrange=Na";
perl sleeprand.pl 20
start "DomanSalesVIC:N-Ta" PublishedMaterialScanner "config=DomainSalesVIC&startrange=N&endrange=Ta";
perl sleeprand.pl 20
start "DomanSalesVIC:T-Zz" PublishedMaterialScanner "config=DomainSalesVIC&startrange=T&endrange=ZZ";

