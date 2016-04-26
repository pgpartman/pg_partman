--
-- Testet, ob alle Funktionen mit SECURITY DEFINER auch den Suchpfad
-- mit pg_temp am Ende gesetzt haben 
--
-- Aus Sicherheitsgründen MUSS pg_temp bei diesen Funktionen gesetzt werden.
-- Siehe
-- http://www.postgresql.org/docs/current/static/sql-createfunction.html#SQL-CREATEFUNCTION-SECURITY
--


BEGIN;

-- 
-- main function, because conditional plan
--

CREATE FUNCTION run_secdef_check() 
   RETURNS SETOF text 
   LANGUAGE plpgsql
   AS
   $code$
   DECLARE cnt INTEGER;
   DECLARE r   RECORD;
   BEGIN
   
      CREATE TEMPORARY TABLE secfunc AS 
        (
          SELECT nspname || '.' || proname AS name, 
                 proconfig,
                 prosecdef
            FROM pg_proc p
       LEFT JOIN pg_namespace n ON pronamespace = n.oid
           WHERE prosecdef
             AND nspname NOT LIKE 'pg_%'
        ORDER BY name
         );
         
      SELECT INTO cnt count(*)::INTEGER FROM secfunc;
      IF cnt = 0 THEN
         RETURN NEXT plan(1);
         RETURN NEXT skip('No security definer function.');
      ELSE
         RETURN NEXT plan(cnt);
         FOR r IN 

            -- TODO:
            -- this is hacky and may fail because only simple regex check 
            -- when there are other parameters set.
            -- Change this to strip down all array elements of proconfig etc!
            -- 

            SELECT matches(
               proconfig::text,
               E'search_path=[^=]+pg_temp"?}',
               'Function ' || name || ' using SECURITY DEFINER needs pg_temp at last position in search_path'
               ) 
               FROM secfunc
         LOOP
            RETURN NEXT r;
         END LOOP;

      END IF;
      
      RETURN;
      
   END
      
   $code$;


SELECT * FROM run_secdef_check();



-- Finish the tests and clean up.
SELECT * FROM finish();
ROLLBACK;

