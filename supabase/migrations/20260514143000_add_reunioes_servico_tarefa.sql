-- =====================================================================
-- Migration: adiciona reunioes internas e externas em Outros Servicos e Tarefas
-- Data: 2026-05-14
--
-- Objetivos:
--   1. Permitir registrar Outros Servicos dos tipos reuniao_interna e reuniao_externa.
--   2. Permitir criar/editar tarefas com esses tipos.
--   3. Concluir tarefa desses tipos criando servico equivalente.
--   4. Contabilizar os novos tipos como horas nas estatisticas completas.
-- =====================================================================

ALTER TABLE public.servicos DROP CONSTRAINT IF EXISTS servicos_tipo_check;
ALTER TABLE public.servicos ADD CONSTRAINT servicos_tipo_check CHECK (tipo IN (
  'email',
  'homologacao',
  'reuniao_interna',
  'reuniao_externa',
  'ouvidoria',
  'cpa',
  'chamado_smax',
  'criacao_script',
  'agendamento_visitas',
  'visitas_virtuais',
  'visitas_presenciais',
  'atendimento_teams',
  'atendimento_balcao',
  'dev_aplicacao',
  'resp_chamado_complexo',
  'analise_rejeites',
  'analise_chamados_antigos',
  'criacao_apresentacao',
  'elaboracao_relatorio',
  'configuracao_sistema',
  'lotacao_usuarios',
  'cadastro_radar',
  'cadastro_melhoria',
  'estudos_atualizacao'
));
COMMENT ON COLUMN public.servicos.tipo IS
  'Tipo: email, homologacao, reuniao_interna, reuniao_externa, ouvidoria, cpa, chamado_smax, criacao_script, agendamento_visitas, visitas_virtuais, visitas_presenciais, atendimento_teams, atendimento_balcao, dev_aplicacao, resp_chamado_complexo, analise_rejeites, analise_chamados_antigos, criacao_apresentacao, elaboracao_relatorio, configuracao_sistema, lotacao_usuarios, cadastro_radar, cadastro_melhoria, estudos_atualizacao';
CREATE OR REPLACE FUNCTION public.criar_servico(
  p_tipo          TEXT,
  p_quantidade    INTEGER,
  p_usuario_id    UUID,
  p_equipe_id     UUID,
  p_observacao    TEXT        DEFAULT NULL,
  p_data_execucao TIMESTAMPTZ DEFAULT NULL,
  p_descricao     TEXT        DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_servico_id   UUID;
  v_usuario_nome TEXT;
  v_data_exec    TIMESTAMPTZ;
BEGIN
  IF p_tipo NOT IN (
    'email','homologacao','reuniao_interna','reuniao_externa','ouvidoria','cpa',
    'chamado_smax','criacao_script','agendamento_visitas','visitas_virtuais',
    'visitas_presenciais','atendimento_teams','atendimento_balcao','dev_aplicacao',
    'resp_chamado_complexo','analise_rejeites','analise_chamados_antigos',
    'criacao_apresentacao','elaboracao_relatorio','configuracao_sistema',
    'lotacao_usuarios','cadastro_radar','cadastro_melhoria','estudos_atualizacao'
  ) THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Tipo de serviço inválido.');
  END IF;

  IF p_quantidade IS NULL OR p_quantidade < 1 THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Quantidade deve ser um número inteiro maior ou igual a 1');
  END IF;

  IF p_equipe_id IS NULL THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Equipe é obrigatória');
  END IF;

  v_data_exec := COALESCE(p_data_execucao, NOW());
  IF v_data_exec > NOW() + INTERVAL '1 minute' THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'A data de execução não pode ser no futuro');
  END IF;

  SELECT COALESCE(nome, email, 'Usuário') INTO v_usuario_nome
  FROM public.users
  WHERE id = p_usuario_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Usuário não encontrado');
  END IF;

  INSERT INTO public.servicos (tipo, quantidade, usuario_id, usuario_nome, equipe_id, observacao, data_execucao, descricao)
  VALUES (p_tipo, p_quantidade, p_usuario_id, v_usuario_nome, p_equipe_id, p_observacao, v_data_exec, p_descricao)
  RETURNING id INTO v_servico_id;

  RETURN jsonb_build_object(
    'sucesso', true,
    'servico_id', v_servico_id,
    'mensagem', 'Serviço registrado com sucesso'
  );

