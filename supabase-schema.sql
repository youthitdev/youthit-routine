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

-- =====================================================
-- [마이그레이션 2026-07-14e] 완주 지급 순간 푸시 알림
-- 완주 기준(2/3) 최초 달성으로 나다움이 일괄 지급되는 순간,
-- 루틴명과 지급 총액을 푸시로 알림. 완주 후 추가 인증(+10)은 알림 없음(피로 방지).
-- =====================================================
CREATE OR REPLACE FUNCTION on_cert_nadaeum_payout()
RETURNS TRIGGER AS $$
DECLARE
  cnt int;
  r_start date;
  r_end date;
  r_title text;
  day_count int;
  cert_goal int;
  paid boolean;
BEGIN
  SELECT count(*) INTO cnt FROM certifications WHERE routine_id = NEW.routine_id AND user_id = NEW.user_id;
  SELECT start_date, end_date, title INTO r_start, r_end, r_title FROM routines WHERE id = NEW.routine_id;
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
    PERFORM notify_push(
      NEW.user_id,
      '🎉 완주 기준 달성!',
      '"' || coalesce(r_title, '루틴') || '"에서 나다움 ' || (cnt * 10) || 'N이 지급됐어요. 상점에서 리워드로 교환해보세요!'
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- [마이그레이션 2026-07-14f] 탈퇴 익명 로그 + 운영진 알림
-- delete-account가 개인정보 포함 완전 삭제하는 방침은 유지하되,
-- "몇 명이 언제 탈퇴했는지"만 남기는 익명 로그(역할+시각, 이름/연락처 없음)와
-- 관리자 푸시 알림을 추가. insert는 Edge Function(service role)만 수행.
-- =====================================================
CREATE TABLE IF NOT EXISTS withdrawal_log (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  role       text,
  withdrew_at timestamptz DEFAULT now()
);
ALTER TABLE withdrawal_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "wl_admin_select" ON withdrawal_log FOR SELECT USING (is_admin());
-- INSERT 정책 없음: service role(Edge Function)만 기록 가능

-- 관리자 전원에게 푸시 (탈퇴 등 운영 알림용)
CREATE OR REPLACE FUNCTION notify_admins(push_title text, push_body text)
RETURNS void AS $$
DECLARE a RECORD;
BEGIN
  FOR a IN SELECT id FROM auth.users WHERE email IN ('dev@youthvoice.or.kr','yv@youthvoice.or.kr') LOOP
    PERFORM notify_push(a.id, push_title, push_body);
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- [마이그레이션 2026-07-15] 카카오 로그인 대응 — 소셜 가입 시 동의 시점 보정
-- 이메일 가입은 폼에서 동의 체크 후 가입하므로 가입 시각 = 동의 시각이지만,
-- 카카오 OAuth 가입은 동의 전에 계정이 먼저 생기므로 privacy_agreed_at을
-- NULL로 뒀다가 추가 정보 입력 화면(동의 체크 포함)에서 클라이언트가 채움.
-- birth_date 메타 존재 여부로 이메일 가입(폼 경유)인지 구분.
-- =====================================================
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO profiles (id, name, role, real_name, birth_date, phone, region_sido, region_sigugun, school_status, kkutjjang_status, privacy_agreed_at, marketing_agreed)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', NEW.raw_user_meta_data->>'full_name', '익명'),
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
    CASE WHEN NULLIF(NEW.raw_user_meta_data->>'birth_date','') IS NOT NULL THEN now() ELSE NULL END,
    COALESCE((NEW.raw_user_meta_data->>'marketing_agreed')::boolean, false)
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- [마이그레이션 2026-07-17] 홈 화면 배너 (루틴 홍보/공지/외부 링크)
-- 관리자가 등록·활성화/비활성화·삭제. 홈 화면엔 active=true인 것 중
-- sort_order가 가장 작은(우선순위 높은) 배너 1개만 노출.
-- =====================================================
CREATE TABLE IF NOT EXISTS banners (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  title       text NOT NULL,
  body        text,
  image_url   text,
  link_url    text,
  active      boolean NOT NULL DEFAULT true,
  sort_order  integer NOT NULL DEFAULT 0,
  created_by  uuid REFERENCES auth.users(id),
  created_at  timestamptz DEFAULT now()
);
ALTER TABLE banners ENABLE ROW LEVEL SECURITY;
CREATE POLICY "banners_select" ON banners FOR SELECT USING (active = true OR is_admin());
CREATE POLICY "banners_admin_insert" ON banners FOR INSERT WITH CHECK (is_admin());
CREATE POLICY "banners_admin_update" ON banners FOR UPDATE USING (is_admin());
CREATE POLICY "banners_admin_delete" ON banners FOR DELETE USING (is_admin());

-- =====================================================
-- [마이그레이션 2026-07-17b] 배너 이미지 업로드 버킷
-- =====================================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('banner-images', 'banner-images', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "banner_images_insert_admin" ON storage.objects;
CREATE POLICY "banner_images_insert_admin" ON storage.objects FOR INSERT WITH CHECK (
  bucket_id = 'banner-images' AND is_admin()
);
DROP POLICY IF EXISTS "banner_images_select_all" ON storage.objects;
CREATE POLICY "banner_images_select_all" ON storage.objects FOR SELECT USING (
  bucket_id = 'banner-images'
);
DROP POLICY IF EXISTS "banner_images_delete_admin" ON storage.objects;
CREATE POLICY "banner_images_delete_admin" ON storage.objects FOR DELETE USING (
  bucket_id = 'banner-images' AND is_admin()
);

-- =====================================================
-- [마이그레이션 2026-07-21] 서류 승인·끗짱 가입 승인 알림
-- 루틴 참여 승인은 이미 알림이 가고 있음(on_participant_status_change).
-- 학교밖청소년 서류 승인, 끗짱 가입 승인은 알림이 없어서 추가.
-- guard 트리거(BEFORE UPDATE)와는 분리된 별도 AFTER UPDATE 트리거.
-- =====================================================
CREATE OR REPLACE FUNCTION on_verify_status_notify()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.verify_status IS DISTINCT FROM OLD.verify_status AND NEW.verify_status = 'approved' THEN
    PERFORM notify_push(NEW.id, '학교밖청소년 인증 완료! ✅', '서류 심사가 승인됐어요. 학교밖청소년 전용 루틴에도 참여할 수 있어요.');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
DROP TRIGGER IF EXISTS trg_verify_status_notify ON profiles;
CREATE TRIGGER trg_verify_status_notify AFTER UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION on_verify_status_notify();

CREATE OR REPLACE FUNCTION on_kkutjjang_status_notify()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.kkutjjang_status IS DISTINCT FROM OLD.kkutjjang_status AND NEW.kkutjjang_status = 'approved' THEN
    PERFORM notify_push(NEW.id, '끗짱 가입이 승인됐어요! 🎉', '이제 루틴을 배정받아 활동할 수 있어요.');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
DROP TRIGGER IF EXISTS trg_kkutjjang_status_notify ON profiles;
CREATE TRIGGER trg_kkutjjang_status_notify AFTER UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION on_kkutjjang_status_notify();

-- =====================================================
-- [마이그레이션 2026-07-22] 커뮤니티 게시글 댓글
-- cert_comments와 동일한 패턴 (댓글 좋아요는 없음, 삭제는 본인/관리자만).
-- 게시글 작성자에게 댓글 알림도 cert_comment_push와 동일하게 추가.
-- =====================================================
CREATE TABLE IF NOT EXISTS post_comments (
  id          bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  post_id     bigint REFERENCES posts(id) ON DELETE CASCADE,
  user_id     uuid   REFERENCES auth.users ON DELETE CASCADE,
  content     text   NOT NULL,
  created_at  timestamptz DEFAULT now()
);
ALTER TABLE post_comments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pc_select" ON post_comments FOR SELECT USING (true);
CREATE POLICY "pc_insert" ON post_comments FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "pc_delete" ON post_comments FOR DELETE USING (auth.uid() = user_id OR is_admin());

CREATE OR REPLACE FUNCTION on_post_comment_push()
RETURNS TRIGGER AS $$
DECLARE
  post_owner uuid;
  commenter_name text;
BEGIN
  SELECT author_id INTO post_owner FROM posts WHERE id = NEW.post_id;
  IF post_owner IS NULL OR post_owner = NEW.user_id THEN RETURN NEW; END IF;
  SELECT name INTO commenter_name FROM profiles WHERE id = NEW.user_id;
  PERFORM notify_push(
    post_owner,
    '💬 내 글에 댓글이 달렸어요',
    coalesce(commenter_name,'누군가') || ': ' || left(coalesce(NEW.content,''), 40) || CASE WHEN length(coalesce(NEW.content,'')) > 40 THEN '…' ELSE '' END
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_post_comment_push ON post_comments;
CREATE TRIGGER trg_post_comment_push
  AFTER INSERT ON post_comments
  FOR EACH ROW EXECUTE FUNCTION on_post_comment_push();

-- =====================================================
-- [마이그레이션 2026-07-22b] 끗짱 "콕 찌르기" (미인증 청소년 응원)
-- 담당 끗짱이 자기 루틴의 미인증 참여자에게 응원 푸시를 보냄.
-- (routine_id, to_user, poke_date) unique로 하루 한 명당 한 번만 허용
-- — 클라이언트는 unique_violation(23505)을 잡아서 안내 메시지만 보여줌.
-- =====================================================
CREATE TABLE IF NOT EXISTS pokes (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  routine_id  bigint REFERENCES routines(id) ON DELETE CASCADE,
  from_user   uuid   REFERENCES auth.users ON DELETE CASCADE,
  to_user     uuid   REFERENCES auth.users ON DELETE CASCADE,
  poke_date   date   NOT NULL DEFAULT current_date,
  created_at  timestamptz DEFAULT now(),
  UNIQUE (routine_id, to_user, poke_date)
);
ALTER TABLE pokes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pokes_select" ON pokes FOR SELECT USING (
  auth.uid() = from_user OR auth.uid() = to_user OR is_admin()
);
CREATE POLICY "pokes_insert" ON pokes FOR INSERT WITH CHECK (
  auth.uid() = from_user AND
  EXISTS (SELECT 1 FROM routines r WHERE r.id = routine_id AND (r.led_by = auth.uid() OR is_admin()))
);

CREATE OR REPLACE FUNCTION on_poke_push()
RETURNS TRIGGER AS $$
DECLARE
  poker_name text;
  r_title text;
BEGIN
  SELECT name INTO poker_name FROM profiles WHERE id = NEW.from_user;
  SELECT title INTO r_title FROM routines WHERE id = NEW.routine_id;
  PERFORM notify_push(
    NEW.to_user,
    '👋 콕! 응원이 왔어요',
    coalesce(poker_name,'끗짱') || '님이 "' || coalesce(r_title,'루틴') || '"에서 응원을 보냈어요. 오늘 한 끗 남겨볼까요?'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_poke_push ON pokes;
CREATE TRIGGER trg_poke_push
  AFTER INSERT ON pokes
  FOR EACH ROW EXECUTE FUNCTION on_poke_push();

-- =====================================================
-- [마이그레이션 2026-07-22c] 인앱 알림 내역함
-- 홈 화면 알림벨이 "알림 설정"만 열던 문제 — 실제 알림 목록이 없어서였음.
-- notify_push()를 거치는 모든 알림(승인/거절/좋아요/댓글/폐강/완주지급/
-- 콕찌르기/탈퇴 등)이 자동으로 여기 쌓이도록 notify_push() 자체에서 기록.
-- 기존 호출부(트리거 10여 곳)는 하나도 안 건드림.
-- =====================================================
CREATE TABLE IF NOT EXISTS notifications (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id     uuid   REFERENCES auth.users ON DELETE CASCADE,
  title       text,
  body        text,
  read        boolean NOT NULL DEFAULT false,
  created_at  timestamptz DEFAULT now()
);
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "notif_select_own" ON notifications FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "notif_update_own" ON notifications FOR UPDATE USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION notify_push(target_user uuid, push_title text, push_body text)
RETURNS void AS $$
DECLARE
  sr_key text;
BEGIN
  INSERT INTO notifications(user_id, title, body) VALUES (target_user, push_title, push_body);
  SELECT decrypted_secret INTO sr_key FROM vault.decrypted_secrets WHERE name = 'sr_key_for_push';
  IF sr_key IS NULL THEN RETURN; END IF;  -- 키 미설정 시 푸시만 조용히 스킵 (인앱 내역은 이미 기록됨)
  PERFORM net.http_post(
    url := 'https://ynqvhsffoesjzefitafv.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || sr_key),
    body := jsonb_build_object('user_id', target_user, 'title', push_title, 'body', push_body, 'url', '/youthit-routine/')
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 루틴 참여 승인 시 알림이 안 온다는 QA 리포트 확인 — 코드 리뷰 결과 트리거 자체엔
-- 결함을 못 찾았음(로직 정확). 혹시 운영 DB에 트리거가 누락/드리프트됐을 가능성에
-- 대비해 동일 정의로 안전하게 재실행(멱등, DROP 후 재생성이라 부작용 없음).
CREATE OR REPLACE FUNCTION on_participant_status_change()
RETURNS TRIGGER AS $$
DECLARE r_title text;
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

-- =====================================================
-- [마이그레이션 2026-07-22d] nadaeum/role 직접 변조 보안 구멍 수정
-- 코드 리뷰로 발견: profiles_update RLS 정책이 auth.uid()=id만 체크해서
-- 로그인 사용자가 REST API로 자기 nadaeum(포인트)이나 role을 직접 아무 값으로나
-- 바꿀 수 있었음(verify_status/kkutjjang_status는 이미 가드 트리거로 보호됨).
-- 특히 댓글/후기 나다움은 클라이언트가 profiles.nadaeum을 직접 update()하는
-- 구조였어서, 실제 댓글/후기 없이도 포인트를 무한정 올릴 수 있는 취약점이었음.
--
-- 수정 방향: 인증(cert) 지급과 동일하게 댓글/후기 나다움도 서버 트리거가
-- 실제 insert(cert_comments/post_comments/posts) 건수를 기준으로 지급하도록
-- 옮기고, profiles.nadaeum/role은 "신뢰된 서버 경로"에서만 바뀌도록 가드.
-- =====================================================

-- 1) 트랜잭션 로컬 플래그로 "신뢰된 나다움 변경"임을 표시하는 헬퍼
--    (기존 지급/차감 함수들이 이 함수를 호출한 뒤에만 profiles.nadaeum을 바꾸도록)
CREATE OR REPLACE FUNCTION _mark_nadaeum_trusted() RETURNS void AS $$
  SELECT set_config('app.nadaeum_trusted', 'true', true);
$$ LANGUAGE sql;

-- 2) 본인이 nadaeum/role을 직접 바꾸지 못하게 가드
--    - nadaeum: 관리자이거나, 신뢰된 서버 함수(트리거)를 거친 변경만 허용
--    - role: 관리자이거나, 최초 가입 완료 이전(실명/생년월일/휴대폰이 아직 비어있는
--            소셜 로그인 추가정보 입력 단계, doCompleteProfile())에서 한 번만 허용
CREATE OR REPLACE FUNCTION guard_nadaeum_role() RETURNS TRIGGER AS $$
BEGIN
  IF NEW.nadaeum IS DISTINCT FROM OLD.nadaeum THEN
    IF NOT is_admin() AND current_setting('app.nadaeum_trusted', true) IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION '나다움 포인트는 실제 활동을 통해서만 적립/차감돼요';
    END IF;
  END IF;
  IF NEW.role IS DISTINCT FROM OLD.role THEN
    IF NOT is_admin() AND NOT (OLD.real_name IS NULL AND OLD.birth_date IS NULL AND OLD.phone IS NULL) THEN
      RAISE EXCEPTION '역할은 최초 가입 완료 시점 이후에는 변경할 수 없어요';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
DROP TRIGGER IF EXISTS trg_guard_nadaeum_role ON profiles;
CREATE TRIGGER trg_guard_nadaeum_role BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION guard_nadaeum_role();

-- 3) 기존 지급/차감 함수들이 신뢰 플래그를 세우도록 재정의 (로직 자체는 동일)
CREATE OR REPLACE FUNCTION on_cert_nadaeum_payout()
RETURNS TRIGGER AS $$
DECLARE
  cnt int;
  r_start date;
  r_end date;
  r_title text;
  day_count int;
  cert_goal int;
  paid boolean;
BEGIN
  SELECT count(*) INTO cnt FROM certifications WHERE routine_id = NEW.routine_id AND user_id = NEW.user_id;
  SELECT start_date, end_date, title INTO r_start, r_end, r_title FROM routines WHERE id = NEW.routine_id;
  day_count := GREATEST(1, COALESCE((r_end - r_start), 20) + 1);
  cert_goal := GREATEST(1, FLOOR(day_count * 2.0 / 3)::int);

  SELECT nadaeum_paid INTO paid FROM routine_participants WHERE routine_id = NEW.routine_id AND user_id = NEW.user_id;

  IF paid THEN
    PERFORM _mark_nadaeum_trusted();
    UPDATE profiles SET nadaeum = nadaeum + 10 WHERE id = NEW.user_id;
    INSERT INTO nadaeum_log(user_id, amount, reason) VALUES (NEW.user_id, 10, '루틴 인증 (완주 후 추가 인증)');
  ELSIF cnt >= cert_goal THEN
    PERFORM _mark_nadaeum_trusted();
    UPDATE profiles SET nadaeum = nadaeum + (cnt * 10) WHERE id = NEW.user_id;
    INSERT INTO nadaeum_log(user_id, amount, reason) VALUES (NEW.user_id, cnt * 10, '루틴 완주 기준 달성 (인증 ' || cnt || '회 적립분 일괄 지급)');
    UPDATE routine_participants SET nadaeum_paid = true WHERE routine_id = NEW.routine_id AND user_id = NEW.user_id;
    PERFORM notify_push(
      NEW.user_id,
      '🎉 완주 기준 달성!',
      '"' || coalesce(r_title, '루틴') || '"에서 나다움 ' || (cnt * 10) || 'N이 지급됐어요. 상점에서 리워드로 교환해보세요!'
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

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
  PERFORM _mark_nadaeum_trusted();
  UPDATE profiles SET nadaeum = nadaeum - r_cost WHERE id = NEW.user_id;
  UPDATE rewards SET stock = stock - 1 WHERE id = NEW.reward_id;
  INSERT INTO nadaeum_log(user_id, amount, reason) VALUES (NEW.user_id, -r_cost, '리워드 교환: ' || r_title);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION expire_nadaeum()
RETURNS void AS $$
DECLARE
  u RECORD;
  e_old int;
  spent int;
  exp int;
BEGIN
  FOR u IN SELECT id, nadaeum FROM profiles WHERE nadaeum > 0 LOOP
    SELECT COALESCE(SUM(amount),0) INTO e_old FROM nadaeum_log
     WHERE user_id = u.id AND amount > 0 AND created_at < now() - interval '3 months';
    SELECT COALESCE(-SUM(amount),0) INTO spent FROM nadaeum_log
     WHERE user_id = u.id AND amount < 0;
    exp := LEAST(u.nadaeum, GREATEST(0, e_old - spent));
    IF exp > 0 THEN
      PERFORM _mark_nadaeum_trusted();
      UPDATE profiles SET nadaeum = nadaeum - exp WHERE id = u.id;
      INSERT INTO nadaeum_log(user_id, amount, reason)
      VALUES (u.id, -exp, '포인트 소멸 (적립 후 3개월 경과)');
    END IF;
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4) 댓글 나다움(+1, 하루 최대 5)을 실제 댓글 insert 기준으로 서버가 지급
--    (cert_comments·post_comments 공용 — 오늘 지급된 로그 건수로 상한 체크)
CREATE OR REPLACE FUNCTION award_comment_nadaeum() RETURNS TRIGGER AS $$
DECLARE today_count int;
BEGIN
  SELECT count(*) INTO today_count FROM nadaeum_log
   WHERE user_id = NEW.user_id AND reason = '댓글 작성' AND created_at >= date_trunc('day', now());
  IF today_count < 5 THEN
    PERFORM _mark_nadaeum_trusted();
    UPDATE profiles SET nadaeum = nadaeum + 1 WHERE id = NEW.user_id;
    INSERT INTO nadaeum_log(user_id, amount, reason) VALUES (NEW.user_id, 1, '댓글 작성');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
DROP TRIGGER IF EXISTS trg_cert_comment_nadaeum ON cert_comments;
CREATE TRIGGER trg_cert_comment_nadaeum AFTER INSERT ON cert_comments
  FOR EACH ROW EXECUTE FUNCTION award_comment_nadaeum();
DROP TRIGGER IF EXISTS trg_post_comment_nadaeum ON post_comments;
CREATE TRIGGER trg_post_comment_nadaeum AFTER INSERT ON post_comments
  FOR EACH ROW EXECUTE FUNCTION award_comment_nadaeum();

-- 5) 후기 나다움(+30, 루틴당 1회)을 실제 게시글(posts, type='review') insert 기준으로 지급
--    ("이미 이 루틴을 리뷰한 적 있는지"를 클라이언트 로컬스토리지가 아니라 DB로 판단)
CREATE OR REPLACE FUNCTION award_review_nadaeum() RETURNS TRIGGER AS $$
DECLARE prior_count int;
BEGIN
  IF NEW.type <> 'review' OR NEW.routine_id IS NULL THEN RETURN NEW; END IF;
  SELECT count(*) INTO prior_count FROM posts
   WHERE type = 'review' AND routine_id = NEW.routine_id AND author_id = NEW.author_id AND id <> NEW.id;
  IF prior_count = 0 THEN
    PERFORM _mark_nadaeum_trusted();
    UPDATE profiles SET nadaeum = nadaeum + 30 WHERE id = NEW.author_id;
    INSERT INTO nadaeum_log(user_id, amount, reason) VALUES (NEW.author_id, 30, '후기 작성');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
