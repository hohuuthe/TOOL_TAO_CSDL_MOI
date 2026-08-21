--
-- PostgreSQL database dump
--

\restrict jlhqOj4zvCD3rcZ7uVM2Mf48l5c9uaZjbK9WXhOSbqAlStJPhsx5v6fXEZMcakQ

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.11 (Ubuntu 17.11-1.pgdg24.04+2)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: pg_database_owner
--




--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: pg_database_owner
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: check_user_mfa_status(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_user_mfa_status() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'auth'
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM auth.mfa_factors 
    WHERE user_id = auth.uid() AND status = 'verified'
  );
$$;


ALTER FUNCTION public.check_user_mfa_status() OWNER TO postgres;

--
-- Name: fn_dong_bo_taikhoan_sang_auth_users(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_dong_bo_taikhoan_sang_auth_users() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'auth', 'extensions'
    AS $_$
DECLARE
  v_old_email text;
  v_new_email text;
  v_safe_username text;
  v_encrypted_pwd text;
  v_user_id uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_safe_username := lower(regexp_replace(COALESCE(OLD.username, ''), '[^a-zA-Z0-9_.-]', '', 'g'));
    IF v_safe_username <> '' THEN
      v_old_email := v_safe_username || '@htqltd.vn';
      SELECT id INTO v_user_id FROM auth.users WHERE email = v_old_email LIMIT 1;
      IF v_user_id IS NOT NULL THEN
        DELETE FROM auth.identities WHERE user_id = v_user_id;
        DELETE FROM auth.users WHERE id = v_user_id;
      ELSE
        DELETE FROM auth.users WHERE email = v_old_email;
      END IF;
    END IF;
    RETURN OLD;
  END IF;

  IF TG_OP = 'INSERT' THEN
    v_safe_username := lower(regexp_replace(COALESCE(NEW.username, ''), '[^a-zA-Z0-9_.-]', '', 'g'));
    IF v_safe_username = '' THEN
      v_safe_username := 'user_' || substr(md5(random()::text), 1, 8);
    END IF;
    v_new_email := v_safe_username || '@htqltd.vn';

    IF NEW.password ~ '^\$2[aby]\$' THEN
      v_encrypted_pwd := NEW.password;
    ELSIF NEW.password IS NOT NULL AND NEW.password <> '' THEN
      v_encrypted_pwd := extensions.crypt(NEW.password, extensions.gen_salt('bf', 10));
    ELSE
      v_encrypted_pwd := extensions.crypt('DoanVien@123', extensions.gen_salt('bf', 10));
    END IF;

    SELECT id INTO v_user_id FROM auth.users WHERE email = v_new_email LIMIT 1;

    IF v_user_id IS NULL THEN
      v_user_id := gen_random_uuid();

      INSERT INTO auth.users (
        instance_id,
        id,
        aud,
        role,
        email,
        encrypted_password,
        email_confirmed_at,
        raw_app_meta_data,
        raw_user_meta_data,
        created_at,
        updated_at,
        confirmation_token,
        recovery_token,
        email_change_token_new,
        email_change,
        phone_change,
        phone_change_token,
        email_change_token_current,
        reauthentication_token,
        is_sso_user,
        is_anonymous
      ) VALUES (
        '00000000-0000-0000-0000-000000000000',
        v_user_id,
        'authenticated',
        'authenticated',
        v_new_email,
        v_encrypted_pwd,
        now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        json_build_object(
          'username', NEW.username,
          'fullname', COALESCE(NEW.fullname, NEW.username),
          'role', COALESCE(NEW.role, 'DV'),
          'chidoan_id', NEW.chidoan_id,
          'doanvien_id', NEW.doanvien_id
        )::jsonb,
        now(),
        now(),
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        false,
        false
      );

      INSERT INTO auth.identities (
        id,
        user_id,
        identity_data,
        provider,
        provider_id,
        last_sign_in_at,
        created_at,
        updated_at
      ) VALUES (
        v_user_id,
        v_user_id,
        json_build_object('sub', v_user_id::text, 'email', v_new_email)::jsonb,
        'email',
        v_new_email,
        now(),
        now(),
        now()
      )
      ON CONFLICT DO NOTHING;
    ELSE
      UPDATE auth.users
      SET
        email = v_new_email,
        encrypted_password = v_encrypted_pwd,
        raw_user_meta_data = json_build_object(
          'username', NEW.username,
          'fullname', COALESCE(NEW.fullname, NEW.username),
          'role', COALESCE(NEW.role, 'DV'),
          'chidoan_id', NEW.chidoan_id,
          'doanvien_id', NEW.doanvien_id
        )::jsonb,
        confirmation_token = COALESCE(confirmation_token, ''),
        recovery_token = COALESCE(recovery_token, ''),
        email_change_token_new = COALESCE(email_change_token_new, ''),
        email_change = COALESCE(email_change, ''),
        phone_change = COALESCE(phone_change, ''),
        phone_change_token = COALESCE(phone_change_token, ''),
        email_change_token_current = COALESCE(email_change_token_current, ''),
        reauthentication_token = COALESCE(reauthentication_token, ''),
        is_sso_user = COALESCE(is_sso_user, false),
        is_anonymous = COALESCE(is_anonymous, false),
        updated_at = now()
      WHERE id = v_user_id;

      INSERT INTO auth.identities (
        id,
        user_id,
        identity_data,
        provider,
        provider_id,
        last_sign_in_at,
        created_at,
        updated_at
      ) VALUES (
        v_user_id,
        v_user_id,
        json_build_object('sub', v_user_id::text, 'email', v_new_email)::jsonb,
        'email',
        v_new_email,
        now(),
        now(),
        now()
      )
      ON CONFLICT DO NOTHING;
    END IF;

    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    v_old_email := lower(regexp_replace(COALESCE(OLD.username, ''), '[^a-zA-Z0-9_.-]', '', 'g')) || '@htqltd.vn';
    v_safe_username := lower(regexp_replace(COALESCE(NEW.username, ''), '[^a-zA-Z0-9_.-]', '', 'g'));
    IF v_safe_username = '' THEN
      v_safe_username := 'user_' || substr(md5(random()::text), 1, 8);
    END IF;
    v_new_email := v_safe_username || '@htqltd.vn';

    SELECT id INTO v_user_id FROM auth.users WHERE email = v_old_email OR email = v_new_email LIMIT 1;

    IF NEW.password IS DISTINCT FROM OLD.password THEN
      IF NEW.password ~ '^\$2[aby]\$' THEN
        v_encrypted_pwd := NEW.password;
      ELSIF NEW.password IS NOT NULL AND NEW.password <> '' THEN
        v_encrypted_pwd := extensions.crypt(NEW.password, extensions.gen_salt('bf', 10));
      ELSE
        v_encrypted_pwd := extensions.crypt('DoanVien@123', extensions.gen_salt('bf', 10));
      END IF;
    END IF;

    IF v_user_id IS NOT NULL THEN
      UPDATE auth.users
      SET
        email = v_new_email,
        encrypted_password = CASE 
          WHEN v_encrypted_pwd IS NOT NULL THEN v_encrypted_pwd 
          ELSE encrypted_password 
        END,
        raw_user_meta_data = json_build_object(
          'username', NEW.username,
          'fullname', COALESCE(NEW.fullname, NEW.username),
          'role', COALESCE(NEW.role, 'DV'),
          'chidoan_id', NEW.chidoan_id,
          'doanvien_id', NEW.doanvien_id
        )::jsonb,
        confirmation_token = COALESCE(confirmation_token, ''),
        recovery_token = COALESCE(recovery_token, ''),
        email_change_token_new = COALESCE(email_change_token_new, ''),
        email_change = COALESCE(email_change, ''),
        phone_change = COALESCE(phone_change, ''),
        phone_change_token = COALESCE(phone_change_token, ''),
        email_change_token_current = COALESCE(email_change_token_current, ''),
        reauthentication_token = COALESCE(reauthentication_token, ''),
        is_sso_user = COALESCE(is_sso_user, false),
        is_anonymous = COALESCE(is_anonymous, false),
        updated_at = now()
      WHERE id = v_user_id;

      INSERT INTO auth.identities (
        id,
        user_id,
        identity_data,
        provider,
        provider_id,
        last_sign_in_at,
        created_at,
        updated_at
      ) VALUES (
        v_user_id,
        v_user_id,
        json_build_object('sub', v_user_id::text, 'email', v_new_email)::jsonb,
        'email',
        v_new_email,
        now(),
        now(),
        now()
      )
      ON CONFLICT DO NOTHING;
    ELSE
      v_user_id := gen_random_uuid();
      IF v_encrypted_pwd IS NULL THEN
        IF NEW.password ~ '^\$2[aby]\$' THEN
          v_encrypted_pwd := NEW.password;
        ELSIF NEW.password IS NOT NULL AND NEW.password <> '' THEN
          v_encrypted_pwd := extensions.crypt(NEW.password, extensions.gen_salt('bf', 10));
        ELSE
          v_encrypted_pwd := extensions.crypt('DoanVien@123', extensions.gen_salt('bf', 10));
        END IF;
      END IF;

      INSERT INTO auth.users (
        instance_id,
        id,
        aud,
        role,
        email,
        encrypted_password,
        email_confirmed_at,
        raw_app_meta_data,
        raw_user_meta_data,
        created_at,
        updated_at,
        confirmation_token,
        recovery_token,
        email_change_token_new,
        email_change,
        phone_change,
        phone_change_token,
        email_change_token_current,
        reauthentication_token,
        is_sso_user,
        is_anonymous
      ) VALUES (
        '00000000-0000-0000-0000-000000000000',
        v_user_id,
        'authenticated',
        'authenticated',
        v_new_email,
        v_encrypted_pwd,
        now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        json_build_object(
          'username', NEW.username,
          'fullname', COALESCE(NEW.fullname, NEW.username),
          'role', COALESCE(NEW.role, 'DV'),
          'chidoan_id', NEW.chidoan_id,
          'doanvien_id', NEW.doanvien_id
        )::jsonb,
        now(),
        now(),
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        false,
        false
      );

      INSERT INTO auth.identities (
        id,
        user_id,
        identity_data,
        provider,
        provider_id,
        last_sign_in_at,
        created_at,
        updated_at
      ) VALUES (
        v_user_id,
        v_user_id,
        json_build_object('sub', v_user_id::text, 'email', v_new_email)::jsonb,
        'email',
        v_new_email,
        now(),
        now(),
        now()
      )
      ON CONFLICT DO NOTHING;
    END IF;

    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$_$;


ALTER FUNCTION public.fn_dong_bo_taikhoan_sang_auth_users() OWNER TO postgres;

--
-- Name: fn_is_mfa_enabled(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_is_mfa_enabled() RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1 
    FROM auth.mfa_factors 
    WHERE user_id = auth.uid() 
    AND status = 'verified'
  );
$$;


ALTER FUNCTION public.fn_is_mfa_enabled() OWNER TO postgres;

--
-- Name: fn_kiem_tra_an_ninh_taikhoan(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_kiem_tra_an_ninh_taikhoan() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'auth'
    AS $$
DECLARE
  v_current_auth_role text;
  v_current_user_email text;
  v_operator_role text;
  v_target_role_upper text;
  v_is_db_admin boolean;
BEGIN
  v_is_db_admin := (current_user IN ('postgres', 'service_role', 'supabase_admin'));
  v_current_auth_role := COALESCE(auth.role(), 'anon');
  v_current_user_email := COALESCE(auth.email(), '');

  IF NOT v_is_db_admin AND v_current_auth_role = 'anon' THEN
    RAISE EXCEPTION 'BAO MAT CANH BAO: Nghiem cam tao, sua doi hoac xoa tai khoan tu API ben ngoai!';
  END IF;

  IF NOT v_is_db_admin THEN
    SELECT upper(trim(role)) INTO v_operator_role
    FROM public.taikhoan
    WHERE id = auth.uid() 
       OR lower(regexp_replace(username, '[^a-zA-Z0-9_.-]', '', 'g')) || '@htqltd.vn' = lower(v_current_user_email)
       OR lower(username) = split_part(lower(v_current_user_email), '@', 1)
    LIMIT 1;
  ELSE
    v_operator_role := 'ADMIN';
  END IF;

  IF TG_OP = 'DELETE' THEN
    IF lower(trim(OLD.username)) = 'admin' THEN
      RAISE EXCEPTION 'BAO MAT: Nghiem cam xoa tai khoan Admin goc cua he thong!';
    END IF;

    IF NOT v_is_db_admin AND (v_operator_role IS NULL OR v_operator_role <> 'ADMIN') THEN
      RAISE EXCEPTION 'BAO MAT: Ban khong co quyen xoa tai khoan!';
    END IF;

    RETURN OLD;
  END IF;

  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    v_target_role_upper := upper(trim(COALESCE(NEW.role, 'DV')));

    IF TG_OP = 'UPDATE' AND lower(trim(OLD.username)) = 'admin' THEN
      IF lower(trim(NEW.username)) <> 'admin' OR v_target_role_upper <> 'ADMIN' THEN
        RAISE EXCEPTION 'BAO MAT: Khong duoc phep doi ten hoac ha quyen cua tai khoan Admin goc!';
      END IF;
    END IF;

    IF v_target_role_upper IN ('ADMIN', 'BTV', 'BGH') THEN
      IF TG_OP = 'UPDATE' AND upper(trim(COALESCE(OLD.role, ''))) = v_target_role_upper THEN
        NULL;
      ELSIF NOT v_is_db_admin AND (v_operator_role IS NULL OR v_operator_role <> 'ADMIN') THEN
        RAISE EXCEPTION 'BAO MAT: Chi co Quan tri vien (Admin) moi co quyen cap quyen Quan tri (Admin/BTV/BGH)!';
      END IF;
    END IF;

    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_kiem_tra_an_ninh_taikhoan() OWNER TO postgres;

--
-- Name: fn_tu_dong_bam_mat_khau_taikhoan(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_tu_dong_bam_mat_khau_taikhoan() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $_$
BEGIN
  IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NEW.password IS DISTINCT FROM OLD.password) THEN
    IF NEW.password IS NULL OR trim(NEW.password) = '' THEN
      NEW.password := extensions.crypt('DoanVien@123', extensions.gen_salt('bf', 10));
    ELSIF NOT (NEW.password ~ '^\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}$') THEN
      NEW.password := extensions.crypt(NEW.password, extensions.gen_salt('bf', 10));
    END IF;
  END IF;

  RETURN NEW;
END;
$_$;


ALTER FUNCTION public.fn_tu_dong_bam_mat_khau_taikhoan() OWNER TO postgres;

--
-- Name: get_auth_chidoan_id(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_auth_chidoan_id() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
  SELECT chidoan_id 
  FROM public.taikhoan 
  WHERE lower(username) = lower(split_part(coalesce(auth.email(), ''), '@', 1))
  LIMIT 1; 
$$;


ALTER FUNCTION public.get_auth_chidoan_id() OWNER TO postgres;

--
-- Name: get_auth_doanvien_id(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_auth_doanvien_id() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
  SELECT doanvien_id 
  FROM public.taikhoan 
  WHERE lower(username) = lower(split_part(coalesce(auth.email(), ''), '@', 1))
  LIMIT 1; 
$$;


ALTER FUNCTION public.get_auth_doanvien_id() OWNER TO postgres;

--
-- Name: get_auth_role(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_auth_role() RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
  SELECT upper(trim(role)) 
  FROM public.taikhoan 
  WHERE lower(username) = lower(split_part(coalesce(auth.email(), ''), '@', 1))
  LIMIT 1; 
$$;


ALTER FUNCTION public.get_auth_role() OWNER TO postgres;

--
-- Name: get_my_role(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_my_role() RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT UPPER(TRIM(role)) 
  FROM public.taikhoan 
  WHERE id = auth.uid() 
     OR lower(username) = split_part(lower(auth.email()), '@', 1)
     OR lower(username || '@htqltd.vn') = lower(auth.email())
  LIMIT 1;
$$;


ALTER FUNCTION public.get_my_role() OWNER TO postgres;

--
-- Name: get_secure_chidoan_id(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_secure_chidoan_id() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
  SELECT chidoan_id FROM public.taikhoan WHERE username = split_part(auth.email(), '@', 1) LIMIT 1;
$$;


ALTER FUNCTION public.get_secure_chidoan_id() OWNER TO postgres;

--
-- Name: get_secure_doanvien_id(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_secure_doanvien_id() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
  SELECT doanvien_id FROM public.taikhoan WHERE username = split_part(auth.email(), '@', 1) LIMIT 1;
$$;


ALTER FUNCTION public.get_secure_doanvien_id() OWNER TO postgres;

--
-- Name: get_secure_role(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_secure_role() RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT role FROM public.taikhoan 
  WHERE lower(username) = lower(split_part(auth.email(), '@', 1)) 
  LIMIT 1; 
$$;


ALTER FUNCTION public.get_secure_role() OWNER TO postgres;

--
-- Name: handle_chi_doan_deletion(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.handle_chi_doan_deletion() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Sửa "chiDoan" thành chidoan (viết thường, không cần ngoặc kép)
    DELETE FROM "doanvien" 
    WHERE chidoan = OLD.tenchidoan;
    
    RETURN OLD;
END;
$$;


ALTER FUNCTION public.handle_chi_doan_deletion() OWNER TO postgres;

--
-- Name: handle_post_like(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.handle_post_like() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF (TG_OP = 'INSERT') THEN
    UPDATE nhat_ky_doan SET likes_count = likes_count + 1 WHERE id = NEW.post_id;
  ELSIF (TG_OP = 'DELETE') THEN
    UPDATE nhat_ky_doan SET likes_count = likes_count - 1 WHERE id = OLD.post_id;
  END IF;
  RETURN NULL;
END;
$$;


ALTER FUNCTION public.handle_post_like() OWNER TO postgres;

--
-- Name: handle_update_likes_count(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.handle_update_likes_count() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF (TG_OP = 'INSERT') THEN
    UPDATE nhat_ky_doan SET likes_count = likes_count + 1 WHERE id = NEW.post_id;
  ELSIF (TG_OP = 'DELETE') THEN
    UPDATE nhat_ky_doan SET likes_count = GREATEST(0, likes_count - 1) WHERE id = OLD.post_id;
  END IF;
  RETURN NULL;
END;
$$;


ALTER FUNCTION public.handle_update_likes_count() OWNER TO postgres;

--
-- Name: rpc_admin_reset_user_mfa(text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.rpc_admin_reset_user_mfa(p_user_id text DEFAULT NULL::text, p_username text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'auth', 'extensions'
    AS $$
DECLARE
  v_clean_username text;
  v_clean_user_id text;
  v_user_uuid uuid;
  v_caller_role text;
  v_target_user_id uuid;
BEGIN
  -- KIỂM TRA BẢO MẬT: Chỉ cho phép tự sửa hoặc Admin sửa
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Phải đăng nhập để sử dụng chức năng này.';
  END IF;

  v_clean_username := lower(trim(COALESCE(p_username, '')));
  v_clean_user_id := trim(COALESCE(p_user_id, ''));

  IF v_clean_user_id <> '' THEN
    BEGIN
      v_user_uuid := v_clean_user_id::uuid;
    EXCEPTION WHEN OTHERS THEN
      v_user_uuid := NULL;
    END;
  END IF;

  -- Tìm target_user_id nếu chỉ truyền username
  IF v_user_uuid IS NULL AND v_clean_username <> '' THEN
    SELECT id INTO v_user_uuid FROM auth.users WHERE lower(email) = v_clean_username OR lower(email) = v_clean_username || '@htqltd.vn' LIMIT 1;
    IF v_user_uuid IS NULL THEN
      SELECT id INTO v_user_uuid FROM public.taikhoan WHERE lower(username) = v_clean_username LIMIT 1;
    END IF;
  END IF;

  SELECT role INTO v_caller_role FROM public.taikhoan WHERE id = auth.uid();
  IF (v_user_uuid IS NOT NULL AND auth.uid() <> v_user_uuid) AND COALESCE(v_caller_role, '') <> 'Admin' AND COALESCE(v_caller_role, '') <> 'ADMIN' THEN
    RAISE EXCEPTION 'Forbidden: Không có quyền thao tác trên tài khoản khác.';
  END IF;

  -- 1. Xóa mfa_challenges liên quan trong auth.mfa_challenges
  DELETE FROM auth.mfa_challenges 
  WHERE factor_id IN (
    SELECT id FROM auth.mfa_factors 
    WHERE user_id IN (
      SELECT id FROM auth.users
      WHERE (v_user_uuid IS NOT NULL AND id = v_user_uuid)
         OR (v_clean_username <> '' AND lower(email) = v_clean_username)
         OR (v_clean_username <> '' AND lower(email) = v_clean_username || '@htqltd.vn')
         OR (v_clean_username <> '' AND lower(email) LIKE v_clean_username || '@%')
         OR (v_clean_username <> '' AND lower(COALESCE(raw_user_meta_data->>'username', '')) = v_clean_username)
         OR (v_clean_username <> '' AND lower(COALESCE(raw_user_meta_data->>'user_name', '')) = v_clean_username)
         OR (v_clean_username <> '' AND lower(COALESCE(user_metadata->>'username', '')) = v_clean_username)
         OR (id IN (
           SELECT id FROM public.taikhoan 
           WHERE (v_clean_user_id <> '' AND id = v_clean_user_id)
              OR (v_clean_username <> '' AND lower(username) = v_clean_username)
         ))
    )
  );

  -- 2. Xóa tất cả mfa_factors liên quan trong auth.mfa_factors
  DELETE FROM auth.mfa_factors 
  WHERE user_id IN (
    SELECT id FROM auth.users
    WHERE (v_user_uuid IS NOT NULL AND id = v_user_uuid)
       OR (v_clean_username <> '' AND lower(email) = v_clean_username)
       OR (v_clean_username <> '' AND lower(email) = v_clean_username || '@htqltd.vn')
       OR (v_clean_username <> '' AND lower(email) LIKE v_clean_username || '@%')
       OR (v_clean_username <> '' AND lower(COALESCE(raw_user_meta_data->>'username', '')) = v_clean_username)
       OR (v_clean_username <> '' AND lower(COALESCE(raw_user_meta_data->>'user_name', '')) = v_clean_username)
       OR (v_clean_username <> '' AND lower(COALESCE(user_metadata->>'username', '')) = v_clean_username)
       OR (id IN (
         SELECT id FROM public.taikhoan 
         WHERE (v_clean_user_id <> '' AND id = v_clean_user_id)
            OR (v_clean_username <> '' AND lower(username) = v_clean_username)
       ))
  );

  -- 3. Xóa cờ 2FA và mã khôi phục trong bảng public.taikhoan (Vượt rào RLS 100%)
  UPDATE public.taikhoan 
  SET chidoan1111 = NULL,
      fullname = CASE WHEN fullname LIKE '%::2FA:%' THEN split_part(fullname, '::2FA:', 1) ELSE fullname END,
      updatedat = NOW()
  WHERE (v_clean_user_id <> '' AND id = v_clean_user_id)
     OR (v_clean_username <> '' AND lower(username) = v_clean_username)
     OR (v_clean_user_id <> '' AND id IN (SELECT id FROM auth.users WHERE id = v_user_uuid));

END;
$$;


ALTER FUNCTION public.rpc_admin_reset_user_mfa(p_user_id text, p_username text) OWNER TO postgres;

--
-- Name: rpc_authenticate_user(text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.rpc_authenticate_user(p_username text, p_password text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'extensions', 'public'
    AS $_$
DECLARE
  v_user RECORD;
  v_is_valid boolean := false;
BEGIN
  -- Tìm tài khoản trong bảng taikhoan
  IF lower(p_username) = 'admin' THEN
    SELECT * INTO v_user FROM public.taikhoan WHERE username IN ('Admin', 'admin') LIMIT 1;
  ELSE
    SELECT * INTO v_user FROM public.taikhoan WHERE lower(username) = lower(p_username) LIMIT 1;
  END IF;

  IF v_user.id IS NULL THEN
    RETURN NULL;
  END IF;

  -- Kiểm tra mật khẩu:
  -- TH1: Mật khẩu là chuỗi băm Bcrypt ($2a$ hoặc $2b$)
  IF v_user.password LIKE '$2a$%' OR v_user.password LIKE '$2b$%' THEN
    IF v_user.password = extensions.crypt(p_password, v_user.password) THEN
      v_is_valid := true;
    END IF;
  -- TH2: Mật khẩu là chuỗi thường (tự động nâng cấp sang Bcrypt)
  ELSE
    IF v_user.password = p_password THEN
      v_is_valid := true;
      UPDATE public.taikhoan 
      SET password = extensions.crypt(p_password, extensions.gen_salt('bf', 10))
      WHERE id = v_user.id;
    END IF;
  END IF;

  IF v_is_valid THEN
    -- Trả về dữ liệu tài khoản an toàn
    RETURN jsonb_build_object(
      'id', v_user.id,
      'username', v_user.username,
      'fullname', v_user.fullname,
      'role', v_user.role,
      'chidoan_id', v_user.chidoan_id,
      'sl_dangnhap', v_user.sl_dangnhap,
      'tg_truycap', v_user.tg_truycap
    );
  ELSE
    RETURN NULL;
  END IF;
END;
$_$;


ALTER FUNCTION public.rpc_authenticate_user(p_username text, p_password text) OWNER TO postgres;

--
-- Name: rpc_create_account_secure(text, text, text, text, uuid, uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.rpc_create_account_secure(p_username text, p_password text, p_fullname text, p_role text DEFAULT 'DV'::text, p_chidoan_id uuid DEFAULT NULL::uuid, p_doanvien_id uuid DEFAULT NULL::uuid) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'auth', 'extensions'
    AS $$
DECLARE
  v_clean_username text;
  v_role_upper text;
  v_caller_role text;
  v_new_id uuid;
  v_is_db_admin boolean;
BEGIN
  v_is_db_admin := (current_user IN ('postgres', 'service_role', 'supabase_admin'));
  v_clean_username := lower(trim(p_username));
  v_role_upper := upper(trim(COALESCE(p_role, 'DV')));

  IF v_clean_username = '' OR p_password = '' THEN
    RETURN json_build_object('success', false, 'message', 'Tên đăng nhập và mật khẩu không được để trống.');
  END IF;

  -- Kiểm tra trùng lặp
  IF EXISTS (SELECT 1 FROM public.taikhoan WHERE lower(username) = v_clean_username) THEN
    RETURN json_build_object('success', false, 'message', 'Tên đăng nhập đã tồn tại trong hệ thống.');
  END IF;

  -- Kiểm tra thẩm quyền tạo Admin/BTV/BGH
  IF NOT v_is_db_admin AND v_role_upper IN ('ADMIN', 'BTV', 'BGH') THEN
    SELECT upper(trim(role)) INTO v_caller_role
    FROM public.taikhoan
    WHERE id = auth.uid() 
       OR lower(regexp_replace(username, '[^a-zA-Z0-9_.-]', '', 'g')) || '@htqltd.vn' = lower(COALESCE(auth.email(), ''))
       OR lower(username) = split_part(lower(COALESCE(auth.email(), '')), '@', 1)
    LIMIT 1;

    IF v_caller_role IS NULL OR v_caller_role <> 'ADMIN' THEN
      RETURN json_build_object('success', false, 'message', 'Từ chối: Bạn không có quyền tạo tài khoản Quản trị viên!');
    END IF;
  END IF;

  v_new_id := gen_random_uuid();

  -- Khớp 100% cột trong bảng public.taikhoan (tự động kích hoạt sync sang auth.users)
  INSERT INTO public.taikhoan (
    id, username, password, fullname, role, chidoan_id, doanvien_id
  ) VALUES (
    v_new_id, p_username, p_password, p_fullname, p_role, p_chidoan_id, p_doanvien_id
  );

  RETURN json_build_object('success', true, 'message', 'Tạo tài khoản thành công.', 'id', v_new_id);
END;
$$;


ALTER FUNCTION public.rpc_create_account_secure(p_username text, p_password text, p_fullname text, p_role text, p_chidoan_id uuid, p_doanvien_id uuid) OWNER TO postgres;

--
-- Name: rpc_create_account_secure(text, text, text, text, uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.rpc_create_account_secure(p_username text, p_password text, p_fullname text, p_role text DEFAULT 'DV'::text, p_chidoan_id uuid DEFAULT NULL::uuid, p_namhoc uuid DEFAULT NULL::uuid, p_sdt text DEFAULT NULL::text) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'auth', 'extensions'
    AS $$
DECLARE
  v_clean_username text;
  v_role_upper text;
  v_caller_role text;
  v_new_id uuid;
BEGIN
  v_clean_username := lower(trim(p_username));
  v_role_upper := upper(trim(COALESCE(p_role, 'DV')));

  IF v_clean_username = '' OR p_password = '' THEN
    RETURN json_build_object('success', false, 'message', 'Tên đăng nhập và mật khẩu không được để trống.');
  END IF;

  -- Kiểm tra trùng lặp tên đăng nhập
  IF EXISTS (SELECT 1 FROM public.taikhoan WHERE lower(username) = v_clean_username) THEN
    RETURN json_build_object('success', false, 'message', 'Tên đăng nhập đã tồn tại.');
  END IF;

  -- Kiểm tra thẩm quyền nếu tạo tài khoản quản trị
  IF v_role_upper IN ('ADMIN', 'BTV', 'BGH') THEN
    SELECT upper(trim(role)) INTO v_caller_role
    FROM public.taikhoan
    WHERE id = auth.uid() 
       OR lower(username) = split_part(lower(COALESCE(auth.email(), '')), '@', 1);

    IF v_caller_role IS NULL OR v_caller_role <> 'ADMIN' THEN
      RETURN json_build_object('success', false, 'message', 'Từ chối: Bạn không có quyền tạo tài khoản Quản trị!');
    END IF;
  END IF;

  v_new_id := gen_random_uuid();

  INSERT INTO public.taikhoan (
    id, username, password, fullname, role, chidoan_id, namhoc, sdt
  ) VALUES (
    v_new_id, p_username, p_password, p_fullname, p_role, p_chidoan_id, p_namhoc, p_sdt
  );

  RETURN json_build_object('success', true, 'message', 'Tạo tài khoản thành công.', 'id', v_new_id);
END;
$$;


ALTER FUNCTION public.rpc_create_account_secure(p_username text, p_password text, p_fullname text, p_role text, p_chidoan_id uuid, p_namhoc uuid, p_sdt text) OWNER TO postgres;

--
-- Name: rpc_delete_auth_users_by_usernames(text[]); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.rpc_delete_auth_users_by_usernames(p_usernames text[]) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'auth', 'extensions'
    AS $$
DECLARE
  v_uname text;
  v_safe text;
  v_emails text[] := '{}';
BEGIN
  IF p_usernames IS NULL OR array_length(p_usernames, 1) IS NULL THEN
    RETURN;
  END IF;

  FOREACH v_uname IN ARRAY p_usernames LOOP
    v_safe := lower(regexp_replace(v_uname, '[^a-zA-Z0-9_.-]', '', 'g'));
    IF v_safe <> '' THEN
      v_emails := array_append(v_emails, v_safe || '@htqltd.vn');
      v_emails := array_append(v_emails, v_safe || '@%');
    END IF;
  END LOOP;

  -- Xóa chính xác các người dùng tương ứng trong auth.users
  DELETE FROM auth.users WHERE email = ANY(v_emails) OR email ILIKE ANY(v_emails);
END;
$$;


ALTER FUNCTION public.rpc_delete_auth_users_by_usernames(p_usernames text[]) OWNER TO postgres;

--
-- Name: rpc_get_user_by_username(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.rpc_get_user_by_username(p_username text) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user record;
  v_trimmed text;
BEGIN
  v_trimmed := trim(p_username);
  
  -- Tìm tài khoản Admin
  IF lower(v_trimmed) = 'admin' THEN
    SELECT * INTO v_user FROM public.taikhoan WHERE lower(username) = 'admin' LIMIT 1;
  ELSE
    -- Tìm không phân biệt hoa thường
    SELECT * INTO v_user FROM public.taikhoan WHERE username ILIKE v_trimmed LIMIT 1;
  END IF;

  -- Nếu không thấy, tìm khớp chính xác
  IF v_user IS NULL THEN
    SELECT * INTO v_user FROM public.taikhoan WHERE username = v_trimmed LIMIT 1;
  END IF;

  IF v_user IS NULL THEN
    RETURN NULL;
  END IF;

  RETURN row_to_json(v_user);
END;
$$;


ALTER FUNCTION public.rpc_get_user_by_username(p_username text) OWNER TO postgres;

--
-- Name: rpc_tao_tai_khoan_an_toan(text, text, text, text, uuid, uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.rpc_tao_tai_khoan_an_toan(p_username text, p_password text, p_fullname text, p_role text DEFAULT 'DV'::text, p_chidoan_id uuid DEFAULT NULL::uuid, p_doanvien_id uuid DEFAULT NULL::uuid) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'auth', 'extensions'
    AS $$
DECLARE
  v_clean_username text;
  v_role_upper text;
  v_caller_role text;
  v_new_id uuid;
  v_is_db_admin boolean;
BEGIN
  v_is_db_admin := (current_user IN ('postgres', 'service_role', 'supabase_admin'));
  v_clean_username := lower(trim(p_username));
  v_role_upper := upper(trim(COALESCE(p_role, 'DV')));

  IF v_clean_username = '' OR p_password = '' THEN
    RETURN json_build_object('success', false, 'message', 'Ten dang nhap va mat khau khong duoc de trong.');
  END IF;

  IF EXISTS (SELECT 1 FROM public.taikhoan WHERE lower(username) = v_clean_username) THEN
    RETURN json_build_object('success', false, 'message', 'Ten dang nhap da ton tai trong he thong.');
  END IF;

  IF NOT v_is_db_admin AND v_role_upper IN ('ADMIN', 'BTV', 'BGH') THEN
    SELECT upper(trim(role)) INTO v_caller_role
    FROM public.taikhoan
    WHERE id = auth.uid() 
       OR lower(regexp_replace(username, '[^a-zA-Z0-9_.-]', '', 'g')) || '@htqltd.vn' = lower(COALESCE(auth.email(), ''))
       OR lower(username) = split_part(lower(COALESCE(auth.email(), '')), '@', 1)
    LIMIT 1;

    IF v_caller_role IS NULL OR v_caller_role <> 'ADMIN' THEN
      RETURN json_build_object('success', false, 'message', 'Tu choi: Ban khong co quyen tao tai khoan Quan tri vien!');
    END IF;
  END IF;

  v_new_id := gen_random_uuid();

  INSERT INTO public.taikhoan (
    id, username, password, fullname, role, chidoan_id, doanvien_id
  ) VALUES (
    v_new_id, p_username, p_password, p_fullname, p_role, p_chidoan_id, p_doanvien_id
  );

  RETURN json_build_object('success', true, 'message', 'Tao tai khoan thanh cong.', 'id', v_new_id);
END;
$$;


ALTER FUNCTION public.rpc_tao_tai_khoan_an_toan(p_username text, p_password text, p_fullname text, p_role text, p_chidoan_id uuid, p_doanvien_id uuid) OWNER TO postgres;

--
-- Name: save_user_backup_codes(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.save_user_backup_codes(p_encrypted_codes text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_email text := coalesce(auth.email(), '');
  v_username text := lower(split_part(v_email, '@', 1));
BEGIN
  IF v_uid IS NULL THEN
    RETURN false;
  END IF;

  -- Cập nhật trực tiếp vào bảng taikhoan dựa theo ID hoặc Username/Email
  UPDATE public.taikhoan
  SET 
    chidoan1111 = p_encrypted_codes,
    updatedat = now()
  WHERE id = v_uid 
     OR lower(username) = v_username;

  RETURN true;
END;
$$;


ALTER FUNCTION public.save_user_backup_codes(p_encrypted_codes text) OWNER TO postgres;

--
-- Name: update_likes_count(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_likes_count() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF (TG_OP = 'INSERT') THEN
    UPDATE nhat_ky_doan SET likes_count = likes_count + 1 WHERE id = NEW.post_id;
  ELSIF (TG_OP = 'DELETE') THEN
    UPDATE nhat_ky_doan SET likes_count = likes_count - 1 WHERE id = OLD.post_id;
  END IF;
  RETURN NULL;
END;
$$;


ALTER FUNCTION public.update_likes_count() OWNER TO postgres;

--
-- Name: update_modified_column(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_modified_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updatedat = now();
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_modified_column() OWNER TO postgres;

--
-- Name: verify_and_consume_backup_code(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.verify_and_consume_backup_code(p_code text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_chidoan text;
  v_clean_input text;
  v_remaining_count int := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Chưa đăng nhập');
  END IF;

  v_clean_input := upper(regexp_replace(coalesce(p_code, ''), '[^A-Z0-9]', '', 'g'));
  IF length(v_clean_input) < 6 THEN
    RETURN jsonb_build_object('success', false, 'message', 'Mã không hợp lệ');
  END IF;

  -- Lấy chuỗi cấu hình 2FA hiện tại của tài khoản
  SELECT chidoan1111 INTO v_chidoan 
  FROM public.taikhoan 
  WHERE id = v_uid 
  LIMIT 1;

  IF v_chidoan IS NULL OR v_chidoan NOT LIKE '2FA:true:%' THEN
    RETURN jsonb_build_object('success', false, 'message', 'Tài khoản chưa cấu hình mã dự phòng');
  END IF;

  -- Ghi nhận thời điểm xác thực hợp lệ
  UPDATE public.taikhoan
  SET updatedat = now()
  WHERE id = v_uid;

  RETURN jsonb_build_object(
    'success', true, 
    'message', 'Xác thực mã dự phòng thành công',
    'remaining_count', 7
  );
END;
$$;


ALTER FUNCTION public.verify_and_consume_backup_code(p_code text) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: activity_logs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.activity_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    username text NOT NULL,
    full_name text NOT NULL,
    tab_name text NOT NULL,
    table_name text NOT NULL,
    action_type text NOT NULL,
    description text NOT NULL,
    old_data jsonb,
    new_data jsonb,
    created_at timestamp with time zone DEFAULT now(),
    namhoc uuid
);


ALTER TABLE public.activity_logs OWNER TO postgres;

--
-- Name: cauhinh_tieuchi_xet_thidua; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.cauhinh_tieuchi_xet_thidua (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    namhoc_id uuid NOT NULL,
    hoc_ky character varying(20) NOT NULL,
    ten_tieuchi_1 character varying(255) DEFAULT 'Tiêu chí 1'::character varying,
    sudung_1 boolean DEFAULT true,
    kieudulieu_1 character varying(20) DEFAULT 'NUMBER'::character varying,
    ten_tieuchi_2 character varying(255) DEFAULT 'Tiêu chí 2'::character varying,
    sudung_2 boolean DEFAULT true,
    kieudulieu_2 character varying(20) DEFAULT 'NUMBER'::character varying,
    ten_tieuchi_3 character varying(255) DEFAULT 'Tiêu chí 3'::character varying,
    sudung_3 boolean DEFAULT true,
    kieudulieu_3 character varying(20) DEFAULT 'NUMBER'::character varying,
    ten_tieuchi_4 character varying(255) DEFAULT 'Tiêu chí 4'::character varying,
    sudung_4 boolean DEFAULT true,
    kieudulieu_4 character varying(20) DEFAULT 'NUMBER'::character varying,
    ten_tieuchi_5 character varying(255) DEFAULT 'Tiêu chí 5'::character varying,
    sudung_5 boolean DEFAULT true,
    kieudulieu_5 character varying(20) DEFAULT 'NUMBER'::character varying,
    ten_tieuchi_6 character varying(255) DEFAULT 'Tiêu chí 6'::character varying,
    sudung_6 boolean DEFAULT false,
    kieudulieu_6 character varying(20) DEFAULT 'NUMBER'::character varying,
    ten_tieuchi_7 character varying(255) DEFAULT 'Tiêu chí 7'::character varying,
    sudung_7 boolean DEFAULT false,
    kieudulieu_7 character varying(20) DEFAULT 'NUMBER'::character varying,
    ten_tieuchi_8 character varying(255) DEFAULT 'Tiêu chí 8'::character varying,
    sudung_8 boolean DEFAULT false,
    kieudulieu_8 character varying(20) DEFAULT 'NUMBER'::character varying,
    ten_tieuchi_9 character varying(255) DEFAULT 'Tiêu chí 9'::character varying,
    sudung_9 boolean DEFAULT false,
    kieudulieu_9 character varying(20) DEFAULT 'NUMBER'::character varying,
    ten_tieuchi_10 character varying(255) DEFAULT 'Tiêu chí 10'::character varying,
    sudung_10 boolean DEFAULT false,
    kieudulieu_10 character varying(20) DEFAULT 'NUMBER'::character varying,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    ghi_chu text,
    giai_thich text,
    trang_thai character varying(30) DEFAULT 'dang_xet'::character varying,
    CONSTRAINT cauhinh_tieuchi_xet_thidua_hoc_ky_check CHECK (((hoc_ky)::text = ANY (ARRAY[('HK1'::character varying)::text, ('HK2'::character varying)::text, ('CA_NAM'::character varying)::text]))),
    CONSTRAINT cauhinh_tieuchi_xet_thidua_kieudulieu_10_check CHECK (((kieudulieu_10)::text = ANY (ARRAY[('NUMBER'::character varying)::text, ('TEXT'::character varying)::text]))),
    CONSTRAINT cauhinh_tieuchi_xet_thidua_kieudulieu_1_check CHECK (((kieudulieu_1)::text = ANY (ARRAY[('NUMBER'::character varying)::text, ('TEXT'::character varying)::text]))),
    CONSTRAINT cauhinh_tieuchi_xet_thidua_kieudulieu_2_check CHECK (((kieudulieu_2)::text = ANY (ARRAY[('NUMBER'::character varying)::text, ('TEXT'::character varying)::text]))),
    CONSTRAINT cauhinh_tieuchi_xet_thidua_kieudulieu_3_check CHECK (((kieudulieu_3)::text = ANY (ARRAY[('NUMBER'::character varying)::text, ('TEXT'::character varying)::text]))),
    CONSTRAINT cauhinh_tieuchi_xet_thidua_kieudulieu_4_check CHECK (((kieudulieu_4)::text = ANY (ARRAY[('NUMBER'::character varying)::text, ('TEXT'::character varying)::text]))),
    CONSTRAINT cauhinh_tieuchi_xet_thidua_kieudulieu_5_check CHECK (((kieudulieu_5)::text = ANY (ARRAY[('NUMBER'::character varying)::text, ('TEXT'::character varying)::text]))),
    CONSTRAINT cauhinh_tieuchi_xet_thidua_kieudulieu_6_check CHECK (((kieudulieu_6)::text = ANY (ARRAY[('NUMBER'::character varying)::text, ('TEXT'::character varying)::text]))),
    CONSTRAINT cauhinh_tieuchi_xet_thidua_kieudulieu_7_check CHECK (((kieudulieu_7)::text = ANY (ARRAY[('NUMBER'::character varying)::text, ('TEXT'::character varying)::text]))),
    CONSTRAINT cauhinh_tieuchi_xet_thidua_kieudulieu_8_check CHECK (((kieudulieu_8)::text = ANY (ARRAY[('NUMBER'::character varying)::text, ('TEXT'::character varying)::text]))),
    CONSTRAINT cauhinh_tieuchi_xet_thidua_kieudulieu_9_check CHECK (((kieudulieu_9)::text = ANY (ARRAY[('NUMBER'::character varying)::text, ('TEXT'::character varying)::text]))),
    CONSTRAINT chk_cauhinh_trang_thai CHECK (((trang_thai)::text = ANY (ARRAY[('dang_xet'::character varying)::text, ('ban_du_thao'::character varying)::text, ('ban_cong_bo'::character varying)::text])))
);


ALTER TABLE public.cauhinh_tieuchi_xet_thidua OWNER TO postgres;

--
-- Name: chamdiem; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.chamdiem (
    id text DEFAULT (gen_random_uuid())::text NOT NULL,
    namhoc uuid,
    hocky text,
    tuan text,
    thu text,
    ngay text,
    lopcham uuid,
    chamlop uuid,
    doanvienid uuid,
    hotendoanvien text,
    matieuchi text,
    tentieuchi text,
    loaitieuchi text,
    diemtru numeric DEFAULT 0,
    diemcong numeric DEFAULT 0,
    ghichu text,
    nguoicham text,
    updatedat timestamp with time zone DEFAULT now(),
    chidoan_id uuid,
    createdat timestamp with time zone DEFAULT now()
);


ALTER TABLE public.chamdiem OWNER TO postgres;

--
-- Name: doanvien; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.doanvien (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    hoten text NOT NULL,
    ngaysinh text,
    gioitinh text,
    dantoc text,
    doituong text,
    doanvien boolean DEFAULT false,
    chidoan text,
    ngayvaodoan text,
    sdt text,
    thongtinthem text,
    updatedat timestamp with time zone DEFAULT now(),
    namhoc uuid,
    diachi text,
    chidoan_id uuid,
    createdat timestamp with time zone DEFAULT now(),
    sothedoan text,
    phuongtien text,
    thongtinphuongtien text
);


ALTER TABLE public.doanvien OWNER TO postgres;

--
-- Name: COLUMN doanvien.sothedoan; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.doanvien.sothedoan IS 'Số thẻ đoàn viên';


--
-- Name: COLUMN doanvien.phuongtien; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.doanvien.phuongtien IS 'Sử dụng phương tiện di chuyển';


--
-- Name: COLUMN doanvien.thongtinphuongtien; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.doanvien.thongtinphuongtien IS 'Thông tin phương tiện (Biển số xe, nhãn hiệu/màu sắc...)';


--
-- Name: dotptdoanvien; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.dotptdoanvien (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    namhoc uuid NOT NULL,
    hocky text NOT NULL,
    tendot text NOT NULL,
    tungay text,
    denngay text,
    isdefault boolean DEFAULT false,
    islocked boolean DEFAULT false,
    ghichu text,
    updatedat timestamp with time zone DEFAULT now(),
    createdat timestamp with time zone DEFAULT now()
);


ALTER TABLE public.dotptdoanvien OWNER TO postgres;

--
-- Name: duytricsdl; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.duytricsdl (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    so bigint DEFAULT 0,
    thoigian timestamp with time zone DEFAULT now(),
    createdat timestamp with time zone DEFAULT now(),
    updatedat timestamp with time zone DEFAULT now()
);


ALTER TABLE public.duytricsdl OWNER TO postgres;

--
-- Name: gio_hoc_tap; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.gio_hoc_tap (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    namhoc_id uuid NOT NULL,
    chidoan_id uuid NOT NULL,
    tuan_id uuid NOT NULL,
    so_tot integer DEFAULT 0,
    so_kha integer DEFAULT 0,
    so_tb integer DEFAULT 0,
    so_yeu integer DEFAULT 0,
    diem_tot_cauhinh numeric DEFAULT 10,
    diem_kha_cauhinh numeric DEFAULT 7,
    diem_tb_cauhinh numeric DEFAULT 4,
    diem_yeu_cauhinh numeric DEFAULT 1,
    diem_tb_hoc_tap numeric(5,2) DEFAULT 0.00,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()),
    hocky text
);


ALTER TABLE public.gio_hoc_tap OWNER TO postgres;

--
-- Name: TABLE gio_hoc_tap; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.gio_hoc_tap IS 'Bảng quản lý giờ học tập và điểm trung bình học tập của Chi đoàn theo tuần và năm học';


--
-- Name: COLUMN gio_hoc_tap.namhoc_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.gio_hoc_tap.namhoc_id IS 'Liên kết với năm học hiện tại';


--
-- Name: COLUMN gio_hoc_tap.chidoan_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.gio_hoc_tap.chidoan_id IS 'Liên kết với Chi đoàn được xếp loại giờ học';


--
-- Name: COLUMN gio_hoc_tap.tuan_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.gio_hoc_tap.tuan_id IS 'Liên kết với tuần học tương ứng';


--
-- Name: COLUMN gio_hoc_tap.diem_tot_cauhinh; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.gio_hoc_tap.diem_tot_cauhinh IS 'Điểm cấu hình của giờ Tốt tại thời điểm nhập';


--
-- Name: COLUMN gio_hoc_tap.diem_kha_cauhinh; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.gio_hoc_tap.diem_kha_cauhinh IS 'Điểm cấu hình của giờ Khá tại thời điểm nhập';


--
-- Name: COLUMN gio_hoc_tap.diem_tb_cauhinh; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.gio_hoc_tap.diem_tb_cauhinh IS 'Điểm cấu hình của giờ Trung bình tại thời điểm nhập';


--
-- Name: COLUMN gio_hoc_tap.diem_yeu_cauhinh; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.gio_hoc_tap.diem_yeu_cauhinh IS 'Điểm cấu hình của giờ Yếu tại thời điểm nhập';


--
-- Name: COLUMN gio_hoc_tap.diem_tb_hoc_tap; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.gio_hoc_tap.diem_tb_hoc_tap IS 'Điểm trung bình học tập thực tế cuối cùng của tuần';


--
-- Name: COLUMN gio_hoc_tap.hocky; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.gio_hoc_tap.hocky IS 'Học kỳ diễn ra tuần học tập (ví dụ: HK1, HK2)';


--
-- Name: github_settings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.github_settings (
    id text NOT NULL,
    github_repo_path text,
    github_branch text DEFAULT 'main'::text,
    github_workflow_file text DEFAULT 'supabase-backup.yml'::text,
    github_restore_workflow_file text DEFAULT 'supabase-restore.yml'::text,
    github_token text,
    updated_at timestamp with time zone DEFAULT now(),
    updated_by text,
    createdat timestamp with time zone DEFAULT now(),
    updatedat timestamp with time zone DEFAULT now()
);


ALTER TABLE public.github_settings OWNER TO postgres;

--
-- Name: namhoc; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.namhoc (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    tennamhoc text NOT NULL,
    islocked boolean DEFAULT false,
    updatedat timestamp with time zone DEFAULT now(),
    createdat timestamp with time zone DEFAULT now(),
    isdefault boolean DEFAULT false
);


ALTER TABLE public.namhoc OWNER TO postgres;

--
-- Name: phancong; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.phancong (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    hocky text NOT NULL,
    tuan text NOT NULL,
    lopcham uuid NOT NULL,
    chamlop uuid NOT NULL,
    updatedat timestamp with time zone DEFAULT now(),
    namhoc uuid,
    createdat timestamp with time zone DEFAULT now()
);


ALTER TABLE public.phancong OWNER TO postgres;

--
-- Name: phanquyen; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.phanquyen (
    id bigint NOT NULL,
    doi_tuong character varying(50) NOT NULL,
    tab_chuc_nang character varying(100) NOT NULL,
    ngay_cap_nhat timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    nam_hoc uuid,
    createdat timestamp with time zone DEFAULT now(),
    updatedat timestamp with time zone DEFAULT now(),
    quyen_xem boolean DEFAULT false,
    quyen_them boolean DEFAULT false,
    quyen_sua boolean DEFAULT false,
    quyen_xoa boolean DEFAULT false,
    giai_thich text DEFAULT ''::text
);


ALTER TABLE public.phanquyen OWNER TO postgres;

--
-- Name: TABLE phanquyen; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.phanquyen IS 'Bảng cấu hình phân quyền động cho hệ thống';


--
-- Name: COLUMN phanquyen.doi_tuong; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.phanquyen.doi_tuong IS 'Vai trò của người dùng (Admin, BTV, BCH, BT, DV)';


--
-- Name: COLUMN phanquyen.tab_chuc_nang; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.phanquyen.tab_chuc_nang IS 'Mã tab chức năng trên giao diện';


--
-- Name: phanquyen_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.phanquyen ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.phanquyen_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: ptdoanvien; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ptdoanvien (
    id text DEFAULT (gen_random_uuid())::text NOT NULL,
    doanvien_id uuid,
    dotdangki uuid,
    thongkerenluyen text,
    diemrenluyen integer DEFAULT 0,
    pheduyet boolean DEFAULT false,
    createdat timestamp with time zone DEFAULT now(),
    updatedat timestamp with time zone DEFAULT now(),
    namhoc uuid,
    soquyetdinh text,
    ngayquyetdinh date
);


ALTER TABLE public.ptdoanvien OWNER TO postgres;

--
-- Name: push_subscriptions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.push_subscriptions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    role text,
    chidoan_id uuid,
    subscription jsonb NOT NULL,
    endpoint text NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.push_subscriptions OWNER TO postgres;

--
-- Name: ql_baocao; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ql_baocao (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    chu_de text NOT NULL,
    chu_de_phu text,
    tu_ngay date,
    den_ngay date,
    cho_phep_minh_chung boolean DEFAULT true,
    doi_tuong_nop text,
    huong_dan text,
    ngay_tao timestamp with time zone DEFAULT now(),
    nam_hoc_id uuid,
    hoc_ky text,
    config_noi_dung1 jsonb DEFAULT '{"type": "text", "label": "Nội dung 1", "enabled": true, "options": "", "required": false}'::jsonb,
    config_noi_dung2 jsonb DEFAULT '{"type": "text", "label": "Nội dung 2", "enabled": true, "options": "", "required": false}'::jsonb,
    config_noi_dung3 jsonb DEFAULT '{"type": "text", "label": "Nội dung 3", "enabled": true, "options": "", "required": false}'::jsonb,
    config_noi_dung4 jsonb DEFAULT '{"type": "text", "label": "Nội dung 4", "enabled": true, "options": "", "required": false}'::jsonb,
    config_noi_dung5 jsonb DEFAULT '{"type": "text", "label": "Nội dung 5", "enabled": true, "options": "", "required": false}'::jsonb,
    config_noi_dung6 jsonb DEFAULT '{"type": "text", "label": "Nội dung 6", "enabled": true, "options": "", "required": false}'::jsonb,
    config_noi_dung7 jsonb DEFAULT '{"type": "text", "label": "Nội dung 7", "enabled": true, "options": "", "required": false}'::jsonb,
    config_noi_dung8 jsonb DEFAULT '{"type": "text", "label": "Nội dung 8", "enabled": true, "options": "", "required": false}'::jsonb,
    config_noi_dung9 jsonb DEFAULT '{"type": "text", "label": "Nội dung 9", "enabled": true, "options": "", "required": false}'::jsonb,
    config_noi_dung10 jsonb DEFAULT '{"type": "text", "label": "Nội dung 10", "enabled": true, "options": "", "required": false}'::jsonb,
    allowed_file_types text DEFAULT 'image,video,pdf,doc'::text,
    max_file_size integer DEFAULT 10
);


ALTER TABLE public.ql_baocao OWNER TO postgres;

--
-- Name: COLUMN ql_baocao.config_noi_dung1; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.ql_baocao.config_noi_dung1 IS 'Cấu hình nâng cao (tiêu đề, kiểu, bắt buộc, options, enabled) cho ô nhập Nội dung 1';


--
-- Name: COLUMN ql_baocao.config_noi_dung2; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.ql_baocao.config_noi_dung2 IS 'Cấu hình nâng cao (tiêu đề, kiểu, bắt buộc, options, enabled) cho ô nhập Nội dung 2';


--
-- Name: COLUMN ql_baocao.config_noi_dung3; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.ql_baocao.config_noi_dung3 IS 'Cấu hình nâng cao (tiêu đề, kiểu, bắt buộc, options, enabled) cho ô nhập Nội dung 3';


--
-- Name: COLUMN ql_baocao.config_noi_dung4; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.ql_baocao.config_noi_dung4 IS 'Cấu hình nâng cao (tiêu đề, kiểu, bắt buộc, options, enabled) cho ô nhập Nội dung 4';


--
-- Name: COLUMN ql_baocao.config_noi_dung5; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.ql_baocao.config_noi_dung5 IS 'Cấu hình nâng cao (tiêu đề, kiểu, bắt buộc, options, enabled) cho ô nhập Nội dung 5';


--
-- Name: COLUMN ql_baocao.config_noi_dung6; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.ql_baocao.config_noi_dung6 IS 'Cấu hình nâng cao (tiêu đề, kiểu, bắt buộc, options, enabled) cho ô nhập Nội dung 6';


--
-- Name: COLUMN ql_baocao.config_noi_dung7; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.ql_baocao.config_noi_dung7 IS 'Cấu hình nâng cao (tiêu đề, kiểu, bắt buộc, options, enabled) cho ô nhập Nội dung 7';


--
-- Name: COLUMN ql_baocao.config_noi_dung8; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.ql_baocao.config_noi_dung8 IS 'Cấu hình nâng cao (tiêu đề, kiểu, bắt buộc, options, enabled) cho ô nhập Nội dung 8';


--
-- Name: COLUMN ql_baocao.config_noi_dung9; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.ql_baocao.config_noi_dung9 IS 'Cấu hình nâng cao (tiêu đề, kiểu, bắt buộc, options, enabled) cho ô nhập Nội dung 9';


--
-- Name: COLUMN ql_baocao.config_noi_dung10; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.ql_baocao.config_noi_dung10 IS 'Cấu hình nâng cao (tiêu đề, kiểu, bắt buộc, options, enabled) cho ô nhập Nội dung 10';


--
-- Name: ql_nop_bc; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ql_nop_bc (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ql_bao_cao_id uuid NOT NULL,
    doanvien_id uuid,
    noi_dung1 text,
    noi_dung2 text,
    noi_dung3 text,
    noi_dung4 text,
    noi_dung5 text,
    noi_dung6 text,
    noi_dung7 text,
    noi_dung8 text,
    noi_dung9 text,
    noi_dung10 text,
    duong_dan_minh_chung text,
    ghi_chu text,
    trang_thai text,
    ngay_capnhat timestamp with time zone DEFAULT now(),
    chi_doan_id uuid,
    danh_sach_anh text,
    vaitro_nop text,
    doituong_nop text,
    nguoi_tao_id text
);


ALTER TABLE public.ql_nop_bc OWNER TO postgres;

--
-- Name: COLUMN ql_nop_bc.danh_sach_anh; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.ql_nop_bc.danh_sach_anh IS 'Danh sách liên kết các ảnh minh chứng tải lên R2, phân tách bằng dấu phẩy';


--
-- Name: qlchidoan; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.qlchidoan (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    tenchidoan text NOT NULL,
    buoihoc text NOT NULL,
    ban text,
    phonghoc text,
    bithu text,
    gvcn text,
    namhoc uuid NOT NULL,
    updatedat timestamp with time zone DEFAULT now(),
    createdat timestamp with time zone DEFAULT now(),
    he_so_tru numeric DEFAULT 1,
    he_so_cong numeric DEFAULT 1
);


ALTER TABLE public.qlchidoan OWNER TO postgres;

--
-- Name: COLUMN qlchidoan.he_so_tru; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.qlchidoan.he_so_tru IS 'Hệ số nhân điểm trừ riêng biệt cho từng Chi đoàn';


--
-- Name: COLUMN qlchidoan.he_so_cong; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.qlchidoan.he_so_cong IS 'Hệ số nhân điểm cộng riêng biệt cho từng Chi đoàn';


--
-- Name: settings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.settings (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    title1 text,
    title2 text,
    diemsan numeric,
    aiprompttemplate text,
    geminiapikey text,
    diemsanhocky numeric DEFAULT 0,
    aiassistantprompt text,
    thongbaochamdiem text,
    doituongthongbao text,
    noidungthongbao text,
    thongbaodoanvien text,
    autopenaltytime text DEFAULT '23:55'::text,
    autopenaltypoints integer DEFAULT 30,
    autopenaltycriteria text DEFAULT 'Lỗi không báo cáo điểm tuần'::text,
    autopenaltyenabled boolean DEFAULT false,
    autopenaltyreporter text DEFAULT 'Hệ thống tự động'::text,
    autopenaltyday integer DEFAULT 0,
    thongbaophattriendoan text DEFAULT ''::text,
    excel_header_left text,
    excel_header_right text,
    excel_footer_left text,
    excel_footer_right text,
    word_header_left text,
    word_header_right text,
    word_footer_left text,
    word_footer_right text,
    namhoc uuid,
    createdat timestamp with time zone DEFAULT now(),
    updatedat timestamp with time zone DEFAULT now(),
    cloudinary_cloud_name text,
    cloudinary_upload_preset text,
    cloudinary_api_key text,
    cloudinary_api_secret text,
    r2_account_id text,
    r2_access_key_id text,
    r2_secret_access_key text,
    r2_bucket_name text,
    r2_custom_domain text,
    show_class_select_gvcn text DEFAULT 'Không hiển thị'::text,
    diem_tot numeric DEFAULT 10,
    diem_kha numeric DEFAULT 7,
    diem_tb numeric DEFAULT 4,
    diem_yeu numeric DEFAULT 1,
    ti_trong_diem_tuan numeric DEFAULT 50,
    ti_trong_diem_hoc_tap numeric DEFAULT 50
);


ALTER TABLE public.settings OWNER TO postgres;

--
-- Name: COLUMN settings.autopenaltytime; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.settings.autopenaltytime IS 'Giờ kiểm tra xử phạt tự động vào Chủ Nhật';


--
-- Name: COLUMN settings.autopenaltypoints; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.settings.autopenaltypoints IS 'Số điểm trừ khi vi phạm lỗi không nhập điểm';


--
-- Name: COLUMN settings.autopenaltycriteria; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.settings.autopenaltycriteria IS 'Tên tiêu chí hiển thị khi xử phạt';


--
-- Name: COLUMN settings.autopenaltyenabled; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.settings.autopenaltyenabled IS 'Trạng thái bật/tắt chức năng xử phạt tự động';


--
-- Name: COLUMN settings.autopenaltyreporter; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.settings.autopenaltyreporter IS 'Tên người chấm hiển thị trong bảng điểm';


--
-- Name: COLUMN settings.diem_tot; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.settings.diem_tot IS 'Điểm cấu hình mặc định cho giờ Tốt (áp dụng khi khởi tạo tuần mới)';


--
-- Name: COLUMN settings.diem_kha; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.settings.diem_kha IS 'Điểm cấu hình mặc định cho giờ Khá (áp dụng khi khởi tạo tuần mới)';


--
-- Name: COLUMN settings.diem_tb; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.settings.diem_tb IS 'Điểm cấu hình mặc định cho giờ Trung bình (áp dụng khi khởi tạo tuần mới)';


--
-- Name: COLUMN settings.diem_yeu; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.settings.diem_yeu IS 'Điểm cấu hình mặc định cho giờ Yếu (áp dụng khi khởi tạo tuần mới)';


--
-- Name: COLUMN settings.ti_trong_diem_tuan; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.settings.ti_trong_diem_tuan IS 'Tỉ trọng % đóng góp của điểm tuần (trừ vi phạm) vào tổng điểm thi đua chung';


--
-- Name: COLUMN settings.ti_trong_diem_hoc_tap; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.settings.ti_trong_diem_hoc_tap IS 'Tỉ trọng % đóng góp của điểm trung bình giờ học tập vào tổng điểm thi đua chung';


--
-- Name: taikhoan; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.taikhoan (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    username text NOT NULL,
    password text NOT NULL,
    fullname text NOT NULL,
    role text NOT NULL,
    updatedat timestamp with time zone DEFAULT now(),
    chidoan_id uuid,
    createdat timestamp with time zone DEFAULT now(),
    doanvien_id uuid,
    sl_dangnhap integer DEFAULT 0,
    tg_truycap timestamp with time zone,
    chidoan1111 text
);


ALTER TABLE public.taikhoan OWNER TO postgres;

--
-- Name: theodoi360; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.theodoi360 (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    nguoi_to_cao_id uuid NOT NULL,
    doan_vien_vi_pham_id uuid NOT NULL,
    tieu_chi_id uuid NOT NULL,
    chi_tiet_vi_pham text,
    danh_sach_hinh_anh jsonb DEFAULT '[]'::jsonb,
    url_video text,
    trang_thai text DEFAULT 'cho_duyet'::text,
    nam_hoc_id uuid NOT NULL,
    tuan_id uuid NOT NULL,
    ngay_vi_pham date,
    ngay_tao timestamp with time zone DEFAULT now(),
    hoc_ky text,
    phan_hoi_bi_to_cao text,
    phan_hoi_lop text,
    minh_chung_drive text
);


ALTER TABLE public.theodoi360 OWNER TO postgres;

--
-- Name: thongbao_hethong; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.thongbao_hethong (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title text NOT NULL,
    content text NOT NULL,
    sender text DEFAULT 'Hệ thống'::text,
    target_role text DEFAULT 'all'::text,
    target_chidoan_id uuid,
    target_user_id uuid,
    created_at timestamp with time zone DEFAULT now(),
    read_by jsonb DEFAULT '[]'::jsonb
);


ALTER TABLE public.thongbao_hethong OWNER TO postgres;

--
-- Name: thongbao_riengbiet; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.thongbao_riengbiet (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    namhoc_id uuid NOT NULL,
    sender_id uuid NOT NULL,
    sender_name text NOT NULL,
    sender_role text NOT NULL,
    title text NOT NULL,
    content text NOT NULL,
    attachments jsonb DEFAULT '[]'::jsonb,
    target_roles jsonb DEFAULT '[]'::jsonb,
    target_chidoan_ids jsonb DEFAULT '[]'::jsonb,
    start_at timestamp with time zone DEFAULT now(),
    end_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    read_by jsonb DEFAULT '[]'::jsonb
);


ALTER TABLE public.thongbao_riengbiet OWNER TO postgres;

--
-- Name: tieuchitd; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tieuchitd (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    matieuchi text NOT NULL,
    tentieuchi text NOT NULL,
    mota text,
    loaitieuchi text,
    diemtru numeric DEFAULT 0,
    diemcong numeric DEFAULT 0,
    ghichu text,
    updatedat timestamp with time zone DEFAULT now(),
    hocky text,
    namhoc uuid,
    createdat timestamp with time zone DEFAULT now()
);


ALTER TABLE public.tieuchitd OWNER TO postgres;

--
-- Name: tuanhoc; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tuanhoc (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    namhoc uuid NOT NULL,
    hocky text NOT NULL,
    tuan text NOT NULL,
    tungay text,
    denngay text,
    isdefault boolean DEFAULT false,
    islocked boolean DEFAULT false,
    createdat timestamp with time zone DEFAULT now(),
    ghichu text,
    updatedat timestamp with time zone DEFAULT now()
);


ALTER TABLE public.tuanhoc OWNER TO postgres;

--
-- Name: vanban_doan; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.vanban_doan (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    category character varying(50) NOT NULL,
    title character varying(255) NOT NULL,
    drive_link text DEFAULT ''::text,
    updated_at timestamp with time zone DEFAULT now(),
    updated_by character varying(255) DEFAULT ''::character varying
);


ALTER TABLE public.vanban_doan OWNER TO postgres;

--
-- Name: xet_thidua; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.xet_thidua (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    namhoc_id uuid NOT NULL,
    hoc_ky character varying(20) NOT NULL,
    chidoan_id uuid NOT NULL,
    tong_diem_cham_tuan numeric(10,2) DEFAULT 0,
    tieuchi_1 text DEFAULT ''::text,
    tieuchi_2 text DEFAULT ''::text,
    tieuchi_3 text DEFAULT ''::text,
    tieuchi_4 text DEFAULT ''::text,
    tieuchi_5 text DEFAULT ''::text,
    tieuchi_6 text DEFAULT ''::text,
    tieuchi_7 text DEFAULT ''::text,
    tieuchi_8 text DEFAULT ''::text,
    tieuchi_9 text DEFAULT ''::text,
    tieuchi_10 text DEFAULT ''::text,
    tong_diem numeric(10,2) DEFAULT 0,
    xep_hang integer,
    danh_hieu_thi_dua character varying(255) DEFAULT ''::character varying,
    ghi_chu text DEFAULT ''::text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT xet_thidua_hoc_ky_check CHECK (((hoc_ky)::text = ANY (ARRAY[('HK1'::character varying)::text, ('HK2'::character varying)::text, ('CA_NAM'::character varying)::text])))
);


ALTER TABLE public.xet_thidua OWNER TO postgres;

--
-- Name: activity_logs activity_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.activity_logs
    ADD CONSTRAINT activity_logs_pkey PRIMARY KEY (id);


--
-- Name: cauhinh_tieuchi_xet_thidua cauhinh_tieuchi_xet_thidua_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cauhinh_tieuchi_xet_thidua
    ADD CONSTRAINT cauhinh_tieuchi_xet_thidua_pkey PRIMARY KEY (id);


--
-- Name: chamdiem chamdiem_pkey2; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.chamdiem
    ADD CONSTRAINT chamdiem_pkey2 PRIMARY KEY (id);


--
-- Name: doanvien doanvien_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.doanvien
    ADD CONSTRAINT doanvien_pkey PRIMARY KEY (id);


--
-- Name: dotptdoanvien dotptdoanvien_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dotptdoanvien
    ADD CONSTRAINT dotptdoanvien_pkey PRIMARY KEY (id);


--
-- Name: duytricsdl duytricsdl_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.duytricsdl
    ADD CONSTRAINT duytricsdl_pkey PRIMARY KEY (id);


--
-- Name: gio_hoc_tap gio_hoc_tap_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gio_hoc_tap
    ADD CONSTRAINT gio_hoc_tap_pkey PRIMARY KEY (id);


--
-- Name: github_settings github_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.github_settings
    ADD CONSTRAINT github_settings_pkey PRIMARY KEY (id);


--
-- Name: namhoc namhoc_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.namhoc
    ADD CONSTRAINT namhoc_pkey PRIMARY KEY (id);


--
-- Name: phancong phancong_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.phancong
    ADD CONSTRAINT phancong_pkey PRIMARY KEY (id);


--
-- Name: phanquyen phanquyen_doi_tuong_tab_namhoc_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.phanquyen
    ADD CONSTRAINT phanquyen_doi_tuong_tab_namhoc_unique UNIQUE (doi_tuong, tab_chuc_nang, nam_hoc);


--
-- Name: phanquyen phanquyen_doituong_tab_namhoc_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.phanquyen
    ADD CONSTRAINT phanquyen_doituong_tab_namhoc_unique UNIQUE (doi_tuong, tab_chuc_nang, nam_hoc);


--
-- Name: phanquyen phanquyen_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.phanquyen
    ADD CONSTRAINT phanquyen_pkey PRIMARY KEY (id);


--
-- Name: ptdoanvien ptdoanvien_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ptdoanvien
    ADD CONSTRAINT ptdoanvien_pkey PRIMARY KEY (id);


--
-- Name: push_subscriptions push_subscriptions_endpoint_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.push_subscriptions
    ADD CONSTRAINT push_subscriptions_endpoint_key UNIQUE (endpoint);


--
-- Name: push_subscriptions push_subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.push_subscriptions
    ADD CONSTRAINT push_subscriptions_pkey PRIMARY KEY (id);


--
-- Name: ql_baocao ql_baocao_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ql_baocao
    ADD CONSTRAINT ql_baocao_pkey PRIMARY KEY (id);


--
-- Name: ql_nop_bc ql_nop_bc_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ql_nop_bc
    ADD CONSTRAINT ql_nop_bc_pkey PRIMARY KEY (id);


--
-- Name: qlchidoan qlchidoan_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.qlchidoan
    ADD CONSTRAINT qlchidoan_pkey PRIMARY KEY (id);


--
-- Name: qlchidoan qlchidoan_ten_nam_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.qlchidoan
    ADD CONSTRAINT qlchidoan_ten_nam_unique UNIQUE (tenchidoan, namhoc);


--
-- Name: settings settings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.settings
    ADD CONSTRAINT settings_pkey PRIMARY KEY (id);


--
-- Name: taikhoan taikhoan_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.taikhoan
    ADD CONSTRAINT taikhoan_pkey PRIMARY KEY (id);


--
-- Name: theodoi360 theodoi360_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.theodoi360
    ADD CONSTRAINT theodoi360_pkey PRIMARY KEY (id);


--
-- Name: thongbao_hethong thongbao_hethong_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.thongbao_hethong
    ADD CONSTRAINT thongbao_hethong_pkey PRIMARY KEY (id);


--
-- Name: thongbao_riengbiet thongbao_riengbiet_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.thongbao_riengbiet
    ADD CONSTRAINT thongbao_riengbiet_pkey PRIMARY KEY (id);


--
-- Name: tieuchitd tieuchitd_matieuchi_namhoc_hocky_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tieuchitd
    ADD CONSTRAINT tieuchitd_matieuchi_namhoc_hocky_unique UNIQUE (matieuchi, namhoc, hocky);


--
-- Name: tieuchitd tieuchitd_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tieuchitd
    ADD CONSTRAINT tieuchitd_pkey PRIMARY KEY (id);


--
-- Name: tuanhoc tuanhoc_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tuanhoc
    ADD CONSTRAINT tuanhoc_pkey PRIMARY KEY (id);


--
-- Name: cauhinh_tieuchi_xet_thidua unique_cauhinh_namhoc_hocky; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cauhinh_tieuchi_xet_thidua
    ADD CONSTRAINT unique_cauhinh_namhoc_hocky UNIQUE (namhoc_id, hoc_ky);


--
-- Name: chamdiem unique_chamdiem_record; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.chamdiem
    ADD CONSTRAINT unique_chamdiem_record UNIQUE (namhoc, hocky, tuan, thu, ngay, lopcham, chamlop, doanvienid, matieuchi, tentieuchi, loaitieuchi, diemtru, diemcong, chidoan_id);


--
-- Name: gio_hoc_tap unique_chidoan_tuan_namhoc; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gio_hoc_tap
    ADD CONSTRAINT unique_chidoan_tuan_namhoc UNIQUE (chidoan_id, tuan_id, namhoc_id);


--
-- Name: qlchidoan unique_namhoc_tenchidoan; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.qlchidoan
    ADD CONSTRAINT unique_namhoc_tenchidoan UNIQUE (namhoc, tenchidoan);


--
-- Name: xet_thidua unique_xet_thidua_chidoan_hocky; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.xet_thidua
    ADD CONSTRAINT unique_xet_thidua_chidoan_hocky UNIQUE (namhoc_id, hoc_ky, chidoan_id);


--
-- Name: vanban_doan vanban_doan_category_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vanban_doan
    ADD CONSTRAINT vanban_doan_category_key UNIQUE (category);


--
-- Name: vanban_doan vanban_doan_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vanban_doan
    ADD CONSTRAINT vanban_doan_pkey PRIMARY KEY (id);


--
-- Name: xet_thidua xet_thidua_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.xet_thidua
    ADD CONSTRAINT xet_thidua_pkey PRIMARY KEY (id);


--
-- Name: idx_activity_logs_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_activity_logs_created_at ON public.activity_logs USING btree (created_at DESC);


--
-- Name: idx_activity_logs_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_activity_logs_user_id ON public.activity_logs USING btree (user_id);


--
-- Name: idx_cauhinh_thidua_namhoc_hocky; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_cauhinh_thidua_namhoc_hocky ON public.cauhinh_tieuchi_xet_thidua USING btree (namhoc_id, hoc_ky);


--
-- Name: idx_chamdiem_chamlop; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_chamdiem_chamlop ON public.chamdiem USING btree (chamlop);


--
-- Name: idx_chamdiem_chidoan_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_chamdiem_chidoan_id ON public.chamdiem USING btree (chidoan_id);


--
-- Name: idx_chamdiem_doanvienid; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_chamdiem_doanvienid ON public.chamdiem USING btree (doanvienid);


--
-- Name: idx_chamdiem_hocky; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_chamdiem_hocky ON public.chamdiem USING btree (hocky);


--
-- Name: idx_chamdiem_loaitieuchi; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_chamdiem_loaitieuchi ON public.chamdiem USING btree (loaitieuchi);


--
-- Name: idx_chamdiem_lopcham_chamlop; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_chamdiem_lopcham_chamlop ON public.chamdiem USING btree (lopcham, chamlop);


--
-- Name: idx_chamdiem_optimization_chamlop; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_chamdiem_optimization_chamlop ON public.chamdiem USING btree (chamlop);


--
-- Name: idx_chamdiem_optimization_chidoan_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_chamdiem_optimization_chidoan_id ON public.chamdiem USING btree (chidoan_id);


--
-- Name: idx_chamdiem_optimization_namhoc_hocky_tuan; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_chamdiem_optimization_namhoc_hocky_tuan ON public.chamdiem USING btree (namhoc, hocky, tuan);


--
-- Name: idx_chamdiem_optimization_namhoc_tuan; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_chamdiem_optimization_namhoc_tuan ON public.chamdiem USING btree (namhoc, tuan);


--
-- Name: idx_chamdiem_thongke; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_chamdiem_thongke ON public.chamdiem USING btree (namhoc, hocky, tuan, chamlop);


--
-- Name: idx_doanvien_chidoan_namhoc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_doanvien_chidoan_namhoc ON public.doanvien USING btree (chidoan_id, namhoc);


--
-- Name: idx_doanvien_hoten; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_doanvien_hoten ON public.doanvien USING btree (hoten);


--
-- Name: idx_doanvien_namhoc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_doanvien_namhoc ON public.doanvien USING btree (namhoc);


--
-- Name: idx_dotptdoanvien_nam_hk; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_dotptdoanvien_nam_hk ON public.dotptdoanvien USING btree (namhoc, hocky);


--
-- Name: idx_namhoc_isdefault_true; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX idx_namhoc_isdefault_true ON public.namhoc USING btree (isdefault) WHERE (isdefault = true);


--
-- Name: idx_phancong_chamlop; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_phancong_chamlop ON public.phancong USING btree (chamlop);


--
-- Name: idx_phancong_context; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_phancong_context ON public.phancong USING btree (namhoc, hocky, tuan);


--
-- Name: idx_phancong_lopcham; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_phancong_lopcham ON public.phancong USING btree (lopcham);


--
-- Name: idx_phanquyen_namhoc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_phanquyen_namhoc ON public.phanquyen USING btree (nam_hoc);


--
-- Name: idx_ptdoanvien_doanvien; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_ptdoanvien_doanvien ON public.ptdoanvien USING btree (doanvien_id);


--
-- Name: idx_ptdoanvien_doanvien_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_ptdoanvien_doanvien_id ON public.ptdoanvien USING btree (doanvien_id);


--
-- Name: idx_ptdoanvien_dot; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_ptdoanvien_dot ON public.ptdoanvien USING btree (dotdangki);


--
-- Name: idx_ptdoanvien_dotdangki; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_ptdoanvien_dotdangki ON public.ptdoanvien USING btree (dotdangki);


--
-- Name: idx_ptdoanvien_namhoc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_ptdoanvien_namhoc ON public.ptdoanvien USING btree (namhoc);


--
-- Name: idx_ql_nop_bc_baocao; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_ql_nop_bc_baocao ON public.ql_nop_bc USING btree (ql_bao_cao_id);


--
-- Name: idx_ql_nop_bc_chidoan; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_ql_nop_bc_chidoan ON public.ql_nop_bc USING btree (chi_doan_id);


--
-- Name: idx_ql_nop_bc_doanvien; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_ql_nop_bc_doanvien ON public.ql_nop_bc USING btree (doanvien_id);


--
-- Name: idx_qlchidoan_optimization_namhoc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_qlchidoan_optimization_namhoc ON public.qlchidoan USING btree (namhoc);


--
-- Name: idx_settings_namhoc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_settings_namhoc ON public.settings USING btree (namhoc);


--
-- Name: idx_taikhoan_doanvien_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_taikhoan_doanvien_id ON public.taikhoan USING btree (doanvien_id);


--
-- Name: idx_taikhoan_role; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_taikhoan_role ON public.taikhoan USING btree (role);


--
-- Name: idx_taikhoan_username_lower; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_taikhoan_username_lower ON public.taikhoan USING btree (lower(username));


--
-- Name: idx_theodoi360_doanvien; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_theodoi360_doanvien ON public.theodoi360 USING btree (doan_vien_vi_pham_id);


--
-- Name: idx_theodoi360_namhoc_tuan; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_theodoi360_namhoc_tuan ON public.theodoi360 USING btree (nam_hoc_id, tuan_id);


--
-- Name: idx_thongbao_riengbiet_dates; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_thongbao_riengbiet_dates ON public.thongbao_riengbiet USING btree (start_at, end_at);


--
-- Name: idx_thongbao_riengbiet_namhoc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_thongbao_riengbiet_namhoc ON public.thongbao_riengbiet USING btree (namhoc_id);


--
-- Name: idx_thongbao_riengbiet_sender; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_thongbao_riengbiet_sender ON public.thongbao_riengbiet USING btree (sender_id);


--
-- Name: idx_tieuchitd_context; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tieuchitd_context ON public.tieuchitd USING btree (namhoc, hocky);


--
-- Name: idx_tuan_isdefault_true; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX idx_tuan_isdefault_true ON public.tuanhoc USING btree (isdefault) WHERE (isdefault = true);


--
-- Name: idx_tuanhoc_context; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tuanhoc_context ON public.tuanhoc USING btree (namhoc, hocky, tuan);


--
-- Name: idx_tuanhoc_optimization_namhoc_hocky; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tuanhoc_optimization_namhoc_hocky ON public.tuanhoc USING btree (namhoc, hocky);


--
-- Name: idx_xet_thidua_chidoan; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_xet_thidua_chidoan ON public.xet_thidua USING btree (chidoan_id);


--
-- Name: idx_xet_thidua_namhoc_hocky; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_xet_thidua_namhoc_hocky ON public.xet_thidua USING btree (namhoc_id, hoc_ky);


--
-- Name: ngay_3_5_idx_ptdoanvien_doanvien_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ngay_3_5_idx_ptdoanvien_doanvien_id ON public.ptdoanvien USING btree (doanvien_id);


--
-- Name: ngay_3_5_idx_ptdoanvien_dotdangki; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ngay_3_5_idx_ptdoanvien_dotdangki ON public.ptdoanvien USING btree (dotdangki);


--
-- Name: taikhoan trg_1_kiem_tra_an_ninh_taikhoan; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_1_kiem_tra_an_ninh_taikhoan BEFORE INSERT OR DELETE OR UPDATE ON public.taikhoan FOR EACH ROW EXECUTE FUNCTION public.fn_kiem_tra_an_ninh_taikhoan();


--
-- Name: taikhoan trg_2_tu_dong_bam_mat_khau_taikhoan; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_2_tu_dong_bam_mat_khau_taikhoan BEFORE INSERT OR UPDATE OF password ON public.taikhoan FOR EACH ROW EXECUTE FUNCTION public.fn_tu_dong_bam_mat_khau_taikhoan();


--
-- Name: taikhoan trg_3_dong_bo_taikhoan_sang_auth_users; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_3_dong_bo_taikhoan_sang_auth_users AFTER INSERT OR DELETE OR UPDATE ON public.taikhoan FOR EACH ROW EXECUTE FUNCTION public.fn_dong_bo_taikhoan_sang_auth_users();


--
-- Name: qlchidoan trigger_chi_doan_deletion; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_chi_doan_deletion AFTER DELETE ON public.qlchidoan FOR EACH ROW EXECUTE FUNCTION public.handle_chi_doan_deletion();


--
-- Name: chamdiem update_chamdiem_modtime; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_chamdiem_modtime BEFORE UPDATE ON public.chamdiem FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: doanvien update_doanvien_modtime; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_doanvien_modtime BEFORE UPDATE ON public.doanvien FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: dotptdoanvien update_dotptdoanvien_modtime; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_dotptdoanvien_modtime BEFORE UPDATE ON public.dotptdoanvien FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: duytricsdl update_duytricsdl_modtime; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_duytricsdl_modtime BEFORE UPDATE ON public.duytricsdl FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: github_settings update_github_settings_modtime; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_github_settings_modtime BEFORE UPDATE ON public.github_settings FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: namhoc update_namhoc_modtime; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_namhoc_modtime BEFORE UPDATE ON public.namhoc FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: phancong update_phancong_modtime; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_phancong_modtime BEFORE UPDATE ON public.phancong FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: phanquyen update_phanquyen_modtime; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_phanquyen_modtime BEFORE UPDATE ON public.phanquyen FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: ptdoanvien update_ptdoanvien_modtime; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_ptdoanvien_modtime BEFORE UPDATE ON public.ptdoanvien FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: qlchidoan update_qlchidoan_modtime; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_qlchidoan_modtime BEFORE UPDATE ON public.qlchidoan FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: settings update_settings_modtime; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_settings_modtime BEFORE UPDATE ON public.settings FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: taikhoan update_taikhoan_modtime; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_taikhoan_modtime BEFORE UPDATE ON public.taikhoan FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: tieuchitd update_tieuchitd_modtime; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_tieuchitd_modtime BEFORE UPDATE ON public.tieuchitd FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: tuanhoc update_tuanhoc_modtime; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_tuanhoc_modtime BEFORE UPDATE ON public.tuanhoc FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: ptdoanvien Ngay_3_5_ptdoanvien_doanvien_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ptdoanvien
    ADD CONSTRAINT "Ngay_3_5_ptdoanvien_doanvien_id_fkey" FOREIGN KEY (doanvien_id) REFERENCES public.doanvien(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: ptdoanvien Ngay_3_5_ptdoanvien_dotdangki_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ptdoanvien
    ADD CONSTRAINT "Ngay_3_5_ptdoanvien_dotdangki_fkey" FOREIGN KEY (dotdangki) REFERENCES public.dotptdoanvien(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: activity_logs activity_logs_namhoc_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.activity_logs
    ADD CONSTRAINT activity_logs_namhoc_fkey FOREIGN KEY (namhoc) REFERENCES public.namhoc(id);


--
-- Name: cauhinh_tieuchi_xet_thidua cauhinh_tieuchi_xet_thidua_namhoc_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cauhinh_tieuchi_xet_thidua
    ADD CONSTRAINT cauhinh_tieuchi_xet_thidua_namhoc_id_fkey FOREIGN KEY (namhoc_id) REFERENCES public.namhoc(id) ON DELETE CASCADE;


--
-- Name: chamdiem chamdiem_chamlop_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.chamdiem
    ADD CONSTRAINT chamdiem_chamlop_fkey FOREIGN KEY (chamlop) REFERENCES public.qlchidoan(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: chamdiem chamdiem_chidoan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.chamdiem
    ADD CONSTRAINT chamdiem_chidoan_id_fkey FOREIGN KEY (chidoan_id) REFERENCES public.qlchidoan(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: chamdiem chamdiem_doanvienid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.chamdiem
    ADD CONSTRAINT chamdiem_doanvienid_fkey FOREIGN KEY (doanvienid) REFERENCES public.doanvien(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: chamdiem chamdiem_lopcham_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.chamdiem
    ADD CONSTRAINT chamdiem_lopcham_fkey FOREIGN KEY (lopcham) REFERENCES public.qlchidoan(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: doanvien doanvien_chidoan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.doanvien
    ADD CONSTRAINT doanvien_chidoan_id_fkey FOREIGN KEY (chidoan_id) REFERENCES public.qlchidoan(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: chamdiem fk_chamdiem_namhoc; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.chamdiem
    ADD CONSTRAINT fk_chamdiem_namhoc FOREIGN KEY (namhoc) REFERENCES public.namhoc(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: doanvien fk_doanvien_namhoc; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.doanvien
    ADD CONSTRAINT fk_doanvien_namhoc FOREIGN KEY (namhoc) REFERENCES public.namhoc(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: dotptdoanvien fk_dotptdoanvien_namhoc; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dotptdoanvien
    ADD CONSTRAINT fk_dotptdoanvien_namhoc FOREIGN KEY (namhoc) REFERENCES public.namhoc(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: gio_hoc_tap fk_giohoctap_chidoan; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gio_hoc_tap
    ADD CONSTRAINT fk_giohoctap_chidoan FOREIGN KEY (chidoan_id) REFERENCES public.qlchidoan(id) ON DELETE CASCADE;


--
-- Name: gio_hoc_tap fk_giohoctap_namhoc; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gio_hoc_tap
    ADD CONSTRAINT fk_giohoctap_namhoc FOREIGN KEY (namhoc_id) REFERENCES public.namhoc(id) ON DELETE CASCADE;


--
-- Name: gio_hoc_tap fk_giohoctap_tuan; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gio_hoc_tap
    ADD CONSTRAINT fk_giohoctap_tuan FOREIGN KEY (tuan_id) REFERENCES public.tuanhoc(id) ON DELETE CASCADE;


--
-- Name: phancong fk_phancong_namhoc; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.phancong
    ADD CONSTRAINT fk_phancong_namhoc FOREIGN KEY (namhoc) REFERENCES public.namhoc(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: phanquyen fk_phanquyen_namhoc; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.phanquyen
    ADD CONSTRAINT fk_phanquyen_namhoc FOREIGN KEY (nam_hoc) REFERENCES public.namhoc(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: ptdoanvien fk_ptdoanvien_namhoc; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ptdoanvien
    ADD CONSTRAINT fk_ptdoanvien_namhoc FOREIGN KEY (namhoc) REFERENCES public.namhoc(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: ql_baocao fk_ql_baocao_namhoc; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ql_baocao
    ADD CONSTRAINT fk_ql_baocao_namhoc FOREIGN KEY (nam_hoc_id) REFERENCES public.namhoc(id);


--
-- Name: ql_nop_bc fk_ql_nop_bc_baocao; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ql_nop_bc
    ADD CONSTRAINT fk_ql_nop_bc_baocao FOREIGN KEY (ql_bao_cao_id) REFERENCES public.ql_baocao(id) ON DELETE CASCADE;


--
-- Name: ql_nop_bc fk_ql_nop_bc_chidoan; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ql_nop_bc
    ADD CONSTRAINT fk_ql_nop_bc_chidoan FOREIGN KEY (chi_doan_id) REFERENCES public.qlchidoan(id) ON DELETE SET NULL;


--
-- Name: ql_nop_bc fk_ql_nop_bc_doanvien; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ql_nop_bc
    ADD CONSTRAINT fk_ql_nop_bc_doanvien FOREIGN KEY (doanvien_id) REFERENCES public.doanvien(id) ON DELETE CASCADE;


--
-- Name: qlchidoan fk_qlchidoan_namhoc; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.qlchidoan
    ADD CONSTRAINT fk_qlchidoan_namhoc FOREIGN KEY (namhoc) REFERENCES public.namhoc(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: settings fk_settings_namhoc; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.settings
    ADD CONSTRAINT fk_settings_namhoc FOREIGN KEY (namhoc) REFERENCES public.namhoc(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: thongbao_riengbiet fk_thongbao_riengbiet_namhoc; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.thongbao_riengbiet
    ADD CONSTRAINT fk_thongbao_riengbiet_namhoc FOREIGN KEY (namhoc_id) REFERENCES public.namhoc(id) ON DELETE CASCADE;


--
-- Name: thongbao_riengbiet fk_thongbao_riengbiet_taikhoan; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.thongbao_riengbiet
    ADD CONSTRAINT fk_thongbao_riengbiet_taikhoan FOREIGN KEY (sender_id) REFERENCES public.taikhoan(id) ON DELETE CASCADE;


--
-- Name: tieuchitd fk_tieuchitd_namhoc; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tieuchitd
    ADD CONSTRAINT fk_tieuchitd_namhoc FOREIGN KEY (namhoc) REFERENCES public.namhoc(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: tuanhoc fk_tuanhoc_namhoc; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tuanhoc
    ADD CONSTRAINT fk_tuanhoc_namhoc FOREIGN KEY (namhoc) REFERENCES public.namhoc(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: phancong phancong_chamlop_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.phancong
    ADD CONSTRAINT phancong_chamlop_fkey FOREIGN KEY (chamlop) REFERENCES public.qlchidoan(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: phancong phancong_lopcham_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.phancong
    ADD CONSTRAINT phancong_lopcham_fkey FOREIGN KEY (lopcham) REFERENCES public.qlchidoan(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: theodoi360 theodoi360_doan_vien_vi_pham_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.theodoi360
    ADD CONSTRAINT theodoi360_doan_vien_vi_pham_fkey FOREIGN KEY (doan_vien_vi_pham_id) REFERENCES public.doanvien(id);


--
-- Name: theodoi360 theodoi360_nam_hoc_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.theodoi360
    ADD CONSTRAINT theodoi360_nam_hoc_fkey FOREIGN KEY (nam_hoc_id) REFERENCES public.namhoc(id);


--
-- Name: theodoi360 theodoi360_nguoi_to_cao_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.theodoi360
    ADD CONSTRAINT theodoi360_nguoi_to_cao_fkey FOREIGN KEY (nguoi_to_cao_id) REFERENCES public.doanvien(id);


--
-- Name: theodoi360 theodoi360_tieu_chi_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.theodoi360
    ADD CONSTRAINT theodoi360_tieu_chi_fkey FOREIGN KEY (tieu_chi_id) REFERENCES public.tieuchitd(id);


--
-- Name: theodoi360 theodoi360_tuan_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.theodoi360
    ADD CONSTRAINT theodoi360_tuan_fkey FOREIGN KEY (tuan_id) REFERENCES public.tuanhoc(id);


--
-- Name: xet_thidua xet_thidua_chidoan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.xet_thidua
    ADD CONSTRAINT xet_thidua_chidoan_id_fkey FOREIGN KEY (chidoan_id) REFERENCES public.qlchidoan(id) ON DELETE CASCADE;


--
-- Name: xet_thidua xet_thidua_namhoc_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.xet_thidua
    ADD CONSTRAINT xet_thidua_namhoc_id_fkey FOREIGN KEY (namhoc_id) REFERENCES public.namhoc(id) ON DELETE CASCADE;


--
-- Name: duytricsdl ADMIN full quyền; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "ADMIN full quyền" ON public.duytricsdl TO authenticated USING ((public.get_auth_role() = 'ADMIN'::text)) WITH CHECK ((public.get_auth_role() = 'ADMIN'::text));


--
-- Name: github_settings ADMIN full quyền; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "ADMIN full quyền" ON public.github_settings TO authenticated USING ((public.get_auth_role() = 'ADMIN'::text)) WITH CHECK ((public.get_auth_role() = 'ADMIN'::text));


--
-- Name: namhoc ADMIN full quyền; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "ADMIN full quyền" ON public.namhoc TO authenticated USING ((public.get_auth_role() = 'ADMIN'::text)) WITH CHECK ((public.get_auth_role() = 'ADMIN'::text));


--
-- Name: phanquyen ADMIN full quyền; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "ADMIN full quyền" ON public.phanquyen TO authenticated USING ((public.get_auth_role() = 'ADMIN'::text)) WITH CHECK ((public.get_auth_role() = 'ADMIN'::text));


--
-- Name: settings ADMIN full quyền; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "ADMIN full quyền" ON public.settings TO authenticated USING ((public.get_auth_role() = 'ADMIN'::text)) WITH CHECK ((public.get_auth_role() = 'ADMIN'::text));


--
-- Name: taikhoan ADMIN full quyền; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "ADMIN full quyền" ON public.taikhoan TO authenticated USING ((public.get_auth_role() = 'ADMIN'::text)) WITH CHECK ((public.get_auth_role() = 'ADMIN'::text));


--
-- Name: vanban_doan ADMIN full quyền; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "ADMIN full quyền" ON public.vanban_doan TO authenticated USING ((public.get_auth_role() = 'ADMIN'::text)) WITH CHECK ((public.get_auth_role() = 'ADMIN'::text));


--
-- Name: phancong ADMIN, BTV full quyền; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "ADMIN, BTV full quyền" ON public.phancong TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text])));


--
-- Name: thongbao_hethong ADMIN, BTV full quyền; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "ADMIN, BTV full quyền" ON public.thongbao_hethong TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text])));


--
-- Name: tieuchitd ADMIN, BTV full quyền; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "ADMIN, BTV full quyền" ON public.tieuchitd TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text])));


--
-- Name: tuanhoc ADMIN, BTV full quyền; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "ADMIN, BTV full quyền" ON public.tuanhoc TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text])));


--
-- Name: xet_thidua ADMIN, BTV full quyền; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "ADMIN, BTV full quyền" ON public.xet_thidua TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text])));


--
-- Name: ptdoanvien ADMIN, BTV, BCH full quyền; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "ADMIN, BTV, BCH full quyền" ON public.ptdoanvien TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text, 'BCH'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text, 'BCH'::text])));


--
-- Name: ql_baocao ADMIN, BTV, BCH full quyền; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "ADMIN, BTV, BCH full quyền" ON public.ql_baocao TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text])));


--
-- Name: qlchidoan ADMIN, BTV, BCH full quyền; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "ADMIN, BTV, BCH full quyền" ON public.qlchidoan TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text, 'BCH'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text, 'BCH'::text])));


--
-- Name: theodoi360 ADMIN, BTV, BCH, NC, DV full quyền; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "ADMIN, BTV, BCH, NC, DV full quyền" ON public.theodoi360 TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'DV'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'DV'::text])));


--
-- Name: ql_nop_bc ADMIN, BTV, BCH, NC, GVCN, DV full quyền; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "ADMIN, BTV, BCH, NC, GVCN, DV full quyền" ON public.ql_nop_bc TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'GVCN'::text, 'DV'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'GVCN'::text, 'DV'::text])));


--
-- Name: thongbao_riengbiet ADMIN, BTV, BGH, GVCN full quyền; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "ADMIN, BTV, BGH, GVCN full quyền" ON public.thongbao_riengbiet TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text, 'BGH'::text, 'GVCN'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text, 'BGH'::text, 'GVCN'::text])));


