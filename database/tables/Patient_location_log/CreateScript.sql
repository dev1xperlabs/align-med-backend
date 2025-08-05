-- Table: public.patient_location_log

-- DROP TABLE IF EXISTS public.patient_location_log;

CREATE TABLE IF NOT EXISTS public.patient_location_log
(
    id bigint NOT NULL DEFAULT nextval('patient_location_log_id_seq'::regclass),
    patient_id bigint NOT NULL,
    location_id bigint NOT NULL,
    visit_date date NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    CONSTRAINT patient_location_log_pkey PRIMARY KEY (id),
    CONSTRAINT patient_location_log_location_id_fkey FOREIGN KEY (location_id)
        REFERENCES public.locations (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION,
    CONSTRAINT patient_location_log_patient_id_fkey FOREIGN KEY (patient_id)
        REFERENCES public.patients (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.patient_location_log
    OWNER to postgres;