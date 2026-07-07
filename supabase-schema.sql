-- =====================================================
-- 한끗루틴 Supabase 스키마
-- Supabase > SQL Editor > New Query 에 붙여넣고 실행
-- =====================================================

-- 1. 프로필 (auth.users 확장)
CREATE TABLE profiles (
  id            uuid REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
  name          text NOT NULL,
  role          text NOT NULL DEFAULT 'youth' CHECK (role IN ('youth', 'kkutjjang')),
  cert_count    int  DEFAULT 0,
  comm_count    int  DEFAULT 0,
  nadaeum       int  DEFAULT 0,
  cert_dates    text[] DEFAULT '{}',
  verify_status text DEFAULT 'none' CHECK (verify_status IN ('none','pending','approved','rejected')),
  verify_doc_url text,
  real_name     text,
  birth_date    date,
  phone         text,
  region_sido   text,
  region_sigugun text,
  school_status text CHECK (school_status IN ('out_of_school','enrolled','alternative')),
  signup_reason text,
  created_at    timestamptz DEFAULT now()
);

-- 2. 루틴
CREATE TABLE routines (
  id          bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  title       text NOT NULL,
  emoji       text DEFAULT '🌱',
  description text,
  partner_org text,
  tag         text,
  start_date  date,
  end_date    date,
  max_people  int  DEFAULT 10,
  eligibility text DEFAULT 'all' CHECK (eligibility IN ('all', 'out_of_school')),
  status      text DEFAULT 'recruit' CHECK (status IN ('recruit', 'active', 'done')),
  created_by  uuid REFERENCES auth.users ON DELETE SET NULL,
  created_at  timestamptz DEFAULT now()
);
-- 기존 DB 마이그레이션: 이미 routines 테이블이 있는 경우 아래 한 줄만 실행하세요.
-- ALTER TABLE routines ADD COLUMN IF NOT EXISTS partner_org text;

-- 3. 루틴 참여자
CREATE TABLE routine_participants (
  routine_id  bigint REFERENCES routines(id) ON DELETE CASCADE,
  user_id     uuid   REFERENCES auth.users   ON DELETE CASCADE,
  status      text   DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  application_note text,
  joined_at   timestamptz DEFAULT now(),
  PRIMARY KEY (routine_id, user_id)
);

-- 4. 인증
CREATE TABLE certifications (
  id          bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  routine_id  bigint REFERENCES routines(id) ON DELETE CASCADE,
  user_id     uuid   REFERENCES auth.users   ON DELETE CASCADE,
  content     text,
  photo_url   text,
  created_at  timestamptz DEFAULT now()
);

-- 5. 인증 좋아요
CREATE TABLE cert_likes (
  cert_id     bigint REFERENCES certifications(id) ON DELETE CASCADE,
  user_id     uuid   REFERENCES auth.users          ON DELETE CASCADE,
  PRIMARY KEY (cert_id, user_id)
);

-- 6. 인증 댓글
CREATE TABLE cert_comments (
  id          bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  cert_id     bigint REFERENCES certifications(id) ON DELETE CASCADE,
  user_id     uuid   REFERENCES auth.users          ON DELETE CASCADE,
  content     text   NOT NULL,
  created_at  timestamptz DEFAULT now()
);

-- 7. 커뮤니티 게시글
CREATE TABLE posts (
  id          bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  type        text   CHECK (type IN ('notice', 'review')),
  title       text,
  content     text,
  author_id   uuid   REFERENCES auth.users ON DELETE SET NULL,
  routine_id  bigint REFERENCES routines(id) ON DELETE SET NULL,
  created_at  timestamptz DEFAULT now()
);

-- 8. 게시글 좋아요
CREATE TABLE post_likes (
  post_id     bigint REFERENCES posts(id) ON DELETE CASCADE,
  user_id     uuid   REFERENCES auth.users ON DELETE CASCADE,
  PRIMARY KEY (post_id, user_id)
);