EXCEPTION
  WHEN check_violation THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Dados inválidos: verifique tipo e quantidade.');
  WHEN foreign_key_violation THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Usuário ou equipe não encontrados.');
  WHEN OTHERS THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Erro ao registrar serviço. Tente novamente.');
END;
$$;
CREATE OR REPLACE FUNCTION public.atualizar_servico(
  p_servico_id    UUID,
  p_tipo          TEXT        DEFAULT NULL,
  p_quantidade    INTEGER     DEFAULT NULL,
  p_observacao    TEXT        DEFAULT NULL,
  p_data_execucao TIMESTAMPTZ DEFAULT NULL,
  p_descricao     TEXT        DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id    UUID := auth.uid();
  v_user_role  TEXT;
  v_servico    RECORD;
  v_alteracoes JSONB := '{}';
BEGIN
  SELECT * INTO v_servico FROM public.servicos WHERE id = p_servico_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Serviço não encontrado');
  END IF;

  SELECT role INTO v_user_role FROM public.users WHERE id = v_user_id;

  IF v_servico.usuario_id != v_user_id AND COALESCE(v_user_role, 'user') != 'admin' THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Apenas o responsável ou administrador pode editar o serviço');
  END IF;

  IF p_tipo IS NOT NULL AND p_tipo != v_servico.tipo THEN
    IF p_tipo NOT IN (
      'email','homologacao','reuniao_interna','reuniao_externa','ouvidoria','cpa',
      'chamado_smax','criacao_script','agendamento_visitas','visitas_virtuais',
      'visitas_presenciais','atendimento_teams','atendimento_balcao','dev_aplicacao',
      'resp_chamado_complexo','analise_rejeites','analise_chamados_antigos',
      'criacao_apresentacao','elaboracao_relatorio','configuracao_sistema',
      'lotacao_usuarios','cadastro_radar','cadastro_melhoria','estudos_atualizacao'
    ) THEN
      RETURN jsonb_build_object('sucesso', false, 'erro', 'Tipo de serviço inválido');
    END IF;

    UPDATE public.servicos SET tipo = p_tipo, atualizado_em = NOW() WHERE id = p_servico_id;
    v_alteracoes := v_alteracoes || jsonb_build_object('tipo', true);
  END IF;

  IF p_quantidade IS NOT NULL AND p_quantidade != v_servico.quantidade THEN
    IF p_quantidade < 1 THEN
      RETURN jsonb_build_object('sucesso', false, 'erro', 'Quantidade deve ser um número inteiro maior ou igual a 1');
    END IF;

    UPDATE public.servicos SET quantidade = p_quantidade, atualizado_em = NOW() WHERE id = p_servico_id;
    v_alteracoes := v_alteracoes || jsonb_build_object('quantidade', true);
  END IF;

  IF p_observacao IS NOT NULL AND COALESCE(p_observacao, '') != COALESCE(v_servico.observacao, '') THEN
    UPDATE public.servicos SET observacao = p_observacao, atualizado_em = NOW() WHERE id = p_servico_id;
    v_alteracoes := v_alteracoes || jsonb_build_object('observacao', true);
  END IF;

  IF p_data_execucao IS NOT NULL AND p_data_execucao != v_servico.data_execucao THEN
    IF p_data_execucao > NOW() + INTERVAL '1 minute' THEN
      RETURN jsonb_build_object('sucesso', false, 'erro', 'A data de execução não pode ser no futuro');
    END IF;

    UPDATE public.servicos SET data_execucao = p_data_execucao, atualizado_em = NOW() WHERE id = p_servico_id;
    v_alteracoes := v_alteracoes || jsonb_build_object('data_execucao', true);
  END IF;

  IF p_descricao IS NOT NULL AND COALESCE(p_descricao, '') != COALESCE(v_servico.descricao, '') THEN
    UPDATE public.servicos SET descricao = p_descricao, atualizado_em = NOW() WHERE id = p_servico_id;
    v_alteracoes := v_alteracoes || jsonb_build_object('descricao', true);
  END IF;

  RETURN jsonb_build_object(
    'sucesso', true,
    'alteracoes', v_alteracoes,
    'mensagem', 'Serviço atualizado com sucesso'
  );

EXCEPTION
  WHEN check_violation THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Dados inválidos: verifique tipo e quantidade.');
  WHEN OTHERS THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Erro ao atualizar serviço. Tente novamente.');
END;
$$;
CREATE OR REPLACE FUNCTION public.obter_servicos_estatisticas_completas(
  p_equipe_id UUID,
  p_periodo   TEXT DEFAULT '30d'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_data_inicio TIMESTAMPTZ;
  v_resultado   JSONB;
BEGIN
  v_data_inicio := CASE p_periodo
    WHEN '24h' THEN NOW() - INTERVAL '24 hours'
    WHEN '48h' THEN NOW() - INTERVAL '48 hours'
    WHEN '72h' THEN NOW() - INTERVAL '72 hours'
    WHEN '7d'  THEN NOW() - INTERVAL '7 days'
    WHEN '30d' THEN NOW() - INTERVAL '30 days'
    WHEN 'all' THEN NULL
    ELSE             NOW() - INTERVAL '30 days'
  END;

  WITH filtrado AS (
    SELECT *
    FROM public.servicos
    WHERE equipe_id = p_equipe_id
      AND (v_data_inicio IS NULL OR data_execucao >= v_data_inicio)
  ),

  kpis AS (
    SELECT jsonb_build_object(
      'total_registros', COUNT(*),
      'total_horas', COALESCE(SUM(quantidade) FILTER (
        WHERE tipo IN ('homologacao','reuniao_interna','reuniao_externa','ouvidoria','cpa','dev_aplicacao',
                        'resp_chamado_complexo','analise_rejeites',
                        'analise_chamados_antigos','criacao_apresentacao',
                        'elaboracao_relatorio','agendamento_visitas',
                        'visitas_virtuais','visitas_presenciais','estudos_atualizacao')
      ), 0),
      'total_unidades', COALESCE(SUM(quantidade) FILTER (
        WHERE tipo IN ('email','chamado_smax','criacao_script',
                        'atendimento_teams','atendimento_balcao',
                        'configuracao_sistema','lotacao_usuarios',
                        'cadastro_radar','cadastro_melhoria')
      ), 0),
      'primeiro_registro', MIN(data_execucao),
      'ultimo_registro', MAX(data_execucao),
      'membros_distintos', COUNT(DISTINCT usuario_id)
    ) AS val FROM filtrado
  ),

  por_tipo AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'tipo', tipo,
        'total_qtd', total_qtd,
        'total_regs', total_regs
      )
      ORDER BY total_qtd DESC
    ) AS val
    FROM (
      SELECT tipo,
             SUM(quantidade)::INTEGER AS total_qtd,
             COUNT(*)::INTEGER AS total_regs
      FROM filtrado
      GROUP BY tipo
    ) sub
  ),

  por_membro AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'usuario_id', usuario_id,
        'usuario_nome', usuario_nome,
        'total_qtd', total_qtd,
        'total_regs', total_regs,
        'tipos_distintos', tipos_distintos
      )
      ORDER BY total_qtd DESC
    ) AS val
    FROM (
      SELECT usuario_id,
             usuario_nome,
             SUM(quantidade)::INTEGER AS total_qtd,
             COUNT(*)::INTEGER AS total_regs,
             COUNT(DISTINCT tipo)::INTEGER AS tipos_distintos
      FROM filtrado
      GROUP BY usuario_id, usuario_nome
    ) sub
  ),

  por_dia_semana AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'dia_semana', dia,
        'dia_label', CASE dia
          WHEN 0 THEN 'Dom' WHEN 1 THEN 'Seg' WHEN 2 THEN 'Ter'
          WHEN 3 THEN 'Qua' WHEN 4 THEN 'Qui' WHEN 5 THEN 'Sex'
          WHEN 6 THEN 'Sáb'
        END,
        'total_qtd', total_qtd,
        'total_regs', total_regs
      )
      ORDER BY dia
    ) AS val
    FROM (
      SELECT EXTRACT(DOW FROM data_execucao AT TIME ZONE 'America/Sao_Paulo')::INTEGER AS dia,
             SUM(quantidade)::INTEGER AS total_qtd,
             COUNT(*)::INTEGER AS total_regs
      FROM filtrado
      GROUP BY dia
    ) sub
  ),

  por_faixa_horaria AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'dia_semana', dia,
        'faixa', faixa,
        'faixa_label', CASE faixa
          WHEN 0 THEN 'Madrugada (0h-6h)'
          WHEN 1 THEN 'Manhã (6h-12h)'
          WHEN 2 THEN 'Tarde (12h-18h)'
          WHEN 3 THEN 'Noite (18h-24h)'
        END,
        'total_qtd', total_qtd
      )
      ORDER BY dia, faixa
    ) AS val
    FROM (
      SELECT
        EXTRACT(DOW FROM data_execucao AT TIME ZONE 'America/Sao_Paulo')::INTEGER AS dia,
        (EXTRACT(HOUR FROM data_execucao AT TIME ZONE 'America/Sao_Paulo')::INTEGER / 6) AS faixa,
        SUM(quantidade)::INTEGER AS total_qtd
      FROM filtrado
      GROUP BY dia, faixa
    ) sub
  ),

  serie_temporal AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'periodo', periodo_key,
        'tipo', tipo,
        'usuario_id', usuario_id,
        'usuario_nome', usuario_nome,
        'total_quantidade', total_quantidade
      )
      ORDER BY periodo_key, usuario_nome
    ) AS val
    FROM (
      SELECT
        CASE
          WHEN p_periodo IN ('24h', '48h', '72h') THEN
            TO_CHAR(data_execucao AT TIME ZONE 'America/Sao_Paulo', 'DD/MM HH24"h"')
          ELSE
            TO_CHAR(data_execucao AT TIME ZONE 'America/Sao_Paulo', 'DD/MM')
        END AS periodo_key,
        tipo,
        usuario_id,
        usuario_nome,
        SUM(quantidade)::INTEGER AS total_quantidade
      FROM filtrado
      GROUP BY periodo_key, tipo, usuario_id, usuario_nome
    ) sub
  ),

  volume_diario AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'data', dia,
        'total_qtd', total_qtd,
        'total_regs', total_regs
      )
      ORDER BY dia
    ) AS val
    FROM (
      SELECT
        TO_CHAR(data_execucao AT TIME ZONE 'America/Sao_Paulo', 'YYYY-MM-DD') AS dia,
        SUM(quantidade)::INTEGER AS total_qtd,
        COUNT(*)::INTEGER AS total_regs
      FROM filtrado
      GROUP BY dia
    ) sub
  )

  SELECT jsonb_build_object(
    'sucesso', true,
    'periodo', p_periodo,
    'kpis', (SELECT val FROM kpis),
    'por_tipo', COALESCE((SELECT val FROM por_tipo), '[]'::jsonb),
    'por_membro', COALESCE((SELECT val FROM por_membro), '[]'::jsonb),
    'por_dia_semana', COALESCE((SELECT val FROM por_dia_semana), '[]'::jsonb),
    'por_faixa_horaria', COALESCE((SELECT val FROM por_faixa_horaria), '[]'::jsonb),
    'serie_temporal', COALESCE((SELECT val FROM serie_temporal), '[]'::jsonb),
    'volume_diario', COALESCE((SELECT val FROM volume_diario), '[]'::jsonb)
  )
  INTO v_resultado;

  RETURN v_resultado;

EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'sucesso', false,
      'erro', 'Erro ao obter estatísticas completas de serviços: ' || SQLERRM
    );
END;
$$;
ALTER TABLE public.tarefas DROP CONSTRAINT IF EXISTS tarefas_tipo_check;
ALTER TABLE public.tarefas ADD CONSTRAINT tarefas_tipo_check CHECK (
  tipo IS NULL OR tipo IN (
    'ouvidoria',
    'cpa',
    'email',
    'aplicacao',
    'chamado_complexo',
    'homologacao',
    'reuniao_interna',
    'reuniao_externa',
    'rejeites',
    'chamados_antigos',
    'chamado_smax',
    'criacao_script',
    'agendamento_visitas',
    'visitas_virtuais',
    'visitas_presenciais',
    'atendimento_teams',
    'atendimento_balcao',
    'dev_aplicacao',
    'resp_chamado_complexo',
    'analise_rejeites',
    'analise_chamados_antigos',
    'criacao_apresentacao',
    'elaboracao_relatorio',
    'configuracao_sistema',
    'lotacao_usuarios',
    'cadastro_radar',
    'cadastro_melhoria',
    'estudos_atualizacao'
  )
);
CREATE OR REPLACE FUNCTION public.criar_tarefa(
  p_titulo TEXT,
  p_descricao TEXT DEFAULT NULL,
  p_equipe_id UUID DEFAULT NULL,
  p_tipo TEXT DEFAULT NULL,
  p_data_limite TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tarefa_id UUID;
  v_user_id UUID := auth.uid();
  v_tipo_final TEXT;
  v_tipos_permitidos CONSTANT TEXT[] := ARRAY[
    'ouvidoria', 'cpa', 'email', 'aplicacao', 'chamado_complexo',
    'homologacao', 'reuniao_interna', 'reuniao_externa', 'rejeites', 'chamados_antigos', 'chamado_smax',
    'criacao_script', 'agendamento_visitas', 'visitas_virtuais',
    'visitas_presenciais', 'atendimento_teams', 'atendimento_balcao',
    'dev_aplicacao', 'resp_chamado_complexo', 'analise_rejeites',
    'analise_chamados_antigos', 'criacao_apresentacao', 'elaboracao_relatorio',
    'configuracao_sistema', 'lotacao_usuarios', 'cadastro_radar',
    'cadastro_melhoria', 'estudos_atualizacao'
  ];
BEGIN
  IF p_titulo IS NULL OR TRIM(p_titulo) = '' THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Título é obrigatório');
  END IF;

  v_tipo_final := NULLIF(TRIM(COALESCE(p_tipo, '')), '');

  IF v_tipo_final IS NOT NULL AND NOT v_tipo_final = ANY(v_tipos_permitidos) THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Tipo inválido.');
  END IF;

  IF p_data_limite IS NOT NULL AND p_data_limite <= NOW() THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'O prazo de entrega deve ser uma data futura.');
  END IF;

  INSERT INTO public.tarefas (titulo, descricao, dono_id, equipe_id, criado_por, tipo, data_limite)
  VALUES (TRIM(p_titulo), p_descricao, v_user_id, p_equipe_id, v_user_id, v_tipo_final, p_data_limite)
  RETURNING id INTO v_tarefa_id;

  INSERT INTO public.tarefa_historico (tarefa_id, usuario_id, tipo_evento, dados)
  VALUES (
    v_tarefa_id,
    v_user_id,
    'criacao',
    jsonb_build_object(
      'titulo', p_titulo,
      'descricao', p_descricao,
      'tipo', v_tipo_final,
      'data_limite', p_data_limite
    )
  );

  RETURN jsonb_build_object(
    'sucesso', true,
    'tarefa_id', v_tarefa_id,
    'mensagem', 'Tarefa criada com sucesso'
  );

