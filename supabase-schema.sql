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
  kickoff_at  timestamptz,
  closing_at  timestamptz,
  meeting_link text,
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
  INSERT INTO profiles (id, name, role, real_name, birth_date, phone, region_sido, region_sigugun, school_status, kkutjjang_status)
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
    CASE
      WHEN COALESCE(NEW.raw_user_meta_data->>'role','youth') <> 'kkutjjang' THEN 'none'
      WHEN NEW.email IN ('dev@youthvoice.or.kr','yv@youthvoice.or.kr') THEN 'approved'
      ELSE 'pending'
    END
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
  SELECT auth.email() IN ('dev@youthvoice.or.kr', 'yv@youthvoice.or.kr');
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
  INSERT INTO profiles (id, name, role, real_name, birth_date, phone, region_sido, region_sigugun, school_status, kkutjjang_status)
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
    CASE
      WHEN COALESCE(NEW.raw_user_meta_data->>'role','youth') <> 'kkutjjang' THEN 'none'
      WHEN NEW.email IN ('dev@youthvoice.or.kr','yv@youthvoice.or.kr') THEN 'approved'
      ELSE 'pending'
    END
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

-- =====================================================
-- [마이그레이션 2026-07-09] OT/클로징 온라인 모임 (줌 연동)
-- 기존 프로젝트는 아래만 실행하세요.
-- =====================================================
ALTER TABLE routines ADD COLUMN IF NOT EXISTS kickoff_at timestamptz;
ALTER TABLE routines ADD COLUMN IF NOT EXISTS closing_at timestamptz;
ALTER TABLE routines ADD COLUMN IF NOT EXISTS meeting_link text;

-- =====================================================
-- [마이그레이션 2026-07-10] 끗짱 가입 승인제 + 루틴 담당 끗짱 지정
-- 기존 프로젝트는 아래만 실행하세요.
-- =====================================================

-- 1) 끗짱 가입 승인 상태 (관리자 승인 전엔 앱 진입 불가)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS kkutjjang_status text DEFAULT 'none' CHECK (kkutjjang_status IN ('none','pending','approved','rejected'));

-- 1-1) 신규 가입 트리거 갱신 (kkutjjang_status까지 함께 저장)
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO profiles (id, name, role, real_name, birth_date, phone, region_sido, region_sigugun, school_status, kkutjjang_status)
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
    CASE
      WHEN COALESCE(NEW.raw_user_meta_data->>'role','youth') <> 'kkutjjang' THEN 'none'
      WHEN NEW.email IN ('dev@youthvoice.or.kr','yv@youthvoice.or.kr') THEN 'approved'
      ELSE 'pending'
    END
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2) 본인이 승인 상태를 임의로 바꾸지 못하게 가드 (관리자만 승인/반려 가능)
CREATE OR REPLACE FUNCTION guard_kkutjjang_status() RETURNS TRIGGER AS $$
BEGIN
  IF NEW.kkutjjang_status IS DISTINCT FROM OLD.kkutjjang_status THEN
    IF NOT is_admin() AND NEW.kkutjjang_status <> 'pending' THEN
      RAISE EXCEPTION '끗짱 승인 상태는 관리자만 변경할 수 있어요';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
DROP TRIGGER IF EXISTS trg_guard_kkutjjang_status ON profiles;
CREATE TRIGGER trg_guard_kkutjjang_status BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION guard_kkutjjang_status();

-- 3) 루틴 담당 끗짱(리더) 지정 — 관리자가 루틴 생성 시 선택
ALTER TABLE routines ADD COLUMN IF NOT EXISTS led_by uuid REFERENCES auth.users ON DELETE SET NULL;

-- 4) 루틴 생성은 관리자만 (당분간 — 추후 끗짱 자율 개설 허용 예정)
DROP POLICY IF EXISTS "routines_insert" ON routines;
CREATE POLICY "routines_insert" ON routines FOR INSERT WITH CHECK (is_admin());