-- 9. 끗짱에게 편지
CREATE TABLE letters (
  id            bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  from_user_id  uuid   REFERENCES auth.users ON DELETE SET NULL,
  routine_id    bigint REFERENCES routines(id) ON DELETE SET NULL,
  content       text,
  opened        boolean DEFAULT false,
  created_at    timestamptz DEFAULT now()
);

-- 10. 나다움 포인트 로그
CREATE TABLE nadaeum_log (
  id          bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  user_id     uuid   REFERENCES auth.users ON DELETE CASCADE,
  amount      int    NOT NULL,
  reason      text,
  created_at  timestamptz DEFAULT now()
);

-- =====================================================
-- RLS (Row Level Security) 활성화
-- =====================================================

ALTER TABLE profiles              ENABLE ROW LEVEL SECURITY;
ALTER TABLE routines              ENABLE ROW LEVEL SECURITY;
ALTER TABLE routine_participants  ENABLE ROW LEVEL SECURITY;
ALTER TABLE certifications        ENABLE ROW LEVEL SECURITY;
ALTER TABLE cert_likes            ENABLE ROW LEVEL SECURITY;
ALTER TABLE cert_comments         ENABLE ROW LEVEL SECURITY;
ALTER TABLE posts                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE post_likes            ENABLE ROW LEVEL SECURITY;
ALTER TABLE letters               ENABLE ROW LEVEL SECURITY;
ALTER TABLE nadaeum_log           ENABLE ROW LEVEL SECURITY;

-- =====================================================
-- RLS 정책
-- =====================================================

-- profiles: 누구나 읽기, 본인만 수정
CREATE POLICY "profiles_select" ON profiles FOR SELECT USING (true);
CREATE POLICY "profiles_insert" ON profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "profiles_update" ON profiles FOR UPDATE USING (auth.uid() = id);

-- routines: 누구나 읽기, 끗짱만 생성
CREATE POLICY "routines_select" ON routines FOR SELECT USING (true);
CREATE POLICY "routines_insert" ON routines FOR INSERT WITH CHECK (auth.uid() = created_by);
CREATE POLICY "routines_update" ON routines FOR UPDATE USING (auth.uid() = created_by);

-- routine_participants: 누구나 읽기, 본인만 신청/삭제
CREATE POLICY "rp_select" ON routine_participants FOR SELECT USING (true);
CREATE POLICY "rp_insert" ON routine_participants FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "rp_update" ON routine_participants FOR UPDATE USING (
  auth.uid() = user_id OR
  auth.uid() IN (SELECT created_by FROM routines WHERE id = routine_id)
);

-- certifications: 누구나 읽기, 본인만 작성
CREATE POLICY "cert_select" ON certifications FOR SELECT USING (true);
CREATE POLICY "cert_insert" ON certifications FOR INSERT WITH CHECK (auth.uid() = user_id);

-- cert_likes: 누구나 읽기, 본인만 좋아요
CREATE POLICY "cl_select" ON cert_likes FOR SELECT USING (true);
CREATE POLICY "cl_insert" ON cert_likes FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "cl_delete" ON cert_likes FOR DELETE USING (auth.uid() = user_id);

-- cert_comments: 누구나 읽기, 로그인 사용자 작성
CREATE POLICY "cc_select" ON cert_comments FOR SELECT USING (true);
CREATE POLICY "cc_insert" ON cert_comments FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "cc_delete" ON cert_comments FOR DELETE USING (auth.uid() = user_id);

-- posts: 누구나 읽기, 로그인 사용자 작성
CREATE POLICY "posts_select" ON posts FOR SELECT USING (true);
CREATE POLICY "posts_insert" ON posts FOR INSERT WITH CHECK (auth.uid() = author_id);

-- post_likes: 누구나 읽기, 본인만 좋아요
CREATE POLICY "pl_select" ON post_likes FOR SELECT USING (true);
CREATE POLICY "pl_insert" ON post_likes FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "pl_delete" ON post_likes FOR DELETE USING (auth.uid() = user_id);

