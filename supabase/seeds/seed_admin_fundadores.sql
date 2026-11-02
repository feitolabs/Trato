-- =============================================================================
-- Seed: Administradores Fundadores do Trato
-- João Vitor Cardoso, Emanoel Cabral e Gabriel Victor
-- Papel: administrador (acesso irrestrito e aprovação dupla cruzada)
-- Idempotente: pode ser executado múltiplas vezes com segurança.
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_joao_id   uuid;
  v_emanoel_id uuid;
  v_gabriel_id uuid;
  v_agora     timestamptz := now();
  v_tem_auth  boolean;
BEGIN
  -- Verifica se o schema auth existe (ambiente Supabase real / local)
  SELECT EXISTS(
    SELECT 1 FROM information_schema.schemata WHERE schema_name = 'auth'
  ) INTO v_tem_auth;

  -- 1. JOÃO VITOR CARDOSO
  IF v_tem_auth THEN
    SELECT id INTO v_joao_id FROM auth.users WHERE lower(email) = 'cardosojoaovitor47@gmail.com' LIMIT 1;
    IF v_joao_id IS NULL THEN
      v_joao_id := gen_random_uuid();
      INSERT INTO auth.users (
        id, instance_id, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at, role, aud
      ) VALUES (
        v_joao_id, '00000000-0000-0000-0000-000000000000', 'cardosojoaovitor47@gmail.com',
        crypt('TratoAdmin@2026', gen_salt('bf')), v_agora,
        '{"provider":"email","providers":["email"]}', '{"nome":"João Vitor Cardoso"}',
        v_agora, v_agora, 'authenticated', 'authenticated'
      );
    END IF;
  ELSE
    v_joao_id := coalesce(v_joao_id, gen_random_uuid());
  END IF;

  -- 2. EMANOEL CABRAL
  IF v_tem_auth THEN
    SELECT id INTO v_emanoel_id FROM auth.users WHERE lower(email) = 'emanoel.cabral@trato.feitolabs.com.br' LIMIT 1;
    IF v_emanoel_id IS NULL THEN
      v_emanoel_id := gen_random_uuid();
      INSERT INTO auth.users (
        id, instance_id, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at, role, aud
      ) VALUES (
        v_emanoel_id, '00000000-0000-0000-0000-000000000000', 'emanoel.cabral@trato.feitolabs.com.br',
        crypt('TratoAdmin@2026', gen_salt('bf')), v_agora,
        '{"provider":"email","providers":["email"]}', '{"nome":"Emanoel Cabral"}',
        v_agora, v_agora, 'authenticated', 'authenticated'
      );
    END IF;
  ELSE
    v_emanoel_id := coalesce(v_emanoel_id, gen_random_uuid());
  END IF;

  -- 3. GABRIEL VICTOR
  IF v_tem_auth THEN
    SELECT id INTO v_gabriel_id FROM auth.users WHERE lower(email) = 'gabriel.victor@trato.feitolabs.com.br' LIMIT 1;
    IF v_gabriel_id IS NULL THEN
      v_gabriel_id := gen_random_uuid();
      INSERT INTO auth.users (
        id, instance_id, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at, role, aud
      ) VALUES (
        v_gabriel_id, '00000000-0000-0000-0000-000000000000', 'gabriel.victor@trato.feitolabs.com.br',
        crypt('TratoAdmin@2026', gen_salt('bf')), v_agora,
        '{"provider":"email","providers":["email"]}', '{"nome":"Gabriel Victor"}',
        v_agora, v_agora, 'authenticated', 'authenticated'
      );
    END IF;
  ELSE
    v_gabriel_id := coalesce(v_gabriel_id, gen_random_uuid());
  END IF;

  -- Inserir / Atualizar em public.usuarios
  INSERT INTO public.usuarios (id, nome, status, criado_em, atualizado_em)
  VALUES
    (v_joao_id, 'João Vitor Cardoso', 'ativo', v_agora, v_agora),
    (v_emanoel_id, 'Emanoel Cabral', 'ativo', v_agora, v_agora),
    (v_gabriel_id, 'Gabriel Victor', 'ativo', v_agora, v_agora)
  ON CONFLICT (id) DO UPDATE SET
    nome = EXCLUDED.nome,
    status = 'ativo',
    atualizado_em = v_agora;

  -- Inserir / Atualizar em public.equipe como administrador
  INSERT INTO public.equipe (usuario_id, papel, ativo, alcada_centavos, criado_em, revogado_em)
  VALUES
    (v_joao_id, 'administrador', true, NULL, v_agora, NULL),
    (v_emanoel_id, 'administrador', true, NULL, v_agora, NULL),
    (v_gabriel_id, 'administrador', true, NULL, v_agora, NULL)
  ON CONFLICT (usuario_id) DO UPDATE SET
    papel = 'administrador',
    ativo = true,
    alcada_centavos = NULL,
    revogado_em = NULL;

  RAISE NOTICE 'Administradores vinculados com sucesso: João (%), Emanoel (%), Gabriel (%)',
    v_joao_id, v_emanoel_id, v_gabriel_id;
END $$;

COMMIT;
