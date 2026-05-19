--
-- PostgreSQL database dump
--

\restrict pUwXR2wJuSVOw6v1ou8eVpsXAZ8Vv6i3CnaxQjKsrIV9gxY9RKzZExCXqkf4UKM

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.10 (Ubuntu 17.10-1.pgdg24.04+1)

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
-- Name: delete_cascade_chidoan_logic(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_cascade_chidoan_logic() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM phancong 
    -- Bỏ dấu ngoặc kép hoặc dùng đúng tên cột viết thường
    WHERE (lopcham = OLD.tenchidoan OR chamlop = OLD.tenchidoan) 
      AND namhoc = OLD.namhoc;
    RETURN OLD;
END;
$$;


ALTER FUNCTION public.delete_cascade_chidoan_logic() OWNER TO postgres;

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

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: taikhoan; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.taikhoan (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    username text NOT NULL,
    password text NOT NULL,
    fullname text NOT NULL,
    role text NOT NULL,
    chidoan text,
    updatedat timestamp with time zone DEFAULT now(),
    namhoc text
);


ALTER TABLE public.taikhoan OWNER TO postgres;

--
-- Name: rpc_get_user_by_username(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.rpc_get_user_by_username(p_username text) RETURNS SETOF public.taikhoan
    LANGUAGE sql SECURITY DEFINER
    AS $$
  SELECT * FROM taikhoan WHERE username = p_username OR username = lower(p_username) LIMIT 1;
$$;


ALTER FUNCTION public.rpc_get_user_by_username(p_username text) OWNER TO postgres;

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
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.activity_logs OWNER TO postgres;

--
-- Name: chamdiem; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.chamdiem (
    id text DEFAULT (gen_random_uuid())::text NOT NULL,
    namhoc text,
    hocky text,
    tuan text,
    thu text,
    ngay text,
    lopcham text,
    chamlop text,
    doanvienid text,
    hotendoanvien text,
    matieuchi text,
    tentieuchi text,
    loaitieuchi text,
    diemtru numeric DEFAULT 0,
    diemcong numeric DEFAULT 0,
    ghichu text,
    nguoicham text,
    updatedat timestamp with time zone DEFAULT now()
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
    namhoc text,
    hocky text,
    diachi text,
    chidoan_id uuid
);


ALTER TABLE public.doanvien OWNER TO postgres;

--
-- Name: dotptdoanvien; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.dotptdoanvien (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    namhoc text NOT NULL,
    hocky text NOT NULL,
    tendot text NOT NULL,
    tungay text,
    denngay text,
    isdefault boolean DEFAULT false,
    islocked boolean DEFAULT false,
    ghichu text,
    updatedat timestamp with time zone DEFAULT now()
);


ALTER TABLE public.dotptdoanvien OWNER TO postgres;

--
-- Name: duytricsdl; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.duytricsdl (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    so bigint DEFAULT 0,
    thoigian timestamp with time zone DEFAULT now()
);


ALTER TABLE public.duytricsdl OWNER TO postgres;

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
    updated_by text
);


ALTER TABLE public.github_settings OWNER TO postgres;

--
-- Name: namhoc; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.namhoc (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    tennamhoc text NOT NULL,
    tenhocky text NOT NULL,
    isdefault boolean DEFAULT false,
    islocked boolean DEFAULT false,
    updatedat timestamp with time zone DEFAULT now()
);


ALTER TABLE public.namhoc OWNER TO postgres;

--
-- Name: phancong; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.phancong (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    hocky text NOT NULL,
    tuan text NOT NULL,
    lopcham text NOT NULL,
    chamlop text NOT NULL,
    updatedat timestamp with time zone DEFAULT now(),
    namhoc text
);


ALTER TABLE public.phancong OWNER TO postgres;

--
-- Name: phanquyen; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.phanquyen (
    id bigint NOT NULL,
    doi_tuong character varying(50) NOT NULL,
    tab_chuc_nang character varying(100) NOT NULL,
    quyen_xem boolean DEFAULT false,
    quyen_them boolean DEFAULT false,
    quyen_sua boolean DEFAULT false,
    quyen_xoa boolean DEFAULT false,
    quyen_chi_doan_phu_trach boolean DEFAULT false,
    ngay_cap_nhat timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    nam_hoc text,
    quyen_xem_tat_ca_chi_doan boolean DEFAULT false
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
-- Name: COLUMN phanquyen.quyen_chi_doan_phu_trach; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.phanquyen.quyen_chi_doan_phu_trach IS 'Giới hạn phạm vi dữ liệu chỉ trong chi đoàn của user';


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
    namhoc text,
    soquyetdinh text,
    ngayquyetdinh date
);


ALTER TABLE public.ptdoanvien OWNER TO postgres;

--
-- Name: qlchidoan; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.qlchidoan (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    tenchidoan text NOT NULL,
    buoihoc text NOT NULL,
    ban text,
    doanvien integer DEFAULT 0,
    thanhnien integer DEFAULT 0,
    tongso integer DEFAULT 0,
    phonghoc text,
    bithu text,
    gvcn text,
    namhoc text NOT NULL,
    updatedat timestamp with time zone DEFAULT now()
);


ALTER TABLE public.qlchidoan OWNER TO postgres;

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
    namhoc text
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
    namhoc text
);


