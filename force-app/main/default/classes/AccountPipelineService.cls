global with sharing class AccountPipelineService {

    @InvocableMethod(
        label='Get Account Pipeline'
        description='Returns open opportunities with line items and computed business intelligence (risk levels, weighted pipeline, health summary) for a given account name. Supports fuzzy matching.'
    )
    global static List<PipelineResult> getAccountPipeline(List<PipelineRequest> requests) {
        List<PipelineResult> results = new List<PipelineResult>();

        for (PipelineRequest request : requests) {
            PipelineResult result = new PipelineResult();

            Account acc = resolveAccount(request.accountName, result);
            if (acc == null) {
                results.add(result);
                continue;
            }

            result.accountFound = true;
            result.accountName = acc.Name;
            result.industry = acc.Industry;
            result.annualRevenue = acc.AnnualRevenue;

            List<Opportunity> opportunities = [
                SELECT Id, Name, Amount, StageName, Probability, CloseDate,
                    Owner.Name,
                    (SELECT Id, Product2.Name, Quantity, UnitPrice, TotalPrice
                     FROM OpportunityLineItems)
                FROM Opportunity
                WHERE AccountId = :acc.Id
                    AND IsClosed = false
                WITH USER_MODE
                ORDER BY Amount DESC NULLS LAST
            ];

            result.totalOpenDeals = opportunities.size();
            Decimal pipelineTotal = 0;
            Decimal weightedTotal = 0;
            Integer closingSoon = 0;
            Integer highRiskCount = 0;
            List<DealInfo> deals = new List<DealInfo>();
            Date today = Date.today();

            for (Opportunity opp : opportunities) {
                DealInfo deal = new DealInfo();
                deal.opportunityName = opp.Name;
                deal.amount = opp.Amount;
                deal.stageName = opp.StageName;
                deal.probability = opp.Probability;
                deal.closeDate = opp.CloseDate;
                deal.ownerName = opp.Owner.Name;

                deal.daysUntilClose = today.daysBetween(opp.CloseDate);
                deal.riskLevel = assessRisk(opp.Probability, deal.daysUntilClose);

                List<LineItemInfo> items = new List<LineItemInfo>();
                for (OpportunityLineItem oli : opp.OpportunityLineItems) {
                    LineItemInfo item = new LineItemInfo();
                    item.productName = oli.Product2.Name;
                    item.quantity = oli.Quantity;
                    item.unitPrice = oli.UnitPrice;
                    item.totalPrice = oli.TotalPrice;
                    items.add(item);
                }
                deal.lineItems = items;
                deals.add(deal);

                Decimal amt = opp.Amount != null ? opp.Amount : 0;
                Decimal prob = opp.Probability != null ? opp.Probability : 0;
                pipelineTotal += amt;
                weightedTotal += amt * (prob / 100);

                if (deal.daysUntilClose <= 30) {
                    closingSoon++;
                }
                if (deal.riskLevel == 'High') {
                    highRiskCount++;
                }
            }

            result.deals = deals;
            result.totalPipelineValue = pipelineTotal;
            result.weightedPipelineValue = weightedTotal;
            result.dealsClosingWithin30Days = closingSoon;
            result.pipelineHealthSummary = assessPipelineHealth(
                deals.size(), highRiskCount, weightedTotal, pipelineTotal
            );
            results.add(result);
        }

        return results;
    }

    private static Account resolveAccount(String accountName, PipelineResult result) {
        List<Account> accounts = [
            SELECT Id, Name, Industry, AnnualRevenue
            FROM Account
            WHERE Name = :accountName
            WITH USER_MODE
            LIMIT 1
        ];

        if (!accounts.isEmpty()) {
            result.matchType = 'exact';
            return accounts[0];
        }

        String fuzzyPattern = '%' + accountName + '%';
        accounts = [
            SELECT Id, Name, Industry, AnnualRevenue
            FROM Account
            WHERE Name LIKE :fuzzyPattern
            WITH USER_MODE
            LIMIT 1
        ];

        if (!accounts.isEmpty()) {
            result.matchType = 'partial';
            return accounts[0];
        }

        result.accountFound = false;
        result.message = 'No account found matching: ' + accountName;
        return null;
    }

    private static String assessRisk(Decimal probability, Integer daysUntilClose) {
        if (daysUntilClose <= 30 && (probability == null || probability < 60)) {
            return 'High';
        }
        if (probability == null || probability < 50) {
            return 'Medium';
        }
        return 'Low';
    }

    private static String assessPipelineHealth(
        Integer totalDeals, Integer highRiskCount, Decimal weightedValue, Decimal totalValue
    ) {
        if (totalDeals == 0) {
            return 'Empty — no open deals';
        }
        Decimal highRiskRatio = (Decimal) highRiskCount / totalDeals;
        Decimal conversionStrength = totalValue > 0 ? weightedValue / totalValue : 0;

        if (highRiskRatio > 0.5) {
            return 'Weak — majority of deals are high risk';
        }
        if (conversionStrength < 0.4) {
            return 'At Risk — low weighted conversion across pipeline';
        }
        if (highRiskRatio <= 0.2 && conversionStrength >= 0.6) {
            return 'Strong — high confidence, low risk';
        }
        return 'Moderate — mixed signals, review recommended';
    }

    global class PipelineRequest {
        @InvocableVariable(required=true description='The name of the Account to look up pipeline for. Supports partial matching.')
        global String accountName;
    }

    global class PipelineResult {
        @InvocableVariable(description='Whether the account was found')
        global Boolean accountFound;
        @InvocableVariable(description='How the account was matched: exact or partial')
        global String matchType;
        @InvocableVariable(description='Message if account was not found')
        global String message;
        @InvocableVariable(description='Account Name')
        global String accountName;
        @InvocableVariable(description='Industry of the account')
        global String industry;
        @InvocableVariable(description='Annual Revenue of the account')
        global Decimal annualRevenue;
        @InvocableVariable(description='Total number of open deals')
        global Integer totalOpenDeals;
        @InvocableVariable(description='Total value of all open pipeline')
        global Decimal totalPipelineValue;
        @InvocableVariable(description='Pipeline value weighted by probability — realistic expected revenue')
        global Decimal weightedPipelineValue;
        @InvocableVariable(description='Number of deals closing within the next 30 days')
        global Integer dealsClosingWithin30Days;
        @InvocableVariable(description='Overall pipeline health: Strong, Moderate, At Risk, or Weak')
        global String pipelineHealthSummary;
        @InvocableVariable(description='List of open deals with line items and risk assessment')
        global List<DealInfo> deals;
    }

    global class DealInfo {
        @InvocableVariable(description='Opportunity Name')
        global String opportunityName;
        @InvocableVariable(description='Deal Amount')
        global Decimal amount;
        @InvocableVariable(description='Current Stage')
        global String stageName;
        @InvocableVariable(description='Probability percentage')
        global Decimal probability;
        @InvocableVariable(description='Expected Close Date')
        global Date closeDate;
        @InvocableVariable(description='Opportunity Owner Name')
        global String ownerName;
        @InvocableVariable(description='Days until expected close — negative means overdue')
        global Integer daysUntilClose;
        @InvocableVariable(description='Risk level: High, Medium, or Low — computed from probability and close date proximity')
        global String riskLevel;
        @InvocableVariable(description='Products on this deal')
        global List<LineItemInfo> lineItems;
    }

    global class LineItemInfo {
        @InvocableVariable(description='Product Name')
        global String productName;
        @InvocableVariable(description='Quantity')
        global Decimal quantity;
        @InvocableVariable(description='Unit Price')
        global Decimal unitPrice;
        @InvocableVariable(description='Total Price')
        global Decimal totalPrice;
    }
}