DROP TRIGGER IF EXISTS trg_award_review_nadaeum ON posts;
CREATE TRIGGER trg_award_review_nadaeum AFTER INSERT ON posts
  FOR EACH ROW EXECUTE FUNCTION award_review_nadaeum();

-- =====================================================
-- [마이그레이션 2026-07-22e] 배지/업적 컬렉션 (MVP 6종)
-- 첫 인증·첫 완주·루틴 3개 완주·연속 7일·연속 30일·인증 50회.
-- 나다움과 마찬가지로 클라이언트가 스스로 지급 조건을 판단하면 위조 가능하므로,
-- 실제 certifications/routine_participants 변화를 트리거가 감지해 서버에서만 지급.
-- =====================================================

CREATE TABLE IF NOT EXISTS user_badges (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id     uuid REFERENCES auth.users ON DELETE CASCADE,
  badge_key   text NOT NULL,
  earned_at   timestamptz DEFAULT now(),
  UNIQUE(user_id, badge_key)
);
ALTER TABLE user_badges ENABLE ROW LEVEL SECURITY;
CREATE POLICY "user_badges_select_own" ON user_badges FOR SELECT USING (auth.uid() = user_id);
-- INSERT 정책 없음: 트리거(SECURITY DEFINER)만 기록 가능

