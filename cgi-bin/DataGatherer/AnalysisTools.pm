#!/usr/bin/perl
# 16 June 2004
# Jeromy Evans
#
# Provides functions for performing analysis of the property database
#
# Started: 16 June 2004
#
# History
#   9 Dec 04 - changed to use MasterPropertyTable and WorkingView_AdvertisedRentalProfiles

# ---CVS---
# Version: $Revision$
# Date: $Date$
# $Id$
#
package AnalysisTools;
require Exporter;
use SQLClient;
use DebugTools;
use PrintLogger;
use SuburbAnalysisTable;

@ISA = qw(Exporter);

my $DEFAULT_SUBURB_CONSTRAINT = "";
my $DEFAULT_TYPE_CONSTRAINT = "Type not like '%Land%' and Type not like '%Lifestyle%'";
my $DEFAULT_TYPEINDEX = '4';
my $DEFAULT_STATE = 'WA';
my $DEFAULT_STATE_CONSTRAINT = "state='WA'";
my $DEFAULT_SALES_ANALYSIS_CONSTRAINT =  "(DateLastAdvertised > date_add(now(), interval -6 month)) and ";
my $DEFAULT_LAST_ADVERTISED_CONSTRAINT = "(DateLastAdvertised > date_add(now(), interval -14 day)) and ";
my $DEFAULT_RENTALS_ADVERTISED_CONSTRAINT = "((DateEntered > date_add(now(), interval -3 month)) or (LastEncountered > date_add(now(), interval -3 month))) and ";
my $DEFAULT_RELATED_SALES_ADVERTISED_CONSTRAINT = "(DateLastAdvertised > date_add(now(), interval -3 month)) and ";


my ($printLogger) = undef;
# -------------------------------------------------------------------------------------------------
# new
# contructor for the analysis toolkit
#
# Purpose:
#  initialisation of the analysis tookkit
#
# Parameters:
#  
#
# Constraints:
#  nil
#
# Updates:
#  Nil
#
# Returns:
#  AnalysisTools object
#    
sub new
{
   my $sqlClient = shift;    
  
   my $suburbAnalysisTable = SuburbAnalysisTable::new($sqlClient);
   my $propertyTypes = PropertyTypes::new();
   my $propertyCategories = PropertyCategories::new($sqlClient, $suburbAnalysisTable);

   
   my $analysisTools = {       
      sqlClient => $sqlClient,
      suburbSearch => $DEFAULT_SUBURB_CONSTRAINT,
      typeSearch => $DEFAULT_TYPE_CONSTRAINT,
      dateSearch => $DEFAULT_SALES_ANALYSIS_CONSTRAINT,      
      date14daySearch => $DEFAULT_LAST_ADVERTISED_CONSTRAINT,
      rentalsDateSearch => $DEFAULT_RENTALS_ADVERTISED_CONSTRAINT,
      relatedSalesDateSearch => $DEFAULT_RELATED_SALES_ADVERTISED_CONSTRAINT,
      suburbAnalysisTable => $suburbAnalysisTable,
      propertyTypes => $propertyTypes,
      propertyCategories => $propertyCategories
   };               
   
   bless $analysisTools;     
   
   return $analysisTools;   # return this
}

# -------------------------------------------------------------------------------------------------
# setSuburbConstraint
# sets a value representing the suburb to search within
sub setSuburbConstraint
{   
   my $this = shift;   
   my $suburbParam = shift;
      
   if (defined $suburbParam)
   {     
      #$this->{'suburbSearch'} = "SuburbName like '%$suburbParam%' and ";
      $this->{'suburbSearch'} = "SuburbIndex='$suburbParam' and ";      
   }
   else
   {            
      $this->{'suburbSearch'} = $DEFAULT_SUBURB_CONSTRAINT;      
   }         
}

# -------------------------------------------------------------------------------------------------
# setTypeConstraint
# sets a value representing the type of property for the analysis
sub setTypeConstraint
{  
   my $this = shift;
   my $typeIndex = shift;

   $propertyTypes = $this->{'propertyTypes'};
   
   if (defined $typeIndex)
   {  
      $this->{'typeIndex'} = $typeIndex; 
      $this->{'typeSearch'} = $propertyTypes->lookupSearchConstraintByTypeName($typeIndex);
   }         
   else
   {
      $this->{'typeIndex'} = $DEFAULT_TYPEINDEX; 
      $this->{'typeSearch'} = $DEFAULT_TYPE_CONSTRAINT
   }
}

