-- =========================================================================
-- V4 - BẢN SAO LƯU CHỈ CẤU TRÚC TỪ CƠ SỞ DỮ LIỆU NGUỒN
-- Bao gồm toàn bộ custom/application schemas của SOURCE_DB_URL. Không dùng TARGET_DB_URL.
-- Không chứa dữ liệu mẫu/seed. Giữ ACL/GRANT/REVOKE của SOURCE.
-- Các schema ứng dụng:
--   - public
--   - audit
-- =========================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;

--
-- PostgreSQL database dump
--


-- Dumped from database version 17.11
-- Dumped by pg_dump version 17.11 (Ubuntu 17.11-1.pgdg26.04+2)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: audit; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA audit;


--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--



--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: insert_update_delete_trigger(); Type: FUNCTION; Schema: audit; Owner: -
--

CREATE FUNCTION audit.insert_update_delete_trigger() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'audit', 'auth'
    AS $$
DECLARE
    v_pkey_cols text[] := audit.primary_key_columns(TG_RELID);
    v_record_id uuid;
    v_old_record_id uuid;
    v_new_record jsonb;
    v_old_record jsonb;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_new_record := to_jsonb(NEW);
        v_record_id := audit.to_record_id(TG_RELID, v_pkey_cols, v_new_record);
        
        INSERT INTO audit.record_version (
            record_id, old_record_id, op, ts,
            table_oid, table_schema, table_name,
            record, old_record, auth_uid, auth_role
        ) VALUES (
            v_record_id, NULL, TG_OP, now(),
            TG_RELID, TG_TABLE_SCHEMA, TG_TABLE_NAME,
            v_new_record, NULL, auth.uid(), auth.role()
        );
        RETURN NEW;

    ELSIF TG_OP = 'UPDATE' THEN
        v_new_record := to_jsonb(NEW);
        v_old_record := to_jsonb(OLD);
        v_record_id := audit.to_record_id(TG_RELID, v_pkey_cols, v_new_record);
        v_old_record_id := audit.to_record_id(TG_RELID, v_pkey_cols, v_old_record);

        INSERT INTO audit.record_version (
            record_id, old_record_id, op, ts,
            table_oid, table_schema, table_name,
            record, old_record, auth_uid, auth_role
        ) VALUES (
            v_record_id, v_old_record_id, TG_OP, now(),
            TG_RELID, TG_TABLE_SCHEMA, TG_TABLE_NAME,
            v_new_record, v_old_record, auth.uid(), auth.role()
        );
        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN
        v_old_record := to_jsonb(OLD);
        v_old_record_id := audit.to_record_id(TG_RELID, v_pkey_cols, v_old_record);

        INSERT INTO audit.record_version (
            record_id, old_record_id, op, ts,
            table_oid, table_schema, table_name,
            record, old_record, auth_uid, auth_role
        ) VALUES (
            NULL, v_old_record_id, TG_OP, now(),
            TG_RELID, TG_TABLE_SCHEMA, TG_TABLE_NAME,
            NULL, v_old_record, auth.uid(), auth.role()
        );
        RETURN OLD;
    END IF;

    RETURN NULL;
END;
$$;


--
-- Name: primary_key_columns(oid); Type: FUNCTION; Schema: audit; Owner: -
--

CREATE FUNCTION audit.primary_key_columns(p_table_oid oid) RETURNS text[]
    LANGUAGE sql STABLE
    AS $$
    SELECT COALESCE(
        (SELECT array_agg(a.attname::text ORDER BY a.attnum)
         FROM pg_index i
         JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
         WHERE i.indrelid = p_table_oid AND i.indisprimary),
        ARRAY['id']::text[]
    );
$$;


--
-- Name: to_record_id(oid, text[], jsonb); Type: FUNCTION; Schema: audit; Owner: -
--

CREATE FUNCTION audit.to_record_id(p_table_oid oid, p_pkey_cols text[], p_record jsonb) RETURNS uuid
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN (p_record ->> COALESCE(p_pkey_cols[1], 'id'))::uuid;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$;


--
-- Name: calculate_scores_advanced(uuid, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_scores_advanced(p_namhoc_id uuid, p_chidoan_id uuid DEFAULT NULL::uuid, p_doanvien_id uuid DEFAULT NULL::uuid) RETURNS TABLE(doanvien_id uuid, diem_hk1 numeric, diem_hk2 numeric, diem_cn numeric)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  v_diem_san NUMERIC;
BEGIN
  -- 1. ĐIỀU KIỆN TIÊN QUYẾT: BẮT BUỘC PHẢI TRUYỀN NĂM HỌC HIỆN TẠI
  IF p_namhoc_id IS NULL THEN
    RAISE EXCEPTION 'Lỗi nghiêm ngặt: Tham số p_namhoc_id (Năm học hiện tại) là bắt buộc và không được để trống!';
  END IF;

  -- 2. LẤY ĐIỂM SÀN CỦA ĐÚNG NĂM HỌC HIỆN TẠI TỪ BẢNG SETTINGS
  SELECT COALESCE(diemsanhocky, 0) INTO v_diem_san 
  FROM public.settings 
  WHERE namhoc = p_namhoc_id 
  LIMIT 1;

  -- Nếu chưa thiết lập riêng theo năm học, lấy cấu hình chung của hệ thống
  IF v_diem_san IS NULL THEN
    SELECT COALESCE(diemsanhocky, 0) INTO v_diem_san 
    FROM public.settings 
    WHERE namhoc IS NULL 
    LIMIT 1;
  END IF;

  IF v_diem_san IS NULL THEN
    SELECT COALESCE(diemsanhocky, 0) INTO v_diem_san 
    FROM public.settings 
    LIMIT 1;
  END IF;

  IF v_diem_san IS NULL THEN
    v_diem_san := 0;
  END IF;

  RETURN QUERY
  -- 3. GOM NHÓM ĐIỂM VÀ LỌC CHẶT CHẼ THEO NĂM HỌC HIỆN TẠI
  WITH ScoreSummary AS (
    SELECT 
      dv.id AS dv_id,
      
      -- Tổng điểm Cộng của riêng HỌC KỲ 1 trong đúng năm học hiện tại
      COALESCE(SUM(
        CASE 
          WHEN (
            REPLACE(REPLACE(LOWER(TRIM(COALESCE(cd.hocky, ''))), ' ', ''), '_', '') IN (
              'hk1', 'hocky1', 'hocki1', 'hki', '1', 
              'họckỳ1', 'họckì1', 'họckỳi', 'họckìi', 'kỳ1', 'kì1', 'ky1', 'ki1'
            )
            OR (
              (LOWER(TRIM(COALESCE(cd.hocky, ''))) LIKE '%1%' OR LOWER(TRIM(COALESCE(cd.hocky, ''))) LIKE '%i')
              AND LOWER(TRIM(COALESCE(cd.hocky, ''))) NOT LIKE '%ii%'
              AND LOWER(TRIM(COALESCE(cd.hocky, ''))) NOT LIKE '%2%'
            )
          ) THEN COALESCE(cd.diemcong::NUMERIC, 0) 
          ELSE 0 
        END
      ), 0) AS total_cong_hk1,
      
      -- Tổng điểm Trừ của riêng HỌC KỲ 1 trong đúng năm học hiện tại
      COALESCE(SUM(
        CASE 
          WHEN (
            REPLACE(REPLACE(LOWER(TRIM(COALESCE(cd.hocky, ''))), ' ', ''), '_', '') IN (
              'hk1', 'hocky1', 'hocki1', 'hki', '1', 
              'họckỳ1', 'họckì1', 'họckỳi', 'họckìi', 'kỳ1', 'kì1', 'ky1', 'ki1'
            )
            OR (
              (LOWER(TRIM(COALESCE(cd.hocky, ''))) LIKE '%1%' OR LOWER(TRIM(COALESCE(cd.hocky, ''))) LIKE '%i')
              AND LOWER(TRIM(COALESCE(cd.hocky, ''))) NOT LIKE '%ii%'
              AND LOWER(TRIM(COALESCE(cd.hocky, ''))) NOT LIKE '%2%'
            )
          ) THEN COALESCE(cd.diemtru::NUMERIC, 0) 
          ELSE 0 
        END
      ), 0) AS total_tru_hk1,
      
      -- Tổng điểm Cộng của riêng HỌC KỲ 2 trong đúng năm học hiện tại
      COALESCE(SUM(
        CASE 
          WHEN (
            REPLACE(REPLACE(LOWER(TRIM(COALESCE(cd.hocky, ''))), ' ', ''), '_', '') IN (
              'hk2', 'hocky2', 'hocki2', 'hkii', '2', 
              'họckỳ2', 'họckì2', 'họckỳii', 'họckìii', 'kỳ2', 'kì2', 'ky2', 'ki2'
            )
            OR (
              LOWER(TRIM(COALESCE(cd.hocky, ''))) LIKE '%2%' 
              OR LOWER(TRIM(COALESCE(cd.hocky, ''))) LIKE '%ii%'
            )
          ) THEN COALESCE(cd.diemcong::NUMERIC, 0) 
          ELSE 0 
        END
      ), 0) AS total_cong_hk2,
      
      -- Tổng điểm Trừ của riêng HỌC KỲ 2 trong đúng năm học hiện tại
      COALESCE(SUM(
        CASE 
          WHEN (
            REPLACE(REPLACE(LOWER(TRIM(COALESCE(cd.hocky, ''))), ' ', ''), '_', '') IN (
              'hk2', 'hocky2', 'hocki2', 'hkii', '2', 
              'họckỳ2', 'họckì2', 'họckỳii', 'họckìii', 'kỳ2', 'kì2', 'ky2', 'ki2'
            )
            OR (
              LOWER(TRIM(COALESCE(cd.hocky, ''))) LIKE '%2%' 
              OR LOWER(TRIM(COALESCE(cd.hocky, ''))) LIKE '%ii%'
            )
          ) THEN COALESCE(cd.diemtru::NUMERIC, 0) 
          ELSE 0 
        END
      ), 0) AS total_tru_hk2

    -- BẢO VỆ 1: CHỈ LẤY ĐOÀN VIÊN THUỘC NĂM HỌC HIỆN TẠI (TUYỆT ĐỐI KHÔNG QUÉT NĂM CŨ)
    FROM public.doanvien dv
    
    -- BẢO VỆ 2: LEFT JOIN ĐẢM BẢO 100% HỌC SINH KHÔNG BỊ MẤT DÒNG
    -- VÀ CHỈ LẤY ĐIỂM CHẤM THUỘC NĂM HỌC HIỆN TẠI
    LEFT JOIN public.chamdiem cd 
           ON dv.id = cd.doanvienid 
          AND cd.namhoc = p_namhoc_id
           
    WHERE 
      -- ĐIỀU KIỆN TIÊN QUYẾT: LUÔN LUÔN VÀ DUY NHẤT TRONG NĂM HỌC ĐƯỢC CHỈ ĐỊNH
      dv.namhoc = p_namhoc_id
      
      -- Phân quyền theo Chi đoàn quản lý (GVCN/BCH) nếu có chỉ định
      AND (p_chidoan_id IS NULL OR dv.chidoan_id = p_chidoan_id)
      
      -- Phân quyền theo cá nhân Đoàn viên nếu là học sinh tự xem
      AND (p_doanvien_id IS NULL OR dv.id = p_doanvien_id)
      
    GROUP BY dv.id
  )
  
  -- 4. ÁP DỤNG CÔNG THỨC TOÁN HỌC NHẤT QUÁN 100% (CN = HK1 + HK2)
  SELECT 
    s.dv_id AS doanvien_id,
    
    -- HK1 = Điểm Sàn + Tổng Cộng HK1 - Tổng Trừ HK1
    (v_diem_san + s.total_cong_hk1 - s.total_tru_hk1) AS diem_hk1,
    
    -- HK2 = Điểm Sàn + Tổng Cộng HK2 - Tổng Trừ HK2
    (v_diem_san + s.total_cong_hk2 - s.total_tru_hk2) AS diem_hk2,
    
    -- CẢ NĂM = Đúng bằng HK1 + HK2 (Toán học nhất quán hoàn hảo)
    ((v_diem_san * 2) + (s.total_cong_hk1 + s.total_cong_hk2) - (s.total_tru_hk1 + s.total_tru_hk2)) AS diem_cn
    
  FROM ScoreSummary s;
END;
$$;


--
-- Name: calculate_scores_by_year(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_scores_by_year(p_namhoc_id uuid) RETURNS TABLE(doanvien_id uuid, diem_hk1 numeric, diem_hk2 numeric, diem_cn numeric)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_diemsan numeric;
BEGIN
    -- Lấy điểm sàn
    SELECT COALESCE(diemsanhocky, 0) INTO v_diemsan
    FROM public.settings
    LIMIT 1;

    IF v_diemsan IS NULL THEN
        v_diemsan := 0;
    END IF;

    RETURN QUERY
    WITH raw_scores AS (
        SELECT
            cd.doanvienid,
            CASE WHEN upper(trim(cd.hocky)) IN ('HK1', 'HỌC KỲ 1', 'HỌC KÌ 1', 'HK I', 'HKI', 'HỌC KỲ I', 'HỌC KÌ I', '1') 
                 THEN COALESCE(cd.diemcong, 0) ELSE 0 END AS hk1_cong,
            CASE WHEN upper(trim(cd.hocky)) IN ('HK1', 'HỌC KỲ 1', 'HỌC KÌ 1', 'HK I', 'HKI', 'HỌC KỲ I', 'HỌC KÌ I', '1') 
                 THEN COALESCE(cd.diemtru, 0) ELSE 0 END AS hk1_tru,
                 
            CASE WHEN upper(trim(cd.hocky)) IN ('HK2', 'HỌC KỲ 2', 'HỌC KÌ 2', 'HK II', 'HKII', 'HỌC KỲ II', 'HỌC KÌ II', '2') 
                 THEN COALESCE(cd.diemcong, 0) ELSE 0 END AS hk2_cong,
            CASE WHEN upper(trim(cd.hocky)) IN ('HK2', 'HỌC KỲ 2', 'HỌC KÌ 2', 'HK II', 'HKII', 'HỌC KỲ II', 'HỌC KÌ II', '2') 
                 THEN COALESCE(cd.diemtru, 0) ELSE 0 END AS hk2_tru
        FROM public.chamdiem cd
        WHERE cd.namhoc = p_namhoc_id
    ),
    aggregated AS (
        SELECT
            r.doanvienid,
            SUM(r.hk1_cong) AS sum_hk1_cong,
            SUM(r.hk1_tru) AS sum_hk1_tru,
            SUM(r.hk2_cong) AS sum_hk2_cong,
            SUM(r.hk2_tru) AS sum_hk2_tru
        FROM raw_scores r
        GROUP BY r.doanvienid
    )
    SELECT
        a.doanvienid,
        (v_diemsan + a.sum_hk1_cong - a.sum_hk1_tru) AS diem_hk1,
        (v_diemsan + a.sum_hk2_cong - a.sum_hk2_tru) AS diem_hk2,
        ((v_diemsan + a.sum_hk1_cong - a.sum_hk1_tru) + (v_diemsan + a.sum_hk2_cong - a.sum_hk2_tru)) AS diem_cn
    FROM aggregated a
    WHERE a.doanvienid IS NOT NULL;
END;
$$;


--
-- Name: check_user_mfa_status(); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: fn_dem_du_lieu_lien_quan_tuan(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_dem_du_lieu_lien_quan_tuan(p_namhoc_id uuid, p_tuan_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_rec_tuan record;
  v_count_phancong integer := 0;
  v_count_chamdiem integer := 0;
  v_count_giohoctap integer := 0;
  v_count_theodoi360 integer := 0;
  v_tuan_num text;
BEGIN
  -- 1. Lấy thông tin tuần và kiểm tra chéo năm học
  SELECT th.id, th.namhoc, th.hocky, th.tuan, th.tungay, th.denngay, th.islocked, nh.tennamhoc
  INTO v_rec_tuan
  FROM public.tuanhoc th
  LEFT JOIN public.namhoc nh ON nh.id = th.namhoc
  WHERE th.id = p_tuan_id AND th.namhoc = p_namhoc_id;

  IF v_rec_tuan.id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Tuần học không tồn tại hoặc không thuộc năm học đã chỉ định!'
    );
  END IF;

  v_tuan_num := regexp_replace(COALESCE(v_rec_tuan.tuan, ''), '[^0-9]', '', 'g');

  -- 2. Đếm số bản ghi phân công chấm chéo
  SELECT count(*) INTO v_count_phancong
  FROM public.phancong pc
  WHERE pc.namhoc = p_namhoc_id
    AND (TRIM(pc.hocky) = TRIM(v_rec_tuan.hocky) OR pc.hocky ILIKE '%' || v_rec_tuan.hocky || '%')
    AND (
      TRIM(pc.tuan) = TRIM(v_rec_tuan.tuan) 
      OR (v_tuan_num <> '' AND regexp_replace(pc.tuan, '[^0-9]', '', 'g') = v_tuan_num)
    );

  -- 3. Đếm số bản ghi phiếu chấm điểm thi đua
  SELECT count(*) INTO v_count_chamdiem
  FROM public.chamdiem cd
  WHERE cd.namhoc = p_namhoc_id
    AND (TRIM(cd.hocky) = TRIM(v_rec_tuan.hocky) OR cd.hocky ILIKE '%' || v_rec_tuan.hocky || '%')
    AND (
      TRIM(cd.tuan) = TRIM(v_rec_tuan.tuan) 
      OR (v_tuan_num <> '' AND regexp_replace(cd.tuan, '[^0-9]', '', 'g') = v_tuan_num)
    );

  -- 4. Đếm số bản ghi giờ học tốt (bảng gio_hoc_tap) - Bọc Try Catch để tránh lỗi db structure
  BEGIN
    SELECT count(*) INTO v_count_giohoctap
    FROM public.gio_hoc_tap gh
    WHERE gh.namhoc_id = p_namhoc_id AND gh.tuan_id = p_tuan_id;
  EXCEPTION WHEN OTHERS THEN
    v_count_giohoctap := 0;
  END;

  -- 5. Đếm số bản ghi theo dõi 360 - Bọc Try Catch để tránh lỗi db structure
  BEGIN
    SELECT count(*) INTO v_count_theodoi360
    FROM public.theodoi360 td
    WHERE td.nam_hoc_id = p_namhoc_id AND td.tuan_id = p_tuan_id;
  EXCEPTION WHEN OTHERS THEN
    v_count_theodoi360 := 0;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'tuan_id', v_rec_tuan.id,
    'tuan', v_rec_tuan.tuan,
    'hocky', v_rec_tuan.hocky,
    'namhoc_id', p_namhoc_id,
    'tennamhoc', COALESCE(v_rec_tuan.tennamhoc, 'Không xác định'),
    'tungay', v_rec_tuan.tungay,
    'denngay', v_rec_tuan.denngay,
    'islocked', v_rec_tuan.islocked,
    'so_phan_cong', v_count_phancong,
    'so_cham_diem', v_count_chamdiem,
    'so_gio_hoc_tap', v_count_giohoctap,
    'so_theodoi360', v_count_theodoi360,
    'tong_ban_ghi', (v_count_phancong + v_count_chamdiem + v_count_giohoctap + v_count_theodoi360 + 1)
  );
END;
$$;


--
-- Name: fn_dong_bo_taikhoan_sang_auth_users(); Type: FUNCTION; Schema: public; Owner: -
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
        '', '', '', '', '', '', '', '', false, false
      );

      INSERT INTO auth.identities (
        id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at
      ) VALUES (
        v_user_id, v_user_id, json_build_object('sub', v_user_id::text, 'email', v_new_email)::jsonb, 'email', v_new_email, now(), now(), now()
      ) ON CONFLICT DO NOTHING;
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
        updated_at = now()
      WHERE id = v_user_id;
    END IF;

    -- [TÍNH NĂNG MỚI] LƯU UID NGƯỢC LẠI BẢNG TÀI KHOẢN
    UPDATE public.taikhoan 
    SET uid = v_user_id 
    WHERE id = NEW.id AND uid IS DISTINCT FROM v_user_id;

    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    -- [TÍNH NĂNG MỚI] THUẬT TOÁN CHỐNG LẶP VÔ HẠN (INFINITE LOOP)
    -- Khi hàm này gọi lệnh UPDATE public.taikhoan ở cuối, nó sẽ kích hoạt lại trigger.
    -- Đoạn mã này sẽ bắt và chặn đứng vòng lặp nếu phát hiện chỉ có cột uid bị thay đổi.
    IF NEW.uid IS DISTINCT FROM OLD.uid 
       AND NEW.username IS NOT DISTINCT FROM OLD.username 
       AND NEW.password IS NOT DISTINCT FROM OLD.password 
       AND NEW.role IS NOT DISTINCT FROM OLD.role 
       AND NEW.chidoan_id IS NOT DISTINCT FROM OLD.chidoan_id 
       AND NEW.doanvien_id IS NOT DISTINCT FROM OLD.doanvien_id THEN
      RETURN NEW;
    END IF;

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
        encrypted_password = CASE WHEN v_encrypted_pwd IS NOT NULL THEN v_encrypted_pwd ELSE encrypted_password END,
        raw_user_meta_data = json_build_object(
          'username', NEW.username,
          'fullname', COALESCE(NEW.fullname, NEW.username),
          'role', COALESCE(NEW.role, 'DV'),
          'chidoan_id', NEW.chidoan_id,
          'doanvien_id', NEW.doanvien_id
        )::jsonb,
        updated_at = now()
      WHERE id = v_user_id;
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
        instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change, phone_change, phone_change_token, email_change_token_current, reauthentication_token, is_sso_user, is_anonymous
      ) VALUES (
        '00000000-0000-0000-0000-000000000000', v_user_id, 'authenticated', 'authenticated', v_new_email, v_encrypted_pwd, now(), '{"provider":"email","providers":["email"]}'::jsonb,
        json_build_object(
          'username', NEW.username, 'fullname', COALESCE(NEW.fullname, NEW.username), 'role', COALESCE(NEW.role, 'DV'), 'chidoan_id', NEW.chidoan_id, 'doanvien_id', NEW.doanvien_id
        )::jsonb, now(), now(), '', '', '', '', '', '', '', '', false, false
      );

      INSERT INTO auth.identities (
        id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at
      ) VALUES (
        v_user_id, v_user_id, json_build_object('sub', v_user_id::text, 'email', v_new_email)::jsonb, 'email', v_new_email, now(), now(), now()
      ) ON CONFLICT DO NOTHING;
    END IF;

    -- [TÍNH NĂNG MỚI] LƯU UID NGƯỢC LẠI BẢNG TÀI KHOẢN
    UPDATE public.taikhoan 
    SET uid = v_user_id 
    WHERE id = NEW.id AND uid IS DISTINCT FROM v_user_id;

    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$_$;


