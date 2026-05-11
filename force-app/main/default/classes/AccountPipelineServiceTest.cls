@IsTest
private class AccountPipelineServiceTest {

    @TestSetup
    static void setupData() {
        Account acc = new Account(
            Name = 'Acme Corporation',
            Industry = 'Technology',
            AnnualRevenue = 50000000
        );
        insert acc;

        Id standardPbId = Test.getStandardPricebookId();

        Product2 prod = new Product2(Name = 'Enterprise License', ProductCode = 'ENT-001', IsActive = true);
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = standardPbId,
            Product2Id = prod.Id,
            UnitPrice = 15000,
            IsActive = true
        );
        insert pbe;

        Opportunity oppHigh = new Opportunity(
            Name = 'Acme - Big Deal',
            AccountId = acc.Id,
            Amount = 200000,
            StageName = 'Prospecting',
            Probability = 20,
            CloseDate = Date.today().addDays(15),
            Pricebook2Id = standardPbId
        );
        Opportunity oppLow = new Opportunity(
            Name = 'Acme - Safe Renewal',
            AccountId = acc.Id,
            Amount = 100000,
            StageName = 'Negotiation/Review',
            Probability = 80,
            CloseDate = Date.today().addDays(90),
            Pricebook2Id = standardPbId
        );
        Opportunity oppMedium = new Opportunity(
            Name = 'Acme - Expansion',
            AccountId = acc.Id,
            Amount = 50000,
            StageName = 'Qualification',
            Probability = 40,
            CloseDate = Date.today().addDays(60),
            Pricebook2Id = standardPbId
        );
        insert new List<Opportunity>{ oppHigh, oppLow, oppMedium };

