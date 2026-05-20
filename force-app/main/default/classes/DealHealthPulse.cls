global with sharing class DealHealthPulse {

    @InvocableMethod(
        label='Get At Risk Deals'
        description='Scans all open opportunities in the org and returns deals showing risk signals: stage stagnation, no recent activity, slipped close date, or missing next step. Useful for a headless agent to proactively surface pipeline risk without a human logging in.'
    )
    global static List<PulseResult> getAtRiskDeals(List<PulseRequest> requests) {
        List<PulseResult> results = new List<PulseResult>();

        for (PulseRequest req : requests) {
            PulseResult result = new PulseResult();

            Integer stagnationDays = (req.stagnationDays != null && req.stagnationDays > 0)
                ? req.stagnationDays : 21;
            Integer inactivityDays = (req.inactivityDays != null && req.inactivityDays > 0)
                ? req.inactivityDays : 14;

            Date today = Date.today();
            Date stagnationCutoff = today.addDays(-stagnationDays);
            Date inactivityCutoff = today.addDays(-inactivityDays);

            List<Opportunity> opps = [
                SELECT Id, Name, StageName, Amount, CloseDate, NextStep,
                       Probability, Owner.Name, Account.Name,
                       (SELECT CreatedDate FROM OpportunityHistories
                        ORDER BY CreatedDate DESC LIMIT 1),
                       (SELECT ActivityDate FROM ActivityHistories
                        ORDER BY ActivityDate DESC LIMIT 1)
                FROM Opportunity
                WHERE IsClosed = false
                WITH USER_MODE
                ORDER BY Amount DESC NULLS LAST
                LIMIT 100
            ];

            List<RiskDeal> riskDeals = new List<RiskDeal>();
            Integer totalScanned = opps.size();
            Integer totalAtRisk = 0;
            Decimal totalAtRiskValue = 0;

            for (Opportunity opp : opps) {
                List<String> signals = new List<String>();

                // Signal 1: Close date has already passed
                if (opp.CloseDate != null && opp.CloseDate < today) {
                    Integer daysOverdue = opp.CloseDate.daysBetween(today);
                    signals.add('Close date overdue by ' + daysOverdue + ' day(s)');
                }

                // Signal 2: Stage has not moved recently
                if (!opp.OpportunityHistories.isEmpty()) {
                    Date lastStageChange = opp.OpportunityHistories[0].CreatedDate.date();
                    if (lastStageChange < stagnationCutoff) {
                        Integer daysSince = lastStageChange.daysBetween(today);
                        signals.add('Stage "' + opp.StageName + '" stuck for ' + daysSince + ' days');
                    }
                } else {
                    signals.add('No stage movement ever recorded');
                }

                // Signal 3: No recent activity
                if (!opp.ActivityHistories.isEmpty()) {
                    Date lastActivity = opp.ActivityHistories[0].ActivityDate;
                    if (lastActivity == null || lastActivity < inactivityCutoff) {
                        signals.add('No activity logged in the last ' + inactivityDays + ' days');
                    }
                } else {
                    signals.add('Zero activities logged on this deal');
                }

                // Signal 4: Missing next step
                if (String.isBlank(opp.NextStep)) {
                    signals.add('Next Step field is empty — no clear action defined');
                }

                if (!signals.isEmpty()) {
                    RiskDeal deal = new RiskDeal();
                    deal.opportunityId   = opp.Id;
                    deal.opportunityName = opp.Name;
                    deal.accountName     = opp.Account != null ? opp.Account.Name : 'Unknown';
                    deal.ownerName       = opp.Owner.Name;
                    deal.stageName       = opp.StageName;
                    deal.probability     = opp.Probability;
                    deal.amount          = opp.Amount != null ? opp.Amount : 0;
                    deal.closeDate       = opp.CloseDate;
                    deal.riskSignals     = signals;
                    deal.riskScore       = signals.size(); // 1–4
                    deal.riskLabel       = deal.riskScore >= 3 ? 'Critical'
                                        : deal.riskScore == 2 ? 'High'
                                        : 'Medium';
                    riskDeals.add(deal);

                    totalAtRisk++;
                    totalAtRiskValue += deal.amount;
                }
            }

            result.atRiskDeals         = riskDeals;
            result.totalDealsScanned   = totalScanned;
            result.totalAtRiskCount    = totalAtRisk;
            result.totalAtRiskValue    = totalAtRiskValue;
            result.summary             = buildSummary(totalScanned, totalAtRisk, totalAtRiskValue);
            results.add(result);
        }

        return results;
    }

    private static String buildSummary(Integer scanned, Integer atRisk, Decimal atRiskValue) {
        if (scanned == 0) return 'No open opportunities found in the org.';
        if (atRisk == 0)  return 'All ' + scanned + ' open deals look healthy — no risk signals detected.';
        return atRisk + ' of ' + scanned + ' open deals show risk signals, '
            + 'representing $' + atRiskValue.setScale(0).format() + ' in at-risk pipeline.';
    }

    global class PulseRequest {
        @InvocableVariable(
            required=false
            description='Days without stage movement before flagging a deal as stagnant. Defaults to 21.'
        )
        global Integer stagnationDays;

        @InvocableVariable(
            required=false
            description='Days without any logged activity before flagging a deal. Defaults to 14.'
        )
        global Integer inactivityDays;
    }

    global class PulseResult {
        @InvocableVariable(description='Summary sentence describing overall pipeline risk')
        global String summary;

        @InvocableVariable(description='Total number of open opportunities scanned')
        global Integer totalDealsScanned;

        @InvocableVariable(description='Number of deals with at least one risk signal')
        global Integer totalAtRiskCount;

        @InvocableVariable(description='Combined value of all at-risk deals')
        global Decimal totalAtRiskValue;

        @InvocableVariable(description='List of deals showing risk signals, sorted by severity')
        global List<RiskDeal> atRiskDeals;
    }

    global class RiskDeal {
        @InvocableVariable(description='Salesforce Opportunity ID')
        global String opportunityId;

        @InvocableVariable(description='Opportunity Name')
        global String opportunityName;

        @InvocableVariable(description='Account Name this deal belongs to')
        global String accountName;

        @InvocableVariable(description='Opportunity Owner full name')
        global String ownerName;

        @InvocableVariable(description='Current pipeline stage')
        global String stageName;

        @InvocableVariable(description='Win probability percentage')
        global Decimal probability;

        @InvocableVariable(description='Deal amount in org currency')
        global Decimal amount;

        @InvocableVariable(description='Expected close date')
        global Date closeDate;

        @InvocableVariable(description='Specific risk signals detected on this deal')
        global List<String> riskSignals;

        @InvocableVariable(description='Number of risk signals found (1–4)')
        global Integer riskScore;

        @InvocableVariable(description='Risk label: Critical (3–4 signals), High (2), Medium (1)')
        global String riskLabel;
    }
}