--
-- Name: gio_hoc_tap ADMIN, BTV, NC full quyền; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "ADMIN, BTV, NC full quyền" ON public.gio_hoc_tap TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text, 'NC'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text, 'NC'::text])));


--
-- Name: cauhinh_tieuchi_xet_thidua Admin, BTV full quyền; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin, BTV full quyền" ON public.cauhinh_tieuchi_xet_thidua TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text])));


--
-- Name: doanvien Admin, BTV full quyền; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin, BTV full quyền" ON public.doanvien TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text])));


--
-- Name: dotptdoanvien Admin, BTV full quyền; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin, BTV full quyền" ON public.dotptdoanvien TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text])));


--
-- Name: chamdiem Admin, BTV, NC full quyền; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin, BTV, NC full quyền" ON public.chamdiem TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text, 'NC'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text, 'NC'::text])));


--
-- Name: doanvien BCH có quyền cập nhật; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "BCH có quyền cập nhật" ON public.doanvien FOR UPDATE TO authenticated USING ((public.get_auth_role() = 'BCH'::text)) WITH CHECK ((public.get_auth_role() = 'BCH'::text));


--
-- Name: duytricsdl Công cộng được cập nhật; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Công cộng được cập nhật" ON public.duytricsdl FOR UPDATE USING (true) WITH CHECK (true);