-- letters: 본인이 보낸/받은 것만
CREATE POLICY "letters_select" ON letters FOR SELECT USING (
  auth.uid() = from_user_id OR
  auth.uid() IN (SELECT created_by FROM routines WHERE id = routine_id)
);
CREATE POLICY "letters_insert" ON letters FOR INSERT WITH CHECK (auth.uid() = from_user_id);
CREATE POLICY "letters_update" ON letters FOR UPDATE USING (
  auth.uid() IN (SELECT created_by FROM routines WHERE id = routine_id)
);

-- nadaeum_log: 본인만
CREATE POLICY "nadaeum_select" ON nadaeum_log FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "nadaeum_insert" ON nadaeum_log FOR INSERT WITH CHECK (auth.uid() = user_id);

-- =====================================================
-- 신규 가입 시 profiles 자동 생성 트리거
-- =====================================================

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO profiles (id, name, role, real_name, birth_date, phone, region_sido, region_sigugun, school_status, signup_reason)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', '익명'),
    COALESCE(NEW.raw_user_meta_data->>'role', 'youth'),
    NEW.raw_user_meta_data->>'real_name',
    NULLIF(NEW.raw_user_meta_data->>'birth_date','')::date,
    NEW.raw_user_meta_data->>'phone',
    NEW.raw_user_meta_data->>'region_sido',
    NEW.raw_user_meta_data->>'region_sigugun',
    NEW.raw_user_meta_data->>'school_status',
    NEW.raw_user_meta_data->>'signup_reason'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- =====================================================
-- 샘플 루틴 데이터 (선택 - 나중에 실제 데이터로 교체)
-- =====================================================
-- 주의: 실제 끗짱 계정 생성 후 created_by 를 채워서 실행하세요
-- INSERT INTO routines (title, emoji, description, tag, start_date, end_date, max_people, status)
-- VALUES ('아침 루틴 21일', '🌱', '매일 아침 기상 후 물 한 잔, 스트레칭 5분, 오늘 할 일 3가지 적기.', '생활', '2026-06-10', '2026-06-30', 10, 'active');

-- =====================================================
-- [마이그레이션 2026-07-08] 학교밖 인증 서류 (2단계)
-- 기존 프로젝트에 이미 profiles 등이 생성돼 있다면 아래만 실행하세요.
-- =====================================================

-- 1) profiles 컬럼 추가 (이미 있으면 무시)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS verify_status text DEFAULT 'none' CHECK (verify_status IN ('none','pending','approved','rejected'));
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS verify_doc_url text;

-- 2) 관리자 판별 함수 (하드코딩된 관리자 이메일 — index.html의 ADMINS와 동일하게 유지)
CREATE OR REPLACE FUNCTION is_admin() RETURNS boolean AS $$
  SELECT auth.email() IN ('soon@youthvoice.or.kr', 'yv@youthvoice.or.kr');
$$ LANGUAGE sql STABLE;

-- 3) 본인이 verify_status를 임의로 'approved'로 바꾸지 못하게 가드
--    (본인은 서류 제출 시 'pending'으로만 바꿀 수 있고, 승인/거절은 관리자만 가능)
CREATE OR REPLACE FUNCTION guard_verify_status() RETURNS TRIGGER AS $$
BEGIN
  IF NEW.verify_status IS DISTINCT FROM OLD.verify_status THEN
    IF NOT is_admin() AND NEW.verify_status <> 'pending' THEN
      RAISE EXCEPTION '인증 상태는 관리자만 변경할 수 있어요';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_guard_verify_status ON profiles;
CREATE TRIGGER trg_guard_verify_status BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION guard_verify_status();

-- 4) 관리자는 모든 프로필을 수정할 수 있도록 정책 추가 (승인/거절 처리용)
DROP POLICY IF EXISTS "profiles_admin_update" ON profiles;
CREATE POLICY "profiles_admin_update" ON profiles FOR UPDATE USING (is_admin());

-- 5) Storage 버킷 생성 (서류 이미지 저장, 비공개)
INSERT INTO storage.buckets (id, name, public)
VALUES ('verify-docs', 'verify-docs', false)
ON CONFLICT (id) DO NOTHING;

