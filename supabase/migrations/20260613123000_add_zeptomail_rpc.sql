-- ============================================================
-- RPCS DE ENVIO DE EMAIL VIA ZEPTOMAIL
-- Padrão replicado do projeto gerenciador-chamados
--
-- USO MANUAL NO SUPABASE SQL EDITOR:
-- 1. Antes de executar, substitua apenas o valor da variável
--    v_api_key em public.enviar_email_zeptomail.
-- 2. Troque:
--    '__CONFIGURE_ZEPTOMAIL_API_KEY__'
--    por:
--    'Zoho-enczapikey ...'
-- 3. Não altere mais nada no corpo da função.
-- ============================================================

create or replace function public.enviar_email_zeptomail(
  p_destinatario text,
  p_assunto text,
  p_corpo_html text,
  p_remetente_email text default 'noreply@catequetico.org',
  p_remetente_nome text default 'Catequético'
)
returns jsonb as $$
declare
  -- Cole aqui a chave HTTP API do ZeptoMail no formato:
  -- Zoho-enczapikey ...
  v_api_key text := '__CONFIGURE_ZEPTOMAIL_API_KEY__';
  v_body jsonb;
  v_request_id bigint;
begin
  if v_api_key = '__CONFIGURE_ZEPTOMAIL_API_KEY__' then
    return jsonb_build_object(
      'success', false,
      'error', 'API key do ZeptoMail nao configurada na migration enviar_email_zeptomail.'
    );
  end if;

  v_body := jsonb_build_object(
    'from', jsonb_build_object(
      'address', p_remetente_email,
      'name', p_remetente_nome
    ),
    'to', jsonb_build_array(
      jsonb_build_object(
        'email_address', jsonb_build_object(
          'address', p_destinatario,
          'name', p_destinatario
        )
      )
    ),
    'subject', p_assunto,
    'htmlbody', p_corpo_html
  );

  select into v_request_id net.http_post(
    url := 'https://api.zeptomail.com/v1.1/email',
    body := v_body,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Accept', 'application/json',
      'Authorization', v_api_key
    )
  );

  return jsonb_build_object(
    'success', true,
    'message', 'Email enfileirado para envio',
    'request_id', v_request_id,
    'destinatario', p_destinatario
  );
exception when others then
  return jsonb_build_object(
    'success', false,
    'error', SQLERRM,
    'sqlstate', SQLSTATE
  );
end;
$$ language plpgsql security definer;

comment on function public.enviar_email_zeptomail is
'Envia email via API ZeptoMail e retorna um JSON com status/request_id.';

grant execute on function public.enviar_email_zeptomail(text, text, text, text, text)
  to authenticated, service_role;

create or replace function public.enviar_emails_zeptomail_lote(
  p_destinatarios text[],
  p_assunto text,
  p_corpo_html text,
  p_remetente_email text default 'noreply@catequetico.org',
  p_remetente_nome text default 'Catequético'
)
returns jsonb as $$
declare
  v_destinatario text;
  v_resultado jsonb;
  v_resultados jsonb[] := array[]::jsonb[];
  v_enviados int := 0;
  v_erros int := 0;
begin
  foreach v_destinatario in array p_destinatarios
  loop
    v_resultado := public.enviar_email_zeptomail(
      p_destinatario := v_destinatario,
      p_assunto := p_assunto,
      p_corpo_html := p_corpo_html,
      p_remetente_email := p_remetente_email,
      p_remetente_nome := p_remetente_nome
    );

    v_resultados := array_append(
      v_resultados,
      jsonb_build_object(
        'email', v_destinatario,
        'success', coalesce((v_resultado->>'success')::boolean, false),
        'request_id', v_resultado->>'request_id',
        'error', v_resultado->>'error'
      )
    );

    if coalesce((v_resultado->>'success')::boolean, false) then
      v_enviados := v_enviados + 1;
    else
      v_erros := v_erros + 1;
    end if;

    perform pg_sleep(0.1);
  end loop;

  return jsonb_build_object(
    'success', v_erros = 0,
    'total', array_length(p_destinatarios, 1),
    'enviados', v_enviados,
    'erros', v_erros,
    'resultados', to_jsonb(v_resultados)
  );
exception when others then
  return jsonb_build_object(
    'success', false,
    'error', SQLERRM,
    'sqlstate', SQLSTATE,
    'enviados', v_enviados,
    'erros', v_erros
  );
end;
$$ language plpgsql security definer;

comment on function public.enviar_emails_zeptomail_lote is
'Envia emails em lote para múltiplos destinatários via ZeptoMail.';

grant execute on function public.enviar_emails_zeptomail_lote(text[], text, text, text, text)
  to authenticated, service_role;

create or replace function public.verificar_status_email(p_request_id bigint)
returns jsonb as $$
declare
  v_status int;
  v_content text;
  v_result jsonb;
begin
  select status_code, content::text into v_status, v_content
  from net._http_response
  where id = p_request_id;

  if v_status is null then
    return jsonb_build_object(
      'success', false,
      'status', 'pending',
      'message', 'Requisição ainda está sendo processada ou não encontrada'
    );
  end if;

  begin
    v_result := v_content::jsonb;
  exception when others then
    v_result := jsonb_build_object('raw_content', v_content);
  end;

  return jsonb_build_object(
    'success', v_status in (200, 201),
    'status_code', v_status,
    'response', v_result
  );
end;
$$ language plpgsql security definer;

grant execute on function public.verificar_status_email(bigint)
  to authenticated, service_role;