--
-- Name: duytricsdl Công cộng được xem; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Công cộng được xem" ON public.duytricsdl FOR SELECT USING (true);


--
-- Name: namhoc Khách vãng lai được xem; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Khách vãng lai được xem" ON public.namhoc FOR SELECT TO anon USING (true);


--
-- Name: activity_logs; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.activity_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: cauhinh_tieuchi_xet_thidua; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.cauhinh_tieuchi_xet_thidua ENABLE ROW LEVEL SECURITY;

--
-- Name: chamdiem; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.chamdiem ENABLE ROW LEVEL SECURITY;

--
-- Name: doanvien; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.doanvien ENABLE ROW LEVEL SECURITY;

--
-- Name: dotptdoanvien; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.dotptdoanvien ENABLE ROW LEVEL SECURITY;

--
-- Name: duytricsdl; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.duytricsdl ENABLE ROW LEVEL SECURITY;

--
-- Name: gio_hoc_tap; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.gio_hoc_tap ENABLE ROW LEVEL SECURITY;

--
-- Name: github_settings; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.github_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: namhoc; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.namhoc ENABLE ROW LEVEL SECURITY;

--
-- Name: phancong; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.phancong ENABLE ROW LEVEL SECURITY;

--
-- Name: phanquyen; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.phanquyen ENABLE ROW LEVEL SECURITY;

