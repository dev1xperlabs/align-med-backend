-- Table: public.providers

-- DROP TABLE IF EXISTS public.providers;

CREATE TABLE IF NOT EXISTS public.providers
(
    id integer NOT NULL DEFAULT nextval('providers_id_seq'::regclass),
    name character varying(255) COLLATE pg_catalog."default" NOT NULL,
    status bit(1) NOT NULL DEFAULT '1'::"bit",
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT providers_pkey PRIMARY KEY (id)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.providers
    OWNER to postgres;