ALTER TABLE public.tieuchitd OWNER TO postgres;

--
-- Name: tuanhoc; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tuanhoc (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    namhoc text NOT NULL,
    hocky text NOT NULL,
    tuan text NOT NULL,
    tungay text,
    denngay text,
    isdefault boolean DEFAULT false,
    islocked boolean DEFAULT false,
    updatedat timestamp with time zone DEFAULT now(),
    ghichu text
);


ALTER TABLE public.tuanhoc OWNER TO postgres;

--
-- Name: activity_logs activity_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.activity_logs
    ADD CONSTRAINT activity_logs_pkey PRIMARY KEY (id);


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
-- Name: taikhoan taikhoan_username_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.taikhoan
    ADD CONSTRAINT taikhoan_username_key UNIQUE (username);


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
-- Name: namhoc unique_namhoc_hocky; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.namhoc
    ADD CONSTRAINT unique_namhoc_hocky UNIQUE (tennamhoc, tenhocky);


--
-- Name: qlchidoan unique_namhoc_tenchidoan; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.qlchidoan
    ADD CONSTRAINT unique_namhoc_tenchidoan UNIQUE (namhoc, tenchidoan);


--
-- Name: idx_activity_logs_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_activity_logs_created_at ON public.activity_logs USING btree (created_at DESC);


--
-- Name: idx_activity_logs_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_activity_logs_user_id ON public.activity_logs USING btree (user_id);


--
-- Name: idx_doanvien_chidoan_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_doanvien_chidoan_id ON public.doanvien USING btree (chidoan_id);


--
-- Name: idx_dotptdoanvien_nam_hk; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_dotptdoanvien_nam_hk ON public.dotptdoanvien USING btree (namhoc, hocky);


--
-- Name: ngay_3_5_idx_ptdoanvien_doanvien_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ngay_3_5_idx_ptdoanvien_doanvien_id ON public.ptdoanvien USING btree (doanvien_id);


--
-- Name: ngay_3_5_idx_ptdoanvien_dotdangki; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ngay_3_5_idx_ptdoanvien_dotdangki ON public.ptdoanvien USING btree (dotdangki);


--
-- Name: qlchidoan trigger_cascade_delete_chidoan; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_cascade_delete_chidoan BEFORE DELETE ON public.qlchidoan FOR EACH ROW EXECUTE FUNCTION public.delete_cascade_chidoan_logic();


--
-- Name: qlchidoan trigger_chi_doan_deletion; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_chi_doan_deletion AFTER DELETE ON public.qlchidoan FOR EACH ROW EXECUTE FUNCTION public.handle_chi_doan_deletion();


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
-- Name: doanvien fk_doanvien_chidoan; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.doanvien
    ADD CONSTRAINT fk_doanvien_chidoan FOREIGN KEY (chidoan_id) REFERENCES public.qlchidoan(id) ON DELETE CASCADE;


