-- Admin-configurable menu word filter. Customer-facing menus hide any item whose
-- name/category/description contains one of these words (owners/admins still see
-- them). Seeded with common alcohol terms + the word "cocktail" so a whole
-- "Signature Cocktails" category is hidden. Comma-separated, case-insensitive.
INSERT INTO app_config (key, value, value_type, category, description)
VALUES ('menu_filter_words',
  'cocktail,vodka,whisky,whiskey,rum,beer,tequila,gin,wine,brandy,liquor,liqueur,bourbon,scotch,vermouth,champagne,prosecco,cider,stout,lager,martini,margarita,mojito,cognac,aperol,campari,sake,absinthe,appleton,absolut,smirnoff,tanqueray,gordons,johnnie walker,johnny walker,jack daniels,jim beam,jameson,wray & nephew,hennessy',
  'string','menu','Comma-separated words; customer menus hide items whose name/category/description contains any of these (case-insensitive).')
ON CONFLICT (key) DO NOTHING;
NOTIFY pgrst, 'reload schema';