-- 배지 지급 + 최초 지급 시에만 축하 푸시 (ON CONFLICT DO NOTHING이라 중복 지급 안 됨)
CREATE OR REPLACE FUNCTION award_badge(p_user uuid, p_key text, p_title text) RETURNS void AS $$
BEGIN
  INSERT INTO user_badges(user_id, badge_key) VALUES (p_user, p_key)
  ON CONFLICT (user_id, badge_key) DO NOTHING;
  IF FOUND THEN
    PERFORM notify_push(p_user, '🏅 새 배지 획득!', p_title || ' 배지를 획득했어요! MY탭에서 확인해보세요.');
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 오늘을 포함해 연속으로 인증한 일수 (gaps-and-islands: 날짜 그룹핑)
CREATE OR REPLACE FUNCTION _current_cert_streak(p_user uuid) RETURNS int AS $$
DECLARE result int;
BEGIN
  WITH days AS (
    SELECT DISTINCT DATE(created_at) AS d FROM certifications WHERE user_id = p_user
  ), ranked AS (
    SELECT d, d - (ROW_NUMBER() OVER (ORDER BY d))::int AS grp FROM days
  )
  SELECT count(*) INTO result FROM ranked
  WHERE grp = (SELECT grp FROM ranked WHERE d = CURRENT_DATE LIMIT 1);
  RETURN COALESCE(result, 0);