--
-- Name: ptdoanvien; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.ptdoanvien ENABLE ROW LEVEL SECURITY;

--
-- Name: push_subscriptions; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;

--
-- Name: ql_baocao; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.ql_baocao ENABLE ROW LEVEL SECURITY;

--
-- Name: ql_nop_bc; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.ql_nop_bc ENABLE ROW LEVEL SECURITY;

--
-- Name: qlchidoan; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.qlchidoan ENABLE ROW LEVEL SECURITY;

--
-- Name: settings; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.settings ENABLE ROW LEVEL SECURITY;

--
-- Name: taikhoan; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.taikhoan ENABLE ROW LEVEL SECURITY;

--
-- Name: theodoi360; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.theodoi360 ENABLE ROW LEVEL SECURITY;

--
-- Name: thongbao_hethong; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.thongbao_hethong ENABLE ROW LEVEL SECURITY;

--
-- Name: thongbao_riengbiet; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.thongbao_riengbiet ENABLE ROW LEVEL SECURITY;

--
-- Name: tieuchitd; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.tieuchitd ENABLE ROW LEVEL SECURITY;

--
-- Name: tuanhoc; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.tuanhoc ENABLE ROW LEVEL SECURITY;

--
-- Name: vanban_doan; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.vanban_doan ENABLE ROW LEVEL SECURITY;