-- 6) Storage 정책: 본인 폴더(자신의 uid 폴더)에만 업로드, 본인 또는 관리자만 조회
DROP POLICY IF EXISTS "verify_docs_insert_own" ON storage.objects;
CREATE POLICY "verify_docs_insert_own" ON storage.objects FOR INSERT WITH CHECK (
  bucket_id = 'verify-docs' AND (storage.foldername(name))[1] = auth.uid()::text
);
DROP POLICY IF EXISTS "verify_docs_select_own_or_admin" ON storage.objects;
CREATE POLICY "verify_docs_select_own_or_admin" ON storage.objects FOR SELECT USING (
  bucket_id = 'verify-docs' AND ((storage.foldername(name))[1] = auth.uid()::text OR is_admin())
);
DROP POLICY IF EXISTS "verify_docs_delete_own" ON storage.objects;
CREATE POLICY "verify_docs_delete_own" ON storage.objects FOR DELETE USING (
  bucket_id = 'verify-docs' AND (storage.foldername(name))[1] = auth.uid()::text
);

-- =====================================================
-- [마이그레이션 2026-07-08b] 루틴 대표 이미지
-- =====================================================

-- 1) routines 컬럼 추가
ALTER TABLE routines ADD COLUMN IF NOT EXISTS cover_image_url text;

-- 2) Storage 버킷 생성 (루틴 대표 이미지, 공개 — 누구나 볼 수 있어야 함)
INSERT INTO storage.buckets (id, name, public)
VALUES ('routine-covers', 'routine-covers', true)
ON CONFLICT (id) DO NOTHING;

-- 3) Storage 정책: 로그인 사용자만 업로드, 누구나 조회(공개 버킷)
DROP POLICY IF EXISTS "routine_covers_insert_auth" ON storage.objects;
CREATE POLICY "routine_covers_insert_auth" ON storage.objects FOR INSERT WITH CHECK (
  bucket_id = 'routine-covers' AND auth.uid() IS NOT NULL
);
DROP POLICY IF EXISTS "routine_covers_select_all" ON storage.objects;
CREATE POLICY "routine_covers_select_all" ON storage.objects FOR SELECT USING (
  bucket_id = 'routine-covers'
);

-- =====================================================
-- [마이그레이션 2026-07-07c] 가입 시 기본정보 + 루틴 참여자격 + 신청 각오
-- 기존 프로젝트에 이미 profiles/routines/routine_participants가 있다면 아래만 실행하세요.
-- =====================================================

-- 1) profiles: 가입 시 받는 기본정보
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS real_name text;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS birth_date date;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS phone text;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS region_sido text;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS region_sigugun text;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS school_status text CHECK (school_status IN ('out_of_school','enrolled','alternative'));
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS signup_reason text;

-- 2) routines: 참여 자격 (전체 / 학교밖청소년 전용)
ALTER TABLE routines ADD COLUMN IF NOT EXISTS eligibility text DEFAULT 'all' CHECK (eligibility IN ('all', 'out_of_school'));

-- 3) routine_participants: 신청 시 각오/소감
ALTER TABLE routine_participants ADD COLUMN IF NOT EXISTS application_note text;

-- 4) 신규 가입 트리거 갱신 (기본정보까지 함께 저장)
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO profiles (id, name, role, real_name, birth_date, phone, region_sido, region_sigugun, school_status, signup_reason)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', '익명'),
    COALESCE(NEW.raw_user_meta_data->>'role', 'youth'),
    NEW.raw_user_meta_data->>'real_name',
    NULLIF(NEW.raw_user_meta_data->>'birth_date','')::date,
    NEW.raw_user_meta_data->>'phone',
    NEW.raw_user_meta_data->>'region_sido',
    NEW.raw_user_meta_data->>'region_sigugun',
    NEW.raw_user_meta_data->>'school_status',
    NEW.raw_user_meta_data->>'signup_reason'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- [마이그레이션 2026-07-07d] 학교 밖 여부 → 재학 상태 셀렉트로 변경
-- 위 2026-07-07c를 이미 실행한 프로젝트라면 아래만 실행하세요.
-- =====================================================
ALTER TABLE profiles DROP COLUMN IF EXISTS is_out_of_school;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS school_status text CHECK (school_status IN ('out_of_school','enrolled','alternative'));
