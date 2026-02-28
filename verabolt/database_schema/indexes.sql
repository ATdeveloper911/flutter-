-- Indexes: License-Lock SaaS (Verabolt)

-- Speed up profile lookup
CREATE INDEX IF NOT EXISTS idx_profiles_id ON public.profiles(id);

-- Speed up activation lookup by key
CREATE INDEX IF NOT EXISTS idx_license_keys_string ON public.license_keys(key_string);

-- Speed up per-user license lookup
CREATE INDEX IF NOT EXISTS idx_license_keys_user_id ON public.license_keys(user_id);
