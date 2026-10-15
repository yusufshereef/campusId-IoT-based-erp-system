# Isolated Supabase integration test

1. Create a separate Supabase project. Do not point this at the demo/
   production project.
2. Run `../schema.sql`, then
   `../migrations/20261010234000_register_teacher_with_classes.sql`.
3. Confirm the four tables and the RPC exist in the test project's SQL editor.
4. Paste and run `isolated-admin-workflow.sql`. It runs the valid two-class
   registration, duplicate employee test, invalid class test, and verification
   query in one transaction, then rolls back.
5. Confirm the verification query returns one teacher with exactly two rows
   before the script's final `rollback`.

The script requires no secret key and does not modify production. The
publishable key may be used only for browser reads/writes in the disposable
test project; never expose a service-role key to Vite.
