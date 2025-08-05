-- Table: public.locations

-- DROP TABLE IF EXISTS public.locations;

CREATE TABLE IF NOT EXISTS public.locations
(
    id integer NOT NULL DEFAULT nextval('locations_id_seq'::regclass),
    name character varying(255) COLLATE pg_catalog."default" NOT NULL,
    status bit(1) NOT NULL DEFAULT '1'::"bit",
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT locations_pkey PRIMARY KEY (id),
    CONSTRAINT locations_name_key UNIQUE (name)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.locations
    OWNER to postgres;