        OpportunityLineItem oli = new OpportunityLineItem(
            OpportunityId = oppHigh.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 10,
            UnitPrice = 15000
        );
        insert oli;
    }

    @IsTest
    static void testExactMatch() {
        AccountPipelineService.PipelineRequest req = new AccountPipelineService.PipelineRequest();
        req.accountName = 'Acme Corporation';

        List<AccountPipelineService.PipelineResult> results =
            AccountPipelineService.getAccountPipeline(new List<AccountPipelineService.PipelineRequest>{ req });

        AccountPipelineService.PipelineResult result = results[0];
        Assert.areEqual(true, result.accountFound);
        Assert.areEqual('exact', result.matchType);
        Assert.areEqual('Acme Corporation', result.accountName);
        Assert.areEqual('Technology', result.industry);
        Assert.areEqual(3, result.totalOpenDeals);
        // Big Deal = 150000 (recalculated from line items: 10 x 15000), Safe = 100000, Expansion = 50000
        Assert.areEqual(300000, result.totalPipelineValue);
    }

    @IsTest
    static void testFuzzyMatch() {
        AccountPipelineService.PipelineRequest req = new AccountPipelineService.PipelineRequest();
        req.accountName = 'Acme';

        List<AccountPipelineService.PipelineResult> results =
            AccountPipelineService.getAccountPipeline(new List<AccountPipelineService.PipelineRequest>{ req });

        AccountPipelineService.PipelineResult result = results[0];
        Assert.areEqual(true, result.accountFound);
        Assert.areEqual('partial', result.matchType);
        Assert.areEqual('Acme Corporation', result.accountName);
    }

    @IsTest
    static void testNotFound() {
        AccountPipelineService.PipelineRequest req = new AccountPipelineService.PipelineRequest();
        req.accountName = 'NonExistentCorp';

        List<AccountPipelineService.PipelineResult> results =
            AccountPipelineService.getAccountPipeline(new List<AccountPipelineService.PipelineRequest>{ req });

        AccountPipelineService.PipelineResult result = results[0];
        Assert.areEqual(false, result.accountFound);
        Assert.isTrue(result.message.contains('NonExistentCorp'));
    }

    @IsTest
    static void testRiskLevels() {
        AccountPipelineService.PipelineRequest req = new AccountPipelineService.PipelineRequest();
        req.accountName = 'Acme Corporation';

        List<AccountPipelineService.PipelineResult> results =
            AccountPipelineService.getAccountPipeline(new List<AccountPipelineService.PipelineRequest>{ req });

        AccountPipelineService.PipelineResult result = results[0];
        Map<String, String> riskByName = new Map<String, String>();
        for (AccountPipelineService.DealInfo deal : result.deals) {
            riskByName.put(deal.opportunityName, deal.riskLevel);
        }

        Assert.areEqual('High', riskByName.get('Acme - Big Deal'));
        Assert.areEqual('Low', riskByName.get('Acme - Safe Renewal'));
        Assert.areEqual('Medium', riskByName.get('Acme - Expansion'));
    }

    @IsTest
    static void testWeightedPipeline() {
        AccountPipelineService.PipelineRequest req = new AccountPipelineService.PipelineRequest();
        req.accountName = 'Acme Corporation';

        List<AccountPipelineService.PipelineResult> results =
            AccountPipelineService.getAccountPipeline(new List<AccountPipelineService.PipelineRequest>{ req });

        AccountPipelineService.PipelineResult result = results[0];
        // 150000*0.20 + 100000*0.80 + 50000*0.40 = 30000 + 80000 + 20000 = 130000
        Assert.areEqual(130000, result.weightedPipelineValue);
    }

    @IsTest
    static void testDealsClosingSoon() {
        AccountPipelineService.PipelineRequest req = new AccountPipelineService.PipelineRequest();
        req.accountName = 'Acme Corporation';

        List<AccountPipelineService.PipelineResult> results =
            AccountPipelineService.getAccountPipeline(new List<AccountPipelineService.PipelineRequest>{ req });

        AccountPipelineService.PipelineResult result = results[0];
        Assert.areEqual(1, result.dealsClosingWithin30Days);
    }

    @IsTest
    static void testPipelineHealthWeak() {
        AccountPipelineService.PipelineRequest req = new AccountPipelineService.PipelineRequest();
        req.accountName = 'Acme Corporation';

        List<AccountPipelineService.PipelineResult> results =
            AccountPipelineService.getAccountPipeline(new List<AccountPipelineService.PipelineRequest>{ req });

        // 1 high risk out of 3 deals = 33% high risk ratio
        // weighted/total = 140000/350000 = 0.4 — exactly at the boundary
        AccountPipelineService.PipelineResult result = results[0];
        Assert.isTrue(result.pipelineHealthSummary.contains('Moderate') ||
                      result.pipelineHealthSummary.contains('At Risk'));
    }

    @IsTest
    static void testLineItems() {
        AccountPipelineService.PipelineRequest req = new AccountPipelineService.PipelineRequest();
        req.accountName = 'Acme Corporation';

        List<AccountPipelineService.PipelineResult> results =
            AccountPipelineService.getAccountPipeline(new List<AccountPipelineService.PipelineRequest>{ req });

        AccountPipelineService.PipelineResult result = results[0];
        Boolean foundLineItem = false;
        for (AccountPipelineService.DealInfo deal : result.deals) {
            if (deal.opportunityName == 'Acme - Big Deal' && !deal.lineItems.isEmpty()) {
                AccountPipelineService.LineItemInfo item = deal.lineItems[0];
                Assert.areEqual('Enterprise License', item.productName);
                Assert.areEqual(10, item.quantity);
                Assert.areEqual(15000, item.unitPrice);
                Assert.areEqual(150000, item.totalPrice);
                foundLineItem = true;
            }
        }
        Assert.isTrue(foundLineItem, 'Expected line item on Big Deal');
    }

    @IsTest
    static void testEmptyPipeline() {
        Account emptyAcc = new Account(Name = 'Empty Corp');
        insert emptyAcc;

        AccountPipelineService.PipelineRequest req = new AccountPipelineService.PipelineRequest();
        req.accountName = 'Empty Corp';

        List<AccountPipelineService.PipelineResult> results =
            AccountPipelineService.getAccountPipeline(new List<AccountPipelineService.PipelineRequest>{ req });

        AccountPipelineService.PipelineResult result = results[0];
        Assert.areEqual(true, result.accountFound);
        Assert.areEqual(0, result.totalOpenDeals);
        Assert.areEqual(0, result.totalPipelineValue);
        Assert.isTrue(result.pipelineHealthSummary.contains('Empty'));
    }
}
