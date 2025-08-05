-- Table: public.rules

-- DROP TABLE IF EXISTS public.rules;

CREATE TABLE IF NOT EXISTS public.rules
(
    id integer NOT NULL DEFAULT nextval('rules_id_seq'::regclass),
    provider_id integer NOT NULL,
    bonus_percentage numeric(18,2) NOT NULL,
    status bit(1) NOT NULL DEFAULT '1'::"bit",
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    rule_name character varying(255) COLLATE pg_catalog."default" NOT NULL DEFAULT ''::character varying,
    CONSTRAINT rules_pkey PRIMARY KEY (id),
    CONSTRAINT rules_provider_id_fkey FOREIGN KEY (provider_id)
        REFERENCES public.providers (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.rules
    OWNER to postgres;