# -------------------------------------------------------------------------------------------------
# setStateConstraint
sub setStateConstraint
{   
   my $this = shift;   
   my $state = shift;

   if (defined $state)
   {     
      $this->{'stateSearch'} = "and State = '$state'";     
      $this->{'state'} = $state;
   }
   else
   {            
      $this->{'stateSearch'} = $DEFAULT_STATE_CONSTRAINT;
      $this->{'state'} = $DEFAULT_STATE;      
   }         
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# performs the query on the database to get selected data for analysis
sub fetchAnalysisResults

{
   my $this = shift;
   
     
   my $sqlClient = $this->{'sqlClient'};
   my $fetchAnalysisData = 1;   
   
   my $state = $this->{'state'};
   my $typeIndex = $this->{'typeIndex'};
   if ($this->{'analysis_loaded'})
   {
      # analysis results have already been loaded - check if they're valid
      
      $lastState = $this->{'analysis_state'};
      $lastTypeIndex = $this->{'analysis_typeIndex'};
      
      if (($lastState == $state) && ($lastTypeIndex == $typeIndex))
      {
         # data already loaded
         $fetchAnalysisData = 0;
      }
   }
   
   if ($fetchAnalysisData)
   {
      print "<br>fetching analysis results (state=$state, type$typeIndex)...</br>\n";
      
      $suburbAnalysisTable = $this->{'suburbAnalysisTable'};
      @analysisResults = $suburbAnalysisTable->getAnalysisResults($state, $typeIndex);
   
      $this->{'analysis_loaded'} = 1;
      $this->{'analysis_state'} = $state;
      $this->{'analysis_typeIndex'} = $typeIndex;
      
   }
   else
   {
       #print "<br>Analysis results in memory ($state, type$typeIndex)...</br>\n";
   }
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# estimate the sale price of an advertised property - pretty simple guess using the advertised price
# or 2/3s of the buyer enquiry range
sub estimateSalePrice
{
 
   my $this = shift;
   my $profileRef = shift;
   
   
   # if a buyer enquiry range is specified, take 2/3rds of the range as the price.
   if (defined $$profileRef{'AdvertisedPriceUpper'} && ($$profileRef{'AdvertisedPriceUpper'}) > 0)
   {
      $distance = $$profileRef{'AdvertisedPriceUpper'} - $$profileRef{'AdvertisedPriceLower'};
      $estimatedPrice = $$profileRef{'AdvertisedPriceLower'} + ($distance * 2 / 3);
      # round up to the nearest $1000
      $estimatedPrice = (int($estimatedPrice/1000) + 1) * 1000;
   }
   else
   {
      $estimatedPrice = $$profileRef{'AdvertisedPriceLower'};  
   }
   
   return $estimatedPrice;
}
# -------------------------------------------------------------------------------------------------

# calculate the cashflow performance for the suburbs.  This function depends on completion of the
# sale and rental analysis first
sub calculateCashflowAnalysis

{
   my $this = shift;
    
   my $ALL = 0;
   my $THREE_BY_ANY = 1;
   my $THREE_BY_ONE = 2;
   my $THREE_BY_TWO = 3;
   my $FOUR_BY_ANY = 4;
   my $FOUR_BY_ONE = 5;
   my $FOUR_BY_TWO = 6;
   my $FIVE_BY_ANY = 7;
   my $NO_OF_CATEGORIES = 8;
  
   my @cashflowMedian;      # array of hashes
 
   my $propertiesListRef =  $this->{'salesResultsList'};
   my $suburbAnalysisTable = $this->{'suburbAnalysisTable'};
   
   # now loop through all the PROPERTIES, this time to estimate the median cashflow
   # this is done in a separate loop because the arrays calculated previously are required
  
   # loop through the very large array of properties
   foreach (@$propertiesListRef)
   {
      $suburbName = $$_{'SuburbName'};
      
      $advertisedPrice = $this->estimateSalePrice($_);     
   
      if ($advertisedPrice > 0)
      {
         
         # for each first occurance of a suburbname, initialise a new list of cashflows
         if (!defined $weeklyCashflowList[$ALL]{$suburbName})
         {
            for ($category = 0; $category < $NO_OF_CATEGORIES; $category++)
            {
               # initialise counters for the first time for this suburbname
               my @newList;
               $weeklyCashflowList[$category]{$suburbName} = \@newList;  # initialise a new array
            }
         }
         
         # --- cashflow analysis ---
         
         # estimate the rent for the property
         ($estimatedRent, $estimatedYield) = $this->estimateRent($advertisedPrice, $_);
         $infoHashRef = $this->estimateWeeklyCashflow($advertisedPrice, $estimatedRent, $_);
         $estimatedCashflow = $$infoHashRef{'weeklyCashflow'};
   
         #print "$suburbName: $advertisedPrice, ER=$estimatedRent, EC=$estimatedCashflow\n";           
         
         # now allocated the estimated cashflow to each applicable category - loop through 
         # all the defined categories and check their suitability
         for ($category = 0; $category < $NO_OF_CATEGORIES; $category++)
         {
            # acertain if this category is applicable for this property
            $useThisCategory = 0;
            if ($category == $ALL)
            {
               $useThisCategory = 1;
            }
            else
            {
               if ($$_{'Bedrooms'} == 3)
               {
                  if ($category == $THREE_BY_ANY)
                  {
                     $useThisCategory = 1;               
                  }
                  else
                  {
                     if (($category == $THREE_BY_ONE) && ($$_{'Bathrooms'} == 1))
                     {
                        $useThisCategory = 1;               
                     }
                     else
                     {
                        if (($category == $THREE_BY_TWO) && ($$_{'Bathrooms'} == 2))
                        {
                           $useThisCategory = 1;               
                        }
                     }
                  }
               }
               else
               {
                  if ($$_{'Bedrooms'} == 4)
                  {
                     if ($category == $FOUR_BY_ANY)
                     {
                        $useThisCategory = 1;               
                     }
                     else
                     {
                        if (($category == $FOUR_BY_ONE) && ($$_{'Bathrooms'} == 1))
                        {
                           $useThisCategory = 1;               
                        }
                        else
                        {
                           if (($category == $FOUR_BY_TWO) && ($$_{'Bathrooms'} == 2))
                           {
                              $useThisCategory = 1;               
                           }
                        }
                     }
                  }
                  else
                  {
                     if ($$_{'Bedrooms'} == 5)
                     {
                        if ($category == $FIVE_BY_ANY)
                        {
                           $useThisCategory = 1;               
                        }
                     }  
                  }
               }
            }

            # this category is appicable for this property - add the cashflow it its list for calculating
            # the median later
            if ($useThisCategory)
            {
               # push this cashflow onto the list for this suburb and category - it's used to calculate the median later
               $listRef = $weeklyCashflowList[$category]{$suburbName};
               push @$listRef, $estimatedCashflow;
               #DebugTools::printList("$suburbName", \@listRef);
            }
         }  
      }
   }
   
   # now calculate the median cashflow for the suburb
   $hashRef = $suburbAnalysisTable->getNoOfSalesHash($ALL);
   foreach (keys %$hashRef)
   {
      $suburbName = $_;
      #print "$suburbName\n";
      # loop for all the different categories
      for ($propertyType = 0; $propertyType < $NO_OF_CATEGORIES; $propertyType++)
      {
         $listRef = $weeklyCashflowList[$propertyType]{$suburbName};
         
         #DebugTools::printList("$suburbName:listRef[$propertyType]", $listRef);
         
         @priceList = sort { $a <=> $b } @$listRef;   # sort numerically
         
         
    #     DebugTools::printList("CASHFLOW($suburbName)", \@priceList);
         
         
         $listLength = @priceList;
         #if ($_ eq "Cable Beach")
         #{
         #   print "listLength{$_} = $listLength (";
         #}
         if (($listLength % 2) == 0)
         {
            # if the list length is even...find the middle pair of numbers and take the centre of those
            $medianLower = $priceList[($listLength / 2)-1];
            $medianUpper = $priceList[$listLength / 2];
            #if ($_ eq "Cable Beach")
            #{
            #   print "lower=$medianLower, upper=$medianUpper\n";
            #}
            $medianPrice = $medianLower + ($medianUpper - $medianLower) / 2;
         }
         else
         {
            # the list length is odd, so the median value is the one in the middle
            $medianPrice = $priceList[$listLength / 2];
         }
         
         $cashflowMedian[$propertyType]{$suburbName} = $medianPrice;
      }
   }
   
   #DebugTools::printList("noOfAdvertised", \@noOfCurrentlyAdvertised);
   #print "noOfAdvertised[0]=", $noOfCurrentlyAdvertised[0], "\n";
   #$hashRef = $cashflowMedian[0];
   #DebugTools::printHash("cashflowMedian[0]", $hashRef);
   
   $this->{'medianCashflowCategoryHash'} = \@cashflowMedian;      
}

# -------------------------------------------------------------------------------------------------

# ------------------------------------------------------------------------------------------------- 
sub getState
{
   my $this = shift;   

  
   return $this->{'state'};
}

# ------------------------------------------------------------------------------------------------- 
sub getTypeIndex
{
   my $this = shift;   

   return $this->{'typeIndex'};
}

# ------------------------------------------------------------------------------------------------- 
# ------------------------------------------------------------------------------------------------- 
# returns the list of hashes of sales data used in the analysis
sub getSalesDataList
{
   my $this = shift;
   my $suburbIndex = shift;   
   my $sqlClient = $this->{'sqlClient'};   
   
   $salesSelectCommand = "select Identifier, DateLastAdvertised, unix_timestamp(DateLastAdvertised) as UnixTimeStamp, StreetNumber, Street, SuburbName, SuburbIndex, AdvertisedPriceLower, AdvertisedPriceUpper, Bedrooms, Bathrooms, YearBuilt from MasterPropertyTable where SuburbIndex=$suburbIndex and ".$this->{'date14daySearch'}." ".$this->{'typeSearch'}." order by Street, StreetNumber";
   print "<br/>", "<tt>SALES  :$salesSelectCommand</tt><br/>";
   my @salesResults = $sqlClient->doSQLSelect($salesSelectCommand);
   
   $length = @salesResults;
   
   print "\n\nlength=$length<br/>\n\n\n\n";
   return \@salesResults;
}

# ------------------------------------------------------------------------------------------------- 
# returns the list of hashes of sales data used in the analysis
sub getRelatedSalesDataList
{
   my $this = shift;   
   my $suburbIndex = shift;
   my $sqlClient = $this->{'sqlClient'};   
   
   $salesSelectCommand = "select Identifier, DateLastAdvertised, unix_timestamp(DateLastAdvertised) as UnixTimeStamp, StreetNumber, Street, SuburbName, SuburbIndex, AdvertisedPriceLower, AdvertisedPriceUpper, Bedrooms, Bathrooms, YearBuilt from MasterPropertyTable where SuburbIndex=$suburbIndex and ".$this->{'relatedSalesDateSearch'}." ".$this->{'typeSearch'}." order by Street, StreetNumber";
   print "<br/>", "<tt>RELATEDSALES  :$salesSelectCommand</tt><br/>";
   my @salesResults = $sqlClient->doSQLSelect($salesSelectCommand);
   
   
   return \@salesResults;
}


# ------------------------------------------------------------------------------------------------- 
# returns the list of hashes of rental data used in the analysis
sub getRentalDataList
{
   my $this = shift;   
   
   my $sqlClient = $this->{'sqlClient'};      
   #$rentalsSelectCommand = "select Identifier, greatest(unix_timestamp(DateEntered), unix_timestamp(LastEncountered)) as LastSeen, StreetNumber, Street, SuburbName, AdvertisedWeeklyRent, Bedrooms, Bathrooms from WorkingView_AdvertisedRentalProfiles where AdvertisedWeeklyRent > 0 and ".$this->{'rentalsDateSearch'}." state='".$this->{'state'}."' and ".$this->{'suburbSearch'}." ".$this->{'typeSearch'}." order by SuburbName, LastSeen desc, AdvertisedWeeklyRent, Street, StreetNumber";
   print "<br/>", "<tt>DISABLED - RENTALS:$rentalsSelectCommand</tt><br/>";

   #my @rentalResults = $sqlClient->doSQLSelect($rentalsSelectCommand);
   
   return \@rentalResults;
}

# ------------------------------------------------------------------------------------------------- 
# returns the suburbAnalysisTable associated with the AnalysisTool
#  provides access to analysis data
sub getSuburbAnalysisTable
{
   my $this = shift;   
   
   return $this->{'suburbAnalysisTable'};
}

# ------------------------------------------------------------------------------------------------- 
# returns the propertyCategories associated with the AnalysisTool
sub getPropertyCategories
{
   my $this = shift;   
   
   return $this->{'propertyCategories'};
}

# ------------------------------------------------------------------------------------------------- 
# returns the propertyTypes associated with the AnalysisTool
sub getPropertyTypes
{
   my $this = shift;   
   
   return $this->{'propertyTypes'};
}
# ------------------------------------------------------------------------------------------------- 
# ------------------------------------------------------------------------------------------------- 
# ------------------------------------------------------------------------------------------------- 
# returns the hashes of official rental medians
sub getOfficialRentalMedianHash
{
   my $this = shift;   
   
   return $this->{'officialRentalMedian'};
}

# ------------------------------------------------------------------------------------------------- 
# returns the hashes of official sales medians
sub getOfficialSalesMedianHash
{
   my $this = shift;   
   
   return $this->{'officialSalesMedian'};
}

# ------------------------------------------------------------------------------------------------- 
# returns the hash of profile data for a property
sub getPropertyProfile
{
   my $this = shift;   
   my $identifier = shift;
   my $sqlClient = $this->{'sqlClient'};   
   
   $quotedIdentifier = $sqlClient->quote($identifier);
   $selectCommand = "select Identifier, DateLastAdvertised, unix_timestamp(DateLastAdvertised) as UnixTimeStamp, StreetNumber, Street, SuburbName, SuburbIndex, AdvertisedPriceLower, AdvertisedPriceUpper, Type, Bedrooms, Bathrooms, YearBuilt from MasterPropertyTable where identifier=".$quotedIdentifier;

   my @profileResults = $sqlClient->doSQLSelect($selectCommand);
   
   $propertyHashRef = $profileResults[0];
   
   return $propertyHashRef;
}


# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# performs the query on the database to get selected suburb information
sub fetchOfficialMedians

{
   my $this = shift;
   my $suburbNameUnquoted = shift;
   my $sqlClient = $this->{'sqlClient'};
   my $suburbName = $sqlClient->quote($suburbNameUnquoted);
   my @suburbResults = $sqlClient->doSQLSelect("select MedianPrice, MedianWeeklyRent from SuburbProfiles where SuburbName like $suburbName order by DateEntered desc");

   foreach (@suburbResults)
   {
      $medianPrice = $$_{'MedianPrice'};
      $medianWeeklyRent = $$_{'MedianWeeklyRent'};    
   }
   
   return ($medianPrice, $medianWeeklyRent);
}

# -------------------------------------------------------------------------------------------------
# estimate the purchase costs for a particular property using the current analysis parameters
sub estimatePurchaseCosts

{      
   my $this = shift;
   my $estimatedPrice = shift;
   my %purchaseCosts;

   $purchaseCosts{'purchasePrice'} = $estimatedPrice;

   
   # --- estimate purchase fees ---
   
   $purchaseCosts{'nre_pc_conveyancy'} = 600.00;
   $purchaseCosts{'nre_pc_landTitleSearch'} = 41.00;  # crap?
   $purchaseCosts{'nre_pc_landTaxDept'} = 30.00;      # crap?
   $purchaseCosts{'nre_pc_councilRatesEnquiry'} = 65.00;      # 
   $purchaseCosts{'nre_pc_waterRatesEnquiry'} = 30.00;      # 
   $purchaseCosts{'nre_pc_govtBankCharge'} = 20.00;      # 
   $purchaseCosts{'nre_pc_transferRegistration'} = 105.00;      # 
   
   # worst case, WA
   if ($estimatedPrice < 80001)
   {
      $purchaseCosts{'nre_pc_conveyancyStampDuty'} = $estimatedPrice/100*2;   
   }
   else
   {
      if ($estimatedPrice < 100001)
      {
         $purchaseCosts{'nre_pc_conveyancyStampDuty'} = 1600+($estimatedPrice-80000)/100*3;            
      }
      else
      {
         if ($estimatedPrice < 250001)
         {
            $purchaseCosts{'nre_pc_conveyancyStampDuty'} = 2200+($estimatedPrice-100000)/100*4;                     
         }
         else
         {
            if ($estimatedPrice < 500001)
            {
               $purchaseCosts{'nre_pc_conveyancyStampDuty'} = 8200+($estimatedPrice-250000)/100*5;                     
            }
            else
            {
               $purchaseCosts{'nre_pc_conveyancyStampDuty'} = 20700+($estimatedPrice-500000)/100*5.4;     
            }
         }
      }
   }
   
   $purchaseCosts{'nre_pc_section43Certificate'} = 55.00;      
   $purchaseCosts{'nre_pc_bankChequeFees'} = 13.00;
   $purchaseCosts{'nre_pc_buildingInspection'} = 300.00;      

   $purchaseCosts{'totalPurchaseFees'} = $purchaseCosts{'nre_pc_conveyancy'} +
                        $purchaseCosts{'nre_pc_landTitleSearch'} +
                        $purchaseCosts{'nre_pc_landTaxDept'} +
                        $purchaseCosts{'nre_pc_councilRatesEnquiry'} +
                        $purchaseCosts{'nre_pc_waterRatesEnquiry'} +
                        $purchaseCosts{'nre_pc_govtBankCharge'} +
                        $purchaseCosts{'nre_pc_transferRegistration'} +
                        $purchaseCosts{'nre_pc_conveyancyStampDuty'} +
                        $purchaseCosts{'nre_pc_section43Certificate'} +
                        $purchaseCosts{'nre_pc_bankChequeFees'} +
                        $purchaseCosts{'nre_pc_buildingInspection'};
   return \%purchaseCosts;   
}

# -------------------------------------------------------------------------------------------------
# estimate the mortgage establishment costs for a particular property using the current analysis parameters
sub estimateMortgageCosts

{      
   my $this = shift;
   my $estimatedPrice = shift;
   my $purchaseCostsRef = shift;
   
   # --- estimate mortgage fees ---
                        
   $$purchaseCostsRef{'nre_me_loanApplicationFee'} = 600.00;
   #### must use actual mortgage costs, rather than estimated price, as the costs are capitalised onto the loan
   $estimatedMortgageStampDuty = $estimatedPrice/100*0.4;   # based on WA state fees only, for investment property
   $$purchaseCostsRef{'nre_me_mortgageRegistration'} = 75.00;
   $$purchaseCostsRef{'nre_me_titleSearch'} = 18.00;
   $$purchaseCostsRef{'nre_me_valuationFee'} = 300.00;
   $$purchaseCostsRef{'nre_me_lmiFee'} = 0.00;                                 # currently assumes no lenders mortgage insurance
      
   $totalMortgageFees = $$purchaseCostsRef{'nre_me_loanApplicationFee'} +
                        $$purchaseCostsRef{'nre_me_mortgageRegistration'} +
                        $$purchaseCostsRef{'nre_me_titleSearch'} +
                        $$purchaseCostsRef{'nre_me_valuationFee'} +
                        $$purchaseCostsRef{'nre_me_lmiFee'};
                        # important STAMP DUTY IS CACLULATED AND ADDED LATER 

   
   # --- calculate loan required and adjust mortgage stamp duty to match---
  
   $stampDutyError = 2; 
   $totalPurchaseFees = $$purchaseCostsRef{'totalPurchaseFees'};
   
   #iterate to calculate the actual mortgage stamp duty (which is included in the mortgage)
   # it's solved using iteration as the total mortgage includes the stamp duty, but the
   # stamp duty depends on the total mortgage
   while ($stampDutyError > 1)
   {
     
      $totalPurchaseCosts = $estimatedPrice + $totalMortgageFees + $estimatedMortgageStampDuty + $totalPurchaseFees;
      #print "ESD: $estimatedMortgageStampDuty  TPC:$totalPurchaseCosts\n";
      $depositRequired = $totalPurchaseCosts * (1 - 0.8);   # 80% LVR
      
      $loanRequired = $estimatedPrice - $depositRequired;
      
      $adjustedMortgageStampDuty = $loanRequired/100*0.4;   # based on WA state fees only, for investment property
      
      # iterate until a local mininim is found (delta is less than one)
      $stampDutyError = abs($adjustedMortgageStampDuty - $estimatedMortgageStampDuty);
      #print "   AMS: $adjustedMortgageStampDuty error:$stampDutyError\n";
      
      if ($stampDutyError > 1)
      {
         $estimatedMortgageStampDuty = $adjustedMortgageStampDuty;
      }
   }
   
   $$purchaseCostsRef{'nre_me_mortgageStampDuty'} = $adjustedMortgageStampDuty;
   # adjust the total mortgage fees to include the refined stamp duty component
   $$purchaseCostsRef{'totalMortgageFees'} = $totalMortgageFees + $adjustedMortgageStampDuty;  # add mortgage stamp duty to total fees        
   
   $apportionedMortgageFees = $$purchaseCostsRef{'totalMortgageFees'} * 0.20;
   

   $$purchaseCostsRef{'cashRequired'} = 0.00; 
   $$purchaseCostsRef{'depositRequired'} = $depositRequired; 
   $$purchaseCostsRef{'loanRequired'} = $loanRequired;    
   
   return $apportionedMortgageFees;
}

# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# estimate the annual income for a particular property using the current analysis parameters
sub estimateAnnualIncome

{      
   my $this = shift;
   my $estimatedRent = shift;
   my %annualIncome;
   
   # cash deposit has no interest on it
   $occupancyRate = 0.8;    # banks use 0.7
   $annualIncome{'occupancyRate'} = $occupancyRate;
   $annualIncome{'weeklyRent'} = $estimatedRent;
   $annualIncome{'annualIncome'} = $estimatedRent * 52 * $occupancyRate;
   
   # --- estimate mortgage fees ---
   
   return \%annualIncome;   
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# estimate the recurring expenses for a particular property using the current analysis parameters
sub estimateAnnualExpenses
{      
   my $this = shift;
   my $purchaseCostsRef = shift;
   my $annualIncomeRef = shift;
   my %annualExpenses;
   
   # --- calculate the interest on the equity portion used as deposit ---
   $equityRequired = $$purchaseCostsRef{'depositRequired'} - $$purchaseCostsRef{'cashDeposit'}; 
   
   # interest-only - calculate annual interest on the equity component
   $annualExpenses{'re_me_equityInterest'} = 0.0675 * $equityRequired;    # assuming 6.75%
   
   # interest-only - calculate annual interest on the mortgage
   $annualExpenses{'re_me_mortgageInterest'} = 0.0675 * $$purchaseCostsRef{'loanRequired'};
   
   $annualExpenses{'re_me_mortgageAdminFees'} = 300.00;
   
   $annualExpenses{'totalAnnualMortgageCosts'} = $annualExpenses{'re_me_equityInterest'} +
                                                 $annualExpenses{'re_me_mortgageInterest'} +
                                                 $annualExpenses{'re_me_mortgageAdminFees'};                        
                         
   # --- estimate management fees ---
                         
   $annualExpenses{'rentalCommission'} = 0.1;                        
   $annualExpenses{'re_am_initialLettingFee'} = $$annualIncomeRef{'weeklyRent'} / 2;                      
   $annualExpenses{'re_am_reLettingFee'} = $$annualIncomeRef{'weeklyRent'};                      
   $annualExpenses{'avgLengthOfStay'} = 9;
   
   $annualExpenses{'totalManagementFees'} = $annualExpenses{'rentalCommission'} * $$annualIncomeRef{'weeklyRent'} * 52 * $$annualIncomeRef{'occupancyRate'} +
                                            $annualExpenses{'re_am_initialLettingFee'} +
                                            $annualExpenses{'avgLengthOfStay'}/12 * $annualExpenses{'re_am_reLettingFee'};
                                       
   # --- estimate maintenance & ownership costs ---
   
   # **** THIS IS ALL CRAP ********
   $annualExpenses{'re_am_maintenance'} = 500.00;
   $annualExpenses{'re_am_strataFees'} = 360.00;
   $annualExpenses{'re_am_propertyInsurance'} = 120.00;
   $annualExpenses{'re_am_councilRates'} = 700.00;    # related to land area and suburb
   $annualExpenses{'re_am_waterRates'} = 700.00;      # related to bathrooms and state?
   
   # this is a rough guess at land tax
   $unimprovedLandValue = $$purchaseCostsRef{'purchasePrice'} * 0.5;
   
   # aggregate land tax
   if ($unimprovedLandValue < 100001)
   {
      $annualExpenses{'re_am_landTax'} = 0;  
   }
   else
   {
      if ($unimprovedLandValue < 220001)
      {
         $annualExpenses{'re_am_landTax'} = 150+($unimprovedLandValue-100000)*0.15;            
      }
      else
      {
         if ($unimprovedLandValue < 570001)
         {
            $annualExpenses{'re_am_landTax'} = 330+($unimprovedLandValue-220000)*0.45;            
         }
         else
         {
            if ($unimprovedLandValue < 2000001)
            {
               $annualExpenses{'re_am_landTax'} = 1905+($unimprovedLandValue-570000)*1.76;            
            }
            else
            {
               if ($unimprovedLandValue < 5000001)
               {
                  $annualExpenses{'re_am_landTax'} = 27073+($unimprovedLandValue-2000000)*2.30;            
               }
               else
               {
                  $annualExpenses{'re_am_landTax'} = 96073+($unimprovedLandValue-5000000)*2.50;          
               }
            }
         }
      }
   }
   
   $annualExpenses{'totalOwnershipCosts'} = $annualExpenses{'re_am_maintenance'} + 
                                       $annualExpenses{'re_am_strataFees'} +
                                       $annualExpenses{'re_am_propertyInsurance'} +
                                       $annualExpenses{'re_am_councilRates'} +
                                       $annualExpenses{'re_am_waterRates'} +
                                       $annualExpenses{'re_am_landTax'};
                                       
   $annualExpenses{'annualExpenses'} = $annualExpenses{'totalAnnualMortgageCosts'} + 
                                       $annualExpenses{'totalManagementFees'} + 
                                       $annualExpenses{'totalOwnershipCosts'};
                                       
   return \%annualExpenses;   
}

# -------------------------------------------------------------------------------------------------
# estimate the recurring expenses for a particular property using the current analysis parameters
sub estimateAnnualDepreciation
{      
   my $this = shift;
   my $profileRef = shift;
   my $purchaseCostsRef = shift;
   my %annualDepreciation;
   
   # check if the year built is specified
   if ($$profileRef{'YearBuilt'})
   {
     
   }
   
   
   # --- calculate the interest on the equity portion used as deposit ---
   $equityRequired = $$purchaseCostsRef{'depositRequired'} - $$purchaseCostsRef{'cashDeposit'}; 
   
   # interest-only - calculate annual interest on the equity component
   $annualExpenses{'re_me_equityInterest'} = 0.0675 * $equityRequired;    # assuming 6.75%
   
   # interest-only - calculate annual interest on the mortgage
   $annualExpenses{'re_me_mortgageInterest'} = 0.0675 * $$purchaseCostsRef{'loanRequired'};
   
   $annualExpenses{'re_me_mortgageAdminFees'} = 300.00;
   
   $annualExpenses{'totalAnnualMortgageCosts'} = $annualExpenses{'re_me_equityInterest'} +
                                                 $annualExpenses{'re_me_mortgageInterest'} +
                                                 $annualExpenses{'re_me_mortgageAdminFees'};                        
                         
   # --- estimate management fees ---
                         
   $annualExpenses{'rentalCommission'} = 0.1;                        
   $annualExpenses{'re_am_initialLettingFee'} = $$annualIncomeRef{'weeklyRent'} / 2;                      
   $annualExpenses{'re_am_reLettingFee'} = $$annualIncomeRef{'weeklyRent'};                      
   $annualExpenses{'avgLengthOfStay'} = 9;
   
   $annualExpenses{'totalManagementFees'} = $annualExpenses{'rentalCommission'} * $$annualIncomeRef{'weeklyRent'} * 52 * $$annualIncomeRef{'occupancyRate'} +
                                            $annualExpenses{'re_am_initialLettingFee'} +
                                            $annualExpenses{'avgLengthOfStay'}/12 * $annualExpenses{'re_am_reLettingFee'};
                                       
   # --- estimate maintenance & ownership costs ---
   
   # **** THIS IS ALL CRAP ********
   $annualExpenses{'re_am_maintenance'} = 500.00;
   $annualExpenses{'re_am_strataFees'} = 360.00;
   $annualExpenses{'re_am_propertyInsurance'} = 120.00;
   $annualExpenses{'re_am_councilRates'} = 700.00;    # related to land area and suburb
   $annualExpenses{'re_am_waterRates'} = 700.00;      # related to bathrooms and state?
   
   # this is a rough guess at land tax
   $unimprovedLandValue = $$purchaseCostsRef{'purchasePrice'} * 0.5;
   
   # aggregate land tax
   if ($unimprovedLandValue < 100001)
   {
      $annualExpenses{'re_am_landTax'} = 0;  
   }
   else
   {
      if ($unimprovedLandValue < 220001)
      {
         $annualExpenses{'re_am_landTax'} = 150+($unimprovedLandValue-100000)*0.15;            
      }
      else
      {
         if ($unimprovedLandValue < 570001)
         {
            $annualExpenses{'re_am_landTax'} = 330+($unimprovedLandValue-220000)*0.45;            
         }
         else
         {
            if ($unimprovedLandValue < 2000001)
            {
               $annualExpenses{'re_am_landTax'} = 1905+($unimprovedLandValue-570000)*1.76;            
            }
            else
            {
               if ($unimprovedLandValue < 5000001)
               {
                  $annualExpenses{'re_am_landTax'} = 27073+($unimprovedLandValue-2000000)*2.30;            
               }
               else
               {
                  $annualExpenses{'re_am_landTax'} = 96073+($unimprovedLandValue-5000000)*2.50;          
               }
            }
         }
      }
   }
   
   $annualExpenses{'totalOwnershipCosts'} = $annualExpenses{'re_am_maintenance'} + 
                                       $annualExpenses{'re_am_strataFees'} +
                                       $annualExpenses{'re_am_propertyInsurance'} +
                                       $annualExpenses{'re_am_councilRates'} +
                                       $annualExpenses{'re_am_waterRates'} +
                                       $annualExpenses{'re_am_landTax'};
                                       
   $annualExpenses{'annualExpenses'} = $annualExpenses{'totalAnnualMortgageCosts'} + 
                                       $annualExpenses{'totalManagementFees'} + 
                                       $annualExpenses{'totalOwnershipCosts'};
                                       
   return \%annualExpenses;   
}

# -------------------------------------------------------------------------------------------------
# estimate the cost of ownership for a particular property using the current analysis parameters
# as in cost per week
sub estimateWeeklyCashflow
{      
   my $this = shift;
   my $estimatedPrice = shift;
   my $estimatedRent = shift;
   my $propertyDataHashRef = shift;

   $purchaseCosts = $this->estimatePurchaseCosts($estimatedPrice);
   $apportionedMortgageFees = $this->estimateMortgageCosts($estimatedPrice, $purchaseCosts);
   
   $annualIncome = $this->estimateAnnualIncome($estimatedRent);
   $annualExpenses = $this->estimateAnnualExpenses($purchaseCosts, $annualIncome);
   #$depreciation = $this->estimateAnnualDepreciation($purchaseCosts);
   $depreciation = 0.00;
   # calculate the gross annual income before depreciation and apportioned expenses 

   $taxableIncome = $$annualIncome{'annualIncome'} - $$annualExpenses{'annualExpenses'} - $$depreciation{'annualDepreciation'} - $apportionedMortgageFees;
   
   if ($taxableIncome < 0)
   {
      # making a loss (negatively geared) - calulate the tax refund      
      $taxRefund = $taxableIncome * 0.485;    # assuming highest tax bracket for now  - this is possibly crap
      # calculate the annual cash outlay which excludes depreciation and apportioned fees and includes the tax refund as income
      # if this is positive the property is cashflow positive
      $annualCashOutlay = $$annualIncome{'annualIncome'} - $$annualExpenses{'annualExpenses'} - $taxRefund;
   }
   else
   {
      # this property makes a profit (positively geared) - calculate the tax owed
      $taxOwed = $taxableIncome * 0.485;     # assuming highest tax bracket for now - this is possibly crap
      
      # calculate the annual cash outlay which excludes depreciation and apportioned fees and includes the tax refund as income
      # if this is positive the property is cashflow positive
      $annualCashOutlay = $$annualIncome{'annualIncome'} - $$annualExpenses{'annualExpenses'} + $taxOwed;    
   }

   my %infoHash;
   $infoHash{'estimatedRent'} = $estimatedRent;
   $infoHash{'purchaseCosts'} = $$purchaseCosts{'totalPurchaseFees'};
   $infoHash{'mortgageCosts'} = $$purchaseCosts{'totalMortgageFees'};
   $infoHash{'annualIncome'} = $$annualIncome{'annualIncome'};
   $infoHash{'annualExpenses'} = $$annualExpenses{'annualExpenses'};
   $infoHash{'taxRefund'} = $taxRefund;
   $infoHash{'weeklyCashflow'} = $annualCashOutlay / 52;
   
   return \%infoHash;   
}

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# estimate the rent for a particular property using the current analysis parameters
sub estimateRent

{      
   my $this = shift;
   my $housePrice = shift;
   my $propertyDataHashRef = shift;
   
   my %salesMean;
   my %salesStdDev;
   my %rentalStdDev;
   my %rentalMean;                         
 
   $suburbIndex = $$propertyDataHashRef{'SuburbIndex'};       
   $sqlClient = $this->{'sqlClient'};
   $suburbAnalysisTable = $this->{'suburbAnalysisTable'};
   $propertyCategories = $this->{'propertyCategories'};   
   
   #($officialSalesMean, $officialRentalMean) = $analysisTools->fetchOfficialMedians($suburbName);
   #$this->fetchAnalysisResults($state, $typeIndex);
  
   $category = $propertyCategories->lookupBestFitCategory($$propertyDataHashRef{'Bedrooms'}, $$propertyDataHashRef{'Bathrooms'}, $suburbIndex);
   
   # get statistical data for the category
   $salesMean = $suburbAnalysisTable->getSalesMeanHash($category);
   $salesStdDev = $suburbAnalysisTable->getSalesStdDevHash($category);
   $rentalMean = $suburbAnalysisTable->getRentalMeanHash($category);
   $rentalStdDev = $suburbAnalysisTable->getRentalStdDevHash($category);

   if ($housePrice > 0)
   {
      $delta = $housePrice - $$salesMean{$suburbIndex};
      #$delta = $housePrice - $officialSalesMean;
           
      if ($$salesStdDev{$suburbIndex} > 0)
      {
         $ratio = $delta / $$salesStdDev{$suburbIndex};                 
      }
      else
      {      
         $ratio = 0;         
      }
 
      if ($$rentalStdDev{$suburbIndex} > 0)
      {
         $estimatedRent = ($ratio * $$rentalStdDev{$suburbIndex}) + $$rentalMean{$suburbIndex};
         #$estimatedRent = ($ratio * $$rentalStdDev{$suburbIndex}) + $officialRentalMean;         
         # round down to the nearest $10.
         $estimatedRent = int($estimatedRent / 10) * 10;         
      }
      else
      {
         $estimatedRent = 0;
      }              
      
      $estimatedYield = ($estimatedRent * 5200) /  $housePrice;  
   }       
 
   return ($estimatedRent, $estimatedYield);
}