--
-- Name: fn_is_mfa_enabled(); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: fn_kiem_tra_an_ninh_taikhoan(); Type: FUNCTION; Schema: public; Owner: -
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
  -- Kiểm tra xem người thực hiện có phải là quản trị viên hệ thống DB (Table Editor) hay không
  v_is_db_admin := (current_user IN ('postgres', 'service_role', 'supabase_admin'));
  
  v_current_auth_role := COALESCE(auth.role(), 'anon');
  v_current_user_email := COALESCE(auth.email(), '');

  -- 1. Cấm hoàn toàn thao tác từ API ẩn danh (áp dụng cho tất cả trừ DB Admin)
  IF NOT v_is_db_admin AND v_current_auth_role = 'anon' THEN
    RAISE EXCEPTION 'BAO MAT CANH BAO: Nghiem cam tao, sua doi hoac xoa tai khoan tu API ben ngoai!';
  END IF;

  -- Xác định quyền của người đang thực hiện thao tác (nếu qua API/App)
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

  -- 2. Xử lý khi XÓA tài khoản (DELETE)
  IF TG_OP = 'DELETE' THEN
    -- Cấm xóa tài khoản admin gốc (BỎ QUA nếu đang thao tác trên Table Editor)
    IF NOT v_is_db_admin AND lower(trim(OLD.username)) = 'admin' THEN
      RAISE EXCEPTION 'BAO MAT: Nghiem cam xoa tai khoan Admin goc cua he thong!';
    END IF;

    -- Chỉ ADMIN hoặc DB Admin mới được xóa tài khoản
    IF NOT v_is_db_admin AND (v_operator_role IS NULL OR v_operator_role <> 'ADMIN') THEN
      RAISE EXCEPTION 'BAO MAT: Ban khong co quyen xoa tai khoan!';
    END IF;

    RETURN OLD;
  END IF;

  -- 3. Xử lý khi THÊM (INSERT) hoặc SỬA (UPDATE)
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    v_target_role_upper := upper(trim(COALESCE(NEW.role, 'DV')));

    -- Cấm đổi tên hoặc hạ quyền tài khoản admin gốc (BỎ QUA nếu đang thao tác trên Table Editor)
    IF NOT v_is_db_admin AND TG_OP = 'UPDATE' AND lower(trim(OLD.username)) = 'admin' THEN
      IF lower(trim(NEW.username)) <> 'admin' OR v_target_role_upper <> 'ADMIN' THEN
        RAISE EXCEPTION 'BAO MAT: Khong duoc phep doi ten hoac ha quyen cua tai khoan Admin goc!';
      END IF;
    END IF;

    -- Cấm người dùng bình thường tự cấp quyền quản trị (ADMIN, BTV, BGH)
    IF v_target_role_upper IN ('ADMIN', 'BTV', 'BGH') THEN
      IF TG_OP = 'UPDATE' AND upper(trim(COALESCE(OLD.role, ''))) = v_target_role_upper THEN
        -- Cho phép nếu giữ nguyên quyền cũ
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


--
-- Name: fn_kiem_tra_va_khoa_tuan(uuid, text, text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_kiem_tra_va_khoa_tuan(p_namhoc_id uuid DEFAULT NULL::uuid, p_hocky text DEFAULT NULL::text, p_tuan text DEFAULT NULL::text, p_force boolean DEFAULT false) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
BEGIN
  RETURN public.fn_tu_dong_khoa_tuan_va_xu_phat_thu_cong();
END;
$$;


--
-- Name: fn_kiem_tra_xu_phat_tuan_thu_cong(text, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_kiem_tra_xu_phat_tuan_thu_cong(p_tuan text, p_hocky text DEFAULT NULL::text, p_namhoc_id uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
    v_namhoc_id uuid;
    v_tennamhoc text;
    v_diem_tru numeric;
    v_tieu_chi text;
    v_nguoi_bao_cao text;
    v_tuan RECORD;
    v_lop_vi_pham RECORD;
    v_so_lop_bi_phat int := 0;
    v_penalized_list jsonb := '[]'::jsonb;
BEGIN
    -- 1. Xác định CHÍNH XÁC Năm học
    IF p_namhoc_id IS NOT NULL THEN
        SELECT id, tennamhoc INTO v_namhoc_id, v_tennamhoc 
        FROM public.namhoc 
        WHERE id = p_namhoc_id 
        LIMIT 1;
    ELSE
        SELECT id, tennamhoc INTO v_namhoc_id, v_tennamhoc 
        FROM public.namhoc 
        WHERE isdefault = true 
        LIMIT 1;
    END IF;

    IF v_namhoc_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Không tìm thấy năm học hợp lệ trong hệ thống.');
    END IF;

    -- 2. 100% ĐỌC CẤU HÌNH TỪ BẢNG SETTINGS CỦA CHÍNH NĂM HỌC NÀY
    SELECT 
        autopenaltypoints,
        autopenaltycriteria,
        autopenaltyreporter
    INTO 
        v_diem_tru, 
        v_tieu_chi, 
        v_nguoi_bao_cao
    FROM public.settings
    WHERE namhoc = v_namhoc_id
    LIMIT 1;

    -- Nếu bảng settings chưa cấu hình hoặc thông số bị để trống -> Báo lỗi ngay lập tức
    IF v_diem_tru IS NULL OR v_tieu_chi IS NULL OR v_nguoi_bao_cao IS NULL THEN
        RETURN jsonb_build_object(
            'success', false, 
            'message', 'Chưa có cấu hình thông số xử phạt trong bảng settings cho năm học: ' || COALESCE(v_tennamhoc, '') || '. Vui lòng lưu cấu hình trước khi xử phạt.'
        );
    END IF;

    -- 3. Tìm thông tin tuần của CHÍNH XÁC năm học này
    SELECT id, tuan, hocky, tungay, denngay, islocked
    INTO v_tuan
    FROM public.tuanhoc
    WHERE namhoc = v_namhoc_id 
      AND (TRIM(tuan) = TRIM(p_tuan) OR regexp_replace(tuan, '[^0-9]', '', 'g') = regexp_replace(p_tuan, '[^0-9]', '', 'g'))
      AND (p_hocky IS NULL OR hocky = p_hocky)
    LIMIT 1;

    IF v_tuan.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Không tìm thấy thông tin Tuần ' || p_tuan || ' trong năm học ' || COALESCE(v_tennamhoc, ''));
    END IF;

    IF v_tuan.islocked IS NOT TRUE THEN
        RETURN jsonb_build_object('success', false, 'message', 'Tuần ' || p_tuan || ' chưa bị khóa. Vui lòng khóa tuần trước khi xử phạt.');
    END IF;

    -- 4. Quét tìm và xử phạt các lớp chưa nộp bài của ĐÚNG năm học này
    FOR v_lop_vi_pham IN
        WITH lop_co_nghia_vu AS (
            SELECT DISTINCT pc.lopcham AS chidoan_id
            FROM public.phancong pc
            WHERE pc.namhoc = v_namhoc_id
              AND (TRIM(pc.tuan) = TRIM(v_tuan.tuan) OR regexp_replace(pc.tuan, '[^0-9]', '', 'g') = regexp_replace(v_tuan.tuan, '[^0-9]', '', 'g'))
              AND (TRIM(pc.hocky) = TRIM(v_tuan.hocky) OR pc.hocky ILIKE '%' || v_tuan.hocky || '%')
              AND pc.lopcham IS NOT NULL
        ),
        lop_da_nop_phieu AS (
            SELECT DISTINCT cd.lopcham AS chidoan_id
            FROM public.chamdiem cd
            WHERE cd.namhoc = v_namhoc_id
              AND (TRIM(cd.tuan) = TRIM(v_tuan.tuan) OR regexp_replace(cd.tuan, '[^0-9]', '', 'g') = regexp_replace(v_tuan.tuan, '[^0-9]', '', 'g'))
              AND (TRIM(cd.hocky) = TRIM(v_tuan.hocky) OR cd.hocky ILIKE '%' || v_tuan.hocky || '%')
              AND (cd.matieuchi IS DISTINCT FROM 'TUDONG')
              AND cd.lopcham IS NOT NULL
        ),
        lop_da_bi_phat AS (
            SELECT DISTINCT COALESCE(cd.chamlop, cd.chidoan_id) AS chidoan_id
            FROM public.chamdiem cd
            WHERE cd.namhoc = v_namhoc_id
              AND (TRIM(cd.tuan) = TRIM(v_tuan.tuan) OR regexp_replace(cd.tuan, '[^0-9]', '', 'g') = regexp_replace(v_tuan.tuan, '[^0-9]', '', 'g'))
              AND (TRIM(cd.hocky) = TRIM(v_tuan.hocky) OR cd.hocky ILIKE '%' || v_tuan.hocky || '%')
              AND (cd.matieuchi = 'TUDONG' OR cd.nguoicham = v_nguoi_bao_cao)
        )
        SELECT 
            nv.chidoan_id,
            COALESCE(qd.tenchidoan, 'Chi đoàn') AS ten_chi_doan
        FROM lop_co_nghia_vu nv
        LEFT JOIN public.qlchidoan qd ON qd.id = nv.chidoan_id
        WHERE nv.chidoan_id NOT IN (SELECT chidoan_id FROM lop_da_nop_phieu)
          AND nv.chidoan_id NOT IN (SELECT chidoan_id FROM lop_da_bi_phat)
    LOOP
        INSERT INTO public.chamdiem (
            id, namhoc, hocky, tuan, thu, ngay,
            lopcham, chamlop, chidoan_id, doanvienid, hotendoanvien,
            matieuchi, tentieuchi, loaitieuchi, diemtru, diemcong,
            ghichu, nguoicham, createdat, updatedat
        ) VALUES (
            gen_random_uuid()::text, v_namhoc_id, v_tuan.hocky, v_tuan.tuan, 'Chủ nhật', v_tuan.denngay,
            NULL, v_lop_vi_pham.chidoan_id, v_lop_vi_pham.chidoan_id, NULL, v_lop_vi_pham.ten_chi_doan,
            'TUDONG', v_tieu_chi, 'Trừ điểm', v_diem_tru, 0,
            'Hệ thống tự động phạt lớp ' || v_lop_vi_pham.ten_chi_doan || ' do không nộp phiếu chấm điểm trong tuần ' || v_tuan.tuan,
            v_nguoi_bao_cao, NOW(), NOW()
        );

        v_so_lop_bi_phat := v_so_lop_bi_phat + 1;
        v_penalized_list := v_penalized_list || jsonb_build_object(
            'lop_id', v_lop_vi_pham.chidoan_id,
            'ten_lop', v_lop_vi_pham.ten_chi_doan,
            'tuan', v_tuan.tuan,
            'diemtru', v_diem_tru,
            'tieuchi', v_tieu_chi,
            'nguoibao', v_nguoi_bao_cao
        );
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'namhoc', v_tennamhoc,
        'so_lop_bi_phat', v_so_lop_bi_phat,
        'danh_sach_lop_bi_phat', v_penalized_list,
        'thong_so_ap_dung', jsonb_build_object(
            'diem_tru', v_diem_tru,
            'tieu_chi', v_tieu_chi,
            'nguoi_bao_cao', v_nguoi_bao_cao
        ),
        'message', 'Đã hoàn tất xử phạt tuần ' || p_tuan || ' (Tổng số lớp bị phạt: ' || v_so_lop_bi_phat || ')'
    );
END;
$$;


--
-- Name: fn_tu_dong_bam_mat_khau_taikhoan(); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: fn_tu_dong_khoa_tuan(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_tu_dong_khoa_tuan() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_now_vn timestamp;
  v_today_date date;
  v_today_str text;
  v_target_namhoc_id uuid;
  v_target_tennamhoc text;
  v_rec record;
  v_raw_denngay text;
  v_denngay_formatted text;
  v_denngay_date date;
  v_should_lock boolean;
  v_reason text;
  v_locked_count integer := 0;
  v_details jsonb := '[]'::jsonb;
  v_parts text[];
BEGIN
  -- 1. Lấy ngày giờ hiện tại chuẩn múi giờ Việt Nam (UTC+7)
  v_now_vn := now() AT TIME ZONE 'Asia/Ho_Chi_Minh';
  v_today_date := v_now_vn::date;
  v_today_str := to_char(v_now_vn, 'YYYY-MM-DD');

  -- 2. Xác định duy nhất 1 năm học mặc định (isdefault = true)
  SELECT id, tennamhoc INTO v_target_namhoc_id, v_target_tennamhoc
  FROM public.namhoc
  WHERE isdefault = true
  LIMIT 1;

  IF v_target_namhoc_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'so_tuan_da_khoa', 0,
      'message', 'Không tìm thấy năm học mặc định. Dừng để bảo vệ dữ liệu.'
    );
  END IF;

  -- 3. Duyệt toàn bộ các tuần của năm học mặc định
  FOR v_rec IN
    SELECT 
      th.id,
      th.namhoc,
      th.hocky,
      th.tuan,
      th.tungay,
      th.denngay,
      th.islocked
    FROM public.tuanhoc th
    WHERE th.namhoc = v_target_namhoc_id
    ORDER BY th.hocky, th.tuan::integer ASC NULLS LAST
  LOOP
    v_should_lock := false;
    v_reason := '';
    v_denngay_formatted := '';
    v_denngay_date := NULL;
    v_raw_denngay := TRIM(COALESCE(v_rec.denngay, ''));

    -- Chuẩn hóa ngày kết thúc về dạng YYYY-MM-DD
    IF v_raw_denngay ~ '^\d{4}-\d{1,2}-\d{1,2}' THEN
      v_parts := string_to_array(SUBSTRING(v_raw_denngay FROM '^\d{4}-\d{1,2}-\d{1,2}'), '-');
      v_denngay_formatted := v_parts[1] || '-' || LPAD(v_parts[2], 2, '0') || '-' || LPAD(v_parts[3], 2, '0');
    ELSIF v_raw_denngay ~ '^\d{1,2}/\d{1,2}/\d{4}' THEN
      v_parts := string_to_array(SUBSTRING(v_raw_denngay FROM '^\d{1,2}/\d{1,2}/\d{4}'), '/');
      v_denngay_formatted := v_parts[3] || '-' || LPAD(v_parts[2], 2, '0') || '-' || LPAD(v_parts[1], 2, '0');
    ELSIF v_raw_denngay ~ '^\d{1,2}-\d{1,2}-\d{4}' THEN
      v_parts := string_to_array(SUBSTRING(v_raw_denngay FROM '^\d{1,2}-\d{1,2}-\d{4}'), '-');
      v_denngay_formatted := v_parts[3] || '-' || LPAD(v_parts[2], 2, '0') || '-' || LPAD(v_parts[1], 2, '0');
    END IF;

    -- Chuyển đổi an toàn sang kiểu DATE
    BEGIN
      IF v_denngay_formatted <> '' THEN
        v_denngay_date := v_denngay_formatted::date;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_denngay_date := NULL;
    END;

    -- =========================================================================
    -- ĐIỀU KIỆN KHÓA TUẦN:
    -- Khóa tất cả các tuần đã qua ngày kết thúc (denngay < today) mà chưa khóa.
    -- Tuyệt đối KHÔNG khóa nếu denngay >= today (ngày hôm nay hoặc tương lai).
    -- TUYỆT ĐỐI KHÔNG XỬ PHẠT (không ghi nhận bất kỳ điểm phạt nào vào chamdiem).
    -- =========================================================================
    IF v_denngay_date IS NOT NULL AND v_denngay_date < v_today_date THEN
      v_reason := 'Tuần đã hết hạn (' || v_denngay_formatted || ' < ' || v_today_str || ').';
      IF v_rec.islocked IS FALSE OR v_rec.islocked IS NULL THEN
        v_should_lock := true;
        UPDATE public.tuanhoc
        SET islocked = true, updatedat = now()
        WHERE id = v_rec.id;
        v_locked_count := v_locked_count + 1;
      END IF;
    ELSE
      v_reason := 'Chưa qua ngày kết thúc (vẫn mở).';
    END IF;

    v_details := v_details || jsonb_build_object(
      'tuan', v_rec.tuan,
      'hocky', v_rec.hocky,
      'denngay_chuan', v_denngay_formatted,
      'da_khoa', (v_rec.islocked = TRUE OR v_should_lock),
      'ly_do', v_reason
    );
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'namhoc_hien_tai', v_target_tennamhoc,
    'so_tuan_da_khoa', v_locked_count,
    'thoi_gian_hien_tai_vn', to_char(v_now_vn, 'YYYY-MM-DD HH24:MI:SS'),
    'chi_tiet_kiem_tra', v_details
  );
END;
$$;


--
-- Name: fn_tu_dong_khoa_tuan_va_xu_phat(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_tu_dong_khoa_tuan_va_xu_phat() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $_$
DECLARE
  v_now_vn timestamp;
  v_today_date date;
  v_today_str text;
  v_time_str text;
  v_target_namhoc_id uuid;
  v_target_tennamhoc text;
  v_rec record;
  v_raw_denngay text;
  v_denngay_formatted text;
  v_denngay_date date;
  v_auto_enabled boolean := true;
  v_penalty_points numeric := 10;
  v_penalty_criteria text := 'Lỗi không nộp phiếu chấm điểm tuần';
  v_penalty_reporter text := 'Hệ thống tự động';
  v_should_lock boolean;
  v_is_past_due boolean;
  v_reason text;
  v_locked_count integer := 0;
  v_penalized_classes_count integer := 0;
  v_penalized_list jsonb := '[]'::jsonb;
  v_details jsonb := '[]'::jsonb;
  v_pc_rec record;
  v_da_nop boolean;
  v_da_bi_phat boolean;
  v_tenchidoan text;
  v_parts text[];
  v_num_pc integer;
  v_num_rec integer;
  
  -- Các biến bổ sung cho Thuật toán tự động kích hoạt Tuần Mặc Định
  v_new_default_tuan_id uuid := NULL;
  v_new_default_tuan_ten text := '';
BEGIN
  -- Lấy ngày giờ hiện tại chuẩn múi giờ Việt Nam (UTC+7)
  v_now_vn := now() AT TIME ZONE 'Asia/Ho_Chi_Minh';
  v_today_date := v_now_vn::date;
  v_today_str := to_char(v_now_vn, 'YYYY-MM-DD');
  v_time_str := to_char(v_now_vn, 'HH24:MI');

  -- 1. Xác định duy nhất 1 năm học mặc định (isdefault = true)
  SELECT id, tennamhoc INTO v_target_namhoc_id, v_target_tennamhoc
  FROM public.namhoc
  WHERE isdefault = true
  LIMIT 1;

  IF v_target_namhoc_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'so_tuan_da_khoa', 0,
      'so_lop_bi_phat', 0,
      'message', 'Không tìm thấy năm học mặc định. Dừng để bảo vệ dữ liệu.'
    );
  END IF;

  -- =========================================================================
  -- TÍNH NĂNG: TỰ ĐỘNG TÌM & KÍCH HOẠT TUẦN MẶC ĐỊNH (Bọc TRIM chống rác khoảng trắng)
  -- =========================================================================
  WITH parsed_weeks AS (
    SELECT 
      id, tuan, isdefault,
      CASE 
        WHEN TRIM(COALESCE(tungay, '')) ~ '^\d{4}-\d{1,2}-\d{1,2}' THEN (string_to_array(SUBSTRING(TRIM(tungay) FROM '^\d{4}-\d{1,2}-\d{1,2}'), '-'))[1] || '-' || LPAD((string_to_array(SUBSTRING(TRIM(tungay) FROM '^\d{4}-\d{1,2}-\d{1,2}'), '-'))[2], 2, '0') || '-' || LPAD((string_to_array(SUBSTRING(TRIM(tungay) FROM '^\d{4}-\d{1,2}-\d{1,2}'), '-'))[3], 2, '0')
        WHEN TRIM(COALESCE(tungay, '')) ~ '^\d{1,2}/\d{1,2}/\d{4}' THEN (string_to_array(SUBSTRING(TRIM(tungay) FROM '^\d{1,2}/\d{1,2}/\d{4}'), '/'))[3] || '-' || LPAD((string_to_array(SUBSTRING(TRIM(tungay) FROM '^\d{1,2}/\d{1,2}/\d{4}'), '/'))[2], 2, '0') || '-' || LPAD((string_to_array(SUBSTRING(TRIM(tungay) FROM '^\d{1,2}/\d{1,2}/\d{4}'), '/'))[1], 2, '0')
        WHEN TRIM(COALESCE(tungay, '')) ~ '^\d{1,2}-\d{1,2}-\d{4}' THEN (string_to_array(SUBSTRING(TRIM(tungay) FROM '^\d{1,2}-\d{1,2}-\d{4}'), '-'))[3] || '-' || LPAD((string_to_array(SUBSTRING(TRIM(tungay) FROM '^\d{1,2}-\d{1,2}-\d{4}'), '-'))[2], 2, '0') || '-' || LPAD((string_to_array(SUBSTRING(TRIM(tungay) FROM '^\d{1,2}-\d{1,2}-\d{4}'), '-'))[1], 2, '0')
        ELSE NULL
      END::date AS tungay_date,
      CASE 
        WHEN TRIM(COALESCE(denngay, '')) ~ '^\d{4}-\d{1,2}-\d{1,2}' THEN (string_to_array(SUBSTRING(TRIM(denngay) FROM '^\d{4}-\d{1,2}-\d{1,2}'), '-'))[1] || '-' || LPAD((string_to_array(SUBSTRING(TRIM(denngay) FROM '^\d{4}-\d{1,2}-\d{1,2}'), '-'))[2], 2, '0') || '-' || LPAD((string_to_array(SUBSTRING(TRIM(denngay) FROM '^\d{4}-\d{1,2}-\d{1,2}'), '-'))[3], 2, '0')
        WHEN TRIM(COALESCE(denngay, '')) ~ '^\d{1,2}/\d{1,2}/\d{4}' THEN (string_to_array(SUBSTRING(TRIM(denngay) FROM '^\d{1,2}/\d{1,2}/\d{4}'), '/'))[3] || '-' || LPAD((string_to_array(SUBSTRING(TRIM(denngay) FROM '^\d{1,2}/\d{1,2}/\d{4}'), '/'))[2], 2, '0') || '-' || LPAD((string_to_array(SUBSTRING(TRIM(denngay) FROM '^\d{1,2}/\d{1,2}/\d{4}'), '/'))[1], 2, '0')
        WHEN TRIM(COALESCE(denngay, '')) ~ '^\d{1,2}-\d{1,2}-\d{4}' THEN (string_to_array(SUBSTRING(TRIM(denngay) FROM '^\d{1,2}-\d{1,2}-\d{4}'), '-'))[3] || '-' || LPAD((string_to_array(SUBSTRING(TRIM(denngay) FROM '^\d{1,2}-\d{1,2}-\d{4}'), '-'))[2], 2, '0') || '-' || LPAD((string_to_array(SUBSTRING(TRIM(denngay) FROM '^\d{1,2}-\d{1,2}-\d{4}'), '-'))[1], 2, '0')
        ELSE NULL
      END::date AS denngay_date
    FROM public.tuanhoc
    WHERE namhoc = v_target_namhoc_id
  )
  SELECT id, tuan INTO v_new_default_tuan_id, v_new_default_tuan_ten
  FROM parsed_weeks
  WHERE 
    (tungay_date <= v_today_date AND denngay_date >= v_today_date) OR (denngay_date < v_today_date)
  ORDER BY 
    CASE 
      WHEN (tungay_date <= v_today_date AND denngay_date >= v_today_date) THEN 1 
      ELSE 2 
    END ASC,
    tungay_date DESC NULLS LAST,
    denngay_date DESC NULLS LAST
  LIMIT 1;

  -- Cập nhật cờ isdefault (Chống ghi đè vô ích: Chỉ update nếu tuần đó CHƯA phải là mặc định)
  IF v_new_default_tuan_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.tuanhoc WHERE id = v_new_default_tuan_id AND isdefault = true) THEN
      UPDATE public.tuanhoc SET isdefault = false WHERE namhoc = v_target_namhoc_id AND isdefault = true;
      UPDATE public.tuanhoc SET isdefault = true WHERE id = v_new_default_tuan_id;
    END IF;
  END IF;
  -- =========================================================================

  -- 2. Lấy cấu hình phạt của năm học mặc định
  SELECT 
    COALESCE(autopenaltyenabled, true),
    COALESCE(autopenaltypoints, 10),
    COALESCE(autopenaltycriteria, 'Lỗi không nộp phiếu chấm điểm tuần'),
    COALESCE(autopenaltyreporter, 'Hệ thống tự động')
  INTO 
    v_auto_enabled,
    v_penalty_points,
    v_penalty_criteria,
    v_penalty_reporter
  FROM public.settings
  WHERE namhoc = v_target_namhoc_id OR namhoc IS NULL
  ORDER BY (namhoc = v_target_namhoc_id) DESC, updatedat DESC NULLS LAST
  LIMIT 1;

  -- 3. Duyệt các tuần của năm học hiện tại
  FOR v_rec IN
    SELECT 
      th.id,
      th.namhoc,
      th.hocky,
      th.tuan,
      th.tungay,
      th.denngay,
      th.islocked
    FROM public.tuanhoc th
    WHERE th.namhoc = v_target_namhoc_id
    ORDER BY th.hocky, th.tuan::integer ASC NULLS LAST
  LOOP
    v_should_lock := false;
    v_is_past_due := false;
    v_reason := '';
    v_denngay_formatted := '';
    v_denngay_date := NULL;
    v_raw_denngay := TRIM(COALESCE(v_rec.denngay, ''));

    -- Chuẩn hóa ngày kết thúc
    IF v_raw_denngay ~ '^\d{4}-\d{1,2}-\d{1,2}' THEN
      v_parts := string_to_array(SUBSTRING(v_raw_denngay FROM '^\d{4}-\d{1,2}-\d{1,2}'), '-');
      v_denngay_formatted := v_parts[1] || '-' || LPAD(v_parts[2], 2, '0') || '-' || LPAD(v_parts[3], 2, '0');
    ELSIF v_raw_denngay ~ '^\d{1,2}/\d{1,2}/\d{4}' THEN
      v_parts := string_to_array(SUBSTRING(v_raw_denngay FROM '^\d{1,2}/\d{1,2}/\d{4}'), '/');
      v_denngay_formatted := v_parts[3] || '-' || LPAD(v_parts[2], 2, '0') || '-' || LPAD(v_parts[1], 2, '0');
    ELSIF v_raw_denngay ~ '^\d{1,2}-\d{1,2}-\d{4}' THEN
      v_parts := string_to_array(SUBSTRING(v_raw_denngay FROM '^\d{1,2}-\d{1,2}-\d{4}'), '-');
      v_denngay_formatted := v_parts[3] || '-' || LPAD(v_parts[2], 2, '0') || '-' || LPAD(v_parts[1], 2, '0');
    END IF;

    -- Chuyển đổi an toàn sang kiểu DATE
    BEGIN
      IF v_denngay_formatted <> '' THEN
        v_denngay_date := v_denngay_formatted::date;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_denngay_date := NULL;
    END;

    -- =========================================================================
    -- ĐIỀU KIỆN 1: KHÓA TUẦN CŨ
    -- =========================================================================
    IF v_denngay_date IS NOT NULL AND v_denngay_date < v_today_date THEN
      IF v_rec.islocked IS FALSE OR v_rec.islocked IS NULL THEN
        v_should_lock := true;
        UPDATE public.tuanhoc
        SET islocked = true, updatedat = now()
        WHERE id = v_rec.id;
        v_locked_count := v_locked_count + 1;
      END IF;
    END IF;

    -- =========================================================================
    -- ĐIỀU KIỆN 2: XÁC ĐỊNH TUẦN BỊ PHẠT (TRONG VÒNG 7 NGÀY QUA)
    -- =========================================================================
    IF v_denngay_date IS NOT NULL 
       AND v_denngay_date < v_today_date 
       AND v_denngay_date >= (v_today_date - INTERVAL '7 days')::date THEN
      v_is_past_due := true;
      IF v_auto_enabled IS TRUE THEN
        v_reason := 'Tuần kết thúc trong vòng 7 ngày gần nhất (' || v_denngay_formatted || ' < ' || v_today_str || ').';
      ELSE
        v_reason := 'Tuần kết thúc trong vòng 7 ngày gần nhất (' || v_denngay_formatted || ' < ' || v_today_str || ') [Cấu hình tự động phạt đang TẮT - Không phạt].';
      END IF;
    ELSE
      v_is_past_due := false;
      v_reason := CASE 
        WHEN v_denngay_date IS NOT NULL AND v_denngay_date < (v_today_date - INTERVAL '7 days')::date 
          THEN 'Tuần cũ đã qua hơn 7 ngày (đã khóa, không phạt)'
        ELSE 'Chưa qua ngày kết thúc (vẫn mở)'
      END;
    END IF;

    -- =========================================================================
    -- ĐIỀU KIỆN 3: XỬ PHẠT (An toàn kiểu số nguyên 01 = 1)
    -- =========================================================================
    IF v_is_past_due AND v_auto_enabled = TRUE THEN
      -- Parse số tuần an toàn
      BEGIN
        v_num_rec := NULLIF(regexp_replace(v_rec.tuan, '[^0-9]', '', 'g'), '')::integer;
      EXCEPTION WHEN OTHERS THEN
        v_num_rec := NULL;
      END;

      FOR v_pc_rec IN
        SELECT DISTINCT pc.lopcham, pc.tuan AS pc_tuan
        FROM public.phancong pc
        WHERE (pc.namhoc = v_target_namhoc_id OR pc.namhoc IS NULL)
          AND (TRIM(pc.hocky) = TRIM(v_rec.hocky) OR pc.hocky ILIKE '%' || v_rec.hocky || '%')
          AND pc.lopcham IS NOT NULL
      LOOP
        -- Parse số tuần phân công an toàn
        BEGIN
          v_num_pc := NULLIF(regexp_replace(v_pc_rec.pc_tuan, '[^0-9]', '', 'g'), '')::integer;
        EXCEPTION WHEN OTHERS THEN
          v_num_pc := NULL;
        END;

        -- Chỉ duyệt nếu chuỗi tên tuần khớp nhau HOẶC số tuần tương đương nhau (vd: "01" = "1")
        IF (TRIM(v_pc_rec.pc_tuan) = TRIM(v_rec.tuan)) OR (v_num_pc IS NOT NULL AND v_num_rec IS NOT NULL AND v_num_pc = v_num_rec) THEN
          
          -- Kiểm tra lớp đã nộp phiếu chưa
          SELECT EXISTS (
            SELECT 1 FROM public.chamdiem
            WHERE (namhoc = v_target_namhoc_id OR namhoc IS NULL)
              AND (TRIM(hocky) = TRIM(v_rec.hocky) OR hocky ILIKE '%' || v_rec.hocky || '%')
              AND (TRIM(tuan) = TRIM(v_rec.tuan) OR (
                NULLIF(regexp_replace(tuan, '[^0-9]', '', 'g'), '') ~ '^[0-9]+$' AND 
                NULLIF(regexp_replace(tuan, '[^0-9]', '', 'g'), '')::integer = v_num_rec
              ))
              AND lopcham = v_pc_rec.lopcham
          ) INTO v_da_nop;

          -- Kiểm tra lớp đã bị phạt tự động chưa
          SELECT EXISTS (
            SELECT 1 FROM public.chamdiem
            WHERE (namhoc = v_target_namhoc_id OR namhoc IS NULL)
              AND (TRIM(hocky) = TRIM(v_rec.hocky) OR hocky ILIKE '%' || v_rec.hocky || '%')
              AND (TRIM(tuan) = TRIM(v_rec.tuan) OR (
                NULLIF(regexp_replace(tuan, '[^0-9]', '', 'g'), '') ~ '^[0-9]+$' AND 
                NULLIF(regexp_replace(tuan, '[^0-9]', '', 'g'), '')::integer = v_num_rec
              ))
              AND (chamlop = v_pc_rec.lopcham OR chidoan_id = v_pc_rec.lopcham)
              AND (matieuchi = 'TUDONG' OR nguoicham = v_penalty_reporter)
          ) INTO v_da_bi_phat;

          -- Ghi nhận phạt nếu chưa nộp và chưa bị phạt
          IF NOT v_da_nop AND NOT v_da_bi_phat THEN
            SELECT tenchidoan INTO v_tenchidoan
            FROM public.qlchidoan
            WHERE id = v_pc_rec.lopcham;

            INSERT INTO public.chamdiem (
              namhoc,
              hocky,
              tuan,
              thu,
              ngay,
              lopcham,
              chamlop,
              chidoan_id,
              hotendoanvien,
              matieuchi,
              tentieuchi,
              loaitieuchi,
              diemtru,
              diemcong,
              ghichu,
              nguoicham,
              createdat,
              updatedat
            ) VALUES (
              v_target_namhoc_id,
              v_rec.hocky,
              v_rec.tuan,
              'Chủ nhật',
              COALESCE(NULLIF(v_denngay_formatted, ''), v_rec.denngay, v_today_str),
              NULL,
              v_pc_rec.lopcham,
              v_pc_rec.lopcham,
              COALESCE(v_tenchidoan, 'Chi đoàn'),
              'TUDONG',
              v_penalty_criteria,
              'Trừ điểm',
              v_penalty_points,
              0,
              'Hệ thống tự động phạt lớp ' || COALESCE(v_tenchidoan, '') || ' do không nộp phiếu chấm điểm trong tuần ' || v_rec.tuan || '.',
              v_penalty_reporter,
              now(),
              now()
            );

            v_penalized_classes_count := v_penalized_classes_count + 1;
            v_penalized_list := v_penalized_list || jsonb_build_object(
              'lop_id', v_pc_rec.lopcham,
              'ten_lop', COALESCE(v_tenchidoan, 'Chi đoàn'),
              'tuan', v_rec.tuan,
              'hocky', v_rec.hocky,
              'diemtru', v_penalty_points
            );
          END IF;
        END IF;
      END LOOP;
    END IF;

    v_details := v_details || jsonb_build_object(
      'tuan', v_rec.tuan,
      'hocky', v_rec.hocky,
      'denngay_chuan', v_denngay_formatted,
      'da_khoa', (v_rec.islocked = TRUE OR v_should_lock),
      'ly_do', v_reason
    );
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'namhoc_hien_tai', v_target_tennamhoc,
    'tuan_mac_dinh_kich_hoat', COALESCE(v_new_default_tuan_ten, 'Chưa thay đổi'),
    'chuc_nang_phat_dang_bat', v_auto_enabled,
    'so_tuan_da_khoa', v_locked_count,
    'so_lop_bi_phat', v_penalized_classes_count,
    'danh_sach_lop_bi_phat', v_penalized_list,
    'thoi_gian_hien_tai_vn', to_char(v_now_vn, 'YYYY-MM-DD HH24:MI:SS'),
    'chi_tiet_kiem_tra', v_details
  );
