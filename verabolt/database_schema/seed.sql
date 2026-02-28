-- Seed data: License-Lock SaaS (Verabolt)

-- Insert a test key so activation can be tested immediately after migrations.
-- Change/remove this for production.

INSERT INTO public.license_keys (key_string, duration_days)
VALUES ('TEST-123', 30)
ON CONFLICT (key_string) DO NOTHING;