--
-- Name: activity_logs Admins can view all activity logs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admins can view all activity logs" ON public.activity_logs FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.taikhoan
  WHERE ((taikhoan.id = auth.uid()) AND (taikhoan.role = 'Admin'::text)))));


--
-- Name: activity_logs Authenticated users can insert activity logs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated users can insert activity logs" ON public.activity_logs FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: chamdiem Authenticated users only; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated users only" ON public.chamdiem TO authenticated USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: doanvien Authenticated users only; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated users only" ON public.doanvien TO authenticated USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: dotptdoanvien Authenticated users only; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated users only" ON public.dotptdoanvien TO authenticated USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: duytricsdl Authenticated users only; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated users only" ON public.duytricsdl TO authenticated USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: namhoc Authenticated users only; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated users only" ON public.namhoc TO authenticated USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: phancong Authenticated users only; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated users only" ON public.phancong TO authenticated USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: phanquyen Authenticated users only; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated users only" ON public.phanquyen TO authenticated USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: ptdoanvien Authenticated users only; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated users only" ON public.ptdoanvien TO authenticated USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: qlchidoan Authenticated users only; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated users only" ON public.qlchidoan TO authenticated USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: settings Authenticated users only; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated users only" ON public.settings TO authenticated USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: taikhoan Authenticated users only; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated users only" ON public.taikhoan TO authenticated USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: tieuchitd Authenticated users only; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated users only" ON public.tieuchitd TO authenticated USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: tuanhoc Authenticated users only; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated users only" ON public.tuanhoc TO authenticated USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: github_settings Cho phép Admin quản lý cấu hình github; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Cho phép Admin quản lý cấu hình github" ON public.github_settings TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.taikhoan
  WHERE ((taikhoan.id = auth.uid()) AND (taikhoan.role = 'Admin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.taikhoan
  WHERE ((taikhoan.id = auth.uid()) AND (taikhoan.role = 'Admin'::text)))));


--
-- Name: github_settings Cho phép người dùng đã đăng nhập thao tác github_se; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Cho phép người dùng đã đăng nhập thao tác github_se" ON public.github_settings TO authenticated USING (true) WITH CHECK (true);


--
-- Name: chamdiem Enable read access for all users; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Enable read access for all users" ON public.chamdiem FOR SELECT USING (true);


--
-- Name: phancong Enable read access for all users; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Enable read access for all users" ON public.phancong FOR SELECT USING (true);


--
-- Name: settings Enable read access for all users; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Enable read access for all users" ON public.settings FOR SELECT USING (true);


--
-- Name: tuanhoc Enable read access for all users; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Enable read access for all users" ON public.tuanhoc FOR SELECT USING (true);


--
-- Name: activity_logs; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.activity_logs ENABLE ROW LEVEL SECURITY;

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
-- Name: tieuchitd; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.tieuchitd ENABLE ROW LEVEL SECURITY;

--
-- Name: tuanhoc; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.tuanhoc ENABLE ROW LEVEL SECURITY;

--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--



--
-- Name: FUNCTION delete_cascade_chidoan_logic(); Type: ACL; Schema: public; Owner: postgres
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
-- Name: TABLE taikhoan; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: FUNCTION rpc_get_user_by_username(p_username text); Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: FUNCTION update_likes_count(); Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: TABLE activity_logs; Type: ACL; Schema: public; Owner: postgres
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
-- Name: TABLE qlchidoan; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: TABLE settings; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: TABLE tieuchitd; Type: ACL; Schema: public; Owner: postgres
--



--
-- Name: TABLE tuanhoc; Type: ACL; Schema: public; Owner: postgres
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

\unrestrict pUwXR2wJuSVOw6v1ou8eVpsXAZ8Vv6i3CnaxQjKsrIV9gxY9RKzZExCXqkf4UKM


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
