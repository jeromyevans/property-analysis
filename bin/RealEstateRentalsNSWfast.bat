REM parse at 4x
start "RealEstateRentalsNSW:A-Ga" PublishedMaterialScanner "config=RealEstateRentalsNSW&startrange=A&endrange=Ga";
perl sleeprand.pl 20
start "RealEstateRentalsNSW:G-Na" PublishedMaterialScanner "config=RealEstateRentalsNSW&startrange=G&endrange=Na";
perl sleeprand.pl 20
start "RealEstateRentalsNSW:N-Ta" PublishedMaterialScanner "config=RealEstateRentalsNSW&startrange=N&endrange=Ta";
perl sleeprand.pl 20
start "RealEstateRentalsNSW:T-Zz" PublishedMaterialScanner "config=RealEstateRentalsNSW&startrange=T&endrange=ZZ";

