-- Migration: driver tip presets in JMD.
--
-- preset_tips still held [2,3,5,10] — US dollar amounts from before the
-- platform was redenominated. The chips render with the JMD symbol, so a
-- customer tipping on a J$1,000 order was offered "J$2", which reads as the
-- customer having made a mistake rather than us.
--
-- The compiled default in AppConstants was updated alongside this, but this
-- row is what the app actually uses: app_config wins at startup.

UPDATE public.app_config
   SET value = '[200,300,500,1000]',
       value_type = 'json'
 WHERE key = 'preset_tips';

INSERT INTO public.app_config (key, value, value_type, description)
SELECT 'preset_tips', '[200,300,500,1000]', 'json',
       'Driver tip chip amounts, in JMD'
WHERE NOT EXISTS (SELECT 1 FROM public.app_config WHERE key = 'preset_tips');

NOTIFY pgrst, 'reload schema';
