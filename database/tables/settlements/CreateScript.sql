-- Table: public.settlements

-- DROP TABLE IF EXISTS public.settlements;

CREATE TABLE IF NOT EXISTS public.settlements
(
    id integer NOT NULL DEFAULT nextval('selttlements_id_seq'::regclass),
    patient_id integer,
    attorney_id integer,
    settlement_date date NOT NULL,
    total_billed_charges numeric(18,2) NOT NULL,
    status bit(1) NOT NULL DEFAULT '1'::"bit",
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    settlement_percentage numeric(18,2),
    settlement_amount numeric(18,2) NOT NULL,
    CONSTRAINT selttlements_pkey PRIMARY KEY (id),
    CONSTRAINT selttlements_attorney_id_fkey FOREIGN KEY (attorney_id)
        REFERENCES public.attornies (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION,
    CONSTRAINT selttlements_patient_id_fkey FOREIGN KEY (patient_id)
        REFERENCES public.patients (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.settlements
    OWNER to postgres;