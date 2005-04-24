start "SA_DomainSales" PublishedMaterialScanner.bat "config=DomainSalesSA"
perl sleeprand.pl 30
start "SA_DomainRentals" PublishedMaterialScanner.bat "config=DomainRentalsSA"
perl sleeprand.pl 30
start "NT_RealEstateSales:A-Na" PublishedMaterialScanner.bat "config=RealEstateSalesNT&startrange=A&endrange=Na"
perl sleeprand.pl 30
start "NT_RealEstateSales:N-ZZ" PublishedMaterialScanner.bat "config=RealEstateSalesNT&startrange=N&endrange=ZZ"
perl sleeprand.pl 30
start "SA_RealEstateRentals" PublishedMaterialScanner.bat "config=RealEstateRentalsSA"