END;
$_$;


--
-- Name: fn_tu_dong_khoa_tuan_va_xu_phat_thu_cong(uuid, uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_tu_dong_khoa_tuan_va_xu_phat_thu_cong(p_namhoc_id uuid, p_tuan_id uuid, p_username text, p_password text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_now_vn timestamp;
  v_today_str text;
  v_user_auth record;
  v_rec_tuan record;
  v_penalty_points numeric := 10;
  v_penalty_criteria text := 'Lỗi không nộp phiếu chấm điểm tuần';
  v_penalty_reporter text := 'Hệ thống tự động';
  v_penalized_classes_count integer := 0;
  v_penalized_list jsonb := '[]'::jsonb;
  v_pc_rec record;
  v_da_nop boolean;
  v_da_bi_phat boolean;
  v_tenchidoan text;
  v_tuan_num text;
BEGIN
  -- Lấy ngày giờ hiện tại chuẩn múi giờ Việt Nam
  v_now_vn := now() AT TIME ZONE 'Asia/Ho_Chi_Minh';
  v_today_str := to_char(v_now_vn, 'YYYY-MM-DD');

  -- =========================================================================
  -- 1. XÁC MINH TÀI KHOẢN VÀ MẬT KHẨU
  -- =========================================================================
  SELECT id, username, matkhau, vaitro, phanquyen, trangthai
  INTO v_user_auth
  FROM public.taikhoan
  WHERE (username = p_username OR LOWER(username) = LOWER(p_username))
    AND (trangthai IS NULL OR trangthai = true)
  LIMIT 1;

  IF v_user_auth.id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Không tìm thấy tài khoản người thực hiện!'
    );
  END IF;

  IF COALESCE(v_user_auth.matkhau, '') <> p_password THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Mật khẩu xác nhận không chính xác. Thao tác xử phạt bị hủy bỏ!'
    );
  END IF;

  -- =========================================================================
  -- 2. KIỂM TRA TUẦN HỌC (NHẮM MỤC TIÊU ĐỘC LẬP)
  -- =========================================================================
  SELECT th.id, th.namhoc, th.hocky, th.tuan, th.denngay, th.islocked, nh.tennamhoc
  INTO v_rec_tuan
  FROM public.tuanhoc th
  LEFT JOIN public.namhoc nh ON nh.id = th.namhoc
  WHERE th.id = p_tuan_id AND th.namhoc = p_namhoc_id;

  IF v_rec_tuan.id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Tuần học không tồn tại hoặc không thuộc đúng năm học được chỉ định!'
    );
  END IF;

  -- BẮT BUỘC TUẦN PHẢI ĐANG KHÓA MỚI ĐƯỢC PHÉP PHẠT
  IF COALESCE(v_rec_tuan.islocked, false) = false THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Tuần ' || COALESCE(v_rec_tuan.tuan, '') || ' chưa được khóa. Bạn phải Khóa tuần này trước khi thực hiện xử phạt!'
    );
  END IF;

  v_tuan_num := regexp_replace(COALESCE(v_rec_tuan.tuan, ''), '[^0-9]', '', 'g');

  -- =========================================================================
  -- 3. LẤY CẤU HÌNH PHẠT
  -- =========================================================================
  SELECT 
    COALESCE(autopenaltypoints, 10),
    COALESCE(autopenaltycriteria, 'Lỗi không nộp phiếu chấm điểm tuần'),
    COALESCE(autopenaltyreporter, 'Hệ thống tự động')
  INTO 
    v_penalty_points,
    v_penalty_criteria,
    v_penalty_reporter
  FROM public.settings
  WHERE namhoc = p_namhoc_id OR namhoc IS NULL
  ORDER BY (namhoc = p_namhoc_id) DESC, updatedat DESC NULLS LAST
  LIMIT 1;

  -- =========================================================================
  -- 4. THỰC THI QUÉT VÀ PHẠT (CHỈ QUÉT LỚP TRONG CHÍNH XÁC TUẦN NÀY)
  -- =========================================================================
  FOR v_pc_rec IN
    SELECT DISTINCT pc.lopcham
    FROM public.phancong pc
    WHERE pc.namhoc = p_namhoc_id
      AND (TRIM(pc.hocky) = TRIM(v_rec_tuan.hocky) OR pc.hocky ILIKE '%' || v_rec_tuan.hocky || '%')
      AND (
        TRIM(pc.tuan) = TRIM(v_rec_tuan.tuan) 
        OR (v_tuan_num <> '' AND regexp_replace(pc.tuan, '[^0-9]', '', 'g') = v_tuan_num)
      )
      AND pc.lopcham IS NOT NULL
  LOOP
    -- A. Kiểm tra lớp đã nộp phiếu chưa (Trong tuần này)
    SELECT EXISTS (
      SELECT 1 FROM public.chamdiem
      WHERE namhoc = p_namhoc_id
        AND (TRIM(hocky) = TRIM(v_rec_tuan.hocky) OR hocky ILIKE '%' || v_rec_tuan.hocky || '%')
        AND (
          TRIM(tuan) = TRIM(v_rec_tuan.tuan) 
          OR (v_tuan_num <> '' AND regexp_replace(tuan, '[^0-9]', '', 'g') = v_tuan_num)
        )
        AND lopcham = v_pc_rec.lopcham
    ) INTO v_da_nop;

    -- B. Kiểm tra lớp đã bị phạt tự động chưa (Trong tuần này)
    SELECT EXISTS (
      SELECT 1 FROM public.chamdiem
      WHERE namhoc = p_namhoc_id
        AND (TRIM(hocky) = TRIM(v_rec_tuan.hocky) OR hocky ILIKE '%' || v_rec_tuan.hocky || '%')
        AND (
          TRIM(tuan) = TRIM(v_rec_tuan.tuan) 
          OR (v_tuan_num <> '' AND regexp_replace(tuan, '[^0-9]', '', 'g') = v_tuan_num)
        )
        AND (chamlop = v_pc_rec.lopcham OR chidoan_id = v_pc_rec.lopcham)
        AND (matieuchi = 'TUDONG' OR nguoicham = v_penalty_reporter)
    ) INTO v_da_bi_phat;

    -- C. Ghi nhận phạt nếu LỚP ĐƯỢC PHÂN CÔNG nhưng KHÔNG NỘP VÀ CHƯA BỊ PHẠT
    IF NOT v_da_nop AND NOT v_da_bi_phat THEN
      SELECT tenchidoan INTO v_tenchidoan
      FROM public.qlchidoan
      WHERE id = v_pc_rec.lopcham;

      INSERT INTO public.chamdiem (
        namhoc,
        hocky,
        tuan,
        thu,
        ngay,
        lopcham,
        chamlop,
        chidoan_id,
        hotendoanvien,
        matieuchi,
        tentieuchi,
        loaitieuchi,
        diemtru,
        diemcong,
        ghichu,
        nguoicham,
        createdat,
        updatedat
      ) VALUES (
        p_namhoc_id,
        v_rec_tuan.hocky,
        v_rec_tuan.tuan,
        'Chủ nhật',
        COALESCE(v_rec_tuan.denngay, v_today_str),
        NULL,
        v_pc_rec.lopcham,
        v_pc_rec.lopcham,
        COALESCE(v_tenchidoan, 'Chi đoàn'),
        'TUDONG',
        v_penalty_criteria,
        'Trừ điểm',
        v_penalty_points,
        0,
        'Hệ thống phạt thủ công lớp ' || COALESCE(v_tenchidoan, '') || ' do không nộp phiếu chấm điểm trong tuần ' || COALESCE(v_rec_tuan.tuan, '') || '.',
        v_penalty_reporter,
        now(),
        now()
      );

      v_penalized_classes_count := v_penalized_classes_count + 1;
      v_penalized_list := v_penalized_list || jsonb_build_object(
        'lop_id', v_pc_rec.lopcham,
        'ten_lop', COALESCE(v_tenchidoan, 'Chi đoàn'),
        'tuan', v_rec_tuan.tuan,
        'hocky', v_rec_tuan.hocky,
        'diemtru', v_penalty_points
      );
    END IF;
  END LOOP;
  
  -- =========================================================================
  -- 5. LƯU LOG KIỂM TOÁN
  -- =========================================================================
  BEGIN
    INSERT INTO public.activity_logs (
      user_id,
      username,
      action,
      table_name,
      record_id,
      details,
      created_at
    ) VALUES (
      v_user_auth.id,
      v_user_auth.username,
      'MANUAL_PENALTY',
      'chamdiem',
      p_tuan_id::text,
      'Thực hiện phạt thủ công tuần ' || COALESCE(v_rec_tuan.tuan, '') || ' (' || COALESCE(v_rec_tuan.hocky, '') || '). Tổng số lớp bị phạt: ' || v_penalized_classes_count,
      now()
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'so_lop_bi_phat', v_penalized_classes_count,
    'danh_sach_lop_bi_phat', v_penalized_list,
    'message', 'Hoàn tất kiểm tra và xử phạt thủ công tuần ' || COALESCE(v_rec_tuan.tuan, '') || '. Có ' || v_penalized_classes_count || ' lớp bị phạt.'
  );
