-- ============================================================
-- BACKUP COMPLETO DO BANCO DE DADOS - Recomp/HailGames
-- Gerado em: 2026-08-22T20:19:02.516897 UTC
-- Projeto Supabase: hailgames (tsriuhkellkwwaqficid)
-- Conteúdo: schema public completo + storage + políticas.
-- PRIVACIDADE: e-mails anonimizados; dados da schema auth
-- (usuários/senhas/sessões) NÃO incluídos.
-- ============================================================

begin;

-- Extensões
create extension if not exists pg_stat_statements;
create extension if not exists pgcrypto;
create extension if not exists plpgsql;
create extension if not exists supabase_vault;
create extension if not exists uuid-ossp;

-- Tabelas: app_releases, categories, content_items, game_screenshots, games, profiles

create table if not exists public.app_releases (
  id uuid primary key default gen_random_uuid(),
  version_code integer not null check (version_code > 0),
  version_name text not null check (btrim(version_name) <> ''),
  download_url text not null check (download_url ~* '^https?://'),
  notes text,
  published_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  icon text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.content_items (
  id uuid primary key default gen_random_uuid(),
  title text,
  description text,
  cover_url text,
  category_id uuid references public.categories(id),
  link_url text,
  file_url text,
  download_url text,
  author text,
  version text,
  size_mb numeric,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.game_screenshots (
  id uuid primary key default gen_random_uuid(),
  game_id uuid references public.games(id),
  image_url text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.games (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  title text not null,
  description text not null default '',
  original_platform text,
  status text not null default 'in_development',
  version text,
  author text,
  source_repo_url text,
  apk_url text,
  file_size_bytes bigint not null default 0,
  sha256 text,
  tags text[] not null default '{}',
  cover_url text,
  banner_url text,
  submitted_by uuid,
  review_status text not null default 'pending',
  review_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.profiles (
  id uuid primary key,
  username text not null default 'player',
  avatar_url text,
  role text not null default 'user',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  email text,
  is_admin boolean not null default false
);


-- Índices
create index if not exists content_items_category_idx on public.content_items(category_id);
create index if not exists content_items_created_at_idx on public.content_items(created_at desc);
create index if not exists idx_screenshots_game_id on public.game_screenshots(game_id);
create index if not exists idx_games_review_status on public.games(review_status);
create index if not exists idx_games_slug on public.games(slug);

-- Funções
CREATE OR REPLACE FUNCTION public.current_user_role()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select role from public.profiles where id = auth.uid();
$function$
;
CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ DECLARE is_first boolean; BEGIN SELECT NOT EXISTS (SELECT 1 FROM public.profiles) INTO is_first; INSERT INTO public.profiles (id, username, email, role) VALUES (new.id, coalesce(new.raw_user_meta_data->>'username', split_part(coalesce(new.email,'player'),'@',1)), new.email, CASE WHEN is_first THEN 'owner' ELSE 'user' END) ON CONFLICT (id) DO NOTHING; RETURN new; END; $function$
;
CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  select exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin)
$function$
;
CREATE OR REPLACE FUNCTION public.is_owner()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(public.current_user_role() = 'owner', false);
$function$
;
CREATE OR REPLACE FUNCTION public.is_principal_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(public.is_owner(), false)
     and coalesce(auth.jwt() ->> 'email', '') = 'PRINCIPAL_ADMIN_EMAIL';
$function$
;
CREATE OR REPLACE FUNCTION public.promote_to_admin(target_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  caller_email     text;
  target_email_norm text;
  target_id        uuid;
  target_role      text;
  target_is_admin  boolean;
begin
  caller_email := nullif(trim(coalesce(auth.jwt() ->> 'email', '')), '');
  if caller_email is distinct from 'PRINCIPAL_ADMIN_EMAIL'
     or not public.is_owner() then
    return jsonb_build_object(
      'ok', false,
      'code', 'forbidden',
      'message', 'Somente o ADM principal pode promover usuários a ADM.');
  end if;

  if target_email is null or target_email !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then
    return jsonb_build_object(
      'ok', false,
      'code', 'invalid_email',
      'message', 'Informe um e-mail válido.');
  end if;

  target_email_norm := lower(btrim(target_email));
  select id, role, is_admin into target_id, target_role, target_is_admin
    from public.profiles
   where lower(email) = target_email_norm
   limit 1;

  if target_id is null then
    return jsonb_build_object(
      'ok', false,
      'code', 'user_not_found',
      'message', 'Nenhum usuário cadastrado com o e-mail informado.');
  end if;

  if target_email_norm = 'PRINCIPAL_ADMIN_EMAIL' then
    return jsonb_build_object(
      'ok', false,
      'code', 'principal',
      'message', 'O ADM principal não precisa ser promovido.');
  end if;

  if target_is_admin then
    return jsonb_build_object(
      'ok', false,
      'code', 'already_admin',
      'message', 'Este usuário já é ADM.');
  end if;

  update public.profiles
     set is_admin = true,
         role = 'admin'
   where id = target_id;

  return jsonb_build_object(
    'ok', true,
    'code', 'promoted',
    'message', 'Usuário promovido a ADM com sucesso.',
    'target_email', target_email_norm);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at = now();
  return new;
end; $function$
;
CREATE OR REPLACE FUNCTION public.sync_profile_username()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ BEGIN UPDATE public.profiles SET username = coalesce(new.raw_user_meta_data->>'username', split_part(coalesce(new.email,'player'),'@',1)), email = new.email, updated_at = now() WHERE id = new.id; RETURN new; END; $function$
;

-- Triggers (public)
drop trigger if exists trg_games_updated_at on public.games;
create trigger trg_games_updated_at BEFORE UPDATE on public.games for each row EXECUTE FUNCTION set_updated_at();

-- ============ DADOS ============
-- profiles (e-mails anonimizados)
insert into public.profiles (id,username,avatar_url,role,created_at,updated_at,email,is_admin) values ('bafed60a-9657-474e-8ebd-a71ab02e8463','hail',NULL,'owner','2026-08-08 22:32:14.370659+00','2026-08-08 22:32:14.370659+00','user@redacted.invalid',false);
insert into public.profiles (id,username,avatar_url,role,created_at,updated_at,email,is_admin) values ('18589e2f-701b-4307-9d00-2915469c769d','hailgamestestes',NULL,'owner','2026-08-20 12:51:43.15023+00','2026-08-20 12:51:43.15023+00','user@redacted.invalid',true);
insert into public.profiles (id,username,avatar_url,role,created_at,updated_at,email,is_admin) values ('e8a3bf19-19d8-4859-b2a8-4d7d8151b43e','manuskk16kk',NULL,'admin','2026-08-20 18:54:01.08781+00','2026-08-20 18:54:01.08781+00','user@redacted.invalid',true);

-- categories
insert into public.categories (id,name,icon,sort_order,created_at) values ('22a88dff-034f-40ae-be28-3315b94ed44f','Jogos','gamepad',1,'2026-08-08 20:45:39.309073+00');
insert into public.categories (id,name,icon,sort_order,created_at) values ('990f47ce-2dfe-4daa-9b27-0f277b2fadfa','Apps','apps',2,'2026-08-08 20:45:39.309073+00');
insert into public.categories (id,name,icon,sort_order,created_at) values ('0ddd95d2-b1ef-45b9-8aff-b30ea60b0a31','Mods','extension',3,'2026-08-08 20:45:39.309073+00');
insert into public.categories (id,name,icon,sort_order,created_at) values ('03586c81-c4eb-4079-ac23-62df30048107','Emuladores','devices',4,'2026-08-08 20:45:39.309073+00');
insert into public.categories (id,name,icon,sort_order,created_at) values ('d4caffcb-6e48-4538-a1e7-0bc79dda381f','Outros','category',5,'2026-08-08 20:45:39.309073+00');

-- games
insert into public.games (id,slug,title,description,original_platform,status,version,author,source_repo_url,apk_url,file_size_bytes,sha256,tags,cover_url,banner_url,submitted_by,review_status,review_reason,created_at,updated_at) values ('794cef97-ed29-47a4-93a6-fea81498f691','unleashed-recomp-android','Unleashed Recomp Android','Unofficial Android port of Unleashed Recompiled, built with Anthropic''s Fable 5 AI under human direction, device testing and debugging. Artifacts, freezes and audio issues possible. Play the Xbox 360 version of Sonic Unleashed natively on a supported Android device through static recompilation rather than emulation. Includes touch controls, gamepad support, mod manager, and custom Vulkan driver for Qualcomm Adreno GPUs.','Xbox 360','released','Unleashed Recomp Android 0.5.3','SansNope','https://github.com/SansNope/UnleashedRecomp-Android','https://github.com/SansNope/UnleashedRecomp-Android/releases/download/v0.5.3/UnleashedRecomp-0.5.3.apk',67035734,NULL,'{"android","sonic","unleashed","recompilation","port","xbox-360","vulkan","adreno","mali","touch-controls","mod-support","static-recompilation"}','https://drive.google.com/uc?export=view&id=1uu_b2lve3DLPW0160J-OVURzzLghOVAu','https://raw.githubusercontent.com/deivid22srk/recomp-games-data/refs/heads/main/games/unleashed-recomp/banner.jpg','18589e2f-701b-4307-9d00-2915469c769d','approved',NULL,'2026-08-20 14:41:29.541866+00','2026-08-20 15:42:49.833863+00');
insert into public.games (id,slug,title,description,original_platform,status,version,author,source_repo_url,apk_url,file_size_bytes,sha256,tags,cover_url,banner_url,submitted_by,review_status,review_reason,created_at,updated_at) values ('d1652f5c-4ccd-43c4-bf62-1887437149f6','skate-3-mobile','Skate 3 Mobile','Play Skate 3 natively on Android. Download one APK, select your own ISO, and skate. ARM64 recompilation with Vulkan rendering.','Xbox 360','released','Skate 3 Mobile v2.0.17','Buku313 / Antonio Seevers','https://github.com/Buku313/Skate3-Mobile','https://github.com/Buku313/Skate3-Mobile/releases/download/v2.0.17/Skate3-Mobile-Android.apk',36004809,NULL,'{"skate-3","android","arm64","recompilation","vulkan","xbox-360","native","mobile","skateboarding"}','https://drive.google.com/uc?export=view&id=1ZlEVsy5eZpfvKlwQvswVt0EsQ02Bhj1I','https://raw.githubusercontent.com/Buku313/Skate3-Mobile/main/docs/skate3-android-social-preview.jpg','18589e2f-701b-4307-9d00-2915469c769d','approved',NULL,'2026-08-20 16:23:27.055734+00','2026-08-20 16:40:46.85837+00');
insert into public.games (id,slug,title,description,original_platform,status,version,author,source_repo_url,apk_url,file_size_bytes,sha256,tags,cover_url,banner_url,submitted_by,review_status,review_reason,created_at,updated_at) values ('64268ad7-02f5-4552-b0cb-994240b31156','gen2recomp','Gen2Recomp','A native LÖVE2D recreation of Pokemon Gold, Silver and Crystal, built on Gen1Recomp''s Red/Blue/Yellow engine. The engine, script VM, and map behavior are hand-written Lua; game data and graphics are decoded from a ROM supplied by the player. Also supports Pokemon Red, Blue and Yellow. Features include the complete Johto and Kanto world, day/night system, breeding and Day-Care, Pokegear, shinies, held items, mod support, and optional 3D-style world via Dramatic Shapes mod.','Game Boy Color (Pokemon Gold, Silver, Crystal) / Game Boy (Pokemon Red, Blue, Yellow)','released','0.7.20','UNDERdecodedHD','https://github.com/UNDERdecoded/Gen2Recomped','https://github.com/UNDERdecoded/Gen2Recomped/releases/download/v0.7.20/Gen2Recomped-0.7.20-android.apk',24701241,NULL,'{"pokemon","gen2","gold","silver","crystal","recomp","love2d","android","modding"}','https://drive.google.com/uc?export=view&id=1TSMennklcqz6CGDV0sXjmAySpDPDit31',NULL,'18589e2f-701b-4307-9d00-2915469c769d','approved',NULL,'2026-08-20 17:10:03.354998+00','2026-08-20 19:02:53.197757+00');

-- game_screenshots
insert into public.game_screenshots (id,game_id,image_url,sort_order,created_at) values ('465ab21c-ef5a-4172-991e-07b3876dd2c3','794cef97-ed29-47a4-93a6-fea81498f691','https://drive.google.com/uc?export=view&id=13EwcvVflvnopV4eiwF4NsB0T9MznLXuG',0,'2026-08-20 15:42:50.514284+00');
insert into public.game_screenshots (id,game_id,image_url,sort_order,created_at) values ('87dc97ad-4b18-4959-a449-656dbcccc355','794cef97-ed29-47a4-93a6-fea81498f691','https://drive.google.com/uc?export=view&id=1pP2grO7M4UT2vq8nL_ejZkLCdd0sz4H8',1,'2026-08-20 15:42:50.514284+00');

-- content_items
-- content_items: sem registros
-- app_releases
-- app_releases: sem registros

-- Row Level Security + Políticas
alter table public.games enable row level security;
alter table public.game_screenshots enable row level security;
alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.content_items enable row level security;
alter table public.app_releases enable row level security;

drop policy if exists "app_releases_delete_principal" on public.app_releases;
create policy "app_releases_delete_principal" on public.app_releases for DELETE using (is_principal_admin());
drop policy if exists "app_releases_insert_principal" on public.app_releases;
create policy "app_releases_insert_principal" on public.app_releases for INSERT with check (is_principal_admin());
drop policy if exists "app_releases_select_all" on public.app_releases;
create policy "app_releases_select_all" on public.app_releases for SELECT using (true);
drop policy if exists "categories_delete" on public.categories;
create policy "categories_delete" on public.categories for DELETE using (is_admin());
drop policy if exists "categories_insert" on public.categories;
create policy "categories_insert" on public.categories for INSERT with check (is_admin());
drop policy if exists "categories_select" on public.categories;
create policy "categories_select" on public.categories for SELECT using (true);
drop policy if exists "categories_update" on public.categories;
create policy "categories_update" on public.categories for UPDATE using (is_admin()) with check (is_admin());
drop policy if exists "content_delete" on public.content_items;
create policy "content_delete" on public.content_items for DELETE using (is_admin());
drop policy if exists "content_insert" on public.content_items;
create policy "content_insert" on public.content_items for INSERT with check (is_admin());
drop policy if exists "content_select" on public.content_items;
create policy "content_select" on public.content_items for SELECT using (true);
drop policy if exists "content_update" on public.content_items;
create policy "content_update" on public.content_items for UPDATE using (is_admin()) with check (is_admin());
drop policy if exists "screenshots_delete_owner_admin" on public.game_screenshots;
create policy "screenshots_delete_owner_admin" on public.game_screenshots for DELETE using ((EXISTS ( SELECT 1
   FROM games g
  WHERE ((g.id = game_screenshots.game_id) AND ((g.submitted_by = auth.uid()) OR is_admin())))));
drop policy if exists "screenshots_insert_owner_admin" on public.game_screenshots;
create policy "screenshots_insert_owner_admin" on public.game_screenshots for INSERT with check ((EXISTS ( SELECT 1
   FROM games g
  WHERE ((g.id = game_screenshots.game_id) AND ((g.submitted_by = auth.uid()) OR is_admin())))));
drop policy if exists "screenshots_select_public" on public.game_screenshots;
create policy "screenshots_select_public" on public.game_screenshots for SELECT using ((EXISTS ( SELECT 1
   FROM games g
  WHERE ((g.id = game_screenshots.game_id) AND ((g.review_status = 'approved'::text) OR (auth.uid() = g.submitted_by) OR is_admin())))));
drop policy if exists "screenshots_update_owner_admin" on public.game_screenshots;
create policy "screenshots_update_owner_admin" on public.game_screenshots for UPDATE using ((EXISTS ( SELECT 1
   FROM games g
  WHERE ((g.id = game_screenshots.game_id) AND ((g.submitted_by = auth.uid()) OR is_admin()))))) with check ((EXISTS ( SELECT 1
   FROM games g
  WHERE ((g.id = game_screenshots.game_id) AND ((g.submitted_by = auth.uid()) OR is_admin())))));
drop policy if exists "games_delete_own_or_admin" on public.games;
create policy "games_delete_own_or_admin" on public.games for DELETE using (((submitted_by = auth.uid()) OR is_admin()));
drop policy if exists "games_insert_auth" on public.games;
create policy "games_insert_auth" on public.games for INSERT with check ((submitted_by = auth.uid()));
drop policy if exists "games_select_public" on public.games;
create policy "games_select_public" on public.games for SELECT using (((review_status = 'approved'::text) OR (auth.uid() = submitted_by) OR is_admin()));
drop policy if exists "games_update_own_or_admin" on public.games;
create policy "games_update_own_or_admin" on public.games for UPDATE using (((submitted_by = auth.uid()) OR is_admin())) with check (((submitted_by = auth.uid()) OR is_admin()));
drop policy if exists "profiles_insert" on public.profiles;
create policy "profiles_insert" on public.profiles for INSERT with check (((auth.uid() = id) AND (role = 'user'::text) AND (is_admin = false)));
drop policy if exists "profiles_select" on public.profiles;
create policy "profiles_select" on public.profiles for SELECT using ((auth.role() = 'authenticated'::text));
drop policy if exists "profiles_update" on public.profiles;
create policy "profiles_update" on public.profiles for UPDATE using ((is_owner() OR (auth.uid() = id))) with check (((is_owner() AND (COALESCE((auth.jwt() ->> 'email'::text), ''::text) = 'PRINCIPAL_ADMIN_EMAIL'::text)) OR ((auth.uid() = id) AND (role = 'user'::text) AND (is_admin = false))));

-- Grants
grant DELETE on public.app_releases to anon;
grant INSERT on public.app_releases to anon;
grant REFERENCES on public.app_releases to anon;
grant SELECT on public.app_releases to anon;
grant TRIGGER on public.app_releases to anon;
grant TRUNCATE on public.app_releases to anon;
grant UPDATE on public.app_releases to anon;
grant DELETE on public.app_releases to authenticated;
grant INSERT on public.app_releases to authenticated;
grant REFERENCES on public.app_releases to authenticated;
grant SELECT on public.app_releases to authenticated;
grant TRIGGER on public.app_releases to authenticated;
grant TRUNCATE on public.app_releases to authenticated;
grant UPDATE on public.app_releases to authenticated;
grant DELETE on public.app_releases to service_role;
grant INSERT on public.app_releases to service_role;
grant REFERENCES on public.app_releases to service_role;
grant SELECT on public.app_releases to service_role;
grant TRIGGER on public.app_releases to service_role;
grant TRUNCATE on public.app_releases to service_role;
grant UPDATE on public.app_releases to service_role;
grant DELETE on public.categories to anon;
grant INSERT on public.categories to anon;
grant REFERENCES on public.categories to anon;
grant SELECT on public.categories to anon;
grant TRIGGER on public.categories to anon;
grant TRUNCATE on public.categories to anon;
grant UPDATE on public.categories to anon;
grant DELETE on public.categories to authenticated;
grant INSERT on public.categories to authenticated;
grant REFERENCES on public.categories to authenticated;
grant SELECT on public.categories to authenticated;
grant TRIGGER on public.categories to authenticated;
grant TRUNCATE on public.categories to authenticated;
grant UPDATE on public.categories to authenticated;
grant DELETE on public.categories to service_role;
grant INSERT on public.categories to service_role;
grant REFERENCES on public.categories to service_role;
grant SELECT on public.categories to service_role;
grant TRIGGER on public.categories to service_role;
grant TRUNCATE on public.categories to service_role;
grant UPDATE on public.categories to service_role;
grant DELETE on public.content_items to anon;
grant INSERT on public.content_items to anon;
grant REFERENCES on public.content_items to anon;
grant SELECT on public.content_items to anon;
grant TRIGGER on public.content_items to anon;
grant TRUNCATE on public.content_items to anon;
grant UPDATE on public.content_items to anon;
grant DELETE on public.content_items to authenticated;
grant INSERT on public.content_items to authenticated;
grant REFERENCES on public.content_items to authenticated;
grant SELECT on public.content_items to authenticated;
grant TRIGGER on public.content_items to authenticated;
grant TRUNCATE on public.content_items to authenticated;
grant UPDATE on public.content_items to authenticated;
grant DELETE on public.content_items to service_role;
grant INSERT on public.content_items to service_role;
grant REFERENCES on public.content_items to service_role;
grant SELECT on public.content_items to service_role;
grant TRIGGER on public.content_items to service_role;
grant TRUNCATE on public.content_items to service_role;
grant UPDATE on public.content_items to service_role;
grant DELETE on public.game_screenshots to anon;
grant INSERT on public.game_screenshots to anon;
grant REFERENCES on public.game_screenshots to anon;
grant SELECT on public.game_screenshots to anon;
grant TRIGGER on public.game_screenshots to anon;
grant TRUNCATE on public.game_screenshots to anon;
grant UPDATE on public.game_screenshots to anon;
grant DELETE on public.game_screenshots to authenticated;
grant INSERT on public.game_screenshots to authenticated;
grant REFERENCES on public.game_screenshots to authenticated;
grant SELECT on public.game_screenshots to authenticated;
grant TRIGGER on public.game_screenshots to authenticated;
grant TRUNCATE on public.game_screenshots to authenticated;
grant UPDATE on public.game_screenshots to authenticated;
grant DELETE on public.game_screenshots to service_role;
grant INSERT on public.game_screenshots to service_role;
grant REFERENCES on public.game_screenshots to service_role;
grant SELECT on public.game_screenshots to service_role;
grant TRIGGER on public.game_screenshots to service_role;
grant TRUNCATE on public.game_screenshots to service_role;
grant UPDATE on public.game_screenshots to service_role;
grant DELETE on public.games to anon;
grant INSERT on public.games to anon;
grant REFERENCES on public.games to anon;
grant SELECT on public.games to anon;
grant TRIGGER on public.games to anon;
grant TRUNCATE on public.games to anon;
grant UPDATE on public.games to anon;
grant DELETE on public.games to authenticated;
grant INSERT on public.games to authenticated;
grant REFERENCES on public.games to authenticated;
grant SELECT on public.games to authenticated;
grant TRIGGER on public.games to authenticated;
grant TRUNCATE on public.games to authenticated;
grant UPDATE on public.games to authenticated;
grant DELETE on public.games to service_role;
grant INSERT on public.games to service_role;
grant REFERENCES on public.games to service_role;
grant SELECT on public.games to service_role;
grant TRIGGER on public.games to service_role;
grant TRUNCATE on public.games to service_role;
grant UPDATE on public.games to service_role;
grant DELETE on public.profiles to anon;
grant INSERT on public.profiles to anon;
grant REFERENCES on public.profiles to anon;
grant SELECT on public.profiles to anon;
grant TRIGGER on public.profiles to anon;
grant TRUNCATE on public.profiles to anon;
grant UPDATE on public.profiles to anon;
grant DELETE on public.profiles to authenticated;
grant INSERT on public.profiles to authenticated;
grant REFERENCES on public.profiles to authenticated;
grant SELECT on public.profiles to authenticated;
grant TRIGGER on public.profiles to authenticated;
grant TRUNCATE on public.profiles to authenticated;
grant UPDATE on public.profiles to authenticated;
grant DELETE on public.profiles to service_role;
grant INSERT on public.profiles to service_role;
grant REFERENCES on public.profiles to service_role;
grant SELECT on public.profiles to service_role;
grant TRIGGER on public.profiles to service_role;
grant TRUNCATE on public.profiles to service_role;
grant UPDATE on public.profiles to service_role;

-- Storage bucket: content (público)
insert into storage.buckets (id, name, public) values ('content','content', true) on conflict (id) do nothing;

drop policy if exists "content_bucket_read" on storage.objects;
create policy "content_bucket_read" on storage.objects for select using (bucket_id = 'content');
drop policy if exists "content_bucket_insert" on storage.objects;
create policy "content_bucket_insert" on storage.objects for insert with check ((bucket_id = 'content') and is_admin());
drop policy if exists "content_bucket_update" on storage.objects;
create policy "content_bucket_update" on storage.objects for update using ((bucket_id = 'content') and is_admin()) with check ((bucket_id = 'content') and is_admin());
drop policy if exists "content_bucket_delete" on storage.objects;
create policy "content_bucket_delete" on storage.objects for delete using ((bucket_id = 'content') and is_admin());

-- ============================================================
-- NOTA DE PRIVACIDADE
-- A schema 'auth' (users, identities, sessions, refresh_tokens, etc.)
-- NÃO foi incluída por conter e-mails, hashes de senha e tokens.
-- Para restaurar o acesso completo, recrie os usuários pelo GoTrue.
--
-- O e-mail do ADM principal aparece nas funções is_principal_admin(),
-- promote_to_admin() e na política profiles_update. Ele foi substituído
-- pelo placeholder PRINCIPAL_ADMIN_EMAIL. Ao restaurar, defina o e-mail
-- real do ADM principal (ex.: sed -i 's/PRINCIPAL_ADMIN_EMAIL/seu@email/g').
-- ============================================================

commit;