-- 5) 담당 끗짱도 자신이 이끄는 루틴을 관리(수정)할 수 있도록
DROP POLICY IF EXISTS "routines_update" ON routines;
CREATE POLICY "routines_update" ON routines FOR UPDATE USING (
  auth.uid() = created_by OR auth.uid() = led_by OR is_admin()
);

-- 6) 참여 신청 승인/거절 — 담당 끗짱 + 관리자도 가능하도록 확장
DROP POLICY IF EXISTS "rp_update" ON routine_participants;
CREATE POLICY "rp_update" ON routine_participants FOR UPDATE USING (
  auth.uid() = user_id
  OR auth.uid() IN (SELECT created_by FROM routines WHERE id = routine_id)
  OR auth.uid() IN (SELECT led_by FROM routines WHERE id = routine_id)
  OR is_admin()
);

-- 7) 편지 조회/응답 — 담당 끗짱 + 관리자도 가능하도록 확장
DROP POLICY IF EXISTS "letters_select" ON letters;
CREATE POLICY "letters_select" ON letters FOR SELECT USING (
  auth.uid() = from_user_id
  OR auth.uid() IN (SELECT created_by FROM routines WHERE id = routine_id)
  OR auth.uid() IN (SELECT led_by FROM routines WHERE id = routine_id)
  OR is_admin()
);
DROP POLICY IF EXISTS "letters_update" ON letters;
CREATE POLICY "letters_update" ON letters FOR UPDATE USING (
  auth.uid() IN (SELECT created_by FROM routines WHERE id = routine_id)
  OR auth.uid() IN (SELECT led_by FROM routines WHERE id = routine_id)
  OR is_admin()
);

-- =====================================================
-- [마이그레이션 2026-07-11] 참여 계기(signup_reason) 필드 제거
-- =====================================================
ALTER TABLE profiles DROP COLUMN IF EXISTS signup_reason;

-- =====================================================
-- [마이그레이션 2026-07-11b] 인증 사진 저장
-- =====================================================

-- 1) certifications: 여러 장 지원 (기존 photo_url은 그대로 두고 배열 컬럼 추가)
ALTER TABLE certifications ADD COLUMN IF NOT EXISTS photo_urls text[] DEFAULT '{}';

-- 2) Storage 버킷 생성 (인증 사진, 공개 — 피드에서 누구나 볼 수 있어야 함)
INSERT INTO storage.buckets (id, name, public)
VALUES ('cert-photos', 'cert-photos', true)
ON CONFLICT (id) DO NOTHING;

-- 3) Storage 정책: 로그인 사용자만 업로드, 누구나 조회(공개 버킷)
DROP POLICY IF EXISTS "cert_photos_insert_auth" ON storage.objects;
CREATE POLICY "cert_photos_insert_auth" ON storage.objects FOR INSERT WITH CHECK (
  bucket_id = 'cert-photos' AND auth.uid() IS NOT NULL
);
DROP POLICY IF EXISTS "cert_photos_select_all" ON storage.objects;
CREATE POLICY "cert_photos_select_all" ON storage.objects FOR SELECT USING (
  bucket_id = 'cert-photos'
);

-- =====================================================
-- [마이그레이션 2026-07-11c] 관리자 끗짱 자동승인 + 서버측 검증
-- 클라이언트가 보낸 kkutjjang_status를 신뢰하지 않고, 이메일을 서버(DB)에서
-- 직접 확인해 관리자 이메일만 즉시 승인되도록 변경 (임의 승인 요청 악용 방지)
-- =====================================================
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO profiles (id, name, role, real_name, birth_date, phone, region_sido, region_sigugun, school_status, kkutjjang_status)
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
    CASE
      WHEN COALESCE(NEW.raw_user_meta_data->>'role','youth') <> 'kkutjjang' THEN 'none'
      WHEN NEW.email IN ('dev@youthvoice.or.kr','yv@youthvoice.or.kr') THEN 'approved'
      ELSE 'pending'
    END
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- [마이그레이션 2026-07-09] 게시글/댓글 삭제 권한 (본인 또는 관리자)
-- =====================================================
DROP POLICY IF EXISTS "posts_delete" ON posts;
CREATE POLICY "posts_delete" ON posts FOR DELETE USING (auth.uid() = author_id OR is_admin());

