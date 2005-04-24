start "NT_DomainSales" PublishedMaterialScanner.bat "config=DomainSalesNT"
perl sleeprand.pl 30
start "NT_DomainRentals" PublishedMaterialScanner.bat "config=DomainRentalsNT"
perl sleeprand.pl 30
start "NT_RealEstateSales:A-Na" PublishedMaterialScanner.bat "config=RealEstateSalesNT&startrange=A&endrange=Na"
perl sleeprand.pl 30
start "NT_RealEstateSales:N-ZZ" PublishedMaterialScanner.bat "config=RealEstateSalesNT&startrange=N&endrange=ZZ"
perl sleeprand.pl 30
start "NT_RealEstateRentals" PublishedMaterialScanner.bat "config=RealEstateRentalsNT"

