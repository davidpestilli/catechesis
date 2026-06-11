-- =====================================================
-- SMAX Rejeites Snapshot
-- Snapshot atual de tickets em status Pronto no SMAX,
-- agrupados por usuario/equipe no Gerenciador.
-- =====================================================

BEGIN;
INSERT INTO public.permissoes_objetos (codigo, nome, descricao, categoria, origem)
VALUES (
  'distribuidor.smax_rejeites_robo_dev',
  'Robo SMAX Rejeites (Dev)',
  'Card dev para extrair o snapshot atual de rejeites no SMAX e salvar no dashboard Rejeites.',
  'distribuidor',
  'src/pages/Home.tsx'
)
ON CONFLICT (codigo) DO UPDATE
SET nome = EXCLUDED.nome,
    descricao = EXCLUDED.descricao,
    categoria = EXCLUDED.categoria,
    origem = EXCLUDED.origem,
    updated_at = now();
CREATE OR REPLACE FUNCTION public.smax_rejeites_normalizar_nome(p_nome text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT NULLIF(
    regexp_replace(
      upper(
        regexp_replace(
          trim(COALESCE(p_nome, '')),
          '^EU[[:space:]]*\((.*)\)$',
          '\1',
          'i'
        )
      ),
      '[[:space:]]+',
      ' ',
      'g'
    ),
    ''
  );
$$;
CREATE TABLE IF NOT EXISTS public.smax_rejeites_usuarios_map (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  equipe_id uuid NOT NULL REFERENCES public.equipes(id) ON DELETE CASCADE,
  user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  smax_nome text NOT NULL,
  smax_nome_key text NOT NULL,
  smax_person_id text,
  ativo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT smax_rejeites_usuarios_map_unique_nome UNIQUE (equipe_id, smax_nome_key),
  CONSTRAINT smax_rejeites_usuarios_map_person_unique UNIQUE (equipe_id, smax_person_id)
);
CREATE INDEX IF NOT EXISTS idx_smax_rejeites_usuarios_map_equipe
  ON public.smax_rejeites_usuarios_map(equipe_id);
CREATE INDEX IF NOT EXISTS idx_smax_rejeites_usuarios_map_user
  ON public.smax_rejeites_usuarios_map(user_id);
CREATE TABLE IF NOT EXISTS public.smax_rejeites_snapshot (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  equipe_id uuid NOT NULL REFERENCES public.equipes(id) ON DELETE CASCADE,
  user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  map_id uuid REFERENCES public.smax_rejeites_usuarios_map(id) ON DELETE SET NULL,
  smax_nome text NOT NULL,
  smax_nome_key text NOT NULL,
  ticket_numero text NOT NULL,
  ultima_atualizacao timestamptz NOT NULL,
  smax_url text NOT NULL,
  capturado_em timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT smax_rejeites_snapshot_unique_ticket UNIQUE (equipe_id, ticket_numero)
);
CREATE INDEX IF NOT EXISTS idx_smax_rejeites_snapshot_equipe_data
  ON public.smax_rejeites_snapshot(equipe_id, ultima_atualizacao DESC);
CREATE INDEX IF NOT EXISTS idx_smax_rejeites_snapshot_user_data
  ON public.smax_rejeites_snapshot(user_id, ultima_atualizacao DESC);
CREATE TABLE IF NOT EXISTS public.smax_rejeites_snapshot_meta (
  equipe_id uuid PRIMARY KEY REFERENCES public.equipes(id) ON DELETE CASCADE,
  pesquisado_em timestamptz NOT NULL,
  total_extraido integer NOT NULL DEFAULT 0,
  total_mapeado integer NOT NULL DEFAULT 0,
  total_ignorado integer NOT NULL DEFAULT 0,
  executado_por uuid REFERENCES public.users(id) ON DELETE SET NULL,
  avisos jsonb NOT NULL DEFAULT '[]'::jsonb,
  detalhes jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.smax_rejeites_usuarios_map ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.smax_rejeites_snapshot ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.smax_rejeites_snapshot_meta ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS smax_rejeites_usuarios_map_select_equipe ON public.smax_rejeites_usuarios_map;
CREATE POLICY smax_rejeites_usuarios_map_select_equipe
  ON public.smax_rejeites_usuarios_map FOR SELECT
  TO authenticated
  USING (
    equipe_id IN (SELECT u.equipe_id FROM public.users u WHERE u.id = auth.uid())
    OR public.tem_permissao('distribuidor.smax_rejeites_robo_dev')
  );
DROP POLICY IF EXISTS smax_rejeites_snapshot_select_equipe ON public.smax_rejeites_snapshot;
CREATE POLICY smax_rejeites_snapshot_select_equipe
  ON public.smax_rejeites_snapshot FOR SELECT
  TO authenticated
  USING (equipe_id IN (SELECT u.equipe_id FROM public.users u WHERE u.id = auth.uid()));
DROP POLICY IF EXISTS smax_rejeites_snapshot_delete_equipe ON public.smax_rejeites_snapshot;
CREATE POLICY smax_rejeites_snapshot_delete_equipe
  ON public.smax_rejeites_snapshot FOR DELETE
  TO authenticated
  USING (equipe_id IN (SELECT u.equipe_id FROM public.users u WHERE u.id = auth.uid()));
DROP POLICY IF EXISTS smax_rejeites_snapshot_meta_select_equipe ON public.smax_rejeites_snapshot_meta;
CREATE POLICY smax_rejeites_snapshot_meta_select_equipe
  ON public.smax_rejeites_snapshot_meta FOR SELECT
  TO authenticated
  USING (equipe_id IN (SELECT u.equipe_id FROM public.users u WHERE u.id = auth.uid()));
GRANT SELECT ON public.smax_rejeites_usuarios_map TO authenticated;
GRANT SELECT, DELETE ON public.smax_rejeites_snapshot TO authenticated;
GRANT SELECT ON public.smax_rejeites_snapshot_meta TO authenticated;
WITH nomes(smax_nome, smax_person_id) AS (
  VALUES
    ('DAVID DE SOUZA DICHIRICO PESTILLI', NULL),
    ('MAYARA MENDES CARDOSO BARBOSA', '41743936'),
    ('MIRIAM LUCIA DA SILVA', '83611'),
    ('INGRID MARIA DOS SANTOS COSTA', '4775910'),
    ('MARIA FERNANDA PERES PINTO SAMPAIO', '28428300'),
    ('NICHOLAS FERREIRA DE SOUZA MELO', '32285266'),
    ('RENATA APARECIDA FERREIRA BISPO', '93970'),
    ('FELIPY WILLIAM FERREIRA', '56684781'),
    ('GLAUCO BARROZO TOLENTINO', '51790382'),
    ('MATHEUS NICOLETTI NASCIMENTO BARBOSA', '51789848')
), resolvidos AS (
  SELECT
    '11111111-1111-1111-1111-111111111111'::uuid AS equipe_id,
    u.id AS user_id,
    n.smax_nome,
    public.smax_rejeites_normalizar_nome(n.smax_nome) AS smax_nome_key,
    n.smax_person_id
  FROM nomes n
  LEFT JOIN LATERAL (
    SELECT usuario.id
    FROM public.users usuario
    WHERE usuario.equipe_id = '11111111-1111-1111-1111-111111111111'::uuid
      AND public.smax_rejeites_normalizar_nome(usuario.nome) = public.smax_rejeites_normalizar_nome(n.smax_nome)
    ORDER BY usuario.ativo DESC NULLS LAST, usuario.created_at DESC NULLS LAST
    LIMIT 1
  ) u ON true
)
INSERT INTO public.smax_rejeites_usuarios_map (
  equipe_id,
  user_id,
  smax_nome,
  smax_nome_key,
  smax_person_id,
  ativo,
  updated_at
)
SELECT
  equipe_id,
  user_id,
  smax_nome,
  smax_nome_key,
  smax_person_id,
  true,
  now()
FROM resolvidos
ON CONFLICT (equipe_id, smax_nome_key) DO UPDATE
SET user_id = COALESCE(EXCLUDED.user_id, public.smax_rejeites_usuarios_map.user_id),
    smax_nome = EXCLUDED.smax_nome,
    smax_person_id = COALESCE(EXCLUDED.smax_person_id, public.smax_rejeites_usuarios_map.smax_person_id),
    ativo = true,
    updated_at = now();
CREATE OR REPLACE FUNCTION public.smax_rejeites_salvar_snapshot(
  p_equipe_id uuid,
  p_registros jsonb,
  p_pesquisado_em timestamptz DEFAULT now(),
  p_avisos jsonb DEFAULT '[]'::jsonb,
  p_detalhes jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_equipe_id uuid;
  v_total_extraido integer := 0;
  v_total_mapeado integer := 0;
  v_total_ignorado integer := 0;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario nao autenticado';
  END IF;

  IF p_equipe_id IS NULL THEN
    RAISE EXCEPTION 'Equipe obrigatoria';
  END IF;

  IF p_registros IS NULL OR jsonb_typeof(p_registros) <> 'array' THEN
    RAISE EXCEPTION 'Registros devem ser um array JSON';
  END IF;

  SELECT u.equipe_id
    INTO v_user_equipe_id
  FROM public.users u
  WHERE u.id = v_user_id;

  IF v_user_equipe_id IS DISTINCT FROM p_equipe_id THEN
    RAISE EXCEPTION 'Equipe informada nao corresponde a equipe do usuario';
  END IF;

  IF NOT public.tem_permissao('distribuidor.smax_rejeites_robo_dev') THEN
    RAISE EXCEPTION 'Usuario sem permissao para executar o robo SMAX Rejeites';
  END IF;

  DELETE FROM public.smax_rejeites_snapshot s
  WHERE s.equipe_id = p_equipe_id;

  WITH entrada_raw AS (
    SELECT item
    FROM jsonb_array_elements(p_registros) AS raw(item)
  ), entrada AS (
    SELECT DISTINCT ON (ticket_numero)
      regexp_replace(COALESCE(
        item->>'ticket_numero',
        item->>'ticketNumero',
        item->>'id',
        ''
      ), '[^0-9]', '', 'g') AS ticket_numero,
      NULLIF(trim(COALESCE(
        item->>'smax_nome',
        item->>'smaxNome',
        item->>'designado_especialista',
        item->>'designadoEspecialista',
        ''
      )), '') AS smax_nome_original,
      public.smax_rejeites_normalizar_nome(COALESCE(
        item->>'smax_nome',
        item->>'smaxNome',
        item->>'designado_especialista',
        item->>'designadoEspecialista',
        ''
      )) AS smax_nome_key,
      NULLIF(trim(COALESCE(item->>'smax_person_id', item->>'smaxPersonId', '')), '') AS smax_person_id,
      NULLIF(trim(COALESCE(item->>'ultima_atualizacao', item->>'ultimaAtualizacao', '')), '')::timestamptz AS ultima_atualizacao,
      NULLIF(trim(COALESCE(item->>'smax_url', item->>'smaxUrl', '')), '') AS smax_url
    FROM entrada_raw
    ORDER BY ticket_numero, NULLIF(trim(COALESCE(item->>'ultima_atualizacao', item->>'ultimaAtualizacao', '')), '')::timestamptz DESC NULLS LAST
  ), validos AS (
    SELECT
      ticket_numero,
      smax_nome_original,
      smax_nome_key,
      smax_person_id,
      ultima_atualizacao,
      COALESCE(smax_url, 'https://suporte.tjsp.jus.br/saw/Request/' || ticket_numero) AS smax_url
    FROM entrada
    WHERE ticket_numero <> ''
      AND smax_nome_key IS NOT NULL
      AND ultima_atualizacao IS NOT NULL
  ), mapeados AS (
    SELECT DISTINCT ON (v.ticket_numero)
      v.ticket_numero,
      v.ultima_atualizacao,
      v.smax_url,
      m.id AS map_id,
      m.user_id,
      m.smax_nome,
      m.smax_nome_key
    FROM validos v
    JOIN public.smax_rejeites_usuarios_map m
      ON m.equipe_id = p_equipe_id
     AND m.ativo = true
     AND (
       m.smax_nome_key = v.smax_nome_key
       OR (
         v.smax_person_id IS NOT NULL
         AND m.smax_person_id IS NOT NULL
         AND m.smax_person_id = v.smax_person_id
       )
     )
    ORDER BY v.ticket_numero, m.user_id NULLS LAST
  ), inseridos AS (
    INSERT INTO public.smax_rejeites_snapshot (
      equipe_id,
      user_id,
      map_id,
      smax_nome,
      smax_nome_key,
      ticket_numero,
      ultima_atualizacao,
      smax_url,
      capturado_em
    )
    SELECT
      p_equipe_id,
      m.user_id,
      m.map_id,
      m.smax_nome,
      m.smax_nome_key,
      m.ticket_numero,
      m.ultima_atualizacao,
      m.smax_url,
      COALESCE(p_pesquisado_em, now())
    FROM mapeados m
    ON CONFLICT (equipe_id, ticket_numero) DO UPDATE
    SET user_id = EXCLUDED.user_id,
        map_id = EXCLUDED.map_id,
        smax_nome = EXCLUDED.smax_nome,
        smax_nome_key = EXCLUDED.smax_nome_key,
        ultima_atualizacao = EXCLUDED.ultima_atualizacao,
        smax_url = EXCLUDED.smax_url,
        capturado_em = EXCLUDED.capturado_em
    RETURNING id
  )
  SELECT
    (SELECT count(*)::integer FROM validos),
    (SELECT count(*)::integer FROM inseridos)
    INTO v_total_extraido, v_total_mapeado;

  v_total_ignorado := GREATEST(COALESCE(v_total_extraido, 0) - COALESCE(v_total_mapeado, 0), 0);

  INSERT INTO public.smax_rejeites_snapshot_meta (
    equipe_id,
    pesquisado_em,
    total_extraido,
    total_mapeado,
    total_ignorado,
    executado_por,
    avisos,
    detalhes,
    updated_at
  )
  VALUES (
    p_equipe_id,
    COALESCE(p_pesquisado_em, now()),
    COALESCE(v_total_extraido, 0),
    COALESCE(v_total_mapeado, 0),
    COALESCE(v_total_ignorado, 0),
    v_user_id,
    COALESCE(p_avisos, '[]'::jsonb),
    COALESCE(p_detalhes, '{}'::jsonb),
    now()
  )
  ON CONFLICT (equipe_id) DO UPDATE
  SET pesquisado_em = EXCLUDED.pesquisado_em,
      total_extraido = EXCLUDED.total_extraido,
      total_mapeado = EXCLUDED.total_mapeado,
      total_ignorado = EXCLUDED.total_ignorado,
      executado_por = EXCLUDED.executado_por,
      avisos = EXCLUDED.avisos,
      detalhes = EXCLUDED.detalhes,
      updated_at = now();

  RETURN jsonb_build_object(
    'success', true,
    'equipe_id', p_equipe_id,
    'pesquisado_em', COALESCE(p_pesquisado_em, now()),
    'total_extraido', COALESCE(v_total_extraido, 0),
    'total_mapeado', COALESCE(v_total_mapeado, 0),
    'total_ignorado', COALESCE(v_total_ignorado, 0)
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.smax_rejeites_listar(p_equipe_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_equipe_id uuid;
  v_equipe_id uuid;
  v_meta jsonb := NULL;
  v_registros jsonb := '[]'::jsonb;
  v_por_usuario jsonb := '[]'::jsonb;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario nao autenticado';
  END IF;

  SELECT u.equipe_id
    INTO v_user_equipe_id
  FROM public.users u
  WHERE u.id = v_user_id;

  v_equipe_id := COALESCE(p_equipe_id, v_user_equipe_id);

  IF v_equipe_id IS NULL THEN
    RETURN jsonb_build_object('meta', NULL, 'registros', '[]'::jsonb, 'por_usuario', '[]'::jsonb);
  END IF;

  IF v_equipe_id IS DISTINCT FROM v_user_equipe_id THEN
    RAISE EXCEPTION 'Usuario sem permissao para consultar esta equipe';
  END IF;

  SELECT to_jsonb(m)
    INTO v_meta
  FROM public.smax_rejeites_snapshot_meta m
  WHERE m.equipe_id = v_equipe_id;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', s.id,
      'equipe_id', s.equipe_id,
      'user_id', s.user_id,
      'usuario_nome', COALESCE(u.nome, s.smax_nome),
      'usuario_email', u.email,
      'smax_nome', s.smax_nome,
      'ticket_numero', s.ticket_numero,
      'ultima_atualizacao', s.ultima_atualizacao,
      'smax_url', s.smax_url,
      'capturado_em', s.capturado_em
    )
    ORDER BY s.ultima_atualizacao DESC, s.ticket_numero
  ), '[]'::jsonb)
    INTO v_registros
  FROM public.smax_rejeites_snapshot s
  LEFT JOIN public.users u ON u.id = s.user_id
  WHERE s.equipe_id = v_equipe_id;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'user_id', grouped.user_id,
      'usuario_nome', grouped.usuario_nome,
      'smax_nome', grouped.smax_nome,
      'total', grouped.total,
      'ultima_atualizacao', grouped.ultima_atualizacao
    )
    ORDER BY grouped.total DESC, grouped.ultima_atualizacao DESC, grouped.usuario_nome
  ), '[]'::jsonb)
    INTO v_por_usuario
  FROM (
    SELECT
      s.user_id,
      COALESCE(u.nome, s.smax_nome) AS usuario_nome,
      s.smax_nome,
      count(*)::integer AS total,
      max(s.ultima_atualizacao) AS ultima_atualizacao
    FROM public.smax_rejeites_snapshot s
    LEFT JOIN public.users u ON u.id = s.user_id
    WHERE s.equipe_id = v_equipe_id
    GROUP BY s.user_id, COALESCE(u.nome, s.smax_nome), s.smax_nome
  ) grouped;

  RETURN jsonb_build_object(
    'meta', v_meta,
    'registros', v_registros,
    'por_usuario', v_por_usuario
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.smax_rejeites_excluir(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_equipe_id uuid;
  v_rejeite record;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario nao autenticado';
  END IF;

  IF p_id IS NULL THEN
    RAISE EXCEPTION 'Rejeite obrigatorio';
  END IF;

  SELECT u.equipe_id
    INTO v_user_equipe_id
  FROM public.users u
  WHERE u.id = v_user_id;

  SELECT s.id, s.equipe_id, s.ticket_numero
    INTO v_rejeite
  FROM public.smax_rejeites_snapshot s
  WHERE s.id = p_id;

  IF v_rejeite.id IS NULL THEN
    RAISE EXCEPTION 'Rejeite nao encontrado';
  END IF;

  IF v_rejeite.equipe_id IS DISTINCT FROM v_user_equipe_id THEN
    RAISE EXCEPTION 'Usuario sem permissao para excluir este rejeite';
  END IF;

  DELETE FROM public.smax_rejeites_snapshot s
  WHERE s.id = p_id;

  RETURN jsonb_build_object(
    'success', true,
    'id', v_rejeite.id,
    'ticket_numero', v_rejeite.ticket_numero
  );
END;
$$;
REVOKE ALL ON FUNCTION public.smax_rejeites_normalizar_nome(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.smax_rejeites_salvar_snapshot(uuid, jsonb, timestamptz, jsonb, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.smax_rejeites_listar(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.smax_rejeites_excluir(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.smax_rejeites_normalizar_nome(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.smax_rejeites_salvar_snapshot(uuid, jsonb, timestamptz, jsonb, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.smax_rejeites_listar(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.smax_rejeites_excluir(uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;