DROP POLICY IF EXISTS "cc_delete" ON cert_comments;
CREATE POLICY "cc_delete" ON cert_comments FOR DELETE USING (auth.uid() = user_id OR is_admin());

-- =====================================================
-- [마이그레이션 2026-07-09b] 관리자 이메일 변경 (soon@ → dev@)
-- =====================================================
CREATE OR REPLACE FUNCTION is_admin() RETURNS boolean AS $$
  SELECT auth.email() IN ('dev@youthvoice.or.kr', 'yv@youthvoice.or.kr');
$$ LANGUAGE sql STABLE;

-- =====================================================
-- [마이그레이션 2026-07-09c] 인증은 승인된 참여자만 가능하도록 서버측 검증
-- (기존엔 로그인만 하면 신청 안 한 루틴도 인증 가능했음)
-- =====================================================
DROP POLICY IF EXISTS "cert_insert" ON certifications;
CREATE POLICY "cert_insert" ON certifications FOR INSERT WITH CHECK (
  auth.uid() = user_id AND (
    EXISTS (
      SELECT 1 FROM routine_participants rp
      WHERE rp.routine_id = certifications.routine_id
        AND rp.user_id = auth.uid()
        AND rp.status = 'approved'
    )
    OR EXISTS (
      SELECT 1 FROM routines r
      WHERE r.id = certifications.routine_id
        AND (r.created_by = auth.uid() OR r.led_by = auth.uid())
    )
    OR is_admin()
  )
);

-- =====================================================
-- [마이그레이션 2026-07-09d] 루틴 보관(archived) + 관리자 삭제 권한
-- =====================================================
ALTER TABLE routines ADD COLUMN IF NOT EXISTS archived boolean DEFAULT false;

DROP POLICY IF EXISTS "routines_delete" ON routines;
CREATE POLICY "routines_delete" ON routines FOR DELETE USING (is_admin());

-- =====================================================
-- [마이그레이션 2026-07-09e] Web Push 구독 저장
-- 사용자가 "알림 켜기"를 누르면 브라우저 푸시 구독 정보를 저장.
-- 발송은 Edge Function(send-push)이 service_role로 읽어서 처리.
-- endpoint는 기기·브라우저마다 고유하므로 UNIQUE — 같은 기기에서
-- 다시 켜면 upsert로 갱신됨 (upsert에 UPDATE 정책 필요)
-- =====================================================
CREATE TABLE push_subscriptions (
  id          bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  user_id     uuid NOT NULL REFERENCES auth.users ON DELETE CASCADE,
  endpoint    text NOT NULL UNIQUE,
  p256dh      text NOT NULL,
  auth        text NOT NULL,
  created_at  timestamptz DEFAULT now()
);

ALTER TABLE push_subscriptions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ps_select" ON push_subscriptions FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "ps_insert" ON push_subscriptions FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "ps_update" ON push_subscriptions FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "ps_delete" ON push_subscriptions FOR DELETE USING (auth.uid() = user_id);

-- =====================================================
-- [마이그레이션 2026-07-10] Web Push 2단계 — 자동 알림 트리거
-- 참여 승인/거절, 인증 좋아요, 인증 댓글 발생 시 DB 트리거가
-- pg_net으로 send-push Edge Function을 호출해 푸시 발송.
--
-- ★ 사전 준비 (이 블록 실행 전에 1회):
--   대시보드 Settings → API 에서 service_role 키를 복사한 뒤 아래 실행
--   SELECT vault.create_secret('<여기에 service_role 키>', 'sr_key_for_push');
-- =====================================================
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- 공용 발송 헬퍼: Vault에서 키를 읽어 send-push 함수를 비동기 호출
CREATE OR REPLACE FUNCTION notify_push(target_user uuid, push_title text, push_body text)
RETURNS void AS $$
DECLARE
  sr_key text;