END;
$$ LANGUAGE plpgsql STABLE;

-- 인증 저장 시: 첫 인증 / 누적 50회 / 연속 7일·30일 배지 체크
CREATE OR REPLACE FUNCTION award_cert_badges() RETURNS TRIGGER AS $$
DECLARE total_certs int; streak int;
BEGIN
  SELECT count(*) INTO total_certs FROM certifications WHERE user_id = NEW.user_id;
  IF total_certs = 1 THEN PERFORM award_badge(NEW.user_id, 'first_cert', '📸 첫 인증'); END IF;
  IF total_certs = 50 THEN PERFORM award_badge(NEW.user_id, 'cert_50', '💯 인증 50회'); END IF;
  streak := _current_cert_streak(NEW.user_id);
  IF streak = 7 THEN PERFORM award_badge(NEW.user_id, 'streak_7', '🔥 연속 인증 7일'); END IF;
  IF streak = 30 THEN PERFORM award_badge(NEW.user_id, 'streak_30', '🔥 연속 인증 30일'); END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
DROP TRIGGER IF EXISTS trg_award_cert_badges ON certifications;
CREATE TRIGGER trg_award_cert_badges AFTER INSERT ON certifications
  FOR EACH ROW EXECUTE FUNCTION award_cert_badges();

-- 완주(나다움 일괄지급 대상이 되는 순간 = 2/3 기준 최초 달성) 시: 첫 완주 / 3개 완주 배지 체크
-- on_cert_nadaeum_payout()이 이 순간 routine_participants.nadaeum_paid를 false→true로 바꾸므로 그 전환을 감지
CREATE OR REPLACE FUNCTION award_completion_badges() RETURNS TRIGGER AS $$
DECLARE done_count int;
BEGIN
  SELECT count(*) INTO done_count FROM routine_participants WHERE user_id = NEW.user_id AND nadaeum_paid = true;
  IF done_count = 1 THEN PERFORM award_badge(NEW.user_id, 'first_complete', '🌱 첫 완주'); END IF;
  IF done_count = 3 THEN PERFORM award_badge(NEW.user_id, 'complete_3', '🏆 루틴 3개 완주'); END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