END;
$$;


--
-- Name: fn_xoa_tuan_hoc_toan_dien(uuid, uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_xoa_tuan_hoc_toan_dien(p_namhoc_id uuid, p_tuan_id uuid, p_username text, p_password text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_rec_tuan record;
  v_user_auth record;
  v_deleted_phancong integer := 0;
  v_deleted_chamdiem integer := 0;
  v_deleted_giohoctap integer := 0;
  v_deleted_theodoi360 integer := 0;
  v_tuan_num text;
  v_log_desc text;
BEGIN
  -- 1. Xác minh tài khoản quản trị viên và mật khẩu
  SELECT id, username, matkhau, vaitro, phanquyen, trangthai
  INTO v_user_auth
  FROM public.taikhoan
  WHERE (username = p_username OR LOWER(username) = LOWER(p_username))
    AND (trangthai IS NULL OR trangthai = true)
  LIMIT 1;

  IF v_user_auth.id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Không tìm thấy tài khoản người thực hiện!'
    );
  END IF;

  -- Kiểm tra mật khẩu (hỗ trợ cả mật khẩu thường hoặc hash)
  IF COALESCE(v_user_auth.matkhau, '') <> p_password THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Mật khẩu xác nhận không chính xác. Thao tác xóa bị hủy bỏ!'
    );
  END IF;

  -- 2. Kiểm tra tuần học có tồn tại và thuộc đúng năm học chỉ định
  SELECT th.id, th.namhoc, th.hocky, th.tuan, nh.tennamhoc
  INTO v_rec_tuan
  FROM public.tuanhoc th
  LEFT JOIN public.namhoc nh ON nh.id = th.namhoc
  WHERE th.id = p_tuan_id AND th.namhoc = p_namhoc_id;

  IF v_rec_tuan.id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Tuần học không tồn tại hoặc không thuộc đúng năm học được chỉ định!'
    );
  END IF;

  v_tuan_num := regexp_replace(COALESCE(v_rec_tuan.tuan, ''), '[^0-9]', '', 'g');

  -- 3. XÓA BẢNG theodoi360 (Khóa theo nam_hoc_id và tuan_id)
  BEGIN
    DELETE FROM public.theodoi360 td
    WHERE td.nam_hoc_id = p_namhoc_id AND td.tuan_id = p_tuan_id;
    GET DIAGNOSTICS v_deleted_theodoi360 = ROW_COUNT;
  EXCEPTION WHEN OTHERS THEN
    v_deleted_theodoi360 := 0;
  END;

  -- 4. XÓA BẢNG phancong (Phân công chấm tuần này của đúng năm học)
  DELETE FROM public.phancong pc
  WHERE pc.namhoc = p_namhoc_id
    AND (TRIM(pc.hocky) = TRIM(v_rec_tuan.hocky) OR pc.hocky ILIKE '%' || v_rec_tuan.hocky || '%')
    AND (
      TRIM(pc.tuan) = TRIM(v_rec_tuan.tuan) 
      OR (v_tuan_num <> '' AND regexp_replace(pc.tuan, '[^0-9]', '', 'g') = v_tuan_num)
    );
  GET DIAGNOSTICS v_deleted_phancong = ROW_COUNT;

  -- 5. XÓA BẢNG chamdiem (Phiếu chấm điểm thi đua của đúng năm học)
  DELETE FROM public.chamdiem cd
  WHERE cd.namhoc = p_namhoc_id
    AND (TRIM(cd.hocky) = TRIM(v_rec_tuan.hocky) OR cd.hocky ILIKE '%' || v_rec_tuan.hocky || '%')
    AND (
      TRIM(cd.tuan) = TRIM(v_rec_tuan.tuan) 
      OR (v_tuan_num <> '' AND regexp_replace(cd.tuan, '[^0-9]', '', 'g') = v_tuan_num)
    );
  GET DIAGNOSTICS v_deleted_chamdiem = ROW_COUNT;

  -- 6. XÓA BẢNG gio_hoc_tap (Dữ liệu giờ học tốt của đúng năm học)
  BEGIN
    DELETE FROM public.gio_hoc_tap gh
    WHERE gh.namhoc_id = p_namhoc_id AND gh.tuan_id = p_tuan_id;
    GET DIAGNOSTICS v_deleted_giohoctap = ROW_COUNT;
  EXCEPTION WHEN OTHERS THEN
    v_deleted_giohoctap := 0;
  END;

  -- 7. XÓA BẢNG tuanhoc (Bản ghi tuần của đúng năm học)
  DELETE FROM public.tuanhoc th
  WHERE th.id = p_tuan_id AND th.namhoc = p_namhoc_id;

  -- 8. Ghi nhật ký vào activity_logs để kiểm toán
  v_log_desc := 'Xóa tuần học an toàn [' || COALESCE(v_rec_tuan.tuan, '') || ' - ' || COALESCE(v_rec_tuan.hocky, '') || '] thuộc năm học: ' || COALESCE(v_rec_tuan.tennamhoc, '') || '. Đã xóa: ' || v_deleted_phancong || ' phân công, ' || v_deleted_chamdiem || ' phiếu chấm, ' || v_deleted_giohoctap || ' giờ học, ' || v_deleted_theodoi360 || ' theo dõi 360.';
  BEGIN
    INSERT INTO public.activity_logs (
      user_id,
      username,
      action,
      table_name,
      record_id,
      details,
      created_at
    ) VALUES (
      v_user_auth.id,
      v_user_auth.username,
      'DELETE_WEEK_CASCADE',
      'tuanhoc',
      p_tuan_id::text,
      v_log_desc,
      now()
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Đã xóa tuần và toàn bộ dữ liệu liên quan thành công!',
    'tuan', v_rec_tuan.tuan,
    'hocky', v_rec_tuan.hocky,
    'da_xoa_phancong', v_deleted_phancong,
    'da_xoa_chamdiem', v_deleted_chamdiem,
    'da_xoa_giohoctap', v_deleted_giohoctap,
    'da_xoa_theodoi360', v_deleted_theodoi360,
    'tong_da_xoa', (v_deleted_phancong + v_deleted_chamdiem + v_deleted_giohoctap + v_deleted_theodoi360 + 1)
  );
END;
$$;


--
-- Name: fn_xu_phat_thu_cong(uuid, uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_xu_phat_thu_cong(p_namhoc_id uuid, p_tuan_id uuid, p_username text, p_password text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_now_vn timestamp;
  v_today_str text;
  v_user_auth record;
  v_rec_tuan record;
  v_penalty_points numeric := 10;
  v_penalty_criteria text := 'Lỗi không nộp phiếu chấm điểm tuần';
  v_penalty_reporter text := 'Hệ thống tự động';
  v_penalized_classes_count integer := 0;
  v_penalized_list jsonb := '[]'::jsonb;
  v_pc_rec record;
  v_da_nop boolean;
  v_da_bi_phat boolean;
  v_tenchidoan text;
  v_tuan_num text;
BEGIN
  v_now_vn := now() AT TIME ZONE 'Asia/Ho_Chi_Minh';
  v_today_str := to_char(v_now_vn, 'YYYY-MM-DD');

  -- =========================================================================
  -- 1. XÁC MINH TÀI KHOẢN VÀ MẬT KHẨU
  -- =========================================================================
  -- Sửa lại đúng tên cột password, role theo cấu trúc bảng taikhoan
  SELECT id, username, password, role
  INTO v_user_auth
  FROM public.taikhoan
  WHERE (username = p_username OR LOWER(username) = LOWER(p_username))
  LIMIT 1;

  IF v_user_auth.id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Không tìm thấy tài khoản người thực hiện!'
    );
  END IF;

  -- Đối chiếu với cột password
  IF COALESCE(v_user_auth.password, '') <> p_password THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Mật khẩu xác nhận không chính xác. Thao tác xử phạt bị hủy bỏ!'
    );
  END IF;

  -- =========================================================================
  -- 2. KIỂM TRA TUẦN HỌC
  -- =========================================================================
  SELECT th.id, th.namhoc, th.hocky, th.tuan, th.denngay, th.islocked, nh.tennamhoc
  INTO v_rec_tuan
  FROM public.tuanhoc th
  LEFT JOIN public.namhoc nh ON nh.id = th.namhoc
  WHERE th.id = p_tuan_id AND th.namhoc = p_namhoc_id;

  IF v_rec_tuan.id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Tuần học không tồn tại hoặc không thuộc đúng năm học được chỉ định!'
    );
  END IF;

  IF COALESCE(v_rec_tuan.islocked, false) = false THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Tuần ' || COALESCE(v_rec_tuan.tuan, '') || ' chưa được khóa. Bạn phải Khóa tuần này trước khi thực hiện xử phạt!'
    );
  END IF;

  v_tuan_num := regexp_replace(COALESCE(v_rec_tuan.tuan, ''), '[^0-9]', '', 'g');

  -- =========================================================================
  -- 3. LẤY CẤU HÌNH PHẠT
  -- =========================================================================
  SELECT 
    COALESCE(autopenaltypoints, 10),
    COALESCE(autopenaltycriteria, 'Lỗi không nộp phiếu chấm điểm tuần'),
    COALESCE(autopenaltyreporter, 'Hệ thống tự động')
  INTO 
    v_penalty_points,
    v_penalty_criteria,
    v_penalty_reporter
  FROM public.settings
  WHERE namhoc = p_namhoc_id OR namhoc IS NULL
  ORDER BY (namhoc = p_namhoc_id) DESC, updatedat DESC NULLS LAST
  LIMIT 1;

  -- =========================================================================
  -- 4. THỰC THI QUÉT VÀ PHẠT (CHỈ QUÉT LỚP TRONG CHÍNH XÁC TUẦN NÀY)
  -- =========================================================================
  FOR v_pc_rec IN
    SELECT DISTINCT pc.lopcham
    FROM public.phancong pc
    WHERE pc.namhoc = p_namhoc_id
      AND (TRIM(pc.hocky) = TRIM(v_rec_tuan.hocky) OR pc.hocky ILIKE '%' || v_rec_tuan.hocky || '%')
      AND (
        TRIM(pc.tuan) = TRIM(v_rec_tuan.tuan) 
        OR (v_tuan_num <> '' AND regexp_replace(pc.tuan, '[^0-9]', '', 'g') = v_tuan_num)
      )
      AND pc.lopcham IS NOT NULL
  LOOP
    SELECT EXISTS (
      SELECT 1 FROM public.chamdiem
      WHERE namhoc = p_namhoc_id
        AND (TRIM(hocky) = TRIM(v_rec_tuan.hocky) OR hocky ILIKE '%' || v_rec_tuan.hocky || '%')
        AND (
          TRIM(tuan) = TRIM(v_rec_tuan.tuan) 
          OR (v_tuan_num <> '' AND regexp_replace(tuan, '[^0-9]', '', 'g') = v_tuan_num)
        )
        AND lopcham = v_pc_rec.lopcham
    ) INTO v_da_nop;

    SELECT EXISTS (
      SELECT 1 FROM public.chamdiem
      WHERE namhoc = p_namhoc_id
        AND (TRIM(hocky) = TRIM(v_rec_tuan.hocky) OR hocky ILIKE '%' || v_rec_tuan.hocky || '%')
        AND (
          TRIM(tuan) = TRIM(v_rec_tuan.tuan) 
          OR (v_tuan_num <> '' AND regexp_replace(tuan, '[^0-9]', '', 'g') = v_tuan_num)
        )
        AND (chamlop = v_pc_rec.lopcham OR chidoan_id = v_pc_rec.lopcham)
        AND (matieuchi = 'TUDONG' OR nguoicham = v_penalty_reporter)
    ) INTO v_da_bi_phat;

    IF NOT v_da_nop AND NOT v_da_bi_phat THEN
      SELECT tenchidoan INTO v_tenchidoan
      FROM public.qlchidoan
      WHERE id = v_pc_rec.lopcham;

      INSERT INTO public.chamdiem (
        namhoc,
        hocky,
        tuan,
        thu,
        ngay,
        lopcham,
        chamlop,
        chidoan_id,
        hotendoanvien,
        matieuchi,
        tentieuchi,
        loaitieuchi,
        diemtru,
        diemcong,
        ghichu,
        nguoicham,
        createdat,
        updatedat
      ) VALUES (
        p_namhoc_id,
        v_rec_tuan.hocky,
        v_rec_tuan.tuan,
        'Chủ nhật',
        COALESCE(v_rec_tuan.denngay, v_today_str),
        NULL,
        v_pc_rec.lopcham,
        v_pc_rec.lopcham,
        COALESCE(v_tenchidoan, 'Chi đoàn'),
        'TUDONG',
        v_penalty_criteria,
        'Trừ điểm',
        v_penalty_points,
        0,
        'Hệ thống phạt thủ công lớp ' || COALESCE(v_tenchidoan, '') || ' do không nộp phiếu chấm điểm trong tuần ' || COALESCE(v_rec_tuan.tuan, '') || '.',
        v_penalty_reporter,
        now(),
        now()
      );

      v_penalized_classes_count := v_penalized_classes_count + 1;
      v_penalized_list := v_penalized_list || jsonb_build_object(
        'lop_id', v_pc_rec.lopcham,
        'ten_lop', COALESCE(v_tenchidoan, 'Chi đoàn'),
        'tuan', v_rec_tuan.tuan,
        'hocky', v_rec_tuan.hocky,
        'diemtru', v_penalty_points
      );
    END IF;
  END LOOP;
  
  -- =========================================================================
  -- 5. LƯU LOG KIỂM TOÁN
  -- =========================================================================
  BEGIN
    INSERT INTO public.activity_logs (
      user_id,
      username,
      action,
      table_name,
      record_id,
      details,
      created_at
    ) VALUES (
      v_user_auth.id,
      v_user_auth.username,
      'MANUAL_PENALTY',
      'chamdiem',
      p_tuan_id::text,
      'Thực hiện phạt thủ công tuần ' || COALESCE(v_rec_tuan.tuan, '') || ' (' || COALESCE(v_rec_tuan.hocky, '') || '). Tổng số lớp bị phạt: ' || v_penalized_classes_count,
      now()
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'so_lop_bi_phat', v_penalized_classes_count,
    'danh_sach_lop_bi_phat', v_penalized_list,
    'message', 'Hoàn tất kiểm tra và xử phạt thủ công tuần ' || COALESCE(v_rec_tuan.tuan, '') || '. Có ' || v_penalized_classes_count || ' lớp bị phạt.'
  );
END;
$$;


--
-- Name: get_auth_chidoan_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_auth_chidoan_id() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
  SELECT chidoan_id 
  FROM public.taikhoan 
  WHERE lower(username) = lower(split_part(coalesce(auth.email(), ''), '@', 1))
  LIMIT 1; 
$$;


--
-- Name: get_auth_doanvien_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_auth_doanvien_id() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
  SELECT doanvien_id 
  FROM public.taikhoan 
  WHERE lower(username) = lower(split_part(coalesce(auth.email(), ''), '@', 1))
  LIMIT 1; 
$$;


