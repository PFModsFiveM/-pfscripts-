-- Enable sales tax and verify all tax settings
UPDATE pf_gov_taxes SET enabled = 1 WHERE tax_type = 'sales';

-- Check all taxes
SELECT tax_type, rate, enabled, min_rate, max_rate, description 
FROM pf_gov_taxes 
ORDER BY tax_type;