DROP TRIGGER IF EXISTS trg_award_completion_badges ON routine_participants;
CREATE TRIGGER trg_award_completion_badges AFTER UPDATE ON routine_participants
  FOR EACH ROW WHEN (NEW.nadaeum_paid IS DISTINCT FROM OLD.nadaeum_paid AND NEW.nadaeum_paid = true)
  EXECUTE FUNCTION award_completion_badges();

-- =====================================================
-- [마이그레이션 2026-07-22f] 루틴 참여 신청 자격을 서버에서도 검증
-- 지금까지는 "끗짱은 신청 UI 자체가 없음"·"학교밖 전용은 verify_status 승인 전엔
-- 신청 버튼이 막힘" 둘 다 클라이언트 쪽 방어뿐이었음(rp_insert RLS는
-- auth.uid()=user_id만 체크). REST API로 직접 routine_participants insert를
-- 호출하면 끗짱 계정도, 미승인 재학 청소년도 신청이 그대로 들어갈 수 있었던 구멍.
-- =====================================================
CREATE OR REPLACE FUNCTION guard_participant_apply() RETURNS TRIGGER AS $$
DECLARE u_role text; u_verify text; r_elig text;
BEGIN
  SELECT role, verify_status INTO u_role, u_verify FROM profiles WHERE id = NEW.user_id;
  IF u_role = 'kkutjjang' THEN
    RAISE EXCEPTION '끗짱은 루틴에 참여 신청할 수 없어요';
  END IF;
  SELECT eligibility INTO r_elig FROM routines WHERE id = NEW.routine_id;
  IF r_elig = 'out_of_school' AND COALESCE(u_verify,'none') <> 'approved' THEN
    RAISE EXCEPTION '학교밖청소년 확인서 승인 후 신청할 수 있어요';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
