-- Table: public.bills

-- DROP TABLE IF EXISTS public.bills;

CREATE TABLE IF NOT EXISTS public.bills
(
    id bigint NOT NULL DEFAULT nextval('bills_id_seq'::regclass),
    patient_id integer NOT NULL,
    attorney_id integer NOT NULL,
    location_id integer,
    description jsonb,
    visit_date date,
    billed_date date NOT NULL,
    total_billed_charges numeric(18,2) NOT NULL,
    status bit(1) NOT NULL DEFAULT '1'::"bit",
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    provider_id integer,
    CONSTRAINT bills_pkey PRIMARY KEY (id),
    CONSTRAINT bills_attorney_id_fkey FOREIGN KEY (attorney_id)
        REFERENCES public.attornies (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION,
    CONSTRAINT bills_location_id_fkey FOREIGN KEY (location_id)
        REFERENCES public.locations (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION,
    CONSTRAINT bills_patient_id_fkey FOREIGN KEY (patient_id)
        REFERENCES public.patients (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION,
    CONSTRAINT bills_provider_id_fkey FOREIGN KEY (provider_id)
        REFERENCES public.providers (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION
        NOT VALID
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.bills
    OWNER to postgres;