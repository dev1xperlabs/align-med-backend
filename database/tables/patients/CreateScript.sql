-- Table: public.patients

-- DROP TABLE IF EXISTS public.patients;

CREATE TABLE IF NOT EXISTS public.patients
(
    id integer NOT NULL DEFAULT nextval('patients_id_seq'::regclass),
    external_mrn character varying(10) COLLATE pg_catalog."default" NOT NULL,
    first_name character varying(255) COLLATE pg_catalog."default" NOT NULL,
    middle_name character varying(255) COLLATE pg_catalog."default",
    last_name character varying(255) COLLATE pg_catalog."default",
    dob date,
    email character varying(255) COLLATE pg_catalog."default",
    phone_number character varying(20) COLLATE pg_catalog."default",
    status bit(1) NOT NULL DEFAULT '1'::"bit",
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    gender character varying(10) COLLATE pg_catalog."default",
    CONSTRAINT patients_pkey PRIMARY KEY (id)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.patients
    OWNER to postgres;