DROP TRIGGER IF EXISTS trg_guard_participant_apply ON routine_participants;
CREATE TRIGGER trg_guard_participant_apply BEFORE INSERT ON routine_participants
  FOR EACH ROW EXECUTE FUNCTION guard_participant_apply();

-- =====================================================
-- [마이그레이션 2026-07-23] 게시글(posts) 수정 기능 추가
-- QA 이슈트래커: 커뮤니티 게시글에 수정 기능이 없었음. UPDATE RLS 정책 자체가
-- 아예 없었어서(SELECT/INSERT/DELETE만 존재) 추가하고, 작성자/관리자 여부와
-- 무관하게 type·author_id·routine_id는 못 바꾸도록(제목/내용만 수정 가능) 가드.
-- =====================================================
CREATE POLICY "posts_update" ON posts FOR UPDATE USING (auth.uid() = author_id OR is_admin());

CREATE OR REPLACE FUNCTION guard_post_update() RETURNS TRIGGER AS $$
BEGIN
  IF NOT is_admin() AND (
    NEW.author_id IS DISTINCT FROM OLD.author_id
    OR NEW.type IS DISTINCT FROM OLD.type
    OR NEW.routine_id IS DISTINCT FROM OLD.routine_id
  ) THEN
    RAISE EXCEPTION '게시글의 작성자·종류·연결된 루틴은 수정할 수 없어요';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
