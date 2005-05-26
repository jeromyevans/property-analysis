start "SA_DomainSales" PublishedMaterialScanner.bat "config=DomainSalesSA"
perl sleeprand.pl 30
REM start "SA_DomainRentals" PublishedMaterialScanner.bat "config=DomainRentalsSA"
REM perl sleeprand.pl 30
start "NT_RealEstateSales:A-M" PublishedMaterialScanner.bat "config=RealEstateSalesNT&startrange=A&endrange=N"
perl sleeprand.pl 30
start "NT_RealEstateSales:N-ZZ" PublishedMaterialScanner.bat "config=RealEstateSalesNT&startrange=N&endrange=ZZ"
perl sleeprand.pl 30
start "SA_RealEstateRentals" PublishedMaterialScanner.bat "config=RealEstateRentalsSA"



