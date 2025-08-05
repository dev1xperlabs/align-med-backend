-- Table: public.patient_attorny_log

-- DROP TABLE IF EXISTS public.patient_attorny_log;

CREATE TABLE IF NOT EXISTS public.patient_attorny_log
(
    id bigint NOT NULL DEFAULT nextval('patient_attorny_log_id_seq'::regclass),
    patient_id bigint NOT NULL,
    attorney_id bigint NOT NULL,
    visit_date date NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    location_id integer,
    CONSTRAINT patient_attorny_log_pkey PRIMARY KEY (id),
    CONSTRAINT patient_attorny_log_attorney_id_fkey FOREIGN KEY (attorney_id)
        REFERENCES public.attornies (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION,
    CONSTRAINT patient_attorny_log_location_id_fkey FOREIGN KEY (location_id)
        REFERENCES public.locations (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION,
    CONSTRAINT patient_attorny_log_patient_id_fkey FOREIGN KEY (patient_id)
        REFERENCES public.patients (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.patient_attorny_log
    OWNER to postgres;