DROP TRIGGER IF EXISTS trg_guard_post_update ON posts;
CREATE TRIGGER trg_guard_post_update BEFORE UPDATE ON posts
  FOR EACH ROW EXECUTE FUNCTION guard_post_update();

-- =====================================================
-- [마이그레이션 2026-07-24] 루틴 모집기간/진행기간 분리
-- 지금까지는 start_date 하나가 "모집 마감일"(모집중일 때 D-day 기준)과
-- "진행 시작일"(진행중일 때 D-day·기간 기준) 두 역할을 동시에 하고 있었음.
-- recruit_end_date를 별도로 둬서 모집 마감과 실제 시작일 사이에 간격을
-- 둘 수 있게 함(예: OT/준비 기간). 기존 루틴은 NULL로 남고, 클라이언트가
-- 화면 표시 시 NULL이면 start_date로 폴백해서 기존 동작 그대로 유지.
-- =====================================================
ALTER TABLE routines ADD COLUMN IF NOT EXISTS recruit_end_date date;

-- =====================================================
-- [마이그레이션 2026-07-24b] 알림 배너 클릭 시 MY탭으로 이동
-- QA: 알림(승인·거절·배지·나다움 등 대부분 MY탭에서 확인하는 내용) 클릭해도
-- 그냥 앱만 열리고 아무 데도 이동을 안 함 — notify_push()가 모든 알림에
-- 항상 같은 루트 URL만 써서 그랬음. MY탭으로 가는 쿼리를 붙임(클라이언트가
-- ?tab=my를 읽어서 로그인 후 자동으로 MY탭 전환, service-worker.js도 이미
-- 열려있는 창을 새 URL로 navigate하도록 같이 수정함).
-- =====================================================
CREATE OR REPLACE FUNCTION notify_push(target_user uuid, push_title text, push_body text)
RETURNS void AS $$
DECLARE
  sr_key text;
