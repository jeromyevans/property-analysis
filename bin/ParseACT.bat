start "ACT_DomainSales" PublishedMaterialScanner.bat "config=DomainSalesACT"
perl sleeprand.pl 30
rem start "ACT_DomainRentals" PublishedMaterialScanner.bat "config=DomainRentalsACT"
rem perl sleeprand.pl 30
start "ACT_RealEstateSales:A-M" PublishedMaterialScanner.bat "config=RealEstateSalesACT&startrange=A&endrange=N"
perl sleeprand.pl 30
start "ACT_RealEstateSales:N-ZZ" PublishedMaterialScanner.bat "config=RealEstateSalesACT&startrange=N&endrange=ZZ"
perl sleeprand.pl 30
start "ACT_RealEstateRentals" PublishedMaterialScanner.bat "config=RealEstateRentalsACT"

