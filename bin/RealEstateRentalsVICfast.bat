REM parse at 4x
start "RealEstateRentalsVIC:A-Ga" PublishedMaterialScanner "config=RealEstateRentalsVIC&startrange=A&endrange=Ga";
perl sleeprand.pl 20
start "RealEstateRentalsVIC:G-Na" PublishedMaterialScanner "config=RealEstateRentalsVIC&startrange=G&endrange=Na";
perl sleeprand.pl 20
start "RealEstateRentalsVIC:N-Ta" PublishedMaterialScanner "config=RealEstateRentalsVIC&startrange=N&endrange=Ta";
perl sleeprand.pl 20
start "RealEstateRentalsVIC:T-Zz" PublishedMaterialScanner "config=RealEstateRentalsVIC&startrange=T&endrange=ZZ";