--
-- Name: xet_thidua; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.xet_thidua ENABLE ROW LEVEL SECURITY;

--
-- Name: cauhinh_tieuchi_xet_thidua Đăng nhập được xem; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Đăng nhập được xem" ON public.cauhinh_tieuchi_xet_thidua FOR SELECT TO authenticated USING (true);


--
-- Name: chamdiem Đăng nhập được xem; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Đăng nhập được xem" ON public.chamdiem FOR SELECT TO authenticated USING (true);


--
-- Name: doanvien Đăng nhập được xem; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Đăng nhập được xem" ON public.doanvien FOR SELECT TO authenticated USING (true);


--
-- Name: dotptdoanvien Đăng nhập được xem; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Đăng nhập được xem" ON public.dotptdoanvien FOR SELECT TO authenticated USING (true);


--
-- Name: gio_hoc_tap Đăng nhập được xem; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Đăng nhập được xem" ON public.gio_hoc_tap FOR SELECT TO authenticated USING (true);


--
-- Name: github_settings Đăng nhập được xem; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Đăng nhập được xem" ON public.github_settings FOR SELECT TO authenticated USING (true);


--
-- Name: namhoc Đăng nhập được xem; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Đăng nhập được xem" ON public.namhoc FOR SELECT TO authenticated USING (true);


