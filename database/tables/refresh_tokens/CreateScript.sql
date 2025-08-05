-- Table: public.refresh_tokens

-- DROP TABLE IF EXISTS public.refresh_tokens;

CREATE TABLE IF NOT EXISTS public.refresh_tokens
(
    id integer NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 2147483647 CACHE 1 ),
    user_id integer NOT NULL,
    token character varying(255) COLLATE pg_catalog."default" NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT refresh_tokens_token_key UNIQUE (token),
    CONSTRAINT refresh_tokens_user_id_fkey FOREIGN KEY (user_id)
        REFERENCES public.users (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.refresh_tokens
    OWNER to postgres;