--
-- Name: get_auth_role(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_auth_role() RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
  SELECT upper(trim(role)) 
  FROM public.taikhoan 
  WHERE uid = auth.uid()
  LIMIT 1; 
$$;


--
-- Name: get_chamdiem_history(text, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_chamdiem_history(p_id text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0) RETURNS TABLE(log_id bigint, thoi_gian timestamp with time zone, hanh_dong text, nguoi_thuc_hien uuid, ten_nguoi_thuc_hien text, vai_tro_nguoi_thuc_hien text, thay_doi_chi_tiet jsonb, du_lieu_cu jsonb, du_lieu_moi jsonb)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'audit', 'auth'
    AS $$
DECLARE
    v_table_oid oid := 'public.chamdiem'::regclass;
    v_pkey_cols text[] := audit.primary_key_columns(v_table_oid);
    v_target_record_id uuid;
    v_current_uid uuid := auth.uid();
    v_current_email text := auth.jwt() ->> 'email';
    v_user_role text;
BEGIN
    -- =====================================================================
    -- BƯỚC 1: KIỂM TRA ĐĂNG NHẬP & VAI TRÒ TỪ BẢNG 'public.taikhoan'
    -- =====================================================================
    
    -- 1.1. Chặn ngay nếu gọi từ Client mà chưa đăng nhập
    IF v_current_uid IS NULL AND auth.role() <> 'service_role' THEN
        RAISE EXCEPTION 'Truy cập bị từ chối: Bạn cần đăng nhập để xem lịch sử chấm điểm.'
            USING ERRCODE = '42501';
    END IF;

    -- 1.2. Kiểm tra cột 'role' trong bảng 'public.taikhoan' (Bỏ qua nếu là service_role/SQL Editor)
    IF auth.role() <> 'service_role' THEN
        
        -- Chuyển dòng của bảng taikhoan sang JSONB giúp khớp tự động dù bạn đặt tên cột 
        -- liên kết là 'id', 'user_id', 'uid' hay liên kết qua 'email'
        SELECT COALESCE(tk_json ->> 'role', tk_json ->> 'vai_tro')
        INTO v_user_role
        FROM public.taikhoan tk
        CROSS JOIN LATERAL to_jsonb(tk) AS tk_json
        WHERE (tk_json ->> 'id') = v_current_uid::text
           OR (tk_json ->> 'user_id') = v_current_uid::text
           OR (tk_json ->> 'auth_id') = v_current_uid::text
           OR (v_current_email IS NOT NULL AND lower(tk_json ->> 'email') = lower(v_current_email))
        LIMIT 1;

        -- Dự phòng: Nếu chưa tìm thấy trong bảng taikhoan thì kiểm tra thêm trong JWT metadata
        IF v_user_role IS NULL THEN
            v_user_role := COALESCE(
                auth.jwt() -> 'app_metadata' ->> 'role',
                auth.jwt() -> 'user_metadata' ->> 'role'
            );
        END IF;

        -- Chỉ cho phép 'Admin' hoặc 'BTV' (không phân biệt chữ hoa/chữ thường hay khoảng trắng thừa)
        IF v_user_role IS NULL OR upper(btrim(v_user_role)) NOT IN ('ADMIN', 'BTV') THEN
            RAISE EXCEPTION 'Truy cập bị từ chối: Tài khoản của bạn (Role: %) không có quyền xem lịch sử. Chỉ Admin hoặc BTV mới được phép.', COALESCE(v_user_role, 'Không xác định')
                USING ERRCODE = '42501';
        END IF;
    END IF;

    -- =====================================================================
    -- BƯỚC 2: BĂM (HASH) KHÓA CHÍNH RA UUID V5 ĐỂ TÌM KIẾM QUA B-TREE INDEX
    -- =====================================================================
    IF p_id IS NOT NULL AND btrim(p_id) <> '' THEN
        v_target_record_id := audit.to_record_id(
            v_table_oid,
            v_pkey_cols,
            jsonb_build_object(v_pkey_cols[1], btrim(p_id))
        );
    END IF;

    -- =====================================================================
    -- BƯỚC 3: TRUY VẤN LỊCH SỬ & KẾT NỐI THÔNG TIN NGƯỜI THỰC HIỆN TỪ 'taikhoan'
    -- =====================================================================
    RETURN QUERY
    SELECT 
        rv.id AS log_id,
        rv.ts AS thoi_gian,
        rv.op::text AS hanh_dong,
        rv.auth_uid AS nguoi_thuc_hien,
        COALESCE(
            tk_info.ten_hien_thi,
            u.email::text,
            'Hệ thống / SQL Editor'
        ) AS ten_nguoi_thuc_hien,
        tk_info.role_hien_thi AS vai_tro_nguoi_thuc_hien,
        -- Tự động bóc tách chỉ những cột có giá trị bị thay đổi khi UPDATE
        CASE 
            WHEN rv.op = 'UPDATE' THEN (
                SELECT COALESCE(
                    jsonb_object_agg(
                        n.key, 
                        jsonb_build_object('old', rv.old_record -> n.key, 'new', n.value)
                    ),
                    '{}'::jsonb
                )
                FROM jsonb_each(rv.record) n
                WHERE rv.old_record -> n.key IS DISTINCT FROM n.value
            )
            ELSE NULL
        END AS thay_doi_chi_tiet,
        rv.old_record AS du_lieu_cu,
        rv.record AS du_lieu_moi
    FROM audit.record_version rv
    LEFT JOIN auth.users u ON u.id = rv.auth_uid
    -- Lấy thêm thông tin Họ tên / Tên đăng nhập / Role của người sửa điểm từ bảng taikhoan
    LEFT JOIN LATERAL (
        SELECT 
            COALESCE(
                tk_j ->> 'ho_ten', 
                tk_j ->> 'hoten', 
                tk_j ->> 'full_name', 
                tk_j ->> 'name', 
                tk_j ->> 'ten', 
                tk_j ->> 'username', 
                tk_j ->> 'email'
            ) AS ten_hien_thi,
            COALESCE(tk_j ->> 'role', tk_j ->> 'vai_tro') AS role_hien_thi
        FROM public.taikhoan tk
        CROSS JOIN LATERAL to_jsonb(tk) AS tk_j
        WHERE (tk_j ->> 'id') = rv.auth_uid::text
           OR (tk_j ->> 'user_id') = rv.auth_uid::text
           OR (tk_j ->> 'auth_id') = rv.auth_uid::text
           OR (u.email IS NOT NULL AND lower(tk_j ->> 'email') = lower(u.email))
        LIMIT 1
    ) tk_info ON true
    WHERE rv.table_oid = v_table_oid
      AND (
          v_target_record_id IS NULL 
          OR rv.record_id = v_target_record_id 
          OR rv.old_record_id = v_target_record_id
      )
    ORDER BY rv.ts DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;


--
-- Name: get_my_role(); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: get_secure_chidoan_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_secure_chidoan_id() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
  SELECT chidoan_id FROM public.taikhoan WHERE username = split_part(auth.email(), '@', 1) LIMIT 1;
$$;


--
-- Name: get_secure_doanvien_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_secure_doanvien_id() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
  SELECT doanvien_id FROM public.taikhoan WHERE username = split_part(auth.email(), '@', 1) LIMIT 1;
$$;


--
-- Name: get_secure_role(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_secure_role() RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT role FROM public.taikhoan 
  WHERE lower(username) = lower(split_part(auth.email(), '@', 1)) 
  LIMIT 1; 
$$;


--
-- Name: get_student_violation_stats_advanced(uuid, text, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_student_violation_stats_advanced(p_namhoc_id uuid, p_hocky text DEFAULT NULL::text, p_chidoan_id uuid DEFAULT NULL::uuid, p_doanvien_id uuid DEFAULT NULL::uuid) RETURNS TABLE(doanvien_id uuid, vi_pham text, thanh_tich text, tong_diem_tru numeric, tong_diem_cong numeric)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
  -- 1. Điều kiện tiên quyết: Bắt buộc phải có ID năm học
  IF p_namhoc_id IS NULL THEN
    RAISE EXCEPTION 'Lỗi nghiêm ngặt: Tham số p_namhoc_id là bắt buộc và không được để trống!';
  END IF;

  RETURN QUERY
  SELECT 
    dv.id AS doanvien_id,
    
    -- Chuỗi tổng hợp Vi phạm: Ví dụ "Vắng không phép (-5) T1, Đi trễ (-2) T3"
    COALESCE(
      STRING_AGG(
        CASE 
          WHEN cd.diemtru > 0 OR cd.loaitieuchi ILIKE '%vi pham%' OR cd.loaitieuchi ILIKE '%vi phạm%'
          THEN (
            COALESCE(NULLIF(TRIM(cd.tentieuchi), ''), 'Lỗi vi phạm') || ' (-' || COALESCE(cd.diemtru::TEXT, '0') || ')' ||
            CASE 
              WHEN cd.tuan IS NOT NULL AND TRIM(cd.tuan) <> '' 
              THEN ' T' || REGEXP_REPLACE(TRIM(cd.tuan), '^(tuần|tuan|t)\s*', '', 'i')
              ELSE '' 
            END
          )
          ELSE NULL 
        END, 
        ', '
      ), ''
    ) AS vi_pham,
    
    -- Chuỗi tổng hợp Thành tích
    COALESCE(
      STRING_AGG(
        CASE 
          WHEN cd.diemcong > 0 OR cd.loaitieuchi ILIKE '%thanh tich%' OR cd.loaitieuchi ILIKE '%thành tích%'
          THEN (
            COALESCE(NULLIF(TRIM(cd.tentieuchi), ''), 'Thành tích') || ' (+' || COALESCE(cd.diemcong::TEXT, '0') || ')'
          )
          ELSE NULL 
        END, 
        ', '
      ), ''
    ) AS thanh_tich,
    
    -- Tổng điểm trừ
    COALESCE(SUM(
      CASE 
        WHEN cd.diemtru > 0 OR cd.loaitieuchi ILIKE '%vi pham%' OR cd.loaitieuchi ILIKE '%vi phạm%'
        THEN COALESCE(cd.diemtru::NUMERIC, 0) 
        ELSE 0 
      END
    ), 0) AS tong_diem_tru,
    
    -- Tổng điểm cộng
    COALESCE(SUM(
      CASE 
        WHEN cd.diemcong > 0 OR cd.loaitieuchi ILIKE '%thanh tich%' OR cd.loaitieuchi ILIKE '%thành tích%'
        THEN COALESCE(cd.diemcong::NUMERIC, 0) 
        ELSE 0 
      END
    ), 0) AS tong_diem_cong

  -- Lấy danh sách đoàn viên của đúng năm học
  FROM public.doanvien dv
  
  -- LEFT JOIN với bảng chấm điểm để giữ nguyên 100% học sinh (kể cả học sinh chưa có lỗi)
  LEFT JOIN public.chamdiem cd 
         ON dv.id = cd.doanvienid 
        AND cd.namhoc = p_namhoc_id
        AND (
          p_hocky IS NULL 
          OR TRIM(p_hocky) = ''
          OR LOWER(TRIM(p_hocky)) IN ('cả năm', 'canam', 'all', 'toàn năm', 'toannam')
          OR REPLACE(LOWER(TRIM(cd.hocky)), ' ', '') = REPLACE(LOWER(TRIM(p_hocky)), ' ', '')
          OR (
            REPLACE(LOWER(TRIM(p_hocky)), ' ', '') IN ('hk1', 'hocky1', '1', 'hki')
            AND (
              REPLACE(LOWER(TRIM(COALESCE(cd.hocky, ''))), ' ', '') IN ('hk1', 'hocky1', 'hocki1', 'hki', '1', 'họckỳ1', 'họckì1', 'họckỳi', 'họckìi', 'kỳ1', 'kì1', 'ky1', 'ki1')
              OR ((LOWER(TRIM(COALESCE(cd.hocky, ''))) LIKE '%1%' OR LOWER(TRIM(COALESCE(cd.hocky, ''))) LIKE '%i') AND LOWER(TRIM(COALESCE(cd.hocky, ''))) NOT LIKE '%ii%' AND LOWER(TRIM(COALESCE(cd.hocky, ''))) NOT LIKE '%2%')
            )
          )
          OR (
            REPLACE(LOWER(TRIM(p_hocky)), ' ', '') IN ('hk2', 'hocky2', '2', 'hkii')
            AND (
              REPLACE(LOWER(TRIM(COALESCE(cd.hocky, ''))), ' ', '') IN ('hk2', 'hocky2', 'hocki2', 'hkii', '2', 'họckỳ2', 'họckì2', 'họckỳii', 'họckìii', 'kỳ2', 'kì2', 'ky2', 'ki2')
              OR (LOWER(TRIM(COALESCE(cd.hocky, ''))) LIKE '%2%' OR LOWER(TRIM(COALESCE(cd.hocky, ''))) LIKE '%ii%')
            )
          )
        )
        
  WHERE 
    dv.namhoc = p_namhoc_id
    AND (p_chidoan_id IS NULL OR dv.chidoan_id = p_chidoan_id)
    AND (p_doanvien_id IS NULL OR dv.id = p_doanvien_id)
    
  GROUP BY dv.id;
END;
$$;


--
-- Name: handle_chi_doan_deletion(); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: handle_post_like(); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: handle_update_likes_count(); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: rpc_admin_reset_user_mfa(text, text); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: rpc_authenticate_user(text, text); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: rpc_create_account_secure(text, text, text, text, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: rpc_create_account_secure(text, text, text, text, uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: rpc_delete_auth_users_by_usernames(text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_delete_auth_users_by_usernames(p_usernames text[]) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'auth', 'extensions'
    AS $$
DECLARE
  v_emails text[];
  v_caller_role text;
BEGIN
  -- 1. KIỂM TRA ĐĂNG NHẬP (Chặn gọi trực tiếp từ bên ngoài mà không có token)
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Vui lòng đăng nhập để thực hiện.';
  END IF;

  -- 2. KIỂM TRA QUYỀN TRỊ VIÊN (Khớp tuyệt đối duy nhất bằng cột uid)
  SELECT role INTO v_caller_role 
  FROM public.taikhoan 
  WHERE uid = auth.uid();

  IF UPPER(v_caller_role) IS DISTINCT FROM 'ADMIN' THEN
    RAISE EXCEPTION 'Forbidden: Bạn không có quyền quản trị viên (Admin) để xóa người dùng.';
  END IF;

  -- 3. THỰC THI XÓA (Tìm các tài khoản tương ứng trong auth.users)
  SELECT array_agg(email) INTO v_emails
  FROM auth.users
  WHERE email LIKE ANY (SELECT unnest(p_usernames) || '@%');

  DELETE FROM auth.users WHERE email = ANY(v_emails) OR email ILIKE ANY(v_emails);
END;
$$;


--
-- Name: rpc_get_user_by_username(text); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: rpc_tao_tai_khoan_an_toan(text, text, text, text, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: save_user_backup_codes(text); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: trigger_update_login_stats(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trigger_update_login_stats() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
  -- Chỉ chạy khi thời gian đăng nhập mới lớn hơn thời gian cũ
  IF NEW.last_sign_in_at > COALESCE(OLD.last_sign_in_at, '1970-01-01'::timestamptz) THEN
    
    -- Cập nhật 1-1, bắt buộc khớp chính xác uid, không dùng bất cứ cơ chế dự phòng nào khác
    UPDATE public.taikhoan
    SET 
        sl_dangnhap = COALESCE(sl_dangnhap, 0) + 1,
        tg_truycap = NEW.last_sign_in_at
    WHERE uid = NEW.id; 
    
  END IF;
  
  RETURN NEW;
END;
$$;


--
-- Name: update_likes_count(); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: update_modified_column(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_modified_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updatedat = now();
    RETURN NEW;
END;
$$;


--
-- Name: verify_and_consume_backup_code(text); Type: FUNCTION; Schema: public; Owner: -
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


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: record_version; Type: TABLE; Schema: audit; Owner: -
--

CREATE TABLE audit.record_version (
    id bigint NOT NULL,
    record_id uuid,
    old_record_id uuid,
    op text NOT NULL,
    ts timestamp with time zone DEFAULT now() NOT NULL,
    table_oid oid NOT NULL,
    table_schema text DEFAULT 'public'::text NOT NULL,
    table_name text NOT NULL,
    record jsonb,
    old_record jsonb,
    auth_uid uuid,
    auth_role text
);


--
-- Name: record_version_id_seq; Type: SEQUENCE; Schema: audit; Owner: -
--

ALTER TABLE audit.record_version ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME audit.record_version_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: activity_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.activity_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    username text DEFAULT ''::text NOT NULL,
    full_name text DEFAULT ''::text NOT NULL,
    tab_name text NOT NULL,
    table_name text NOT NULL,
    action_type text NOT NULL,
    description text NOT NULL,
    old_data jsonb,
    new_data jsonb,
    created_at timestamp with time zone DEFAULT now(),
    namhoc uuid
);


--
-- Name: cauhinh_tieuchi_xet_thidua; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: chamdiem; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: doanvien; Type: TABLE; Schema: public; Owner: -
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
    thongtinphuongtien text,
    hinh_anh text,
    thongtintheodoi text
);


--
-- Name: COLUMN doanvien.sothedoan; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.doanvien.sothedoan IS 'Số thẻ đoàn viên';


--
-- Name: COLUMN doanvien.phuongtien; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.doanvien.phuongtien IS 'Sử dụng phương tiện di chuyển';


--
-- Name: COLUMN doanvien.thongtinphuongtien; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.doanvien.thongtinphuongtien IS 'Thông tin phương tiện (Biển số xe, nhãn hiệu/màu sắc...)';


--
-- Name: dotptdoanvien; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: duytricsdl; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.duytricsdl (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    so bigint DEFAULT 0,
    thoigian timestamp with time zone DEFAULT now(),
    createdat timestamp with time zone DEFAULT now(),
    updatedat timestamp with time zone DEFAULT now()
);


--
-- Name: gio_hoc_tap; Type: TABLE; Schema: public; Owner: -
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
    hocky text,
    nguoi_nhap text
);


--
-- Name: TABLE gio_hoc_tap; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.gio_hoc_tap IS 'Bảng quản lý giờ học tập và điểm trung bình học tập của Chi đoàn theo tuần và năm học';


--
-- Name: COLUMN gio_hoc_tap.namhoc_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.gio_hoc_tap.namhoc_id IS 'Liên kết với năm học hiện tại';


--
-- Name: COLUMN gio_hoc_tap.chidoan_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.gio_hoc_tap.chidoan_id IS 'Liên kết với Chi đoàn được xếp loại giờ học';


--
-- Name: COLUMN gio_hoc_tap.tuan_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.gio_hoc_tap.tuan_id IS 'Liên kết với tuần học tương ứng';


--
-- Name: COLUMN gio_hoc_tap.diem_tot_cauhinh; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.gio_hoc_tap.diem_tot_cauhinh IS 'Điểm cấu hình của giờ Tốt tại thời điểm nhập';


--
-- Name: COLUMN gio_hoc_tap.diem_kha_cauhinh; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.gio_hoc_tap.diem_kha_cauhinh IS 'Điểm cấu hình của giờ Khá tại thời điểm nhập';


--
-- Name: COLUMN gio_hoc_tap.diem_tb_cauhinh; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.gio_hoc_tap.diem_tb_cauhinh IS 'Điểm cấu hình của giờ Trung bình tại thời điểm nhập';


--
-- Name: COLUMN gio_hoc_tap.diem_yeu_cauhinh; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.gio_hoc_tap.diem_yeu_cauhinh IS 'Điểm cấu hình của giờ Yếu tại thời điểm nhập';


--
-- Name: COLUMN gio_hoc_tap.diem_tb_hoc_tap; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.gio_hoc_tap.diem_tb_hoc_tap IS 'Điểm trung bình học tập thực tế cuối cùng của tuần';


--
-- Name: COLUMN gio_hoc_tap.hocky; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.gio_hoc_tap.hocky IS 'Học kỳ diễn ra tuần học tập (ví dụ: HK1, HK2)';


--
-- Name: github_settings; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: homthugopy; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.homthugopy (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    nam_hoc_id uuid,
    namhoc character varying(50),
    hocky character varying(20) NOT NULL,
    chu_de character varying(100) NOT NULL,
    che_do_danh_tinh character varying(30) DEFAULT 'cong_khai'::character varying NOT NULL,
    tieu_de character varying(255) NOT NULL,
    noi_dung text NOT NULL,
    hinh_anh text[] DEFAULT ARRAY[]::text[],
    nguoi_gui_id text,
    ho_ten_nguoi_gui character varying(100),
    chidoan_id text,
    ten_chidoan character varying(50),
    thoi_gian_gop_y timestamp with time zone DEFAULT now(),
    trang_thai character varying(30) DEFAULT 'tiep_nhan'::character varying NOT NULL,
    noi_dung_tra_loi text,
    nguoi_tra_loi_id text,
    ten_nguoi_tra_loi character varying(100),
    thoi_gian_tra_loi timestamp with time zone,
    cong_khai_cau_tra_loi boolean DEFAULT false,
    ghi_chu text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    nguoi_nhan_gop_y character varying(50) DEFAULT 'Đoàn trường'::character varying
);


--
-- Name: namhoc; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.namhoc (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    tennamhoc text NOT NULL,
    islocked boolean DEFAULT false,
    updatedat timestamp with time zone DEFAULT now(),
    createdat timestamp with time zone DEFAULT now(),
    isdefault boolean DEFAULT false
);


--
-- Name: phancong; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.phancong (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    hocky text NOT NULL,
    tuan text NOT NULL,
    lopcham uuid NOT NULL,
    chamlop uuid NOT NULL,
    updatedat timestamp with time zone DEFAULT now(),
    namhoc uuid,
    createdat timestamp with time zone DEFAULT now(),
    chophepsuachamdiem boolean DEFAULT false,
    chophepsuagiohoctap boolean DEFAULT false
);


--
-- Name: phanquyen; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: TABLE phanquyen; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.phanquyen IS 'Bảng cấu hình phân quyền động cho hệ thống';


--
-- Name: COLUMN phanquyen.doi_tuong; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.phanquyen.doi_tuong IS 'Vai trò của người dùng (Admin, BTV, BCH, BT, DV)';


--
-- Name: COLUMN phanquyen.tab_chuc_nang; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.phanquyen.tab_chuc_nang IS 'Mã tab chức năng trên giao diện';


--
-- Name: phanquyen_id_seq; Type: SEQUENCE; Schema: public; Owner: -
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
-- Name: ptdoanvien; Type: TABLE; Schema: public; Owner: -
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
    ngayquyetdinh date,
    ly_do text
);


--
-- Name: push_subscriptions; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: ql_baocao; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: COLUMN ql_baocao.config_noi_dung1; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ql_baocao.config_noi_dung1 IS 'Cấu hình nâng cao (tiêu đề, kiểu, bắt buộc, options, enabled) cho ô nhập Nội dung 1';


--
-- Name: COLUMN ql_baocao.config_noi_dung2; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ql_baocao.config_noi_dung2 IS 'Cấu hình nâng cao (tiêu đề, kiểu, bắt buộc, options, enabled) cho ô nhập Nội dung 2';


--
-- Name: COLUMN ql_baocao.config_noi_dung3; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ql_baocao.config_noi_dung3 IS 'Cấu hình nâng cao (tiêu đề, kiểu, bắt buộc, options, enabled) cho ô nhập Nội dung 3';


--
-- Name: COLUMN ql_baocao.config_noi_dung4; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ql_baocao.config_noi_dung4 IS 'Cấu hình nâng cao (tiêu đề, kiểu, bắt buộc, options, enabled) cho ô nhập Nội dung 4';


--
-- Name: COLUMN ql_baocao.config_noi_dung5; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ql_baocao.config_noi_dung5 IS 'Cấu hình nâng cao (tiêu đề, kiểu, bắt buộc, options, enabled) cho ô nhập Nội dung 5';


--
-- Name: COLUMN ql_baocao.config_noi_dung6; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ql_baocao.config_noi_dung6 IS 'Cấu hình nâng cao (tiêu đề, kiểu, bắt buộc, options, enabled) cho ô nhập Nội dung 6';


--
-- Name: COLUMN ql_baocao.config_noi_dung7; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ql_baocao.config_noi_dung7 IS 'Cấu hình nâng cao (tiêu đề, kiểu, bắt buộc, options, enabled) cho ô nhập Nội dung 7';


--
-- Name: COLUMN ql_baocao.config_noi_dung8; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ql_baocao.config_noi_dung8 IS 'Cấu hình nâng cao (tiêu đề, kiểu, bắt buộc, options, enabled) cho ô nhập Nội dung 8';


--
-- Name: COLUMN ql_baocao.config_noi_dung9; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ql_baocao.config_noi_dung9 IS 'Cấu hình nâng cao (tiêu đề, kiểu, bắt buộc, options, enabled) cho ô nhập Nội dung 9';


--
-- Name: COLUMN ql_baocao.config_noi_dung10; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ql_baocao.config_noi_dung10 IS 'Cấu hình nâng cao (tiêu đề, kiểu, bắt buộc, options, enabled) cho ô nhập Nội dung 10';


--
-- Name: ql_nop_bc; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: COLUMN ql_nop_bc.danh_sach_anh; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ql_nop_bc.danh_sach_anh IS 'Danh sách liên kết các ảnh minh chứng tải lên R2, phân tách bằng dấu phẩy';


--
-- Name: qlchidoan; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: COLUMN qlchidoan.he_so_tru; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.qlchidoan.he_so_tru IS 'Hệ số nhân điểm trừ riêng biệt cho từng Chi đoàn';


--
-- Name: COLUMN qlchidoan.he_so_cong; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.qlchidoan.he_so_cong IS 'Hệ số nhân điểm cộng riêng biệt cho từng Chi đoàn';


--
-- Name: settings; Type: TABLE; Schema: public; Owner: -
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
    show_class_select_gvcn text DEFAULT 'Không hiển thị'::text,
    diem_tot numeric DEFAULT 10,
    diem_kha numeric DEFAULT 7,
    diem_tb numeric DEFAULT 4,
    diem_yeu numeric DEFAULT 1,
    ti_trong_diem_tuan numeric DEFAULT 50,
    ti_trong_diem_hoc_tap numeric DEFAULT 50,
    co_che_nhap_gio_hoc character varying(20) DEFAULT 'tiet'::character varying
);


--
-- Name: COLUMN settings.autopenaltytime; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.settings.autopenaltytime IS 'Giờ kiểm tra xử phạt tự động vào Chủ Nhật';


--
-- Name: COLUMN settings.autopenaltypoints; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.settings.autopenaltypoints IS 'Số điểm trừ khi vi phạm lỗi không nhập điểm';


--
-- Name: COLUMN settings.autopenaltycriteria; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.settings.autopenaltycriteria IS 'Tên tiêu chí hiển thị khi xử phạt';


--
-- Name: COLUMN settings.autopenaltyenabled; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.settings.autopenaltyenabled IS 'Trạng thái bật/tắt chức năng xử phạt tự động';


--
-- Name: COLUMN settings.autopenaltyreporter; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.settings.autopenaltyreporter IS 'Tên người chấm hiển thị trong bảng điểm';


--
-- Name: COLUMN settings.diem_tot; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.settings.diem_tot IS 'Điểm cấu hình mặc định cho giờ Tốt (áp dụng khi khởi tạo tuần mới)';


--
-- Name: COLUMN settings.diem_kha; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.settings.diem_kha IS 'Điểm cấu hình mặc định cho giờ Khá (áp dụng khi khởi tạo tuần mới)';


--
-- Name: COLUMN settings.diem_tb; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.settings.diem_tb IS 'Điểm cấu hình mặc định cho giờ Trung bình (áp dụng khi khởi tạo tuần mới)';


--
-- Name: COLUMN settings.diem_yeu; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.settings.diem_yeu IS 'Điểm cấu hình mặc định cho giờ Yếu (áp dụng khi khởi tạo tuần mới)';


--
-- Name: COLUMN settings.ti_trong_diem_tuan; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.settings.ti_trong_diem_tuan IS 'Tỉ trọng % đóng góp của điểm tuần (trừ vi phạm) vào tổng điểm thi đua chung';


--
-- Name: COLUMN settings.ti_trong_diem_hoc_tap; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.settings.ti_trong_diem_hoc_tap IS 'Tỉ trọng % đóng góp của điểm trung bình giờ học tập vào tổng điểm thi đua chung';


--
-- Name: COLUMN settings.co_che_nhap_gio_hoc; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.settings.co_che_nhap_gio_hoc IS 'Cơ chế nhập điểm giờ học: tiet (tính theo số tiết) hoặc tructiep (nhập trực tiếp điểm TB)';


--
-- Name: taikhoan; Type: TABLE; Schema: public; Owner: -
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
    chidoan1111 text,
    uid uuid
);


--
-- Name: theodoi360; Type: TABLE; Schema: public; Owner: -
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
    minh_chung_drive text,
    ly_do_bac_bo text,
    ly_do_duyet text
);


--
-- Name: thongbao_hethong; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: thongbao_riengbiet; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: tieuchitd; Type: TABLE; Schema: public; Owner: -
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
    createdat timestamp with time zone DEFAULT now(),
    nhom text
);


--
-- Name: tuanhoc; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: vanban_doan; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vanban_doan (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    category character varying(50) NOT NULL,
    title character varying(255) NOT NULL,
    drive_link text DEFAULT ''::text,
    updated_at timestamp with time zone DEFAULT now(),
    updated_by character varying(255) DEFAULT ''::character varying
);


--
-- Name: xet_thidua; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: record_version record_version_pkey; Type: CONSTRAINT; Schema: audit; Owner: -
--

ALTER TABLE ONLY audit.record_version
    ADD CONSTRAINT record_version_pkey PRIMARY KEY (id);


--
-- Name: activity_logs activity_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity_logs
    ADD CONSTRAINT activity_logs_pkey PRIMARY KEY (id);


--
-- Name: cauhinh_tieuchi_xet_thidua cauhinh_tieuchi_xet_thidua_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cauhinh_tieuchi_xet_thidua
    ADD CONSTRAINT cauhinh_tieuchi_xet_thidua_pkey PRIMARY KEY (id);


--
-- Name: chamdiem chamdiem_pkey2; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chamdiem
    ADD CONSTRAINT chamdiem_pkey2 PRIMARY KEY (id);


--
-- Name: doanvien doanvien_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.doanvien
    ADD CONSTRAINT doanvien_pkey PRIMARY KEY (id);


--
-- Name: dotptdoanvien dotptdoanvien_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dotptdoanvien
    ADD CONSTRAINT dotptdoanvien_pkey PRIMARY KEY (id);


--
-- Name: duytricsdl duytricsdl_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.duytricsdl
    ADD CONSTRAINT duytricsdl_pkey PRIMARY KEY (id);


--
-- Name: gio_hoc_tap gio_hoc_tap_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gio_hoc_tap
    ADD CONSTRAINT gio_hoc_tap_pkey PRIMARY KEY (id);


--
-- Name: github_settings github_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.github_settings
    ADD CONSTRAINT github_settings_pkey PRIMARY KEY (id);


--
-- Name: homthugopy homthugopy_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.homthugopy
    ADD CONSTRAINT homthugopy_pkey PRIMARY KEY (id);


--
-- Name: namhoc namhoc_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.namhoc
    ADD CONSTRAINT namhoc_pkey PRIMARY KEY (id);


--
-- Name: phancong phancong_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.phancong
    ADD CONSTRAINT phancong_pkey PRIMARY KEY (id);


--
-- Name: phanquyen phanquyen_doi_tuong_tab_namhoc_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.phanquyen
    ADD CONSTRAINT phanquyen_doi_tuong_tab_namhoc_unique UNIQUE (doi_tuong, tab_chuc_nang, nam_hoc);


--
-- Name: phanquyen phanquyen_doituong_tab_namhoc_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.phanquyen
    ADD CONSTRAINT phanquyen_doituong_tab_namhoc_unique UNIQUE (doi_tuong, tab_chuc_nang, nam_hoc);


--
-- Name: phanquyen phanquyen_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.phanquyen
    ADD CONSTRAINT phanquyen_pkey PRIMARY KEY (id);


--
-- Name: ptdoanvien ptdoanvien_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ptdoanvien
    ADD CONSTRAINT ptdoanvien_pkey PRIMARY KEY (id);


--
-- Name: push_subscriptions push_subscriptions_endpoint_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_subscriptions
    ADD CONSTRAINT push_subscriptions_endpoint_key UNIQUE (endpoint);


--
-- Name: push_subscriptions push_subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_subscriptions
    ADD CONSTRAINT push_subscriptions_pkey PRIMARY KEY (id);


--
-- Name: ql_baocao ql_baocao_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ql_baocao
    ADD CONSTRAINT ql_baocao_pkey PRIMARY KEY (id);


--
-- Name: ql_nop_bc ql_nop_bc_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ql_nop_bc
    ADD CONSTRAINT ql_nop_bc_pkey PRIMARY KEY (id);


--
-- Name: qlchidoan qlchidoan_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.qlchidoan
    ADD CONSTRAINT qlchidoan_pkey PRIMARY KEY (id);


--
-- Name: qlchidoan qlchidoan_ten_nam_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.qlchidoan
    ADD CONSTRAINT qlchidoan_ten_nam_unique UNIQUE (tenchidoan, namhoc);


--
-- Name: settings settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.settings
    ADD CONSTRAINT settings_pkey PRIMARY KEY (id);


--
-- Name: taikhoan taikhoan_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taikhoan
    ADD CONSTRAINT taikhoan_pkey PRIMARY KEY (id);


--
-- Name: theodoi360 theodoi360_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.theodoi360
    ADD CONSTRAINT theodoi360_pkey PRIMARY KEY (id);


--
-- Name: thongbao_hethong thongbao_hethong_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.thongbao_hethong
    ADD CONSTRAINT thongbao_hethong_pkey PRIMARY KEY (id);


--
-- Name: thongbao_riengbiet thongbao_riengbiet_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.thongbao_riengbiet
    ADD CONSTRAINT thongbao_riengbiet_pkey PRIMARY KEY (id);


--
-- Name: tieuchitd tieuchitd_matieuchi_namhoc_hocky_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tieuchitd
    ADD CONSTRAINT tieuchitd_matieuchi_namhoc_hocky_unique UNIQUE (matieuchi, namhoc, hocky);


--
-- Name: tieuchitd tieuchitd_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tieuchitd
    ADD CONSTRAINT tieuchitd_pkey PRIMARY KEY (id);


--
-- Name: tuanhoc tuanhoc_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tuanhoc
    ADD CONSTRAINT tuanhoc_pkey PRIMARY KEY (id);


--
-- Name: cauhinh_tieuchi_xet_thidua unique_cauhinh_namhoc_hocky; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cauhinh_tieuchi_xet_thidua
    ADD CONSTRAINT unique_cauhinh_namhoc_hocky UNIQUE (namhoc_id, hoc_ky);


--
-- Name: chamdiem unique_chamdiem_record; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chamdiem
    ADD CONSTRAINT unique_chamdiem_record UNIQUE (namhoc, hocky, tuan, thu, ngay, lopcham, chamlop, doanvienid, matieuchi, tentieuchi, loaitieuchi, diemtru, diemcong, chidoan_id);


--
-- Name: gio_hoc_tap unique_chidoan_tuan_namhoc; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gio_hoc_tap
    ADD CONSTRAINT unique_chidoan_tuan_namhoc UNIQUE (chidoan_id, tuan_id, namhoc_id);


--
-- Name: qlchidoan unique_namhoc_tenchidoan; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.qlchidoan
    ADD CONSTRAINT unique_namhoc_tenchidoan UNIQUE (namhoc, tenchidoan);


--
-- Name: xet_thidua unique_xet_thidua_chidoan_hocky; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.xet_thidua
    ADD CONSTRAINT unique_xet_thidua_chidoan_hocky UNIQUE (namhoc_id, hoc_ky, chidoan_id);


--
-- Name: vanban_doan vanban_doan_category_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vanban_doan
    ADD CONSTRAINT vanban_doan_category_key UNIQUE (category);


--
-- Name: vanban_doan vanban_doan_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vanban_doan
    ADD CONSTRAINT vanban_doan_pkey PRIMARY KEY (id);


--
-- Name: xet_thidua xet_thidua_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.xet_thidua
    ADD CONSTRAINT xet_thidua_pkey PRIMARY KEY (id);


--
-- Name: idx_activity_logs_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_activity_logs_created_at ON public.activity_logs USING btree (created_at DESC);


--
-- Name: idx_activity_logs_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_activity_logs_user_id ON public.activity_logs USING btree (user_id);


--
-- Name: idx_cauhinh_thidua_namhoc_hocky; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cauhinh_thidua_namhoc_hocky ON public.cauhinh_tieuchi_xet_thidua USING btree (namhoc_id, hoc_ky);


--
-- Name: idx_chamdiem_chamlop; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chamdiem_chamlop ON public.chamdiem USING btree (chamlop);


--
-- Name: idx_chamdiem_chidoan_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chamdiem_chidoan_id ON public.chamdiem USING btree (chidoan_id);


--
-- Name: idx_chamdiem_doanvienid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chamdiem_doanvienid ON public.chamdiem USING btree (doanvienid);


--
-- Name: idx_chamdiem_hocky; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chamdiem_hocky ON public.chamdiem USING btree (hocky);


--
-- Name: idx_chamdiem_loaitieuchi; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chamdiem_loaitieuchi ON public.chamdiem USING btree (loaitieuchi);


--
-- Name: idx_chamdiem_lopcham_chamlop; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chamdiem_lopcham_chamlop ON public.chamdiem USING btree (lopcham, chamlop);


--
-- Name: idx_chamdiem_optimization_chamlop; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chamdiem_optimization_chamlop ON public.chamdiem USING btree (chamlop);


--
-- Name: idx_chamdiem_optimization_chidoan_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chamdiem_optimization_chidoan_id ON public.chamdiem USING btree (chidoan_id);


--
-- Name: idx_chamdiem_optimization_namhoc_hocky_tuan; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chamdiem_optimization_namhoc_hocky_tuan ON public.chamdiem USING btree (namhoc, hocky, tuan);


--
-- Name: idx_chamdiem_optimization_namhoc_tuan; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chamdiem_optimization_namhoc_tuan ON public.chamdiem USING btree (namhoc, tuan);


--
-- Name: idx_chamdiem_thongke; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chamdiem_thongke ON public.chamdiem USING btree (namhoc, hocky, tuan, chamlop);


--
-- Name: idx_doanvien_chidoan_namhoc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_doanvien_chidoan_namhoc ON public.doanvien USING btree (chidoan_id, namhoc);


--
-- Name: idx_doanvien_hoten; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_doanvien_hoten ON public.doanvien USING btree (hoten);


--
-- Name: idx_doanvien_namhoc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_doanvien_namhoc ON public.doanvien USING btree (namhoc);


--
-- Name: idx_dotptdoanvien_nam_hk; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dotptdoanvien_nam_hk ON public.dotptdoanvien USING btree (namhoc, hocky);


--
-- Name: idx_homthugopy_che_do; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_homthugopy_che_do ON public.homthugopy USING btree (che_do_danh_tinh);


--
-- Name: idx_homthugopy_chu_de; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_homthugopy_chu_de ON public.homthugopy USING btree (chu_de);


--
-- Name: idx_homthugopy_hocky; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_homthugopy_hocky ON public.homthugopy USING btree (hocky);


--
-- Name: idx_homthugopy_nam_hoc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_homthugopy_nam_hoc ON public.homthugopy USING btree (nam_hoc_id);


--
-- Name: idx_homthugopy_nguoi_gui; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_homthugopy_nguoi_gui ON public.homthugopy USING btree (nguoi_gui_id);


--
-- Name: idx_homthugopy_nguoi_nhan; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_homthugopy_nguoi_nhan ON public.homthugopy USING btree (nguoi_nhan_gop_y);


--
-- Name: idx_homthugopy_thoi_gian; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_homthugopy_thoi_gian ON public.homthugopy USING btree (thoi_gian_gop_y DESC);


--
-- Name: idx_homthugopy_trang_thai; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_homthugopy_trang_thai ON public.homthugopy USING btree (trang_thai);


--
-- Name: idx_namhoc_isdefault_true; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_namhoc_isdefault_true ON public.namhoc USING btree (isdefault) WHERE (isdefault = true);


--
-- Name: idx_phancong_chamlop; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_phancong_chamlop ON public.phancong USING btree (chamlop);


--
-- Name: idx_phancong_context; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_phancong_context ON public.phancong USING btree (namhoc, hocky, tuan);


--
-- Name: idx_phancong_lopcham; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_phancong_lopcham ON public.phancong USING btree (lopcham);


--
-- Name: idx_phanquyen_namhoc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_phanquyen_namhoc ON public.phanquyen USING btree (nam_hoc);


--
-- Name: idx_ptdoanvien_doanvien; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ptdoanvien_doanvien ON public.ptdoanvien USING btree (doanvien_id);


--
-- Name: idx_ptdoanvien_doanvien_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ptdoanvien_doanvien_id ON public.ptdoanvien USING btree (doanvien_id);


--
-- Name: idx_ptdoanvien_dot; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ptdoanvien_dot ON public.ptdoanvien USING btree (dotdangki);


--
-- Name: idx_ptdoanvien_dotdangki; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ptdoanvien_dotdangki ON public.ptdoanvien USING btree (dotdangki);


--
-- Name: idx_ptdoanvien_namhoc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ptdoanvien_namhoc ON public.ptdoanvien USING btree (namhoc);


--
-- Name: idx_ql_nop_bc_baocao; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ql_nop_bc_baocao ON public.ql_nop_bc USING btree (ql_bao_cao_id);


--
-- Name: idx_ql_nop_bc_chidoan; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ql_nop_bc_chidoan ON public.ql_nop_bc USING btree (chi_doan_id);


--
-- Name: idx_ql_nop_bc_doanvien; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ql_nop_bc_doanvien ON public.ql_nop_bc USING btree (doanvien_id);


--
-- Name: idx_qlchidoan_optimization_namhoc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_qlchidoan_optimization_namhoc ON public.qlchidoan USING btree (namhoc);


--
-- Name: idx_settings_namhoc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_settings_namhoc ON public.settings USING btree (namhoc);


--
-- Name: idx_taikhoan_doanvien_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_taikhoan_doanvien_id ON public.taikhoan USING btree (doanvien_id);


--
-- Name: idx_taikhoan_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_taikhoan_role ON public.taikhoan USING btree (role);


--
-- Name: idx_taikhoan_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_taikhoan_uid ON public.taikhoan USING btree (uid);


--
-- Name: idx_taikhoan_username_lower; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_taikhoan_username_lower ON public.taikhoan USING btree (lower(username));


--
-- Name: idx_theodoi360_doanvien; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_theodoi360_doanvien ON public.theodoi360 USING btree (doan_vien_vi_pham_id);


--
-- Name: idx_theodoi360_namhoc_tuan; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_theodoi360_namhoc_tuan ON public.theodoi360 USING btree (nam_hoc_id, tuan_id);


--
-- Name: idx_thongbao_riengbiet_dates; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_thongbao_riengbiet_dates ON public.thongbao_riengbiet USING btree (start_at, end_at);


--
-- Name: idx_thongbao_riengbiet_namhoc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_thongbao_riengbiet_namhoc ON public.thongbao_riengbiet USING btree (namhoc_id);


--
-- Name: idx_thongbao_riengbiet_sender; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_thongbao_riengbiet_sender ON public.thongbao_riengbiet USING btree (sender_id);


--
-- Name: idx_tieuchitd_context; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tieuchitd_context ON public.tieuchitd USING btree (namhoc, hocky);


--
-- Name: idx_tuan_isdefault_true; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_tuan_isdefault_true ON public.tuanhoc USING btree (isdefault) WHERE (isdefault = true);


--
-- Name: idx_tuanhoc_context; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tuanhoc_context ON public.tuanhoc USING btree (namhoc, hocky, tuan);


--
-- Name: idx_tuanhoc_optimization_namhoc_hocky; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tuanhoc_optimization_namhoc_hocky ON public.tuanhoc USING btree (namhoc, hocky);


--
-- Name: idx_unique_default_namhoc; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_unique_default_namhoc ON public.namhoc USING btree (isdefault) WHERE (isdefault = true);


--
-- Name: idx_xet_thidua_chidoan; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_xet_thidua_chidoan ON public.xet_thidua USING btree (chidoan_id);


--
-- Name: idx_xet_thidua_namhoc_hocky; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_xet_thidua_namhoc_hocky ON public.xet_thidua USING btree (namhoc_id, hoc_ky);


--
-- Name: ngay_3_5_idx_ptdoanvien_doanvien_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ngay_3_5_idx_ptdoanvien_doanvien_id ON public.ptdoanvien USING btree (doanvien_id);


--
-- Name: ngay_3_5_idx_ptdoanvien_dotdangki; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ngay_3_5_idx_ptdoanvien_dotdangki ON public.ptdoanvien USING btree (dotdangki);


--
-- Name: chamdiem audit_chamdiem_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_chamdiem_trigger AFTER INSERT OR DELETE OR UPDATE ON public.chamdiem FOR EACH ROW EXECUTE FUNCTION audit.insert_update_delete_trigger();


--
-- Name: taikhoan trg_1_kiem_tra_an_ninh_taikhoan; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_1_kiem_tra_an_ninh_taikhoan BEFORE INSERT OR DELETE OR UPDATE ON public.taikhoan FOR EACH ROW EXECUTE FUNCTION public.fn_kiem_tra_an_ninh_taikhoan();


--
-- Name: taikhoan trg_2_tu_dong_bam_mat_khau_taikhoan; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_2_tu_dong_bam_mat_khau_taikhoan BEFORE INSERT OR UPDATE OF password ON public.taikhoan FOR EACH ROW EXECUTE FUNCTION public.fn_tu_dong_bam_mat_khau_taikhoan();


--
-- Name: taikhoan trg_3_dong_bo_taikhoan_sang_auth_users; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_3_dong_bo_taikhoan_sang_auth_users AFTER INSERT OR DELETE OR UPDATE ON public.taikhoan FOR EACH ROW EXECUTE FUNCTION public.fn_dong_bo_taikhoan_sang_auth_users();


--
-- Name: qlchidoan trigger_chi_doan_deletion; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_chi_doan_deletion AFTER DELETE ON public.qlchidoan FOR EACH ROW EXECUTE FUNCTION public.handle_chi_doan_deletion();


--
-- Name: chamdiem update_chamdiem_modtime; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_chamdiem_modtime BEFORE UPDATE ON public.chamdiem FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: doanvien update_doanvien_modtime; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_doanvien_modtime BEFORE UPDATE ON public.doanvien FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: dotptdoanvien update_dotptdoanvien_modtime; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_dotptdoanvien_modtime BEFORE UPDATE ON public.dotptdoanvien FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: duytricsdl update_duytricsdl_modtime; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_duytricsdl_modtime BEFORE UPDATE ON public.duytricsdl FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: github_settings update_github_settings_modtime; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_github_settings_modtime BEFORE UPDATE ON public.github_settings FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: namhoc update_namhoc_modtime; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_namhoc_modtime BEFORE UPDATE ON public.namhoc FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: phancong update_phancong_modtime; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_phancong_modtime BEFORE UPDATE ON public.phancong FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: phanquyen update_phanquyen_modtime; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_phanquyen_modtime BEFORE UPDATE ON public.phanquyen FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: ptdoanvien update_ptdoanvien_modtime; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_ptdoanvien_modtime BEFORE UPDATE ON public.ptdoanvien FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: qlchidoan update_qlchidoan_modtime; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_qlchidoan_modtime BEFORE UPDATE ON public.qlchidoan FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: settings update_settings_modtime; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_settings_modtime BEFORE UPDATE ON public.settings FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: taikhoan update_taikhoan_modtime; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_taikhoan_modtime BEFORE UPDATE ON public.taikhoan FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: tieuchitd update_tieuchitd_modtime; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_tieuchitd_modtime BEFORE UPDATE ON public.tieuchitd FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: tuanhoc update_tuanhoc_modtime; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_tuanhoc_modtime BEFORE UPDATE ON public.tuanhoc FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: ptdoanvien Ngay_3_5_ptdoanvien_doanvien_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ptdoanvien
    ADD CONSTRAINT "Ngay_3_5_ptdoanvien_doanvien_id_fkey" FOREIGN KEY (doanvien_id) REFERENCES public.doanvien(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: ptdoanvien Ngay_3_5_ptdoanvien_dotdangki_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ptdoanvien
    ADD CONSTRAINT "Ngay_3_5_ptdoanvien_dotdangki_fkey" FOREIGN KEY (dotdangki) REFERENCES public.dotptdoanvien(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: activity_logs activity_logs_namhoc_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity_logs
    ADD CONSTRAINT activity_logs_namhoc_fkey FOREIGN KEY (namhoc) REFERENCES public.namhoc(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cauhinh_tieuchi_xet_thidua cauhinh_tieuchi_xet_thidua_namhoc_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cauhinh_tieuchi_xet_thidua
    ADD CONSTRAINT cauhinh_tieuchi_xet_thidua_namhoc_id_fkey FOREIGN KEY (namhoc_id) REFERENCES public.namhoc(id) ON DELETE CASCADE;


--
-- Name: chamdiem chamdiem_chamlop_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chamdiem
    ADD CONSTRAINT chamdiem_chamlop_fkey FOREIGN KEY (chamlop) REFERENCES public.qlchidoan(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: chamdiem chamdiem_chidoan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chamdiem
    ADD CONSTRAINT chamdiem_chidoan_id_fkey FOREIGN KEY (chidoan_id) REFERENCES public.qlchidoan(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: chamdiem chamdiem_doanvienid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chamdiem
    ADD CONSTRAINT chamdiem_doanvienid_fkey FOREIGN KEY (doanvienid) REFERENCES public.doanvien(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: chamdiem chamdiem_lopcham_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chamdiem
    ADD CONSTRAINT chamdiem_lopcham_fkey FOREIGN KEY (lopcham) REFERENCES public.qlchidoan(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: doanvien doanvien_chidoan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.doanvien
    ADD CONSTRAINT doanvien_chidoan_id_fkey FOREIGN KEY (chidoan_id) REFERENCES public.qlchidoan(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: chamdiem fk_chamdiem_namhoc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chamdiem
    ADD CONSTRAINT fk_chamdiem_namhoc FOREIGN KEY (namhoc) REFERENCES public.namhoc(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: doanvien fk_doanvien_namhoc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.doanvien
    ADD CONSTRAINT fk_doanvien_namhoc FOREIGN KEY (namhoc) REFERENCES public.namhoc(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: dotptdoanvien fk_dotptdoanvien_namhoc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dotptdoanvien
    ADD CONSTRAINT fk_dotptdoanvien_namhoc FOREIGN KEY (namhoc) REFERENCES public.namhoc(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: gio_hoc_tap fk_giohoctap_chidoan; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gio_hoc_tap
    ADD CONSTRAINT fk_giohoctap_chidoan FOREIGN KEY (chidoan_id) REFERENCES public.qlchidoan(id) ON DELETE CASCADE;


--
-- Name: gio_hoc_tap fk_giohoctap_namhoc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gio_hoc_tap
    ADD CONSTRAINT fk_giohoctap_namhoc FOREIGN KEY (namhoc_id) REFERENCES public.namhoc(id) ON DELETE CASCADE;


--
-- Name: gio_hoc_tap fk_giohoctap_tuan; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gio_hoc_tap
    ADD CONSTRAINT fk_giohoctap_tuan FOREIGN KEY (tuan_id) REFERENCES public.tuanhoc(id) ON DELETE CASCADE;


--
-- Name: phancong fk_phancong_namhoc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.phancong
    ADD CONSTRAINT fk_phancong_namhoc FOREIGN KEY (namhoc) REFERENCES public.namhoc(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: phanquyen fk_phanquyen_namhoc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.phanquyen
    ADD CONSTRAINT fk_phanquyen_namhoc FOREIGN KEY (nam_hoc) REFERENCES public.namhoc(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: ptdoanvien fk_ptdoanvien_namhoc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ptdoanvien
    ADD CONSTRAINT fk_ptdoanvien_namhoc FOREIGN KEY (namhoc) REFERENCES public.namhoc(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: ql_baocao fk_ql_baocao_namhoc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ql_baocao
    ADD CONSTRAINT fk_ql_baocao_namhoc FOREIGN KEY (nam_hoc_id) REFERENCES public.namhoc(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: ql_nop_bc fk_ql_nop_bc_baocao; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ql_nop_bc
    ADD CONSTRAINT fk_ql_nop_bc_baocao FOREIGN KEY (ql_bao_cao_id) REFERENCES public.ql_baocao(id) ON DELETE CASCADE;


--
-- Name: ql_nop_bc fk_ql_nop_bc_chidoan; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ql_nop_bc
    ADD CONSTRAINT fk_ql_nop_bc_chidoan FOREIGN KEY (chi_doan_id) REFERENCES public.qlchidoan(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: ql_nop_bc fk_ql_nop_bc_doanvien; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ql_nop_bc
    ADD CONSTRAINT fk_ql_nop_bc_doanvien FOREIGN KEY (doanvien_id) REFERENCES public.doanvien(id) ON DELETE CASCADE;


--
-- Name: qlchidoan fk_qlchidoan_namhoc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.qlchidoan
    ADD CONSTRAINT fk_qlchidoan_namhoc FOREIGN KEY (namhoc) REFERENCES public.namhoc(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: settings fk_settings_namhoc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.settings
    ADD CONSTRAINT fk_settings_namhoc FOREIGN KEY (namhoc) REFERENCES public.namhoc(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: thongbao_riengbiet fk_thongbao_riengbiet_namhoc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.thongbao_riengbiet
    ADD CONSTRAINT fk_thongbao_riengbiet_namhoc FOREIGN KEY (namhoc_id) REFERENCES public.namhoc(id) ON DELETE CASCADE;


--
-- Name: thongbao_riengbiet fk_thongbao_riengbiet_taikhoan; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.thongbao_riengbiet
    ADD CONSTRAINT fk_thongbao_riengbiet_taikhoan FOREIGN KEY (sender_id) REFERENCES public.taikhoan(id) ON DELETE CASCADE;


--
-- Name: tieuchitd fk_tieuchitd_namhoc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tieuchitd
    ADD CONSTRAINT fk_tieuchitd_namhoc FOREIGN KEY (namhoc) REFERENCES public.namhoc(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: tuanhoc fk_tuanhoc_namhoc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tuanhoc
    ADD CONSTRAINT fk_tuanhoc_namhoc FOREIGN KEY (namhoc) REFERENCES public.namhoc(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: homthugopy homthugopy_nam_hoc_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.homthugopy
    ADD CONSTRAINT homthugopy_nam_hoc_id_fkey FOREIGN KEY (nam_hoc_id) REFERENCES public.namhoc(id) ON DELETE CASCADE;


--
-- Name: phancong phancong_chamlop_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.phancong
    ADD CONSTRAINT phancong_chamlop_fkey FOREIGN KEY (chamlop) REFERENCES public.qlchidoan(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: phancong phancong_lopcham_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.phancong
    ADD CONSTRAINT phancong_lopcham_fkey FOREIGN KEY (lopcham) REFERENCES public.qlchidoan(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: taikhoan taikhoan_uid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taikhoan
    ADD CONSTRAINT taikhoan_uid_fkey FOREIGN KEY (uid) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: theodoi360 theodoi360_doan_vien_vi_pham_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.theodoi360
    ADD CONSTRAINT theodoi360_doan_vien_vi_pham_fkey FOREIGN KEY (doan_vien_vi_pham_id) REFERENCES public.doanvien(id) ON DELETE CASCADE;


--
-- Name: theodoi360 theodoi360_nam_hoc_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.theodoi360
    ADD CONSTRAINT theodoi360_nam_hoc_fkey FOREIGN KEY (nam_hoc_id) REFERENCES public.namhoc(id) ON DELETE CASCADE;


--
-- Name: theodoi360 theodoi360_nguoi_to_cao_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.theodoi360
    ADD CONSTRAINT theodoi360_nguoi_to_cao_fkey FOREIGN KEY (nguoi_to_cao_id) REFERENCES public.doanvien(id) ON DELETE CASCADE;


--
-- Name: theodoi360 theodoi360_tieu_chi_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.theodoi360
    ADD CONSTRAINT theodoi360_tieu_chi_fkey FOREIGN KEY (tieu_chi_id) REFERENCES public.tieuchitd(id) ON DELETE CASCADE;


--
-- Name: theodoi360 theodoi360_tuan_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.theodoi360
    ADD CONSTRAINT theodoi360_tuan_fkey FOREIGN KEY (tuan_id) REFERENCES public.tuanhoc(id) ON DELETE CASCADE;


--
-- Name: xet_thidua xet_thidua_chidoan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.xet_thidua
    ADD CONSTRAINT xet_thidua_chidoan_id_fkey FOREIGN KEY (chidoan_id) REFERENCES public.qlchidoan(id) ON DELETE CASCADE;


--
-- Name: xet_thidua xet_thidua_namhoc_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.xet_thidua
    ADD CONSTRAINT xet_thidua_namhoc_id_fkey FOREIGN KEY (namhoc_id) REFERENCES public.namhoc(id) ON DELETE CASCADE;


--
-- Name: record_version; Type: ROW SECURITY; Schema: audit; Owner: -
--

ALTER TABLE audit.record_version ENABLE ROW LEVEL SECURITY;

--
-- Name: duytricsdl ADMIN full quyền; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "ADMIN full quyền" ON public.duytricsdl TO authenticated USING ((public.get_auth_role() = 'ADMIN'::text)) WITH CHECK ((public.get_auth_role() = 'ADMIN'::text));


--
-- Name: github_settings ADMIN full quyền; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "ADMIN full quyền" ON public.github_settings TO authenticated USING ((public.get_auth_role() = 'ADMIN'::text)) WITH CHECK ((public.get_auth_role() = 'ADMIN'::text));


--
-- Name: homthugopy ADMIN full quyền; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "ADMIN full quyền" ON public.homthugopy TO authenticated USING ((public.get_auth_role() = 'ADMIN'::text)) WITH CHECK ((public.get_auth_role() = 'ADMIN'::text));


--
-- Name: namhoc ADMIN full quyền; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "ADMIN full quyền" ON public.namhoc TO authenticated USING ((public.get_auth_role() = 'ADMIN'::text)) WITH CHECK ((public.get_auth_role() = 'ADMIN'::text));


--
-- Name: phanquyen ADMIN full quyền; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "ADMIN full quyền" ON public.phanquyen TO authenticated USING ((public.get_auth_role() = 'ADMIN'::text)) WITH CHECK ((public.get_auth_role() = 'ADMIN'::text));


--
-- Name: settings ADMIN full quyền; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "ADMIN full quyền" ON public.settings TO authenticated USING ((public.get_auth_role() = 'ADMIN'::text)) WITH CHECK ((public.get_auth_role() = 'ADMIN'::text));


--
-- Name: taikhoan ADMIN full quyền; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "ADMIN full quyền" ON public.taikhoan TO authenticated USING ((public.get_auth_role() = 'ADMIN'::text)) WITH CHECK ((public.get_auth_role() = 'ADMIN'::text));


--
-- Name: vanban_doan ADMIN full quyền; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "ADMIN full quyền" ON public.vanban_doan TO authenticated USING ((public.get_auth_role() = 'ADMIN'::text)) WITH CHECK ((public.get_auth_role() = 'ADMIN'::text));


--
-- Name: phancong ADMIN, BTV full quyền; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "ADMIN, BTV full quyền" ON public.phancong TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text])));


--
-- Name: thongbao_hethong ADMIN, BTV full quyền; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "ADMIN, BTV full quyền" ON public.thongbao_hethong TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text])));


--
-- Name: tieuchitd ADMIN, BTV full quyền; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "ADMIN, BTV full quyền" ON public.tieuchitd TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text])));


--
-- Name: tuanhoc ADMIN, BTV full quyền; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "ADMIN, BTV full quyền" ON public.tuanhoc TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text])));


--
-- Name: xet_thidua ADMIN, BTV full quyền; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "ADMIN, BTV full quyền" ON public.xet_thidua TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text])));


--
-- Name: ptdoanvien ADMIN, BTV, BCH full quyền; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "ADMIN, BTV, BCH full quyền" ON public.ptdoanvien TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text, 'BCH'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text, 'BCH'::text])));