BEGIN
  SELECT decrypted_secret INTO sr_key FROM vault.decrypted_secrets WHERE name = 'sr_key_for_push';
  IF sr_key IS NULL THEN RETURN; END IF;  -- 키 미설정 시 알림만 조용히 스킵 (본 동작엔 영향 없음)
  PERFORM net.http_post(
    url := 'https://ynqvhsffoesjzefitafv.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || sr_key),
    body := jsonb_build_object('user_id', target_user, 'title', push_title, 'body', push_body, 'url', '/youthit-routine/')
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 1) 루틴 참여 승인/거절 → 신청자에게
CREATE OR REPLACE FUNCTION on_participant_status_change()
RETURNS TRIGGER AS $$
DECLARE
  r_title text;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status NOT IN ('approved','rejected') THEN
    RETURN NEW;
  END IF;
  SELECT title INTO r_title FROM routines WHERE id = NEW.routine_id;
  IF NEW.status = 'approved' THEN
    PERFORM notify_push(NEW.user_id, '루틴 참여가 승인됐어요! 🎉', '"' || coalesce(r_title,'루틴') || '" 이제 함께 시작해요!');
  ELSE
    PERFORM notify_push(NEW.user_id, '루틴 참여 안내', '"' || coalesce(r_title,'루틴') || '" 참여가 이번엔 어려워요. 다른 루틴도 둘러봐요.');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_participant_status_push ON routine_participants;
CREATE TRIGGER trg_participant_status_push
  AFTER UPDATE ON routine_participants
  FOR EACH ROW EXECUTE FUNCTION on_participant_status_change();

-- 2) 인증 좋아요 → 인증 작성자에게 (본인이 본인 글에 누른 건 제외)
CREATE OR REPLACE FUNCTION on_cert_like_push()
RETURNS TRIGGER AS $$
DECLARE
  cert_owner uuid;
  liker_name text;
BEGIN
  SELECT user_id INTO cert_owner FROM certifications WHERE id = NEW.cert_id;
  IF cert_owner IS NULL OR cert_owner = NEW.user_id THEN RETURN NEW; END IF;
  SELECT name INTO liker_name FROM profiles WHERE id = NEW.user_id;
  PERFORM notify_push(cert_owner, '❤️ 응원이 도착했어요', coalesce(liker_name,'누군가') || '님이 내 인증을 응원해요!');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_cert_like_push ON cert_likes;
CREATE TRIGGER trg_cert_like_push
  AFTER INSERT ON cert_likes
  FOR EACH ROW EXECUTE FUNCTION on_cert_like_push();

-- 3) 인증 댓글 → 인증 작성자에게 (본인 댓글 제외, 내용은 40자까지만)
CREATE OR REPLACE FUNCTION on_cert_comment_push()
RETURNS TRIGGER AS $$
DECLARE
  cert_owner uuid;
  commenter_name text;
