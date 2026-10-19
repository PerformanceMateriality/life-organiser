-- Life Organiser — private storage for "Add to Calendar" (build 23). Idempotent.
--
-- Why: on the iPhone home-screen app, iOS only offers "Add to Calendar" when Safari opens
-- a calendar file from a real web address (tested by Martijn, 2026-10-19). So the app
-- uploads the .ics to this PRIVATE bucket and opens a signed link that expires after
-- two minutes. Each signed-in user has one file, <their user id>/latest.ics, which is
-- overwritten every time — nothing accumulates. Nobody can read it without a signed
-- link, and only the owner can create one.
--
-- Run once in the Supabase SQL editor. Safe to run again.

-- The bucket: private, small files, calendar files only.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('ics', 'ics', false, 65536, array['text/calendar'])
on conflict (id) do update
  set public = false, file_size_limit = 65536, allowed_mime_types = array['text/calendar'];

-- Policies: a signed-in user may only touch files in their own folder (<uid>/...).
drop policy if exists "ics: owner reads"   on storage.objects;
drop policy if exists "ics: owner writes"  on storage.objects;
drop policy if exists "ics: owner updates" on storage.objects;
drop policy if exists "ics: owner deletes" on storage.objects;

create policy "ics: owner reads" on storage.objects
  for select to authenticated
  using (bucket_id = 'ics' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "ics: owner writes" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'ics' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "ics: owner updates" on storage.objects
  for update to authenticated
  using (bucket_id = 'ics' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'ics' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "ics: owner deletes" on storage.objects
  for delete to authenticated
  using (bucket_id = 'ics' and (storage.foldername(name))[1] = auth.uid()::text);