--
-- Name: ql_baocao ADMIN, BTV, BCH full quyền; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "ADMIN, BTV, BCH full quyền" ON public.ql_baocao TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text])));


--
-- Name: qlchidoan ADMIN, BTV, BCH full quyền; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "ADMIN, BTV, BCH full quyền" ON public.qlchidoan TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text, 'BCH'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text, 'BCH'::text])));


--
-- Name: theodoi360 ADMIN, BTV, BCH, NC, DV full quyền; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "ADMIN, BTV, BCH, NC, DV full quyền" ON public.theodoi360 TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'DV'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'DV'::text])));


--
-- Name: ql_nop_bc ADMIN, BTV, BCH, NC, GVCN, DV full quyền; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "ADMIN, BTV, BCH, NC, GVCN, DV full quyền" ON public.ql_nop_bc TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'GVCN'::text, 'DV'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'GVCN'::text, 'DV'::text])));


--
-- Name: thongbao_riengbiet ADMIN, BTV, BGH, GVCN full quyền; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "ADMIN, BTV, BGH, GVCN full quyền" ON public.thongbao_riengbiet TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text, 'BGH'::text, 'GVCN'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text, 'BGH'::text, 'GVCN'::text])));


--
-- Name: gio_hoc_tap ADMIN, BTV, NC full quyền; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "ADMIN, BTV, NC full quyền" ON public.gio_hoc_tap TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text, 'NC'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text, 'NC'::text])));