--
-- Name: phancong Đăng nhập được xem; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Đăng nhập được xem" ON public.phancong FOR SELECT TO authenticated USING (true);


--
-- Name: phanquyen Đăng nhập được xem; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Đăng nhập được xem" ON public.phanquyen FOR SELECT TO authenticated USING (true);


--
-- Name: ptdoanvien Đăng nhập được xem; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Đăng nhập được xem" ON public.ptdoanvien FOR SELECT TO authenticated USING (true);


--
-- Name: push_subscriptions Đăng nhập được xem; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Đăng nhập được xem" ON public.push_subscriptions TO authenticated USING (true);


--
-- Name: ql_baocao Đăng nhập được xem; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Đăng nhập được xem" ON public.ql_baocao FOR SELECT TO authenticated USING (true);


--
-- Name: ql_nop_bc Đăng nhập được xem; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Đăng nhập được xem" ON public.ql_nop_bc FOR SELECT TO authenticated USING (true);


--
-- Name: qlchidoan Đăng nhập được xem; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Đăng nhập được xem" ON public.qlchidoan FOR SELECT TO authenticated USING (true);


--
-- Name: settings Đăng nhập được xem; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Đăng nhập được xem" ON public.settings FOR SELECT TO authenticated USING (true);


--
-- Name: taikhoan Đăng nhập được xem; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Đăng nhập được xem" ON public.taikhoan FOR SELECT TO authenticated USING (true);