BEGIN
  SELECT user_id INTO cert_owner FROM certifications WHERE id = NEW.cert_id;
  IF cert_owner IS NULL OR cert_owner = NEW.user_id THEN RETURN NEW; END IF;
  SELECT name INTO commenter_name FROM profiles WHERE id = NEW.user_id;
  PERFORM notify_push(
    cert_owner,
    '💬 댓글이 달렸어요',
    coalesce(commenter_name,'누군가') || ': ' || left(coalesce(NEW.content,''), 40) || CASE WHEN length(coalesce(NEW.content,'')) > 40 THEN '…' ELSE '' END
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_cert_comment_push ON cert_comments;
CREATE TRIGGER trg_cert_comment_push
  AFTER INSERT ON cert_comments
  FOR EACH ROW EXECUTE FUNCTION on_cert_comment_push();

-- =====================================================
-- [마이그레이션 2026-07-10b] 알림 메시지 템플릿
-- admin.html "알림 보내기" 탭에서 자주 쓰는 제목/내용을 저장해두고
-- 드롭다운으로 불러 쓰는 용도. 관리자만 읽기/쓰기 가능.
-- =====================================================
CREATE TABLE notify_templates (
  id          bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  title       text NOT NULL,
  body        text,
  created_at  timestamptz DEFAULT now()
);

ALTER TABLE notify_templates ENABLE ROW LEVEL SECURITY;
CREATE POLICY "nt_select" ON notify_templates FOR SELECT USING (is_admin());
CREATE POLICY "nt_insert" ON notify_templates FOR INSERT WITH CHECK (is_admin());
CREATE POLICY "nt_delete" ON notify_templates FOR DELETE USING (is_admin());

-- =====================================================
-- [마이그레이션 2026-07-11] Web Push 4단계 — 마일스톤 축하 + 인증 리마인드
-- ① 마일스톤: 인증 저장 시 해당 루틴 누적 인증이 5/10/15/20회면 축하 푸시 (트리거)
-- ② 리마인드: 사용자가 고른 시간(reminder_hour, KST)에 아직 오늘 인증 전이면
--    푸시 발송 — pg_cron이 매시 정각에 send_cert_reminders() 실행
-- =====================================================
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS reminder_hour int
  CHECK (reminder_hour >= 0 AND reminder_hour <= 23);

-- ① 마일스톤 축하 트리거
CREATE OR REPLACE FUNCTION on_cert_milestone()
RETURNS TRIGGER AS $$
DECLARE
  cnt int;
  r_title text;
BEGIN
  SELECT count(*) INTO cnt FROM certifications
   WHERE routine_id = NEW.routine_id AND user_id = NEW.user_id;
  IF cnt IN (5, 10, 15, 20) THEN
    SELECT title INTO r_title FROM routines WHERE id = NEW.routine_id;
    PERFORM notify_push(
      NEW.user_id,
      '🎉 ' || cnt || '번째 인증 달성!',
      '"' || coalesce(r_title, '루틴') || '" 꾸준함이 빛나고 있어요. 계속 가봐요!'
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_cert_milestone_push ON certifications;
CREATE TRIGGER trg_cert_milestone_push
  AFTER INSERT ON certifications
  FOR EACH ROW EXECUTE FUNCTION on_cert_milestone();

-- ② 인증 리마인드 (pg_cron)
CREATE EXTENSION IF NOT EXISTS pg_cron;

CREATE OR REPLACE FUNCTION send_cert_reminders()
RETURNS void AS $$
DECLARE
  u record;
BEGIN
  FOR u IN
    SELECT p.id FROM profiles p
    WHERE p.reminder_hour = EXTRACT(hour FROM now() AT TIME ZONE 'Asia/Seoul')::int
      -- 진행 중 루틴에 승인 참여 중인 사람만
      AND EXISTS (
        SELECT 1 FROM routine_participants rp
        JOIN routines r ON r.id = rp.routine_id
        WHERE rp.user_id = p.id AND rp.status = 'approved'
          AND r.status = 'active' AND coalesce(r.archived, false) = false
      )
      -- 오늘(KST) 이미 인증했으면 제외
      AND NOT EXISTS (
        SELECT 1 FROM certifications c
        WHERE c.user_id = p.id
          AND (c.created_at AT TIME ZONE 'Asia/Seoul')::date = (now() AT TIME ZONE 'Asia/Seoul')::date
      )
  LOOP
    PERFORM notify_push(u.id, '🔔 오늘의 한끗, 잊지 않으셨죠?', '아직 오늘 인증 전이에요. 지금 한 끗 남겨봐요!');
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 매시 정각 실행 (이미 등록돼 있으면 교체)
SELECT cron.unschedule('hankkut-cert-reminder')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'hankkut-cert-reminder');
SELECT cron.schedule('hankkut-cert-reminder', '0 * * * *', 'SELECT send_cert_reminders()');

-- =====================================================
-- [마이그레이션 2026-07-11b] 거절 사유 안내
-- 서류 반려/끗짱 가입 반려/루틴 참여 거절 시 사유를 저장해서
-- 신청자 본인에게 보여주기 위한 컬럼들
-- =====================================================
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS verify_reject_reason text;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS kkutjjang_reject_reason text;
ALTER TABLE routine_participants ADD COLUMN IF NOT EXISTS reject_reason text;

-- =====================================================
-- [마이그레이션 2026-07-14] 가입 시 개인정보 수집·이용 동의 저장
-- 필수 동의(만 14세 이상 확인 + 개인정보 수집·이용 동의)는 체크해야만
-- 가입이 진행되므로 가입 시점 = 동의 시점으로 기록. 마케팅 동의는 선택.
-- =====================================================
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS privacy_agreed_at timestamptz;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS marketing_agreed boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO profiles (id, name, role, real_name, birth_date, phone, region_sido, region_sigugun, school_status, kkutjjang_status, privacy_agreed_at, marketing_agreed)
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
    CASE
      WHEN COALESCE(NEW.raw_user_meta_data->>'role','youth') <> 'kkutjjang' THEN 'none'
      WHEN NEW.email IN ('dev@youthvoice.or.kr','yv@youthvoice.or.kr') THEN 'approved'
      ELSE 'pending'
    END,
    now(),
    COALESCE((NEW.raw_user_meta_data->>'marketing_agreed')::boolean, false)
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- [마이그레이션 2026-07-14b] 최소 인원 미달 폐강 (수동)
-- min_people은 선택 입력(NULL이면 폐강 기능 자체를 안 씀).
-- 자동 전환 아님 — 끗짱/관리자가 "폐강 처리" 버튼으로만 status를 cancelled로 전환.
-- =====================================================
ALTER TABLE routines ADD COLUMN IF NOT EXISTS min_people integer;

ALTER TABLE routines DROP CONSTRAINT IF EXISTS routines_status_check;
ALTER TABLE routines ADD CONSTRAINT routines_status_check CHECK (status IN ('recruit','active','done','cancelled'));

-- 폐강 시 이미 신청(대기/승인)한 청소년들에게 자동 알림
CREATE OR REPLACE FUNCTION on_routine_cancelled()
RETURNS TRIGGER AS $$
DECLARE p RECORD;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'cancelled' THEN
    FOR p IN SELECT user_id FROM routine_participants WHERE routine_id = NEW.id AND status IN ('approved','pending') LOOP
      PERFORM notify_push(p.user_id, '루틴이 폐강됐어요', '"' || NEW.title || '" 루틴이 최소 인원 미달로 폐강됐어요.');
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_routine_cancelled ON routines;
CREATE TRIGGER trg_routine_cancelled AFTER UPDATE ON routines
  FOR EACH ROW EXECUTE FUNCTION on_routine_cancelled();

-- =====================================================
-- [마이그레이션 2026-07-14c] 리워드 시스템 (나다움 포인트 + 상점) — DB
-- 인증 나다움은 화면 연출은 즉시, 실제 지급은 루틴 완주 기준(2/3) 달성 시
-- 그동안 쌓인 인증분을 한 번에, 이후 추가 인증은 즉시 지급.
-- 댓글(+1)/후기(+30)는 기존처럼 즉시 지급 유지(변경 없음).
-- =====================================================

CREATE TABLE rewards (
  id          bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  title       text NOT NULL,
  description text,
  cost        int NOT NULL CHECK (cost > 0),
  stock       int NOT NULL DEFAULT 0,
  image_url   text,
  active      boolean NOT NULL DEFAULT true,
  created_at  timestamptz DEFAULT now()
);

CREATE TABLE reward_redemptions (
  id           bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  user_id      uuid REFERENCES auth.users ON DELETE CASCADE,
  reward_id    bigint REFERENCES rewards(id) ON DELETE CASCADE,
  status       text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','fulfilled')),
  requested_at timestamptz DEFAULT now(),
  fulfilled_at timestamptz
);

ALTER TABLE rewards             ENABLE ROW LEVEL SECURITY;
ALTER TABLE reward_redemptions  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rewards_select" ON rewards FOR SELECT USING (true);
CREATE POLICY "rewards_admin_insert" ON rewards FOR INSERT WITH CHECK (is_admin());
CREATE POLICY "rewards_admin_update" ON rewards FOR UPDATE USING (is_admin());
CREATE POLICY "rewards_admin_delete" ON rewards FOR DELETE USING (is_admin());

CREATE POLICY "redemptions_select" ON reward_redemptions FOR SELECT USING (auth.uid() = user_id OR is_admin());
CREATE POLICY "redemptions_insert" ON reward_redemptions FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "redemptions_admin_update" ON reward_redemptions FOR UPDATE USING (is_admin());

-- 루틴별 완주 지급 중복 방지
ALTER TABLE routine_participants ADD COLUMN IF NOT EXISTS nadaeum_paid boolean NOT NULL DEFAULT false;

-- 인증 저장 시: 완주 기준 최초 달성 순간 누적분 일괄 지급, 이후엔 인증마다 즉시 지급
CREATE OR REPLACE FUNCTION on_cert_nadaeum_payout()
RETURNS TRIGGER AS $$
DECLARE
  cnt int;
  r_start date;
  r_end date;
  day_count int;
  cert_goal int;
  paid boolean;
BEGIN
  SELECT count(*) INTO cnt FROM certifications WHERE routine_id = NEW.routine_id AND user_id = NEW.user_id;
  SELECT start_date, end_date INTO r_start, r_end FROM routines WHERE id = NEW.routine_id;
  day_count := GREATEST(1, COALESCE((r_end - r_start), 20) + 1);
  cert_goal := GREATEST(1, FLOOR(day_count * 2.0 / 3)::int);

  SELECT nadaeum_paid INTO paid FROM routine_participants WHERE routine_id = NEW.routine_id AND user_id = NEW.user_id;

  IF paid THEN
    UPDATE profiles SET nadaeum = nadaeum + 10 WHERE id = NEW.user_id;
    INSERT INTO nadaeum_log(user_id, amount, reason) VALUES (NEW.user_id, 10, '루틴 인증 (완주 후 추가 인증)');
  ELSIF cnt >= cert_goal THEN
    UPDATE profiles SET nadaeum = nadaeum + (cnt * 10) WHERE id = NEW.user_id;
    INSERT INTO nadaeum_log(user_id, amount, reason) VALUES (NEW.user_id, cnt * 10, '루틴 완주 기준 달성 (인증 ' || cnt || '회 적립분 일괄 지급)');
    UPDATE routine_participants SET nadaeum_paid = true WHERE routine_id = NEW.routine_id AND user_id = NEW.user_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_cert_nadaeum_payout ON certifications;
CREATE TRIGGER trg_cert_nadaeum_payout
  AFTER INSERT ON certifications
  FOR EACH ROW EXECUTE FUNCTION on_cert_nadaeum_payout();

-- 리워드 교환: 잔액·재고·활성여부 확인 후 원자적으로 차감 (조건 위반 시 신청 자체를 막음)
CREATE OR REPLACE FUNCTION guard_redemption()
RETURNS TRIGGER AS $$
DECLARE
  bal int;
  r_cost int;
  r_stock int;
  r_active boolean;
  r_title text;
BEGIN
  SELECT nadaeum INTO bal FROM profiles WHERE id = NEW.user_id;
  SELECT cost, stock, active, title INTO r_cost, r_stock, r_active, r_title FROM rewards WHERE id = NEW.reward_id;
  IF r_cost IS NULL THEN
    RAISE EXCEPTION '존재하지 않는 리워드예요';
  END IF;
  IF NOT r_active THEN
    RAISE EXCEPTION '지금은 교환할 수 없는 리워드예요';
  END IF;
  IF r_stock <= 0 THEN
    RAISE EXCEPTION '재고가 없어요';
  END IF;
  IF COALESCE(bal,0) < r_cost THEN
    RAISE EXCEPTION '나다움 포인트가 부족해요';
  END IF;
  UPDATE profiles SET nadaeum = nadaeum - r_cost WHERE id = NEW.user_id;
  UPDATE rewards SET stock = stock - 1 WHERE id = NEW.reward_id;
  INSERT INTO nadaeum_log(user_id, amount, reason) VALUES (NEW.user_id, -r_cost, '리워드 교환: ' || r_title);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_guard_redemption ON reward_redemptions;
CREATE TRIGGER trg_guard_redemption
  BEFORE INSERT ON reward_redemptions
  FOR EACH ROW EXECUTE FUNCTION guard_redemption();

-- 관리자가 다른 참가자에게 수동으로 포인트를 지급/기록할 수 있도록 허용
CREATE POLICY "nadaeum_admin_insert" ON nadaeum_log FOR INSERT WITH CHECK (is_admin());

-- =====================================================
-- [마이그레이션 2026-07-14d] 나다움 포인트 소멸기간 (적립 후 3개월)
-- nadaeum_log를 장부 삼아 선입선출로 계산: "3개월 지난 적립 총액 − 지금까지
-- 쓴 총액(교환·소멸 포함)"의 초과분을 매일 자정에 소멸 처리.
-- 소멸 내역도 음수 로그로 남아서 다음 실행 때 이중 소멸되지 않음(멱등).
-- 전제: 모든 적립이 nadaeum_log에 기록돼야 함 — 인증(트리거)·교환(트리거)·
-- 수동지급(admin)은 이미 기록 중, 댓글/후기는 index.html earnNadaeum에서 기록 추가함.
-- =====================================================

-- 소멸기간 도입 전에 쌓인 잔액은 로그가 없으므로 현재 시점 적립분으로 백필
-- (= 기존 보유분도 오늘부터 3개월 뒤 소멸 대상이 됨)
INSERT INTO nadaeum_log(user_id, amount, reason)
SELECT id, nadaeum, '기존 적립분 (소멸기간 도입 시점 백필)'
FROM profiles WHERE nadaeum > 0;

CREATE OR REPLACE FUNCTION expire_nadaeum()
RETURNS void AS $$
DECLARE
  u RECORD;
  e_old int;
  spent int;
  exp int;
BEGIN
  FOR u IN SELECT id, nadaeum FROM profiles WHERE nadaeum > 0 LOOP
    -- 3개월 지난 적립 총액
    SELECT COALESCE(SUM(amount),0) INTO e_old FROM nadaeum_log
     WHERE user_id = u.id AND amount > 0 AND created_at < now() - interval '3 months';
    -- 지금까지 쓴 총액 (교환 차감 + 과거 소멸분, 음수 로그의 절댓값 합)
    SELECT COALESCE(-SUM(amount),0) INTO spent FROM nadaeum_log
     WHERE user_id = u.id AND amount < 0;
    exp := LEAST(u.nadaeum, GREATEST(0, e_old - spent));
    IF exp > 0 THEN
      UPDATE profiles SET nadaeum = nadaeum - exp WHERE id = u.id;
      INSERT INTO nadaeum_log(user_id, amount, reason)
      VALUES (u.id, -exp, '포인트 소멸 (적립 후 3개월 경과)');
    END IF;
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 매일 00:10 실행 (이미 등록돼 있으면 교체)
SELECT cron.unschedule('hankkut-nadaeum-expiry')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'hankkut-nadaeum-expiry');
SELECT cron.schedule('hankkut-nadaeum-expiry', '10 0 * * *', 'SELECT expire_nadaeum()');
