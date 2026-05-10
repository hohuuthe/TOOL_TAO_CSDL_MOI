--
-- PostgreSQL database dump
--

\restrict zmkjZFdgGYUetqg7rtp5GBLVA3eJt3CL7S89pxyBUwJu4ZYZIgybFQ41LgSO844

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.9 (Ubuntu 17.9-1.pgdg24.04+1)

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

CREATE SCHEMA public;


ALTER SCHEMA public OWNER TO pg_database_owner;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: pg_database_owner
--

COMMENT ON SCHEMA public IS 'standard public schema';


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
    updatedat timestamp with time zone DEFAULT now(),
    chidoan_id uuid,
    createdat timestamp with time zone DEFAULT now()
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
    hocky text,
    diachi text,
    chidoan_id uuid,
    createdat timestamp with time zone DEFAULT now()
);


ALTER TABLE public.doanvien OWNER TO postgres;

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
    isdefault boolean DEFAULT false,
    islocked boolean DEFAULT false,
    updatedat timestamp with time zone DEFAULT now(),
    createdat timestamp with time zone DEFAULT now()
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
    quyen_xem boolean DEFAULT false,
    quyen_them boolean DEFAULT false,
    quyen_sua boolean DEFAULT false,
    quyen_xoa boolean DEFAULT false,
    quyen_chi_doan_phu_trach boolean DEFAULT false,
    ngay_cap_nhat timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    nam_hoc uuid,
    quyen_xem_tat_ca_chi_doan boolean DEFAULT false,
    createdat timestamp with time zone DEFAULT now(),
    updatedat timestamp with time zone DEFAULT now()
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
    namhoc uuid,
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
    phonghoc text,
    bithu text,
    gvcn text,
    namhoc uuid NOT NULL,
    updatedat timestamp with time zone DEFAULT now(),
    createdat timestamp with time zone DEFAULT now()
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
    namhoc uuid,
    createdat timestamp with time zone DEFAULT now(),
    updatedat timestamp with time zone DEFAULT now()
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
-- Name: idx_chamdiem_chidoan_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_chamdiem_chidoan_id ON public.chamdiem USING btree (chidoan_id);


--
-- Name: idx_chamdiem_doanvienid; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_chamdiem_doanvienid ON public.chamdiem USING btree (doanvienid);


--
-- Name: idx_chamdiem_loaitieuchi; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_chamdiem_loaitieuchi ON public.chamdiem USING btree (loaitieuchi);


--
-- Name: idx_chamdiem_namhoc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_chamdiem_namhoc ON public.chamdiem USING btree (namhoc);


--
-- Name: idx_chamdiem_thoigian_context; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_chamdiem_thoigian_context ON public.chamdiem USING btree (namhoc, hocky, tuan);


--
-- Name: idx_doanvien_chidoan_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_doanvien_chidoan_id ON public.doanvien USING btree (chidoan_id);


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
-- Name: idx_dotptdoanvien_namhoc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_dotptdoanvien_namhoc ON public.dotptdoanvien USING btree (namhoc);


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
-- Name: idx_phancong_namhoc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_phancong_namhoc ON public.phancong USING btree (namhoc);


--
-- Name: idx_phanquyen_namhoc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_phanquyen_namhoc ON public.phanquyen USING btree (nam_hoc);


--
-- Name: idx_ptdoanvien_doanvien; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_ptdoanvien_doanvien ON public.ptdoanvien USING btree (doanvien_id);


--
-- Name: idx_ptdoanvien_dot; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_ptdoanvien_dot ON public.ptdoanvien USING btree (dotdangki);


--
-- Name: idx_ptdoanvien_namhoc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_ptdoanvien_namhoc ON public.ptdoanvien USING btree (namhoc);


--
-- Name: idx_qlchidoan_namhoc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_qlchidoan_namhoc ON public.qlchidoan USING btree (namhoc);


--
-- Name: idx_settings_namhoc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_settings_namhoc ON public.settings USING btree (namhoc);


--
-- Name: idx_taikhoan_chidoan; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_taikhoan_chidoan ON public.taikhoan USING btree (chidoan_id);


--
-- Name: idx_tieuchitd_context; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tieuchitd_context ON public.tieuchitd USING btree (namhoc, hocky);


--
-- Name: idx_tieuchitd_namhoc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tieuchitd_namhoc ON public.tieuchitd USING btree (namhoc);


--
-- Name: idx_tuanhoc_context; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tuanhoc_context ON public.tuanhoc USING btree (namhoc, hocky, tuan);


--
-- Name: idx_tuanhoc_namhoc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tuanhoc_namhoc ON public.tuanhoc USING btree (namhoc);


--
-- Name: ngay_3_5_idx_ptdoanvien_doanvien_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ngay_3_5_idx_ptdoanvien_doanvien_id ON public.ptdoanvien USING btree (doanvien_id);


--
-- Name: ngay_3_5_idx_ptdoanvien_dotdangki; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ngay_3_5_idx_ptdoanvien_dotdangki ON public.ptdoanvien USING btree (dotdangki);


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
-- Name: taikhoan taikhoan_chidoan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.taikhoan
    ADD CONSTRAINT taikhoan_chidoan_id_fkey FOREIGN KEY (chidoan_id) REFERENCES public.qlchidoan(id) ON UPDATE CASCADE ON DELETE CASCADE;


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
-- Name: taikhoan Enable read access for all users; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Enable read access for all users" ON public.taikhoan FOR SELECT USING (true);


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
-- Name: FUNCTION update_modified_column(); Type: ACL; Schema: public; Owner: postgres
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

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- PostgreSQL database dump complete
--

\unrestrict zmkjZFdgGYUetqg7rtp5GBLVA3eJt3CL7S89pxyBUwJu4ZYZIgybFQ41LgSO844

