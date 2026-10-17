-- PostgreSQL otherwise treats person_id in qualified predicates as ambiguous
-- between the local variable and table columns. Prefer the command's bound ID.
do $$
declare
  definition text;
begin
  select pg_get_functiondef(
    'public.complete_device_command(uuid,uuid,boolean,integer,text)'::regprocedure
  ) into definition;
  definition := replace(definition, 'AS $function$',
                        'AS $function$' || E'\n#variable_conflict use_variable\n');
  execute definition;
end;
$$;
