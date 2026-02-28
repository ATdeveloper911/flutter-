-- RLS Policies: License-Lock SaaS (Verabolt)

-- PROFILES
-- Users can view their own profile
CREATE POLICY "Users can view their own profile"
ON public.profiles
FOR SELECT
USING (auth.uid() = id);

-- Users can update their own profile
CREATE POLICY "Users can update their own profile"
ON public.profiles
FOR UPDATE
USING (auth.uid() = id);

-- LICENSE KEYS
-- Users can view their own license keys (the one bound to them)
CREATE POLICY "Users can view their own license"
ON public.license_keys
FOR SELECT
USING (auth.uid() = user_id);

-- Important: No INSERT/UPDATE/DELETE policies for end users on license_keys.
-- Activation and status changes are handled through a Supabase Edge Function
-- using the service_role key.
