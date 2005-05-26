start "NT_DomainSales" PublishedMaterialScanner.bat "config=DomainSalesNT"
perl sleeprand.pl 30
REM start "NT_DomainRentals" PublishedMaterialScanner.bat "config=DomainRentalsNT"
REM perl sleeprand.pl 30
start "NT_RealEstateSales:A-M" PublishedMaterialScanner.bat "config=RealEstateSalesNT&startrange=A&endrange=N"
perl sleeprand.pl 30
start "NT_RealEstateSales:N-ZZ" PublishedMaterialScanner.bat "config=RealEstateSalesNT&startrange=N&endrange=ZZ"
perl sleeprand.pl 30
start "NT_RealEstateRentals" PublishedMaterialScanner.bat "config=RealEstateRentalsNT"