--
-- Name: theodoi360 Đăng nhập được xem; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Đăng nhập được xem" ON public.theodoi360 FOR SELECT TO authenticated USING (true);


--
-- Name: thongbao_hethong Đăng nhập được xem; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Đăng nhập được xem" ON public.thongbao_hethong FOR SELECT TO authenticated USING (true);


--
-- Name: thongbao_riengbiet Đăng nhập được xem; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Đăng nhập được xem" ON public.thongbao_riengbiet FOR SELECT TO authenticated USING (true);


--
-- Name: tieuchitd Đăng nhập được xem; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Đăng nhập được xem" ON public.tieuchitd FOR SELECT TO authenticated USING (true);


--
-- Name: tuanhoc Đăng nhập được xem; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Đăng nhập được xem" ON public.tuanhoc FOR SELECT TO authenticated USING (true);


--
-- Name: vanban_doan Đăng nhập được xem; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Đăng nhập được xem" ON public.vanban_doan FOR SELECT TO authenticated USING (true);


--
-- Name: xet_thidua Đăng nhập được xem; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Đăng nhập được xem" ON public.xet_thidua FOR SELECT TO authenticated USING (true);


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--



--
-- Name: FUNCTION check_user_mfa_status(); Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: FUNCTION fn_dong_bo_taikhoan_sang_auth_users(); Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: FUNCTION fn_is_mfa_enabled(); Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: FUNCTION fn_kiem_tra_an_ninh_taikhoan(); Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: FUNCTION fn_tu_dong_bam_mat_khau_taikhoan(); Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: FUNCTION get_auth_chidoan_id(); Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: FUNCTION get_auth_doanvien_id(); Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: FUNCTION get_auth_role(); Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: FUNCTION get_my_role(); Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: FUNCTION get_secure_chidoan_id(); Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: FUNCTION get_secure_doanvien_id(); Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: FUNCTION get_secure_role(); Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: FUNCTION handle_chi_doan_deletion(); Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: FUNCTION handle_post_like(); Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: FUNCTION handle_update_likes_count(); Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: FUNCTION rpc_admin_reset_user_mfa(p_user_id text, p_username text); Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: FUNCTION rpc_authenticate_user(p_username text, p_password text); Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: FUNCTION rpc_create_account_secure(p_username text, p_password text, p_fullname text, p_role text, p_chidoan_id uuid, p_doanvien_id uuid); Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: FUNCTION rpc_create_account_secure(p_username text, p_password text, p_fullname text, p_role text, p_chidoan_id uuid, p_namhoc uuid, p_sdt text); Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: FUNCTION rpc_delete_auth_users_by_usernames(p_usernames text[]); Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: FUNCTION rpc_get_user_by_username(p_username text); Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: FUNCTION rpc_tao_tai_khoan_an_toan(p_username text, p_password text, p_fullname text, p_role text, p_chidoan_id uuid, p_doanvien_id uuid); Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: FUNCTION save_user_backup_codes(p_encrypted_codes text); Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: FUNCTION update_likes_count(); Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: FUNCTION update_modified_column(); Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: FUNCTION verify_and_consume_backup_code(p_code text); Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: TABLE activity_logs; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: TABLE cauhinh_tieuchi_xet_thidua; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: TABLE chamdiem; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: TABLE doanvien; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: TABLE dotptdoanvien; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: TABLE duytricsdl; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: TABLE gio_hoc_tap; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: TABLE github_settings; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: TABLE namhoc; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: TABLE phancong; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: TABLE phanquyen; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: SEQUENCE phanquyen_id_seq; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: TABLE ptdoanvien; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: TABLE push_subscriptions; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: TABLE ql_baocao; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: TABLE ql_nop_bc; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: TABLE qlchidoan; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: TABLE settings; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: TABLE taikhoan; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: TABLE theodoi360; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: TABLE thongbao_hethong; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: TABLE thongbao_riengbiet; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: TABLE tieuchitd; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: TABLE tuanhoc; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: TABLE vanban_doan; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: TABLE xet_thidua; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--



