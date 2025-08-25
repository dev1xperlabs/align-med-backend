CREATE TABLE IF NOT EXISTS public.forget_password_tokens
(
    id integer NOT NULL DEFAULT nextval('forget_password_tokens_id_seq'::regclass),
    token character varying(255) COLLATE pg_catalog."default" NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    CONSTRAINT forget_password_tokens_pkey PRIMARY KEY (id)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.forget_password_tokens
    OWNER to admin;