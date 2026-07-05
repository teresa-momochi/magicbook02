-- ============================================================
-- MagicBook02 — Supabase Schema (Phase 1：單一使用者模式，尚未接 Auth)
--
-- 在 Supabase 專案的 SQL Editor 貼上整份執行即可。
--
-- 表名一律加上 magicbook02_ 前綴，即使之後跟 MagicBook01 共用同一個
-- Supabase 專案，也不會撞名（MagicBook01 已經有自己的 books/pages 等表）。
--
-- 第一階段（本檔案）：RLS Policy 全部開放（using (true)），因為還沒有
-- 登入機制，前端一律用 anon key 存取。
-- 之後要加 Auth 時：
--   1. 幫每一列資料補上真正的 user_id
--   2. 把下面每一條 "phase1_allow_all_*" policy 改成
--        using (auth.uid() = user_id) with check (auth.uid() = user_id)
--   3. 不需要更動任何資料表結構，也不需要更動前端的 BookRepository 介面。
-- ============================================================

-- ---------- Tables ----------

create table if not exists magicbook02_books (
  id uuid primary key default gen_random_uuid(),
  user_id uuid null, -- 保留給之後的 Auth 使用，Phase 1 一律是 null
  name text not null default '未命名教材',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists magicbook02_lessons (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references magicbook02_books(id) on delete cascade,
  number integer not null,
  title text not null default '未命名 Lesson',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint magicbook02_lessons_book_number_unique unique (book_id, number)
);

create table if not exists magicbook02_pages (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references magicbook02_lessons(id) on delete cascade,
  number integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint magicbook02_pages_lesson_number_unique unique (lesson_id, number)
);

create table if not exists magicbook02_image_blocks (
  id uuid primary key default gen_random_uuid(),
  page_id uuid not null references magicbook02_pages(id) on delete cascade,
  position integer not null default 0,
  content text,        -- 空 Image Block 的提示文字（例如「點擊或拖曳圖片到這裡」）
  image_url text,      -- Supabase Storage 的公開網址；null 代表這格還是空的
  file_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists magicbook02_text_blocks (
  id uuid primary key default gen_random_uuid(),
  page_id uuid not null references magicbook02_pages(id) on delete cascade,
  position integer not null default 0,
  raw_text text not null default '',  -- Single Source of Truth
  html text not null default '',      -- 由 raw_text 轉換產生的呈現格式
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_magicbook02_lessons_book_id on magicbook02_lessons(book_id);
create index if not exists idx_magicbook02_pages_lesson_id on magicbook02_pages(lesson_id);
create index if not exists idx_magicbook02_image_blocks_page_id on magicbook02_image_blocks(page_id);
create index if not exists idx_magicbook02_text_blocks_page_id on magicbook02_text_blocks(page_id);

-- ---------- Summary views（首頁／教材頁用，避免每次都要撈全部內容）----------
-- security_invoker = true：讓查詢者自己的權限／RLS 套用在底層表，
-- 而不是用 view 擁有者的權限（Postgres 15+ 語法，Supabase 支援）。

create or replace view magicbook02_book_summary
with (security_invoker = true) as
select
  b.id,
  b.name,
  b.created_at,
  b.updated_at,
  count(distinct l.id) as lesson_count,
  count(p.id) as page_count
from magicbook02_books b
left join magicbook02_lessons l on l.book_id = b.id
left join magicbook02_pages p on p.lesson_id = l.id
group by b.id;

create or replace view magicbook02_lesson_summary
with (security_invoker = true) as
select
  l.id,
  l.book_id,
  l.number,
  l.title,
  l.created_at,
  l.updated_at,
  count(p.id) as page_count
from magicbook02_lessons l
left join magicbook02_pages p on p.lesson_id = l.id
group by l.id;

-- ---------- RLS：Phase 1 全部開放（單一使用者，尚未接 Auth）----------

alter table magicbook02_books enable row level security;
alter table magicbook02_lessons enable row level security;
alter table magicbook02_pages enable row level security;
alter table magicbook02_image_blocks enable row level security;
alter table magicbook02_text_blocks enable row level security;

drop policy if exists phase1_allow_all_books on magicbook02_books;
create policy phase1_allow_all_books on magicbook02_books
  for all using (true) with check (true);

drop policy if exists phase1_allow_all_lessons on magicbook02_lessons;
create policy phase1_allow_all_lessons on magicbook02_lessons
  for all using (true) with check (true);

drop policy if exists phase1_allow_all_pages on magicbook02_pages;
create policy phase1_allow_all_pages on magicbook02_pages
  for all using (true) with check (true);

drop policy if exists phase1_allow_all_image_blocks on magicbook02_image_blocks;
create policy phase1_allow_all_image_blocks on magicbook02_image_blocks
  for all using (true) with check (true);

drop policy if exists phase1_allow_all_text_blocks on magicbook02_text_blocks;
create policy phase1_allow_all_text_blocks on magicbook02_text_blocks
  for all using (true) with check (true);

-- 明確授權 anon／authenticated 角色可以存取這些資料表與 view
-- （Supabase 通常預設就有，這裡明確寫出來以防萬一）。
grant select, insert, update, delete on
  magicbook02_books,
  magicbook02_lessons,
  magicbook02_pages,
  magicbook02_image_blocks,
  magicbook02_text_blocks
to anon, authenticated;

grant select on magicbook02_book_summary, magicbook02_lesson_summary to anon, authenticated;

-- ---------- Storage：圖片 Bucket ----------

insert into storage.buckets (id, name, public)
values ('magicbook02-images', 'magicbook02-images', true)
on conflict (id) do nothing;

drop policy if exists magicbook02_storage_public_read on storage.objects;
create policy magicbook02_storage_public_read on storage.objects
  for select using (bucket_id = 'magicbook02-images');

drop policy if exists magicbook02_storage_public_insert on storage.objects;
create policy magicbook02_storage_public_insert on storage.objects
  for insert with check (bucket_id = 'magicbook02-images');

drop policy if exists magicbook02_storage_public_update on storage.objects;
create policy magicbook02_storage_public_update on storage.objects
  for update using (bucket_id = 'magicbook02-images');

drop policy if exists magicbook02_storage_public_delete on storage.objects;
create policy magicbook02_storage_public_delete on storage.objects
  for delete using (bucket_id = 'magicbook02-images');

-- ============================================================
-- 執行完後：
--   1. 到 Project Settings → API，複製 Project URL 與 anon public key
--   2. 貼到 magicbook02.html 裡的 SUPABASE_URL / SUPABASE_ANON_KEY
--   3. 部署到 Vercel（或本地開啟）即可開始使用
-- ============================================================
