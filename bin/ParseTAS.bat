start "TAS_DomainSales" PublishedMaterialScanner.bat "config=DomainSalesTAS"
perl sleeprand.pl 30
rem start "TAS_DomainRentals" PublishedMaterialScanner.bat "config=DomainRentalsTAS"
rem perl sleeprand.pl 30
start "TAS_RealEstateSales:A-M" PublishedMaterialScanner.bat "config=RealEstateSalesTAS&startrange=A&endrange=N"
perl sleeprand.pl 30
start "TAS_RealEstateSales:N-ZZ" PublishedMaterialScanner.bat "config=RealEstateSalesTAS&startrange=N&endrange=ZZ"
perl sleeprand.pl 30
start "TAS_RealEstateRentals" PublishedMaterialScanner.bat "config=RealEstateRentalsTAS"

