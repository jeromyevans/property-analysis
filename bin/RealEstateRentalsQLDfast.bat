REM parse at 4x
start "RealEstateRentalsQLD:A-Ga" PublishedMaterialScanner "config=RealEstateRentalsQLD&startrange=A&endrange=Ga";
perl sleeprand.pl 20
start "RealEstateRentalsQLD:G-Na" PublishedMaterialScanner "config=RealEstateRentalsQLD&startrange=G&endrange=Na";
perl sleeprand.pl 20
start "RealEstateRentalsQLD:N-Ta" PublishedMaterialScanner "config=RealEstateRentalsQLD&startrange=N&endrange=Ta";
perl sleeprand.pl 20
start "RealEstateRentalsQLD:T-Zz" PublishedMaterialScanner "config=RealEstateRentalsQLD&startrange=T&endrange=ZZ";