EXCEPTION
  WHEN check_violation THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Tipo de tarefa inválido.');
  WHEN OTHERS THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Erro ao criar tarefa. Tente novamente.');
END;
$$;
CREATE OR REPLACE FUNCTION public.atualizar_tarefa(
  p_tarefa_id UUID,
  p_titulo TEXT DEFAULT NULL,
  p_descricao TEXT DEFAULT NULL,
  p_tipo TEXT DEFAULT NULL,
  p_data_limite TIMESTAMPTZ DEFAULT NULL,
  p_remover_prazo BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_tarefa RECORD;
  v_tipos_permitidos CONSTANT TEXT[] := ARRAY[
    'ouvidoria', 'cpa', 'email', 'aplicacao', 'chamado_complexo',
    'homologacao', 'reuniao_interna', 'reuniao_externa', 'rejeites', 'chamados_antigos', 'chamado_smax',
    'criacao_script', 'agendamento_visitas', 'visitas_virtuais',
    'visitas_presenciais', 'atendimento_teams', 'atendimento_balcao',
    'dev_aplicacao', 'resp_chamado_complexo', 'analise_rejeites',
    'analise_chamados_antigos', 'criacao_apresentacao', 'elaboracao_relatorio',
    'configuracao_sistema', 'lotacao_usuarios', 'cadastro_radar',
    'cadastro_melhoria', 'estudos_atualizacao'
  ];
BEGIN
  SELECT * INTO v_tarefa
  FROM public.tarefas
  WHERE id = p_tarefa_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Tarefa nao encontrada');
  END IF;

  IF v_tarefa.dono_id != v_user_id AND NOT public.tem_permissao('tarefas.admin_acoes') THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Sem permissao para editar esta tarefa');
  END IF;

  IF p_tipo IS NOT NULL AND p_tipo <> '' AND NOT p_tipo = ANY(v_tipos_permitidos) THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Tipo de tarefa invalido.');
  END IF;

  UPDATE public.tarefas
  SET
    titulo = COALESCE(NULLIF(TRIM(p_titulo), ''), titulo),
    descricao = CASE WHEN p_descricao IS NOT NULL THEN p_descricao ELSE descricao END,
    tipo = CASE WHEN p_tipo IS NOT NULL THEN NULLIF(TRIM(p_tipo), '') ELSE tipo END,
    data_limite = CASE
      WHEN p_remover_prazo = TRUE THEN NULL
      WHEN p_data_limite IS NOT NULL THEN p_data_limite
      ELSE data_limite
    END,
    atualizado_em = NOW()
  WHERE id = p_tarefa_id;

  IF p_titulo IS NOT NULL AND TRIM(p_titulo) != '' AND TRIM(p_titulo) != v_tarefa.titulo THEN
    INSERT INTO public.tarefa_historico (tarefa_id, usuario_id, tipo_evento, dados)
    VALUES (p_tarefa_id, v_user_id, 'edicao_titulo',
      jsonb_build_object('titulo_anterior', v_tarefa.titulo, 'titulo_novo', TRIM(p_titulo)));
  END IF;

  IF p_descricao IS NOT NULL AND p_descricao IS DISTINCT FROM v_tarefa.descricao THEN
    INSERT INTO public.tarefa_historico (tarefa_id, usuario_id, tipo_evento, dados)
    VALUES (p_tarefa_id, v_user_id, 'edicao_descricao',
      jsonb_build_object('descricao_anterior', v_tarefa.descricao, 'descricao_nova', p_descricao));
  END IF;

  IF p_data_limite IS NOT NULL OR p_remover_prazo = TRUE THEN
    INSERT INTO public.tarefa_historico (tarefa_id, usuario_id, tipo_evento, dados)
    VALUES (p_tarefa_id, v_user_id, 'edicao_prazo',
      jsonb_build_object(
        'prazo_anterior', v_tarefa.data_limite,
        'prazo_novo', CASE WHEN p_remover_prazo THEN NULL ELSE p_data_limite END
      ));
  END IF;

  RETURN jsonb_build_object('sucesso', true, 'mensagem', 'Tarefa atualizada');

EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Erro ao atualizar tarefa.');
END;
$$;
CREATE OR REPLACE FUNCTION public.concluir_tarefa_com_servico(
  p_tarefa_id UUID,
  p_resumo TEXT,
  p_quantidade INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_tarefa RECORD;
  v_tipo_servico TEXT;
  v_usuario_nome TEXT;
  v_finalizador_nome TEXT;
  v_descricao_servico TEXT;
  v_servico_id UUID;
  v_estado_resultado JSONB;
  v_supervisores_notificados INTEGER := 0;
  v_resumo_normalizado TEXT;
BEGIN
  IF p_quantidade IS NULL OR p_quantidade < 1 THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Quantidade deve ser um número inteiro maior ou igual a 1');
  END IF;

  v_resumo_normalizado := NULLIF(TRIM(COALESCE(p_resumo, '')), '');

  SELECT COALESCE(nome, email, 'Usuário') INTO v_finalizador_nome
  FROM public.users
  WHERE id = v_user_id;

  IF v_finalizador_nome IS NULL THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Usuário autenticado não encontrado');
  END IF;

  SELECT * INTO v_tarefa
  FROM public.tarefas
  WHERE id = p_tarefa_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Tarefa não encontrada');
  END IF;

  IF v_tarefa.estado != 'em_andamento' THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Apenas tarefas em andamento podem ser concluídas por este fluxo');
  END IF;

  IF v_tarefa.tipo IS NULL THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Defina um tipo para a tarefa antes de concluir');
  END IF;

  IF v_tarefa.equipe_id IS NULL THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'A tarefa precisa estar vinculada a uma equipe para gerar serviço');
  END IF;

  v_tipo_servico := CASE
    WHEN v_tarefa.tipo = 'aplicacao' THEN 'dev_aplicacao'
    WHEN v_tarefa.tipo = 'chamado_complexo' THEN 'resp_chamado_complexo'
    WHEN v_tarefa.tipo = 'rejeites' THEN 'analise_rejeites'
    WHEN v_tarefa.tipo = 'chamados_antigos' THEN 'analise_chamados_antigos'
    WHEN v_tarefa.tipo IN (
      'email', 'homologacao', 'reuniao_interna', 'reuniao_externa', 'ouvidoria', 'cpa', 'chamado_smax',
      'criacao_script', 'agendamento_visitas', 'visitas_virtuais',
      'visitas_presenciais', 'atendimento_teams', 'atendimento_balcao',
      'dev_aplicacao', 'resp_chamado_complexo', 'analise_rejeites',
      'analise_chamados_antigos', 'criacao_apresentacao', 'elaboracao_relatorio',
      'configuracao_sistema', 'lotacao_usuarios', 'cadastro_radar',
      'cadastro_melhoria', 'estudos_atualizacao'
    ) THEN v_tarefa.tipo
    ELSE NULL
  END;

  IF v_tipo_servico IS NULL THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Tipo de tarefa sem serviço equivalente');
  END IF;

  SELECT COALESCE(nome, email, 'Usuário') INTO v_usuario_nome
  FROM public.users
  WHERE id = v_tarefa.dono_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Responsável da tarefa não encontrado');
  END IF;

  v_descricao_servico := concat_ws(
    ' - ',
    NULLIF(TRIM(COALESCE(v_tarefa.titulo, '')), ''),
    NULLIF(TRIM(COALESCE(v_tarefa.descricao, '')), '')
  );

  v_estado_resultado := public.alterar_estado_tarefa(p_tarefa_id, 'concluida', NULL, v_resumo_normalizado);

  IF COALESCE((v_estado_resultado->>'sucesso')::BOOLEAN, false) IS NOT TRUE THEN
    RETURN v_estado_resultado;
  END IF;

  INSERT INTO public.servicos (tipo, quantidade, usuario_id, usuario_nome, equipe_id, observacao, data_execucao, descricao)
  VALUES (v_tipo_servico, p_quantidade, v_tarefa.dono_id, v_usuario_nome, v_tarefa.equipe_id, NULL, NOW(), v_descricao_servico)
  RETURNING id INTO v_servico_id;

  WITH supervisores AS (
    SELECT DISTINCT u.id
    FROM public.users u
    WHERE u.ativo IS DISTINCT FROM FALSE
      AND u.id IS DISTINCT FROM v_user_id
      AND (
        (u.role = 'supervisor' AND u.equipe_id = v_tarefa.equipe_id)
        OR EXISTS (
          SELECT 1
          FROM public.usuario_funcoes_equipe ufe
          WHERE ufe.user_id = u.id
            AND ufe.equipe_id = v_tarefa.equipe_id
            AND ufe.funcao = 'supervisor'
            AND ufe.ativo = TRUE
        )
      )
  )
  INSERT INTO public.tarefa_notificacoes (tarefa_id, destinatario_id, remetente_id, tipo, dados)
  SELECT
    p_tarefa_id,
    supervisores.id,
    v_user_id,
    'tarefa_concluida',
    jsonb_build_object(
      'tarefa_titulo', v_tarefa.titulo,
      'remetente_nome', v_finalizador_nome,
      'estado_novo', 'concluida',
      'servico_id', v_servico_id,
      'tipo_servico', v_tipo_servico,
      'quantidade', p_quantidade
    )
  FROM supervisores;

  GET DIAGNOSTICS v_supervisores_notificados = ROW_COUNT;

  RETURN jsonb_build_object(
    'sucesso', true,
    'estado', 'concluida',
    'servico_id', v_servico_id,
    'tipo_servico', v_tipo_servico,
    'supervisores_notificados', v_supervisores_notificados,
    'mensagem', 'Tarefa concluída e serviço registrado com sucesso'
  );

EXCEPTION
  WHEN check_violation THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Dados inválidos: verifique tipo de serviço, notificação e quantidade.');
  WHEN OTHERS THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Erro ao concluir tarefa e registrar serviço: ' || SQLERRM);
END;
$$;
GRANT EXECUTE ON FUNCTION public.criar_servico(TEXT, INTEGER, UUID, UUID, TEXT, TIMESTAMPTZ, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.atualizar_servico(UUID, TEXT, INTEGER, TEXT, TIMESTAMPTZ, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obter_servicos_estatisticas_completas(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.criar_tarefa(TEXT, TEXT, UUID, TEXT, TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION public.atualizar_tarefa(UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.concluir_tarefa_com_servico(UUID, TEXT, INTEGER) TO authenticated;
