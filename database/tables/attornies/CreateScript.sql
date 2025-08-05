-- Table: public.attornies

-- DROP TABLE IF EXISTS public.attornies;

CREATE TABLE IF NOT EXISTS public.attornies
(
    id integer NOT NULL DEFAULT nextval('attornies_id_seq'::regclass),
    name character varying(255) COLLATE pg_catalog."default" NOT NULL,
    phone_number character varying(20) COLLATE pg_catalog."default",
    status bit(1) NOT NULL DEFAULT '1'::"bit",
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT attornies_pkey PRIMARY KEY (id),
    CONSTRAINT attornies_name_key UNIQUE (name)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.attornies
    OWNER to postgres;