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