--
-- Name: cauhinh_tieuchi_xet_thidua Admin, BTV full quyền; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admin, BTV full quyền" ON public.cauhinh_tieuchi_xet_thidua TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text])));


--
-- Name: doanvien Admin, BTV full quyền; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admin, BTV full quyền" ON public.doanvien TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text])));


--
-- Name: dotptdoanvien Admin, BTV full quyền; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admin, BTV full quyền" ON public.dotptdoanvien TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text])));


--
-- Name: chamdiem Admin, BTV, NC full quyền; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admin, BTV, NC full quyền" ON public.chamdiem TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text, 'NC'::text]))) WITH CHECK ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BTV'::text, 'NC'::text])));


--
-- Name: doanvien BCH có quyền cập nhật; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "BCH có quyền cập nhật" ON public.doanvien FOR UPDATE TO authenticated USING ((public.get_auth_role() = 'BCH'::text)) WITH CHECK ((public.get_auth_role() = 'BCH'::text));


--
-- Name: homthugopy BGH cập nhật toàn bộ; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "BGH cập nhật toàn bộ" ON public.homthugopy FOR UPDATE TO authenticated USING ((public.get_auth_role() = 'BGH'::text)) WITH CHECK ((public.get_auth_role() = 'BGH'::text));


--
-- Name: homthugopy BGH xem toàn bộ; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "BGH xem toàn bộ" ON public.homthugopy FOR SELECT TO authenticated USING ((public.get_auth_role() = 'BGH'::text));


--
-- Name: homthugopy BTV full quyền; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "BTV full quyền" ON public.homthugopy TO authenticated USING ((public.get_auth_role() = 'BTV'::text)) WITH CHECK ((public.get_auth_role() = 'BTV'::text));


--
-- Name: duytricsdl Công cộng được cập nhật; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Công cộng được cập nhật" ON public.duytricsdl FOR UPDATE USING (true) WITH CHECK (true);


--
-- Name: duytricsdl Công cộng được xem; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Công cộng được xem" ON public.duytricsdl FOR SELECT USING (true);


--
-- Name: homthugopy Học sinh gửi góp ý; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Học sinh gửi góp ý" ON public.homthugopy FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: homthugopy Học sinh sửa góp ý khi chưa xử lý; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Học sinh sửa góp ý khi chưa xử lý" ON public.homthugopy FOR UPDATE TO authenticated USING (((nguoi_gui_id = (auth.uid())::text) AND ((trang_thai)::text = 'tiep_nhan'::text))) WITH CHECK (((nguoi_gui_id = (auth.uid())::text) AND ((trang_thai)::text = 'tiep_nhan'::text)));


--
-- Name: homthugopy Học sinh xem góp ý của mình và công khai; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Học sinh xem góp ý của mình và công khai" ON public.homthugopy FOR SELECT TO authenticated USING (((nguoi_gui_id = (auth.uid())::text) OR (cong_khai_cau_tra_loi = true)));


--
-- Name: namhoc Khách vãng lai được xem; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Khách vãng lai được xem" ON public.namhoc FOR SELECT TO anon USING (true);


--
-- Name: tuanhoc Khách vãng lai được xem; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Khách vãng lai được xem" ON public.tuanhoc FOR SELECT TO anon USING (true);


--
-- Name: activity_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.activity_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: cauhinh_tieuchi_xet_thidua; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cauhinh_tieuchi_xet_thidua ENABLE ROW LEVEL SECURITY;

--
-- Name: chamdiem; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.chamdiem ENABLE ROW LEVEL SECURITY;

--
-- Name: doanvien; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.doanvien ENABLE ROW LEVEL SECURITY;

--
-- Name: dotptdoanvien; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.dotptdoanvien ENABLE ROW LEVEL SECURITY;

--
-- Name: duytricsdl; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.duytricsdl ENABLE ROW LEVEL SECURITY;

--
-- Name: gio_hoc_tap; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.gio_hoc_tap ENABLE ROW LEVEL SECURITY;

--
-- Name: github_settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.github_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: homthugopy; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.homthugopy ENABLE ROW LEVEL SECURITY;

--
-- Name: namhoc; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.namhoc ENABLE ROW LEVEL SECURITY;

--
-- Name: phancong; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.phancong ENABLE ROW LEVEL SECURITY;

--
-- Name: phanquyen; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.phanquyen ENABLE ROW LEVEL SECURITY;

--
-- Name: ptdoanvien; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ptdoanvien ENABLE ROW LEVEL SECURITY;

--
-- Name: push_subscriptions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;

--
-- Name: ql_baocao; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ql_baocao ENABLE ROW LEVEL SECURITY;

--
-- Name: ql_nop_bc; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ql_nop_bc ENABLE ROW LEVEL SECURITY;

--
-- Name: qlchidoan; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.qlchidoan ENABLE ROW LEVEL SECURITY;

--
-- Name: settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.settings ENABLE ROW LEVEL SECURITY;

--
-- Name: taikhoan; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.taikhoan ENABLE ROW LEVEL SECURITY;

--
-- Name: theodoi360; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.theodoi360 ENABLE ROW LEVEL SECURITY;

--
-- Name: thongbao_hethong; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.thongbao_hethong ENABLE ROW LEVEL SECURITY;

--
-- Name: thongbao_riengbiet; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.thongbao_riengbiet ENABLE ROW LEVEL SECURITY;

--
-- Name: tieuchitd; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tieuchitd ENABLE ROW LEVEL SECURITY;

--
-- Name: tuanhoc; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tuanhoc ENABLE ROW LEVEL SECURITY;

--
-- Name: vanban_doan; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.vanban_doan ENABLE ROW LEVEL SECURITY;

--
-- Name: xet_thidua; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.xet_thidua ENABLE ROW LEVEL SECURITY;

--
-- Name: activity_logs Đăng nhập được xem; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Đăng nhập được xem" ON public.activity_logs FOR SELECT TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BGH'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'GVCN'::text, 'DV'::text, 'PH'::text])));


--
-- Name: cauhinh_tieuchi_xet_thidua Đăng nhập được xem; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Đăng nhập được xem" ON public.cauhinh_tieuchi_xet_thidua FOR SELECT TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BGH'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'GVCN'::text, 'DV'::text, 'PH'::text])));


--
-- Name: chamdiem Đăng nhập được xem; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Đăng nhập được xem" ON public.chamdiem FOR SELECT TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BGH'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'GVCN'::text, 'DV'::text, 'PH'::text])));


--
-- Name: doanvien Đăng nhập được xem; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Đăng nhập được xem" ON public.doanvien FOR SELECT TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BGH'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'GVCN'::text, 'DV'::text, 'PH'::text])));


--
-- Name: dotptdoanvien Đăng nhập được xem; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Đăng nhập được xem" ON public.dotptdoanvien FOR SELECT TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BGH'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'GVCN'::text, 'DV'::text, 'PH'::text])));


--
-- Name: duytricsdl Đăng nhập được xem; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Đăng nhập được xem" ON public.duytricsdl FOR SELECT TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BGH'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'GVCN'::text, 'DV'::text, 'PH'::text])));


--
-- Name: gio_hoc_tap Đăng nhập được xem; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Đăng nhập được xem" ON public.gio_hoc_tap FOR SELECT TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BGH'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'GVCN'::text, 'DV'::text, 'PH'::text])));


--
-- Name: github_settings Đăng nhập được xem; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Đăng nhập được xem" ON public.github_settings FOR SELECT TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BGH'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'GVCN'::text, 'DV'::text, 'PH'::text])));


--
-- Name: namhoc Đăng nhập được xem; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Đăng nhập được xem" ON public.namhoc FOR SELECT TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BGH'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'GVCN'::text, 'DV'::text, 'PH'::text])));


--
-- Name: phancong Đăng nhập được xem; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Đăng nhập được xem" ON public.phancong FOR SELECT TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BGH'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'GVCN'::text, 'DV'::text, 'PH'::text])));


--
-- Name: phanquyen Đăng nhập được xem; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Đăng nhập được xem" ON public.phanquyen FOR SELECT TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BGH'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'GVCN'::text, 'DV'::text, 'PH'::text])));


--
-- Name: ptdoanvien Đăng nhập được xem; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Đăng nhập được xem" ON public.ptdoanvien FOR SELECT TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BGH'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'GVCN'::text, 'DV'::text, 'PH'::text])));


--
-- Name: push_subscriptions Đăng nhập được xem; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Đăng nhập được xem" ON public.push_subscriptions FOR SELECT TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BGH'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'GVCN'::text, 'DV'::text, 'PH'::text])));


--
-- Name: ql_baocao Đăng nhập được xem; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Đăng nhập được xem" ON public.ql_baocao FOR SELECT TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BGH'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'GVCN'::text, 'DV'::text, 'PH'::text])));


--
-- Name: ql_nop_bc Đăng nhập được xem; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Đăng nhập được xem" ON public.ql_nop_bc FOR SELECT TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BGH'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'GVCN'::text, 'DV'::text, 'PH'::text])));


--
-- Name: qlchidoan Đăng nhập được xem; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Đăng nhập được xem" ON public.qlchidoan FOR SELECT TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BGH'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'GVCN'::text, 'DV'::text, 'PH'::text])));


--
-- Name: settings Đăng nhập được xem; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Đăng nhập được xem" ON public.settings FOR SELECT TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BGH'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'GVCN'::text, 'DV'::text, 'PH'::text])));


--
-- Name: taikhoan Đăng nhập được xem; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Đăng nhập được xem" ON public.taikhoan FOR SELECT TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BGH'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'GVCN'::text, 'DV'::text, 'PH'::text])));


--
-- Name: theodoi360 Đăng nhập được xem; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Đăng nhập được xem" ON public.theodoi360 FOR SELECT TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BGH'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'GVCN'::text, 'DV'::text, 'PH'::text])));


--
-- Name: thongbao_hethong Đăng nhập được xem; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Đăng nhập được xem" ON public.thongbao_hethong FOR SELECT TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BGH'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'GVCN'::text, 'DV'::text, 'PH'::text])));


--
-- Name: thongbao_riengbiet Đăng nhập được xem; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Đăng nhập được xem" ON public.thongbao_riengbiet FOR SELECT TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BGH'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'GVCN'::text, 'DV'::text, 'PH'::text])));


--
-- Name: tieuchitd Đăng nhập được xem; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Đăng nhập được xem" ON public.tieuchitd FOR SELECT TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BGH'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'GVCN'::text, 'DV'::text, 'PH'::text])));


--
-- Name: tuanhoc Đăng nhập được xem; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Đăng nhập được xem" ON public.tuanhoc FOR SELECT TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BGH'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'GVCN'::text, 'DV'::text, 'PH'::text])));


--
-- Name: vanban_doan Đăng nhập được xem; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Đăng nhập được xem" ON public.vanban_doan FOR SELECT TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BGH'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'GVCN'::text, 'DV'::text, 'PH'::text])));