BEGIN
  INSERT INTO notifications(user_id, title, body) VALUES (target_user, push_title, push_body);
  SELECT decrypted_secret INTO sr_key FROM vault.decrypted_secrets WHERE name = 'sr_key_for_push';
  IF sr_key IS NULL THEN RETURN; END IF;
  PERFORM net.http_post(
    url := 'https://ynqvhsffoesjzefitafv.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || sr_key),
    body := jsonb_build_object('user_id', target_user, 'title', push_title, 'body', push_body, 'url', '/youthit-routine/?tab=my')
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- [마이그레이션 2026-07-24c] 모집 시작일 추가 + 모집 기간 신청 차단
-- 모집 마감일만 있고 모집 시작일이 없어서 "언제부터 신청받을지"가 없었음.
-- recruit_start_date 신설하고, 신청 자체를 모집 기간(시작일~마감일) 밖에서는
-- 서버에서 막음. 기존 루틴은 두 필드 다 NULL이라 이 검사를 건너뛰어(기존
-- 동작 그대로 유지) 새로 만드는 루틴부터만 실제로 적용됨(폼에서 두 필드를
-- 필수로 받기 시작했으므로).
-- =====================================================
ALTER TABLE routines ADD COLUMN IF NOT EXISTS recruit_start_date date;

CREATE OR REPLACE FUNCTION guard_participant_apply() RETURNS TRIGGER AS $$
DECLARE u_role text; u_verify text; r_elig text; r_start date; r_end date;
BEGIN
  SELECT role, verify_status INTO u_role, u_verify FROM profiles WHERE id = NEW.user_id;
  IF u_role = 'kkutjjang' THEN
    RAISE EXCEPTION '끗짱은 루틴에 참여 신청할 수 없어요';
  END IF;
  SELECT eligibility, recruit_start_date, recruit_end_date INTO r_elig, r_start, r_end FROM routines WHERE id = NEW.routine_id;
  IF r_elig = 'out_of_school' AND COALESCE(u_verify,'none') <> 'approved' THEN
    RAISE EXCEPTION '학교밖청소년 확인서 승인 후 신청할 수 있어요';
  END IF;
  IF r_start IS NOT NULL AND CURRENT_DATE < r_start THEN
    RAISE EXCEPTION '아직 모집 시작 전이에요';
  END IF;
  IF r_end IS NOT NULL AND CURRENT_DATE > r_end THEN
    RAISE EXCEPTION '모집이 마감됐어요';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
