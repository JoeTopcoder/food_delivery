-- ────────────────────────────────────────────────────────────────
-- Banks per country reference table
-- ────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.banks (
  id           uuid    PRIMARY KEY DEFAULT gen_random_uuid(),
  country_code text    NOT NULL,
  country_name text    NOT NULL,
  bank_name    text    NOT NULL,
  swift_code   text,
  branches     text[]  NOT NULL DEFAULT '{}',
  is_active    boolean NOT NULL DEFAULT true,
  sort_order   integer NOT NULL DEFAULT 0,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_banks_country_code ON public.banks(country_code);
CREATE INDEX IF NOT EXISTS idx_banks_is_active    ON public.banks(is_active);

ALTER TABLE public.banks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "banks_public_read" ON public.banks
  FOR SELECT USING (is_active = true);
CREATE POLICY "banks_admin_all"   ON public.banks
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role');

-- ── Save country code on driver / restaurant profiles ─────────
ALTER TABLE public.drivers     ADD COLUMN IF NOT EXISTS bank_country_code text DEFAULT 'KY';
ALTER TABLE public.restaurants ADD COLUMN IF NOT EXISTS bank_country_code text DEFAULT 'KY';

-- ────────────────────────────────────────────────────────────────
-- Seed: Cayman Islands
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.banks (country_code, country_name, bank_name, swift_code, branches, sort_order) VALUES
('KY','Cayman Islands','Cayman National Bank','CAYIKYKX',
 ARRAY['George Town Main','Seven Mile Beach','Camana Bay','West Bay','Bodden Town','East End','North Side','Cayman Brac'], 1),
('KY','Cayman Islands','Butterfield Bank (Cayman)','BNTBKYKY',
 ARRAY['George Town','Camana Bay'], 2),
('KY','Cayman Islands','CIBC FirstCaribbean','FCIBKYKY',
 ARRAY['George Town','Seven Mile Beach','Camana Bay'], 3),
('KY','Cayman Islands','Scotiabank & Trust (Cayman)','NOSCKYKY',
 ARRAY['George Town','Camana Bay','Seven Mile Beach'], 4),
('KY','Cayman Islands','RBC Royal Bank (Cayman)','ROYCKYKY',
 ARRAY['George Town','Camana Bay'], 5),
('KY','Cayman Islands','Fidelity Bank (Cayman)','FDLCKYKY',
 ARRAY['George Town','Camana Bay'], 6)
ON CONFLICT DO NOTHING;

-- ────────────────────────────────────────────────────────────────
-- Seed: Jamaica
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.banks (country_code, country_name, bank_name, swift_code, branches, sort_order) VALUES
('JM','Jamaica','NCB (National Commercial Bank)','JNCBJMKX',
 ARRAY['Half Way Tree','New Kingston','Liguanea','Portmore','Spanish Town','Montego Bay','Ocho Rios','Mandeville'], 1),
('JM','Jamaica','Scotiabank Jamaica','NOSCJMKX',
 ARRAY['Duke Street','New Kingston','Half Way Tree','Portmore','Montego Bay','Ocho Rios'], 2),
('JM','Jamaica','JN Bank','JNBSJMKX',
 ARRAY['Constant Spring','New Kingston','Half Way Tree','Portmore','Montego Bay'], 3),
('JM','Jamaica','JMMB Bank','JMMBKJMX',
 ARRAY['New Kingston','Half Way Tree','Portmore'], 4),
('JM','Jamaica','First Global Bank','FGBLJMKX',
 ARRAY['New Kingston','Manor Park','Liguanea'], 5),
('JM','Jamaica','CIBC FirstCaribbean (Jamaica)','FCIBKJMX',
 ARRAY['New Kingston','Half Way Tree','Montego Bay'], 6),
('JM','Jamaica','Sagicor Bank Jamaica','SAGIJMKX',
 ARRAY['New Kingston','Half Way Tree','Montego Bay'], 7),
('JM','Jamaica','Barita Investments','',
 ARRAY['New Kingston'], 8)
ON CONFLICT DO NOTHING;

-- ────────────────────────────────────────────────────────────────
-- Seed: Trinidad and Tobago
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.banks (country_code, country_name, bank_name, swift_code, branches, sort_order) VALUES
('TT','Trinidad and Tobago','Republic Bank','RBTTTTPS',
 ARRAY['Port of Spain','San Fernando','Chaguanas','Arima','Scarborough Tobago'], 1),
('TT','Trinidad and Tobago','First Citizens Bank','FCTTTTPX',
 ARRAY['Port of Spain','San Fernando','Chaguanas','Marabella'], 2),
('TT','Trinidad and Tobago','Scotiabank Trinidad','NOSCTTTX',
 ARRAY['Port of Spain','San Fernando','Chaguanas'], 3),
('TT','Trinidad and Tobago','RBC Royal Bank (T&T)','ROYCTTTX',
 ARRAY['Port of Spain','San Fernando','Chaguanas'], 4),
('TT','Trinidad and Tobago','CIBC FirstCaribbean (T&T)','FCIBTTPS',
 ARRAY['Port of Spain','San Fernando'], 5),
('TT','Trinidad and Tobago','Sagicor Bank (T&T)','',
 ARRAY['Port of Spain','San Fernando'], 6)
ON CONFLICT DO NOTHING;

-- ────────────────────────────────────────────────────────────────
-- Seed: Barbados
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.banks (country_code, country_name, bank_name, swift_code, branches, sort_order) VALUES
('BB','Barbados','Scotiabank Barbados','NOSCBBBB',
 ARRAY['Bridgetown','Warrens','Speightstown','Oistins'], 1),
('BB','Barbados','Republic Bank (Barbados)','RBNKBBBB',
 ARRAY['Bridgetown','Warrens','Speightstown'], 2),
('BB','Barbados','CIBC FirstCaribbean (Barbados)','FCIBBBBB',
 ARRAY['Bridgetown','Wildey','Warrens'], 3),
('BB','Barbados','Butterfield Bank (Barbados)','BNTBBBBB',
 ARRAY['Bridgetown'], 4),
('BB','Barbados','Caribbean Commerce Bank','',
 ARRAY['Bridgetown'], 5)
ON CONFLICT DO NOTHING;

-- ────────────────────────────────────────────────────────────────
-- Seed: Guyana
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.banks (country_code, country_name, bank_name, swift_code, branches, sort_order) VALUES
('GY','Guyana','Demerara Bank','DMBKGYGX',
 ARRAY['Georgetown','Water Street','Linden','New Amsterdam'], 1),
('GY','Guyana','Guyana Bank for Trade & Industry (GBTI)','GBTIGYGX',
 ARRAY['Georgetown','Bartica','Corriverton'], 2),
('GY','Guyana','Republic Bank (Guyana)','RBNKGYGX',
 ARRAY['Georgetown','Linden','New Amsterdam'], 3),
('GY','Guyana','Citizens Bank Guyana','CBGYGYGX',
 ARRAY['Georgetown'], 4),
('GY','Guyana','Scotiabank Guyana','NOSCGYGX',
 ARRAY['Georgetown'], 5)
ON CONFLICT DO NOTHING;

-- ────────────────────────────────────────────────────────────────
-- Seed: Bahamas
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.banks (country_code, country_name, bank_name, swift_code, branches, sort_order) VALUES
('BS','Bahamas','Commonwealth Bank','CBAHBSNS',
 ARRAY['Nassau Main','Cable Beach','Freeport','Marsh Harbour'], 1),
('BS','Bahamas','RBC Royal Bank (Bahamas)','ROYCBSNS',
 ARRAY['Nassau','Freeport'], 2),
('BS','Bahamas','Scotiabank Bahamas','NOSCBSNS',
 ARRAY['Nassau','Freeport'], 3),
('BS','Bahamas','Citibank (Bahamas)','CITIBSNS',
 ARRAY['Nassau'], 4),
('BS','Bahamas','FirstCaribbean (Bahamas)','FCIBBSNS',
 ARRAY['Nassau','Freeport'], 5)
ON CONFLICT DO NOTHING;

-- ────────────────────────────────────────────────────────────────
-- Seed: Belize
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.banks (country_code, country_name, bank_name, swift_code, branches, sort_order) VALUES
('BZ','Belize','Belize Bank','BELBZE2B',
 ARRAY['Belize City','Belmopan','Orange Walk','Dangriga','San Ignacio'], 1),
('BZ','Belize','Atlantic Bank','ATLBBZE2',
 ARRAY['Belize City','Belmopan','Orange Walk','San Ignacio'], 2),
('BZ','Belize','Heritage Bank','HRTGBZE2',
 ARRAY['Belize City','Belmopan'], 3),
('BZ','Belize','Scotiabank Belize','NOSCBZE2',
 ARRAY['Belize City','Belmopan','Orange Walk'], 4)
ON CONFLICT DO NOTHING;

-- ────────────────────────────────────────────────────────────────
-- Seed: Saint Lucia
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.banks (country_code, country_name, bank_name, swift_code, branches, sort_order) VALUES
('LC','Saint Lucia','Bank of Saint Lucia','BSLCLCLC',
 ARRAY['Castries','Vieux Fort','Rodney Bay'], 1),
('LC','Saint Lucia','CIBC FirstCaribbean (Saint Lucia)','FCIBLCLC',
 ARRAY['Castries','Rodney Bay'], 2),
('LC','Saint Lucia','RBC Royal Bank (Saint Lucia)','ROYCLCLC',
 ARRAY['Castries'], 3),
('LC','Saint Lucia','Republic Bank (Saint Lucia)','RBNKLCLC',
 ARRAY['Castries','Vieux Fort'], 4)
ON CONFLICT DO NOTHING;

-- ────────────────────────────────────────────────────────────────
-- Seed: Antigua and Barbuda
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.banks (country_code, country_name, bank_name, swift_code, branches, sort_order) VALUES
('AG','Antigua & Barbuda','Antigua Commercial Bank','ACBAAGAS',
 ARRAY['St. John''s','Woods Centre'], 1),
('AG','Antigua & Barbuda','CIBC FirstCaribbean (Antigua)','FCIBAGAS',
 ARRAY['St. John''s'], 2),
('AG','Antigua & Barbuda','Scotiabank Antigua','NOSCAGAS',
 ARRAY['St. John''s'], 3),
('AG','Antigua & Barbuda','Bank of Antigua','BANAAGAG',
 ARRAY['St. John''s','Woods'], 4)
ON CONFLICT DO NOTHING;

-- ────────────────────────────────────────────────────────────────
-- Seed: United States
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.banks (country_code, country_name, bank_name, swift_code, branches, sort_order) VALUES
('US','United States','Chase Bank','CHASUS33', ARRAY[]::text[], 1),
('US','United States','Bank of America','BOFAUS3N', ARRAY[]::text[], 2),
('US','United States','Wells Fargo','WFBIUS6S', ARRAY[]::text[], 3),
('US','United States','Citibank','CITIUS33', ARRAY[]::text[], 4),
('US','United States','US Bank','USBKUS44', ARRAY[]::text[], 5),
('US','United States','Capital One','NFBKUS33', ARRAY[]::text[], 6),
('US','United States','TD Bank','NRTHUS33', ARRAY[]::text[], 7),
('US','United States','PNC Bank','PNCCUS33', ARRAY[]::text[], 8),
('US','United States','Truist Bank','BRBTUS33', ARRAY[]::text[], 9),
('US','United States','Goldman Sachs (Marcus)','GOLSUS33', ARRAY[]::text[], 10),
('US','United States','Ally Bank','', ARRAY[]::text[], 11),
('US','United States','SoFi Bank','', ARRAY[]::text[], 12),
('US','United States','Cash App (Sutton Bank)','', ARRAY[]::text[], 13),
('US','United States','Chime (Bancorp)','', ARRAY[]::text[], 14)
ON CONFLICT DO NOTHING;

-- ────────────────────────────────────────────────────────────────
-- Seed: Canada
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.banks (country_code, country_name, bank_name, swift_code, branches, sort_order) VALUES
('CA','Canada','Royal Bank of Canada (RBC)','ROYCCAT2', ARRAY[]::text[], 1),
('CA','Canada','TD Canada Trust','TDOMCATTTOR', ARRAY[]::text[], 2),
('CA','Canada','Scotiabank Canada','NOSCCATT', ARRAY[]::text[], 3),
('CA','Canada','BMO Bank of Montreal','BOFMCAM2', ARRAY[]::text[], 4),
('CA','Canada','CIBC','CIBCCATT', ARRAY[]::text[], 5),
('CA','Canada','National Bank of Canada','BNDCCAMMINT', ARRAY[]::text[], 6),
('CA','Canada','Desjardins','CCDQCAMM', ARRAY[]::text[], 7),
('CA','Canada','EQ Bank','', ARRAY[]::text[], 8),
('CA','Canada','Tangerine (Scotiabank)','', ARRAY[]::text[], 9)
ON CONFLICT DO NOTHING;

-- ────────────────────────────────────────────────────────────────
-- Seed: United Kingdom
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.banks (country_code, country_name, bank_name, swift_code, branches, sort_order) VALUES
('GB','United Kingdom','Barclays','BARCGB22', ARRAY[]::text[], 1),
('GB','United Kingdom','HSBC UK','HBUKGB4B', ARRAY[]::text[], 2),
('GB','United Kingdom','Lloyds Bank','LOYDGB2L', ARRAY[]::text[], 3),
('GB','United Kingdom','NatWest','NWBKGB2L', ARRAY[]::text[], 4),
('GB','United Kingdom','Santander UK','ABBYGB2L', ARRAY[]::text[], 5),
('GB','United Kingdom','Standard Chartered','SCBLGB2L', ARRAY[]::text[], 6),
('GB','United Kingdom','Halifax','HLFXGB21', ARRAY[]::text[], 7),
('GB','United Kingdom','TSB Bank','TSBSGB2A', ARRAY[]::text[], 8),
('GB','United Kingdom','Monzo','MONZGB2L', ARRAY[]::text[], 9),
('GB','United Kingdom','Revolut','REVOGB21', ARRAY[]::text[], 10),
('GB','United Kingdom','Starling Bank','SRLGGB3L', ARRAY[]::text[], 11)
ON CONFLICT DO NOTHING;

-- ────────────────────────────────────────────────────────────────
-- Seed: Nigeria
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.banks (country_code, country_name, bank_name, swift_code, branches, sort_order) VALUES
('NG','Nigeria','Access Bank','ABNGNGLA', ARRAY[]::text[], 1),
('NG','Nigeria','First Bank of Nigeria','FBNINGLA', ARRAY[]::text[], 2),
('NG','Nigeria','Guaranty Trust Bank (GTB)','GTBINGLA', ARRAY[]::text[], 3),
('NG','Nigeria','Zenith Bank','ZEIBNGLA', ARRAY[]::text[], 4),
('NG','Nigeria','United Bank for Africa (UBA)','UNAFNGLA', ARRAY[]::text[], 5),
('NG','Nigeria','Sterling Bank','NAMENGLA', ARRAY[]::text[], 6),
('NG','Nigeria','Fidelity Bank Nigeria','FIDTNGLA', ARRAY[]::text[], 7),
('NG','Nigeria','Stanbic IBTC Bank','SBICNGLA', ARRAY[]::text[], 8),
('NG','Nigeria','Ecobank Nigeria','ECOCNGLA', ARRAY[]::text[], 9),
('NG','Nigeria','Wema Bank','WEMANGLA', ARRAY[]::text[], 10),
('NG','Nigeria','Opay (OPay Digital Services)','', ARRAY[]::text[], 11),
('NG','Nigeria','Kuda Bank','', ARRAY[]::text[], 12),
('NG','Nigeria','Palmpay','', ARRAY[]::text[], 13)
ON CONFLICT DO NOTHING;

-- ────────────────────────────────────────────────────────────────
-- Seed: Ghana
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.banks (country_code, country_name, bank_name, swift_code, branches, sort_order) VALUES
('GH','Ghana','GCB Bank','GHCBGHAC', ARRAY[]::text[], 1),
('GH','Ghana','Ecobank Ghana','ECOCGHAC', ARRAY[]::text[], 2),
('GH','Ghana','Standard Chartered Ghana','SCBLGHAC', ARRAY[]::text[], 3),
('GH','Ghana','Stanbic Bank Ghana','SBICGHAC', ARRAY[]::text[], 4),
('GH','Ghana','Agricultural Development Bank','AGBKGHAC', ARRAY[]::text[], 5),
('GH','Ghana','Access Bank Ghana','ABNGGHAC', ARRAY[]::text[], 6),
('GH','Ghana','Absa Bank Ghana','ABSAGHAC', ARRAY[]::text[], 7),
('GH','Ghana','Fidelity Bank Ghana','FIDTGHAC', ARRAY[]::text[], 8),
('GH','Ghana','MTN Mobile Money (MoMo)','', ARRAY[]::text[], 9),
('GH','Ghana','Vodafone Cash','', ARRAY[]::text[], 10)
ON CONFLICT DO NOTHING;

-- ────────────────────────────────────────────────────────────────
-- Seed: Kenya
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.banks (country_code, country_name, bank_name, swift_code, branches, sort_order) VALUES
('KE','Kenya','Equity Bank','EQBLKENA', ARRAY[]::text[], 1),
('KE','Kenya','KCB Bank (Kenya Commercial Bank)','KCBLKENA', ARRAY[]::text[], 2),
('KE','Kenya','Cooperative Bank','COKEKENA', ARRAY[]::text[], 3),
('KE','Kenya','Absa Bank Kenya','BARCKENX', ARRAY[]::text[], 4),
('KE','Kenya','Standard Chartered Kenya','SCBLKENA', ARRAY[]::text[], 5),
('KE','Kenya','NCBA Bank','CBAFKENA', ARRAY[]::text[], 6),
('KE','Kenya','Family Bank','KFAMKENA', ARRAY[]::text[], 7),
('KE','Kenya','M-Pesa (Safaricom)','', ARRAY[]::text[], 8)
ON CONFLICT DO NOTHING;

-- ────────────────────────────────────────────────────────────────
-- Seed: South Africa
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.banks (country_code, country_name, bank_name, swift_code, branches, sort_order) VALUES
('ZA','South Africa','Absa Bank','ABSAZAJJ', ARRAY[]::text[], 1),
('ZA','South Africa','Standard Bank','SBZAZAJJ', ARRAY[]::text[], 2),
('ZA','South Africa','First National Bank (FNB)','FIRNZAJJ', ARRAY[]::text[], 3),
('ZA','South Africa','Nedbank','NEDSZAJJ', ARRAY[]::text[], 4),
('ZA','South Africa','Capitec Bank','CABLZAJJ', ARRAY[]::text[], 5),
('ZA','South Africa','Investec Bank','INVZZAJJ', ARRAY[]::text[], 6),
('ZA','South Africa','Discovery Bank','', ARRAY[]::text[], 7),
('ZA','South Africa','TymeBank','', ARRAY[]::text[], 8)
ON CONFLICT DO NOTHING;

-- ────────────────────────────────────────────────────────────────
-- Seed: India
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.banks (country_code, country_name, bank_name, swift_code, branches, sort_order) VALUES
('IN','India','State Bank of India (SBI)','SBININBB', ARRAY[]::text[], 1),
('IN','India','HDFC Bank','HDFCINBB', ARRAY[]::text[], 2),
('IN','India','ICICI Bank','ICICININ', ARRAY[]::text[], 3),
('IN','India','Axis Bank','AXISINBB', ARRAY[]::text[], 4),
('IN','India','Punjab National Bank','PUNBINBB', ARRAY[]::text[], 5),
('IN','India','Bank of Baroda','BAROINBB', ARRAY[]::text[], 6),
('IN','India','Kotak Mahindra Bank','KKBKINBB', ARRAY[]::text[], 7),
('IN','India','Paytm Payments Bank','', ARRAY[]::text[], 8)
ON CONFLICT DO NOTHING;

-- ────────────────────────────────────────────────────────────────
-- Seed: Australia
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.banks (country_code, country_name, bank_name, swift_code, branches, sort_order) VALUES
('AU','Australia','Commonwealth Bank (CBA)','CTBAAU2S', ARRAY[]::text[], 1),
('AU','Australia','Westpac','WPACAU2S', ARRAY[]::text[], 2),
('AU','Australia','ANZ Bank','ANZBAU3M', ARRAY[]::text[], 3),
('AU','Australia','National Australia Bank (NAB)','NATAAU33', ARRAY[]::text[], 4),
('AU','Australia','Macquarie Bank','MACQAU2S', ARRAY[]::text[], 5),
('AU','Australia','Bank of Queensland','QLDAAU2S', ARRAY[]::text[], 6),
('AU','Australia','ING Australia','INGBAU2S', ARRAY[]::text[], 7),
('AU','Australia','Up Bank','', ARRAY[]::text[], 8)
ON CONFLICT DO NOTHING;

-- ────────────────────────────────────────────────────────────────
-- Seed: Singapore
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.banks (country_code, country_name, bank_name, swift_code, branches, sort_order) VALUES
('SG','Singapore','DBS Bank','DBSSSGSG', ARRAY[]::text[], 1),
('SG','Singapore','OCBC Bank','OCBCSGSG', ARRAY[]::text[], 2),
('SG','Singapore','United Overseas Bank (UOB)','UOVBSGSG', ARRAY[]::text[], 3),
('SG','Singapore','Standard Chartered Singapore','SCBLSGSG', ARRAY[]::text[], 4),
('SG','Singapore','Citibank Singapore','CITISGSG', ARRAY[]::text[], 5),
('SG','Singapore','HSBC Singapore','HSBCSGSG', ARRAY[]::text[], 6)
ON CONFLICT DO NOTHING;

-- ────────────────────────────────────────────────────────────────
-- Seed: Philippines
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.banks (country_code, country_name, bank_name, swift_code, branches, sort_order) VALUES
('PH','Philippines','BDO Unibank','BNORPHMM', ARRAY[]::text[], 1),
('PH','Philippines','BPI (Bank of the Philippine Islands)','BOPIPHMM', ARRAY[]::text[], 2),
('PH','Philippines','Metrobank','MBTCPHMM', ARRAY[]::text[], 3),
('PH','Philippines','Landbank of the Philippines','TLBPPHMM', ARRAY[]::text[], 4),
('PH','Philippines','Security Bank','SETCPHMM', ARRAY[]::text[], 5),
('PH','Philippines','GCash (Globe Telecom)','', ARRAY[]::text[], 6),
('PH','Philippines','Maya (PayMaya)','', ARRAY[]::text[], 7)
ON CONFLICT DO NOTHING;