--
-- Name: xet_thidua Đăng nhập được xem; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Đăng nhập được xem" ON public.xet_thidua FOR SELECT TO authenticated USING ((public.get_auth_role() = ANY (ARRAY['ADMIN'::text, 'BGH'::text, 'BTV'::text, 'BCH'::text, 'NC'::text, 'GVCN'::text, 'DV'::text, 'PH'::text])));


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: FUNCTION calculate_scores_advanced(p_namhoc_id uuid, p_chidoan_id uuid, p_doanvien_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.calculate_scores_advanced(p_namhoc_id uuid, p_chidoan_id uuid, p_doanvien_id uuid) TO anon;
GRANT ALL ON FUNCTION public.calculate_scores_advanced(p_namhoc_id uuid, p_chidoan_id uuid, p_doanvien_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.calculate_scores_advanced(p_namhoc_id uuid, p_chidoan_id uuid, p_doanvien_id uuid) TO service_role;


--
-- Name: FUNCTION calculate_scores_by_year(p_namhoc_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.calculate_scores_by_year(p_namhoc_id uuid) TO anon;
GRANT ALL ON FUNCTION public.calculate_scores_by_year(p_namhoc_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.calculate_scores_by_year(p_namhoc_id uuid) TO service_role;


--
-- Name: FUNCTION check_user_mfa_status(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.check_user_mfa_status() TO anon;
GRANT ALL ON FUNCTION public.check_user_mfa_status() TO authenticated;
GRANT ALL ON FUNCTION public.check_user_mfa_status() TO service_role;


--
-- Name: FUNCTION fn_dem_du_lieu_lien_quan_tuan(p_namhoc_id uuid, p_tuan_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_dem_du_lieu_lien_quan_tuan(p_namhoc_id uuid, p_tuan_id uuid) TO anon;
GRANT ALL ON FUNCTION public.fn_dem_du_lieu_lien_quan_tuan(p_namhoc_id uuid, p_tuan_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.fn_dem_du_lieu_lien_quan_tuan(p_namhoc_id uuid, p_tuan_id uuid) TO service_role;


--
-- Name: FUNCTION fn_dong_bo_taikhoan_sang_auth_users(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_dong_bo_taikhoan_sang_auth_users() TO anon;
GRANT ALL ON FUNCTION public.fn_dong_bo_taikhoan_sang_auth_users() TO authenticated;
GRANT ALL ON FUNCTION public.fn_dong_bo_taikhoan_sang_auth_users() TO service_role;


--
-- Name: FUNCTION fn_is_mfa_enabled(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_is_mfa_enabled() TO anon;
GRANT ALL ON FUNCTION public.fn_is_mfa_enabled() TO authenticated;
GRANT ALL ON FUNCTION public.fn_is_mfa_enabled() TO service_role;


--
-- Name: FUNCTION fn_kiem_tra_an_ninh_taikhoan(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_kiem_tra_an_ninh_taikhoan() TO anon;
GRANT ALL ON FUNCTION public.fn_kiem_tra_an_ninh_taikhoan() TO authenticated;
GRANT ALL ON FUNCTION public.fn_kiem_tra_an_ninh_taikhoan() TO service_role;


--
-- Name: FUNCTION fn_kiem_tra_va_khoa_tuan(p_namhoc_id uuid, p_hocky text, p_tuan text, p_force boolean); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_kiem_tra_va_khoa_tuan(p_namhoc_id uuid, p_hocky text, p_tuan text, p_force boolean) TO anon;
GRANT ALL ON FUNCTION public.fn_kiem_tra_va_khoa_tuan(p_namhoc_id uuid, p_hocky text, p_tuan text, p_force boolean) TO authenticated;
GRANT ALL ON FUNCTION public.fn_kiem_tra_va_khoa_tuan(p_namhoc_id uuid, p_hocky text, p_tuan text, p_force boolean) TO service_role;


--
-- Name: FUNCTION fn_kiem_tra_xu_phat_tuan_thu_cong(p_tuan text, p_hocky text, p_namhoc_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_kiem_tra_xu_phat_tuan_thu_cong(p_tuan text, p_hocky text, p_namhoc_id uuid) TO anon;
GRANT ALL ON FUNCTION public.fn_kiem_tra_xu_phat_tuan_thu_cong(p_tuan text, p_hocky text, p_namhoc_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.fn_kiem_tra_xu_phat_tuan_thu_cong(p_tuan text, p_hocky text, p_namhoc_id uuid) TO service_role;


--
-- Name: FUNCTION fn_tu_dong_bam_mat_khau_taikhoan(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_tu_dong_bam_mat_khau_taikhoan() TO anon;
GRANT ALL ON FUNCTION public.fn_tu_dong_bam_mat_khau_taikhoan() TO authenticated;
GRANT ALL ON FUNCTION public.fn_tu_dong_bam_mat_khau_taikhoan() TO service_role;


--
-- Name: FUNCTION fn_tu_dong_khoa_tuan(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_tu_dong_khoa_tuan() TO anon;
GRANT ALL ON FUNCTION public.fn_tu_dong_khoa_tuan() TO authenticated;
GRANT ALL ON FUNCTION public.fn_tu_dong_khoa_tuan() TO service_role;


--
-- Name: FUNCTION fn_tu_dong_khoa_tuan_va_xu_phat(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_tu_dong_khoa_tuan_va_xu_phat() TO anon;
GRANT ALL ON FUNCTION public.fn_tu_dong_khoa_tuan_va_xu_phat() TO authenticated;
GRANT ALL ON FUNCTION public.fn_tu_dong_khoa_tuan_va_xu_phat() TO service_role;


--
-- Name: FUNCTION fn_tu_dong_khoa_tuan_va_xu_phat_thu_cong(p_namhoc_id uuid, p_tuan_id uuid, p_username text, p_password text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_tu_dong_khoa_tuan_va_xu_phat_thu_cong(p_namhoc_id uuid, p_tuan_id uuid, p_username text, p_password text) TO anon;
GRANT ALL ON FUNCTION public.fn_tu_dong_khoa_tuan_va_xu_phat_thu_cong(p_namhoc_id uuid, p_tuan_id uuid, p_username text, p_password text) TO authenticated;
GRANT ALL ON FUNCTION public.fn_tu_dong_khoa_tuan_va_xu_phat_thu_cong(p_namhoc_id uuid, p_tuan_id uuid, p_username text, p_password text) TO service_role;


--
-- Name: FUNCTION fn_xoa_tuan_hoc_toan_dien(p_namhoc_id uuid, p_tuan_id uuid, p_username text, p_password text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_xoa_tuan_hoc_toan_dien(p_namhoc_id uuid, p_tuan_id uuid, p_username text, p_password text) TO anon;
GRANT ALL ON FUNCTION public.fn_xoa_tuan_hoc_toan_dien(p_namhoc_id uuid, p_tuan_id uuid, p_username text, p_password text) TO authenticated;
GRANT ALL ON FUNCTION public.fn_xoa_tuan_hoc_toan_dien(p_namhoc_id uuid, p_tuan_id uuid, p_username text, p_password text) TO service_role;


--
-- Name: FUNCTION fn_xu_phat_thu_cong(p_namhoc_id uuid, p_tuan_id uuid, p_username text, p_password text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_xu_phat_thu_cong(p_namhoc_id uuid, p_tuan_id uuid, p_username text, p_password text) TO anon;
GRANT ALL ON FUNCTION public.fn_xu_phat_thu_cong(p_namhoc_id uuid, p_tuan_id uuid, p_username text, p_password text) TO authenticated;
GRANT ALL ON FUNCTION public.fn_xu_phat_thu_cong(p_namhoc_id uuid, p_tuan_id uuid, p_username text, p_password text) TO service_role;


--
-- Name: FUNCTION get_auth_chidoan_id(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.get_auth_chidoan_id() TO anon;
GRANT ALL ON FUNCTION public.get_auth_chidoan_id() TO authenticated;
GRANT ALL ON FUNCTION public.get_auth_chidoan_id() TO service_role;


--
-- Name: FUNCTION get_auth_doanvien_id(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.get_auth_doanvien_id() TO anon;
GRANT ALL ON FUNCTION public.get_auth_doanvien_id() TO authenticated;
GRANT ALL ON FUNCTION public.get_auth_doanvien_id() TO service_role;


--
-- Name: FUNCTION get_auth_role(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.get_auth_role() TO anon;
GRANT ALL ON FUNCTION public.get_auth_role() TO authenticated;
GRANT ALL ON FUNCTION public.get_auth_role() TO service_role;


--
-- Name: FUNCTION get_chamdiem_history(p_id text, p_limit integer, p_offset integer); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.get_chamdiem_history(p_id text, p_limit integer, p_offset integer) TO anon;
GRANT ALL ON FUNCTION public.get_chamdiem_history(p_id text, p_limit integer, p_offset integer) TO authenticated;
GRANT ALL ON FUNCTION public.get_chamdiem_history(p_id text, p_limit integer, p_offset integer) TO service_role;


--
-- Name: FUNCTION get_my_role(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.get_my_role() TO anon;
GRANT ALL ON FUNCTION public.get_my_role() TO authenticated;
GRANT ALL ON FUNCTION public.get_my_role() TO service_role;


--
-- Name: FUNCTION get_secure_chidoan_id(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.get_secure_chidoan_id() TO anon;
GRANT ALL ON FUNCTION public.get_secure_chidoan_id() TO authenticated;
GRANT ALL ON FUNCTION public.get_secure_chidoan_id() TO service_role;


--
-- Name: FUNCTION get_secure_doanvien_id(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.get_secure_doanvien_id() TO anon;
GRANT ALL ON FUNCTION public.get_secure_doanvien_id() TO authenticated;
GRANT ALL ON FUNCTION public.get_secure_doanvien_id() TO service_role;


--
-- Name: FUNCTION get_secure_role(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.get_secure_role() TO anon;
GRANT ALL ON FUNCTION public.get_secure_role() TO authenticated;
GRANT ALL ON FUNCTION public.get_secure_role() TO service_role;


--
-- Name: FUNCTION get_student_violation_stats_advanced(p_namhoc_id uuid, p_hocky text, p_chidoan_id uuid, p_doanvien_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.get_student_violation_stats_advanced(p_namhoc_id uuid, p_hocky text, p_chidoan_id uuid, p_doanvien_id uuid) TO anon;
GRANT ALL ON FUNCTION public.get_student_violation_stats_advanced(p_namhoc_id uuid, p_hocky text, p_chidoan_id uuid, p_doanvien_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_student_violation_stats_advanced(p_namhoc_id uuid, p_hocky text, p_chidoan_id uuid, p_doanvien_id uuid) TO service_role;


--
-- Name: FUNCTION handle_chi_doan_deletion(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.handle_chi_doan_deletion() TO anon;
GRANT ALL ON FUNCTION public.handle_chi_doan_deletion() TO authenticated;
GRANT ALL ON FUNCTION public.handle_chi_doan_deletion() TO service_role;


--
-- Name: FUNCTION handle_post_like(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.handle_post_like() TO anon;
GRANT ALL ON FUNCTION public.handle_post_like() TO authenticated;
GRANT ALL ON FUNCTION public.handle_post_like() TO service_role;


--
-- Name: FUNCTION handle_update_likes_count(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.handle_update_likes_count() TO anon;
GRANT ALL ON FUNCTION public.handle_update_likes_count() TO authenticated;
GRANT ALL ON FUNCTION public.handle_update_likes_count() TO service_role;


--
-- Name: FUNCTION rpc_admin_reset_user_mfa(p_user_id text, p_username text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.rpc_admin_reset_user_mfa(p_user_id text, p_username text) TO anon;
GRANT ALL ON FUNCTION public.rpc_admin_reset_user_mfa(p_user_id text, p_username text) TO authenticated;
GRANT ALL ON FUNCTION public.rpc_admin_reset_user_mfa(p_user_id text, p_username text) TO service_role;


--
-- Name: FUNCTION rpc_authenticate_user(p_username text, p_password text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.rpc_authenticate_user(p_username text, p_password text) TO anon;
GRANT ALL ON FUNCTION public.rpc_authenticate_user(p_username text, p_password text) TO authenticated;
GRANT ALL ON FUNCTION public.rpc_authenticate_user(p_username text, p_password text) TO service_role;


--
-- Name: FUNCTION rpc_create_account_secure(p_username text, p_password text, p_fullname text, p_role text, p_chidoan_id uuid, p_doanvien_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.rpc_create_account_secure(p_username text, p_password text, p_fullname text, p_role text, p_chidoan_id uuid, p_doanvien_id uuid) TO anon;
GRANT ALL ON FUNCTION public.rpc_create_account_secure(p_username text, p_password text, p_fullname text, p_role text, p_chidoan_id uuid, p_doanvien_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.rpc_create_account_secure(p_username text, p_password text, p_fullname text, p_role text, p_chidoan_id uuid, p_doanvien_id uuid) TO service_role;


--
-- Name: FUNCTION rpc_create_account_secure(p_username text, p_password text, p_fullname text, p_role text, p_chidoan_id uuid, p_namhoc uuid, p_sdt text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.rpc_create_account_secure(p_username text, p_password text, p_fullname text, p_role text, p_chidoan_id uuid, p_namhoc uuid, p_sdt text) TO anon;
GRANT ALL ON FUNCTION public.rpc_create_account_secure(p_username text, p_password text, p_fullname text, p_role text, p_chidoan_id uuid, p_namhoc uuid, p_sdt text) TO authenticated;
GRANT ALL ON FUNCTION public.rpc_create_account_secure(p_username text, p_password text, p_fullname text, p_role text, p_chidoan_id uuid, p_namhoc uuid, p_sdt text) TO service_role;


--
-- Name: FUNCTION rpc_delete_auth_users_by_usernames(p_usernames text[]); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.rpc_delete_auth_users_by_usernames(p_usernames text[]) TO anon;
GRANT ALL ON FUNCTION public.rpc_delete_auth_users_by_usernames(p_usernames text[]) TO authenticated;
GRANT ALL ON FUNCTION public.rpc_delete_auth_users_by_usernames(p_usernames text[]) TO service_role;


--
-- Name: FUNCTION rpc_get_user_by_username(p_username text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.rpc_get_user_by_username(p_username text) TO anon;
GRANT ALL ON FUNCTION public.rpc_get_user_by_username(p_username text) TO authenticated;
GRANT ALL ON FUNCTION public.rpc_get_user_by_username(p_username text) TO service_role;


--
-- Name: FUNCTION rpc_tao_tai_khoan_an_toan(p_username text, p_password text, p_fullname text, p_role text, p_chidoan_id uuid, p_doanvien_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.rpc_tao_tai_khoan_an_toan(p_username text, p_password text, p_fullname text, p_role text, p_chidoan_id uuid, p_doanvien_id uuid) TO anon;
GRANT ALL ON FUNCTION public.rpc_tao_tai_khoan_an_toan(p_username text, p_password text, p_fullname text, p_role text, p_chidoan_id uuid, p_doanvien_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.rpc_tao_tai_khoan_an_toan(p_username text, p_password text, p_fullname text, p_role text, p_chidoan_id uuid, p_doanvien_id uuid) TO service_role;


--
-- Name: FUNCTION save_user_backup_codes(p_encrypted_codes text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.save_user_backup_codes(p_encrypted_codes text) TO anon;
GRANT ALL ON FUNCTION public.save_user_backup_codes(p_encrypted_codes text) TO authenticated;
GRANT ALL ON FUNCTION public.save_user_backup_codes(p_encrypted_codes text) TO service_role;


--
-- Name: FUNCTION trigger_update_login_stats(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trigger_update_login_stats() TO anon;
GRANT ALL ON FUNCTION public.trigger_update_login_stats() TO authenticated;
GRANT ALL ON FUNCTION public.trigger_update_login_stats() TO service_role;


--
-- Name: FUNCTION update_likes_count(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.update_likes_count() TO anon;
GRANT ALL ON FUNCTION public.update_likes_count() TO authenticated;
GRANT ALL ON FUNCTION public.update_likes_count() TO service_role;


--
-- Name: FUNCTION update_modified_column(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.update_modified_column() TO anon;
GRANT ALL ON FUNCTION public.update_modified_column() TO authenticated;
GRANT ALL ON FUNCTION public.update_modified_column() TO service_role;


--
-- Name: FUNCTION verify_and_consume_backup_code(p_code text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.verify_and_consume_backup_code(p_code text) TO anon;
GRANT ALL ON FUNCTION public.verify_and_consume_backup_code(p_code text) TO authenticated;
GRANT ALL ON FUNCTION public.verify_and_consume_backup_code(p_code text) TO service_role;


--
-- Name: TABLE activity_logs; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.activity_logs TO anon;
GRANT ALL ON TABLE public.activity_logs TO authenticated;
GRANT ALL ON TABLE public.activity_logs TO service_role;


--
-- Name: TABLE cauhinh_tieuchi_xet_thidua; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.cauhinh_tieuchi_xet_thidua TO anon;
GRANT ALL ON TABLE public.cauhinh_tieuchi_xet_thidua TO authenticated;
GRANT ALL ON TABLE public.cauhinh_tieuchi_xet_thidua TO service_role;


--
-- Name: TABLE chamdiem; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.chamdiem TO anon;
GRANT ALL ON TABLE public.chamdiem TO authenticated;
GRANT ALL ON TABLE public.chamdiem TO service_role;


--
-- Name: TABLE doanvien; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.doanvien TO anon;
GRANT ALL ON TABLE public.doanvien TO authenticated;
GRANT ALL ON TABLE public.doanvien TO service_role;


--
-- Name: TABLE dotptdoanvien; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.dotptdoanvien TO anon;
GRANT ALL ON TABLE public.dotptdoanvien TO authenticated;
GRANT ALL ON TABLE public.dotptdoanvien TO service_role;


--
-- Name: TABLE duytricsdl; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.duytricsdl TO anon;
GRANT ALL ON TABLE public.duytricsdl TO authenticated;
GRANT ALL ON TABLE public.duytricsdl TO service_role;


--
-- Name: TABLE gio_hoc_tap; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.gio_hoc_tap TO anon;
GRANT ALL ON TABLE public.gio_hoc_tap TO authenticated;
GRANT ALL ON TABLE public.gio_hoc_tap TO service_role;


--
-- Name: TABLE github_settings; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.github_settings TO anon;
GRANT ALL ON TABLE public.github_settings TO authenticated;
GRANT ALL ON TABLE public.github_settings TO service_role;


--
-- Name: TABLE homthugopy; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.homthugopy TO anon;
GRANT ALL ON TABLE public.homthugopy TO authenticated;
GRANT ALL ON TABLE public.homthugopy TO service_role;


--
-- Name: TABLE namhoc; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.namhoc TO anon;
GRANT ALL ON TABLE public.namhoc TO authenticated;
GRANT ALL ON TABLE public.namhoc TO service_role;


--
-- Name: TABLE phancong; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.phancong TO anon;
GRANT ALL ON TABLE public.phancong TO authenticated;
GRANT ALL ON TABLE public.phancong TO service_role;


--
-- Name: TABLE phanquyen; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.phanquyen TO anon;
GRANT ALL ON TABLE public.phanquyen TO authenticated;
GRANT ALL ON TABLE public.phanquyen TO service_role;


--
-- Name: SEQUENCE phanquyen_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.phanquyen_id_seq TO anon;
GRANT ALL ON SEQUENCE public.phanquyen_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.phanquyen_id_seq TO service_role;


--
-- Name: TABLE ptdoanvien; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.ptdoanvien TO anon;
GRANT ALL ON TABLE public.ptdoanvien TO authenticated;
GRANT ALL ON TABLE public.ptdoanvien TO service_role;


--
-- Name: TABLE push_subscriptions; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.push_subscriptions TO anon;
GRANT ALL ON TABLE public.push_subscriptions TO authenticated;
GRANT ALL ON TABLE public.push_subscriptions TO service_role;


--
-- Name: TABLE ql_baocao; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.ql_baocao TO anon;
GRANT ALL ON TABLE public.ql_baocao TO authenticated;
GRANT ALL ON TABLE public.ql_baocao TO service_role;


--
-- Name: TABLE ql_nop_bc; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.ql_nop_bc TO anon;
GRANT ALL ON TABLE public.ql_nop_bc TO authenticated;
GRANT ALL ON TABLE public.ql_nop_bc TO service_role;


--
-- Name: TABLE qlchidoan; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.qlchidoan TO anon;
GRANT ALL ON TABLE public.qlchidoan TO authenticated;
GRANT ALL ON TABLE public.qlchidoan TO service_role;


--
-- Name: TABLE settings; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.settings TO anon;
GRANT ALL ON TABLE public.settings TO authenticated;
GRANT ALL ON TABLE public.settings TO service_role;


--
-- Name: TABLE taikhoan; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.taikhoan TO anon;
GRANT ALL ON TABLE public.taikhoan TO authenticated;
GRANT ALL ON TABLE public.taikhoan TO service_role;


--
-- Name: TABLE theodoi360; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.theodoi360 TO anon;
GRANT ALL ON TABLE public.theodoi360 TO authenticated;
GRANT ALL ON TABLE public.theodoi360 TO service_role;


--
-- Name: TABLE thongbao_hethong; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.thongbao_hethong TO anon;
GRANT ALL ON TABLE public.thongbao_hethong TO authenticated;
GRANT ALL ON TABLE public.thongbao_hethong TO service_role;


--
-- Name: TABLE thongbao_riengbiet; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.thongbao_riengbiet TO anon;
GRANT ALL ON TABLE public.thongbao_riengbiet TO authenticated;
GRANT ALL ON TABLE public.thongbao_riengbiet TO service_role;


--
-- Name: TABLE tieuchitd; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.tieuchitd TO anon;
GRANT ALL ON TABLE public.tieuchitd TO authenticated;
GRANT ALL ON TABLE public.tieuchitd TO service_role;


--
-- Name: TABLE tuanhoc; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.tuanhoc TO anon;
GRANT ALL ON TABLE public.tuanhoc TO authenticated;
GRANT ALL ON TABLE public.tuanhoc TO service_role;


--
-- Name: TABLE vanban_doan; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.vanban_doan TO anon;
GRANT ALL ON TABLE public.vanban_doan TO authenticated;
GRANT ALL ON TABLE public.vanban_doan TO service_role;


--
-- Name: TABLE xet_thidua; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.xet_thidua TO anon;
GRANT ALL ON TABLE public.xet_thidua TO authenticated;
GRANT ALL ON TABLE public.xet_thidua TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- PostgreSQL database dump complete
--


