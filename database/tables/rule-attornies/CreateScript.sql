-- Table: public.rule_attorneys_mapping

-- DROP TABLE IF EXISTS public.rule_attorneys_mapping;

CREATE TABLE IF NOT EXISTS public.rule_attorneys_mapping
(
    id integer NOT NULL DEFAULT nextval('rule_attorneys_mapping_id_seq'::regclass),
    rule_id integer NOT NULL,
    attorney_id integer NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    CONSTRAINT rule_attorneys_mapping_pkey PRIMARY KEY (id),
    CONSTRAINT rule_attorneys_mapping_attorney_id_fkey FOREIGN KEY (attorney_id)
        REFERENCES public.attornies (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION,
    CONSTRAINT rule_attorneys_mapping_rule_id_fkey FOREIGN KEY (rule_id)
        REFERENCES public.rules (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.rule_attorneys_mapping
    OWNER to postgres;