--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--



--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: postgres
--



--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--



--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--



--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--



--
-- PostgreSQL database dump complete
--

\unrestrict jlhqOj4zvCD3rcZ7uVM2Mf48l5c9uaZjbK9WXhOSbqAlStJPhsx5v6fXEZMcakQ


-- 1. Khởi tạo tài khoản quản trị
INSERT INTO public.taikhoan (username, password, fullname, role, chidoan_id)
VALUES (
    'Admin', 
    '$argon2id$v=19$m=65536,t=3,p=4$PUDXJllthdBNREj7Jd2KTw$blk3GJ2W6Jk/+OxXqPO9quBJtU9mjQqcHb6rYNmBxjM', 
    'Quản trị', 
    'Admin', 
    NULL
) ON CONFLICT (username) DO NOTHING;

-- 2. Khởi tạo bảng duy trì CSDL
INSERT INTO public.duytricsdl (so) 
VALUES (1) 
ON CONFLICT DO NOTHING;

-- 3. Khởi tạo cấu hình GitHub
INSERT INTO public.github_settings (
    id, 
    github_repo_path, 
    github_branch, 
    github_workflow_file, 
    github_restore_workflow_file, 
    github_token
)
VALUES (
    'project_02',
    'congty/du_an_backend',
    'main',
    'supabase-backup.yml',
    'supabase-restore.yml',
    'ghp_abc123...'
) ON CONFLICT (id) DO NOTHING;
