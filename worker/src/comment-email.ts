interface CommentNotificationEmailTemplateInput {
  contentLabel: string
  contentTitle: string
  contentUrl: string
  replyAuthorName: string
  replyAuthorKind: 'guest' | 'admin' | 'catequista'
  replyBody: string
  unsubscribeUrl: string
  siteName: string
}

interface ThreadSubscriptionEmailTemplateInput {
  contentLabel: string
  contentTitle: string
  contentUrl: string
  subscriberName: string
  unsubscribeUrl: string
  siteName: string
}

interface UserCredentialsEmailTemplateInput {
  loginUrl: string
  profileLabel: string
  recipientEmail: string
  recipientPassword: string
  siteName: string
}

interface ArticleCategorySubscriptionEmailTemplateInput {
  categoryLabel: string
  categoryUrl: string
  subscriberName: string
  unsubscribeUrl: string
  siteName: string
}

interface ArticlePublicationEmailTemplateInput {
  articleTitle: string
  articleExcerpt: string
  articleUrl: string
  categoryLabel: string
  categoryUrl: string
  cardImageUrl?: string
  publishedAtLabel: string
  featured: boolean
  tags: string[]
  unsubscribeUrl: string
  siteName: string
}

function escapeHtml(value: string) {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;')
}

function formatParagraphs(value: string) {
  return escapeHtml(value)
    .split(/\n{2,}/)
    .map((paragraph) => `<p style="margin: 0 0 12px; color: #334155; line-height: 1.75;">${paragraph.replaceAll('\n', '<br>')}</p>`)
    .join('')
}

function renderBadge(label: string, tone: 'default' | 'muted' = 'default') {
  const styles =
    tone === 'muted'
      ? 'background:#e7e5e4;color:#57534e;'
      : 'background:#e6efe9;color:#315c43;'

  return `<span style="display:inline-block;${styles}padding:6px 12px;border-radius:999px;font-size:12px;font-weight:700;margin:0 8px 8px 0;">${escapeHtml(label)}</span>`
}

export function buildCommentNotificationSubject(input: CommentNotificationEmailTemplateInput) {
  return `Nova resposta em ${input.contentTitle} | ${input.siteName}`
}

export function buildCommentNotificationHtml(input: CommentNotificationEmailTemplateInput) {
  const senderBadge = input.replyAuthorKind === 'guest' ? 'Participante da conversa' : 'Catequista'

  return `
    <!DOCTYPE html>
    <html lang="pt-BR">
      <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <title>${escapeHtml(input.siteName)}</title>
      </head>
      <body style="margin:0;padding:32px 16px;background:#f5f1e8;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Arial,sans-serif;color:#1c1917;">
        <div style="max-width:640px;margin:0 auto;background:#ffffff;border-radius:24px;overflow:hidden;box-shadow:0 18px 45px rgba(28,25,23,0.12);">
          <div style="background:linear-gradient(135deg,#315c43 0%,#1f3f2f 100%);padding:32px 28px;text-align:center;">
            <div style="width:58px;height:58px;margin:0 auto 16px;border-radius:50%;background:rgba(255,255,255,0.14);display:flex;align-items:center;justify-content:center;font-size:28px;">💬</div>
            <div style="color:#f8fafc;font-size:24px;font-weight:700;margin-bottom:8px;">Nova resposta na conversa</div>
            <div style="color:rgba(248,250,252,0.86);font-size:14px;">Alguém comentou no ${escapeHtml(input.contentLabel.toLowerCase())} que você acompanha.</div>
          </div>

          <div style="padding:28px;">
            <div style="background:#f7f4ee;border:1px solid #e7dfd1;border-radius:18px;padding:18px 20px;margin-bottom:20px;">
              <div style="font-size:11px;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:#6b7280;margin-bottom:6px;">Conteúdo</div>
              <div style="font-size:20px;font-weight:700;color:#1f2937;">${escapeHtml(input.contentTitle)}</div>
              <div style="margin-top:10px;display:inline-block;background:#e6efe9;color:#315c43;padding:6px 12px;border-radius:999px;font-size:12px;font-weight:700;">
                ${escapeHtml(input.contentLabel)}
              </div>
            </div>

            <div style="display:flex;align-items:flex-start;gap:14px;margin-bottom:18px;">
              <div style="width:44px;height:44px;border-radius:16px;background:#eff6ff;display:flex;align-items:center;justify-content:center;font-size:20px;">✍️</div>
              <div>
                <div style="font-size:16px;font-weight:700;color:#111827;">${escapeHtml(input.replyAuthorName)}</div>
                <div style="font-size:12px;color:#6b7280;text-transform:uppercase;letter-spacing:0.08em;">${escapeHtml(senderBadge)}</div>
              </div>
            </div>

            <div style="border:1px solid #d6e2da;background:#fbfdfc;border-radius:20px;padding:20px 20px 8px;margin-bottom:24px;">
              <div style="font-size:11px;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:#315c43;margin-bottom:12px;">Mensagem publicada</div>
              ${formatParagraphs(input.replyBody)}
            </div>

            <div style="text-align:center;margin-bottom:20px;">
              <a href="${escapeHtml(input.contentUrl)}" style="display:inline-block;background:#315c43;color:#ffffff;text-decoration:none;padding:14px 24px;border-radius:999px;font-weight:700;font-size:15px;">
                Abrir conversa no ${escapeHtml(input.siteName)}
              </a>
            </div>

            <div style="background:#fff7ed;border:1px solid #fed7aa;border-radius:16px;padding:14px 16px;font-size:13px;color:#9a3412;line-height:1.6;">
              Você recebeu este email porque marcou a opção para acompanhar esta conversa.
            </div>
          </div>

          <div style="padding:22px 28px;background:#fafaf9;border-top:1px solid #ece7de;text-align:center;">
            <div style="font-size:13px;font-weight:700;color:#44403c;margin-bottom:8px;">${escapeHtml(input.siteName)}</div>
            <div style="font-size:12px;color:#78716c;line-height:1.6;margin-bottom:12px;">Este email foi enviado automaticamente para avisar sobre novas respostas na thread que você acompanha.</div>
            <a href="${escapeHtml(input.unsubscribeUrl)}" style="font-size:12px;color:#57534e;text-decoration:underline;">Parar de receber emails desta conversa</a>
          </div>
        </div>
      </body>
    </html>
  `
}

export function buildThreadSubscriptionSubject(input: ThreadSubscriptionEmailTemplateInput) {
  return `Voce esta acompanhando a conversa em ${input.contentTitle} | ${input.siteName}`
}

export function buildThreadSubscriptionHtml(input: ThreadSubscriptionEmailTemplateInput) {
  const subscriberName = input.subscriberName.trim() || 'Participante'

  return `
    <!DOCTYPE html>
    <html lang="pt-BR">
      <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <title>${escapeHtml(input.siteName)}</title>
      </head>
      <body style="margin:0;padding:32px 16px;background:#f5f1e8;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Arial,sans-serif;color:#1c1917;">
        <div style="max-width:640px;margin:0 auto;background:#ffffff;border-radius:24px;overflow:hidden;box-shadow:0 18px 45px rgba(28,25,23,0.12);">
          <div style="background:linear-gradient(135deg,#315c43 0%,#1f3f2f 100%);padding:32px 28px;text-align:center;">
            <div style="width:58px;height:58px;margin:0 auto 16px;border-radius:50%;background:rgba(255,255,255,0.14);display:flex;align-items:center;justify-content:center;font-size:28px;">🔔</div>
            <div style="color:#f8fafc;font-size:24px;font-weight:700;margin-bottom:8px;">Assinatura confirmada</div>
            <div style="color:rgba(248,250,252,0.86);font-size:14px;">Voce passara a receber avisos sobre novas respostas nesta thread especifica.</div>
          </div>

          <div style="padding:28px;">
            <div style="font-size:16px;color:#334155;line-height:1.75;margin-bottom:20px;">
              Ola, <strong>${escapeHtml(subscriberName)}</strong>. Sua assinatura foi registrada com sucesso.
            </div>

            <div style="background:#f7f4ee;border:1px solid #e7dfd1;border-radius:18px;padding:18px 20px;margin-bottom:20px;">
              <div style="font-size:11px;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:#6b7280;margin-bottom:6px;">Conversa acompanhada</div>
              <div style="font-size:20px;font-weight:700;color:#1f2937;">${escapeHtml(input.contentTitle)}</div>
              <div style="margin-top:10px;display:inline-block;background:#e6efe9;color:#315c43;padding:6px 12px;border-radius:999px;font-size:12px;font-weight:700;">
                ${escapeHtml(input.contentLabel)}
              </div>
            </div>

            <div style="border:1px solid #d6e2da;background:#fbfdfc;border-radius:20px;padding:18px 20px;margin-bottom:24px;">
              <div style="font-size:11px;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:#315c43;margin-bottom:12px;">O que acontece agora</div>
              <p style="margin:0 0 12px;color:#334155;line-height:1.75;">Sempre que alguem publicar uma nova resposta nesta thread, enviaremos um aviso para este email.</p>
              <p style="margin:0;color:#334155;line-height:1.75;">O descadastro continua disponivel em todos os emails enviados para essa conversa.</p>
            </div>

            <div style="text-align:center;margin-bottom:20px;">
              <a href="${escapeHtml(input.contentUrl)}" style="display:inline-block;background:#315c43;color:#ffffff;text-decoration:none;padding:14px 24px;border-radius:999px;font-weight:700;font-size:15px;">
                Abrir conversa no ${escapeHtml(input.siteName)}
              </a>
            </div>

            <div style="background:#fff7ed;border:1px solid #fed7aa;border-radius:16px;padding:14px 16px;font-size:13px;color:#9a3412;line-height:1.6;">
              Esta assinatura vale apenas para esta thread especifica.
            </div>
          </div>

          <div style="padding:22px 28px;background:#fafaf9;border-top:1px solid #ece7de;text-align:center;">
            <div style="font-size:13px;font-weight:700;color:#44403c;margin-bottom:8px;">${escapeHtml(input.siteName)}</div>
            <div style="font-size:12px;color:#78716c;line-height:1.6;margin-bottom:12px;">Voce pode parar de receber avisos desta conversa a qualquer momento.</div>
            <a href="${escapeHtml(input.unsubscribeUrl)}" style="font-size:12px;color:#57534e;text-decoration:underline;">Parar de receber emails desta conversa</a>
          </div>
        </div>
      </body>
    </html>
  `
}

export function buildUserCredentialsSubject(input: UserCredentialsEmailTemplateInput) {
  return `Seu acesso ao ${input.siteName} foi criado`
}

export function buildUserCredentialsHtml(input: UserCredentialsEmailTemplateInput) {
  return `
    <!DOCTYPE html>
    <html lang="pt-BR">
      <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <title>${escapeHtml(input.siteName)}</title>
      </head>
      <body style="margin:0;padding:32px 16px;background:#f5f1e8;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Arial,sans-serif;color:#1c1917;">
        <div style="max-width:640px;margin:0 auto;background:#ffffff;border-radius:24px;overflow:hidden;box-shadow:0 18px 45px rgba(28,25,23,0.12);">
          <div style="background:linear-gradient(135deg,#315c43 0%,#1f3f2f 100%);padding:32px 28px;text-align:center;">
            <div style="width:58px;height:58px;margin:0 auto 16px;border-radius:50%;background:rgba(255,255,255,0.14);display:flex;align-items:center;justify-content:center;font-size:28px;">🔐</div>
            <div style="color:#f8fafc;font-size:24px;font-weight:700;margin-bottom:8px;">Acesso criado com sucesso</div>
            <div style="color:rgba(248,250,252,0.86);font-size:14px;">Seu perfil no ${escapeHtml(input.siteName)} ja esta ativo.</div>
          </div>

          <div style="padding:28px;">
            <p style="margin:0 0 16px;color:#334155;line-height:1.75;">
              Um administrador cadastrou seu acesso com o perfil <strong>${escapeHtml(input.profileLabel)}</strong>.
            </p>

            <div style="background:#f7f4ee;border:1px solid #e7dfd1;border-radius:18px;padding:18px 20px;margin-bottom:20px;">
              <div style="font-size:11px;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:#6b7280;margin-bottom:10px;">Credenciais iniciais</div>
              <p style="margin:0 0 8px;color:#111827;"><strong>Email:</strong> ${escapeHtml(input.recipientEmail)}</p>
              <p style="margin:0;color:#111827;"><strong>Senha:</strong> ${escapeHtml(input.recipientPassword)}</p>
            </div>

            <div style="background:#fbfdfc;border:1px solid #d6e2da;border-radius:20px;padding:18px 20px;margin-bottom:24px;">
              <div style="font-size:11px;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:#315c43;margin-bottom:12px;">Recomendacao</div>
              <p style="margin:0;color:#334155;line-height:1.75;">
                Entre no sistema e altere a senha assim que possivel para manter sua conta protegida.
              </p>
            </div>

            <div style="text-align:center;margin-bottom:20px;">
              <a href="${escapeHtml(input.loginUrl)}" style="display:inline-block;background:#315c43;color:#ffffff;text-decoration:none;padding:14px 24px;border-radius:999px;font-weight:700;font-size:15px;">
                Abrir tela de login
              </a>
            </div>
          </div>

          <div style="padding:22px 28px;background:#fafaf9;border-top:1px solid #ece7de;text-align:center;">
            <div style="font-size:13px;font-weight:700;color:#44403c;margin-bottom:8px;">${escapeHtml(input.siteName)}</div>
            <div style="font-size:12px;color:#78716c;line-height:1.6;">Este email foi enviado automaticamente no momento da criacao do usuario.</div>
          </div>
        </div>
      </body>
    </html>
  `
}

export function buildArticleCategorySubscriptionSubject(
  input: ArticleCategorySubscriptionEmailTemplateInput,
) {
  return `Inscricao confirmada em ${input.categoryLabel} | ${input.siteName}`
}

export function buildArticleCategorySubscriptionHtml(
  input: ArticleCategorySubscriptionEmailTemplateInput,
) {
  const subscriberName = input.subscriberName.trim() || 'Participante'

  return `
    <!DOCTYPE html>
    <html lang="pt-BR">
      <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <title>${escapeHtml(input.siteName)}</title>
      </head>
      <body style="margin:0;padding:32px 16px;background:#f5f1e8;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Arial,sans-serif;color:#1c1917;">
        <div style="max-width:640px;margin:0 auto;background:#ffffff;border-radius:24px;overflow:hidden;box-shadow:0 18px 45px rgba(28,25,23,0.12);">
          <div style="background:linear-gradient(135deg,#315c43 0%,#1f3f2f 100%);padding:32px 28px;text-align:center;">
            <div style="width:58px;height:58px;margin:0 auto 16px;border-radius:50%;background:rgba(255,255,255,0.14);display:flex;align-items:center;justify-content:center;font-size:28px;">🔔</div>
            <div style="color:#f8fafc;font-size:24px;font-weight:700;margin-bottom:8px;">Inscricao confirmada</div>
            <div style="color:rgba(248,250,252,0.86);font-size:14px;">Voce recebera avisos sempre que um novo artigo for publicado nesta pasta.</div>
          </div>

          <div style="padding:28px;">
            <div style="font-size:16px;color:#334155;line-height:1.75;margin-bottom:20px;">
              Ola, <strong>${escapeHtml(subscriberName)}</strong>. Sua inscricao foi registrada com sucesso.
            </div>

            <div style="background:#f7f4ee;border:1px solid #e7dfd1;border-radius:18px;padding:18px 20px;margin-bottom:20px;">
              <div style="font-size:11px;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:#6b7280;margin-bottom:6px;">Pasta acompanhada</div>
              <div style="font-size:20px;font-weight:700;color:#1f2937;">${escapeHtml(input.categoryLabel)}</div>
              <div style="margin-top:10px;">${renderBadge('Novos artigos por email')}</div>
            </div>

            <div style="border:1px solid #d6e2da;background:#fbfdfc;border-radius:20px;padding:18px 20px;margin-bottom:24px;">
              <div style="font-size:11px;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:#315c43;margin-bottom:12px;">O que acontece agora</div>
              <p style="margin:0 0 12px;color:#334155;line-height:1.75;">Sempre que um novo artigo for criado em ${escapeHtml(input.categoryLabel)}, enviaremos um aviso para este email.</p>
              <p style="margin:0;color:#334155;line-height:1.75;">Cada aviso trara as informacoes principais da publicacao e um atalho para abrir o artigo no ${escapeHtml(input.siteName)}.</p>
            </div>

            <div style="text-align:center;margin-bottom:20px;">
              <a href="${escapeHtml(input.categoryUrl)}" style="display:inline-block;background:#315c43;color:#ffffff;text-decoration:none;padding:14px 24px;border-radius:999px;font-weight:700;font-size:15px;">
                Abrir ${escapeHtml(input.categoryLabel)}
              </a>
            </div>
          </div>

          <div style="padding:22px 28px;background:#fafaf9;border-top:1px solid #ece7de;text-align:center;">
            <div style="font-size:13px;font-weight:700;color:#44403c;margin-bottom:8px;">${escapeHtml(input.siteName)}</div>
            <div style="font-size:12px;color:#78716c;line-height:1.6;margin-bottom:12px;">Voce pode cancelar essa inscricao a qualquer momento.</div>
            <a href="${escapeHtml(input.unsubscribeUrl)}" style="font-size:12px;color:#57534e;text-decoration:underline;">Parar de receber avisos desta pasta</a>
          </div>
        </div>
      </body>
    </html>
  `
}

export function buildArticlePublicationSubject(input: ArticlePublicationEmailTemplateInput) {
  return `Novo artigo em ${input.categoryLabel}: ${input.articleTitle} | ${input.siteName}`
}

export function buildArticlePublicationHtml(input: ArticlePublicationEmailTemplateInput) {
  const tagsMarkup = [
    input.featured ? renderBadge('Destaque') : '',
    ...input.tags.slice(0, 2).map((tag) => renderBadge(tag, 'muted')),
  ]
    .filter(Boolean)
    .join('')

  return `
    <!DOCTYPE html>
    <html lang="pt-BR">
      <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <title>${escapeHtml(input.siteName)}</title>
      </head>
      <body style="margin:0;padding:32px 16px;background:#f5f1e8;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Arial,sans-serif;color:#1c1917;">
        <div style="max-width:640px;margin:0 auto;background:#ffffff;border-radius:24px;overflow:hidden;box-shadow:0 18px 45px rgba(28,25,23,0.12);">
          <div style="background:linear-gradient(135deg,#315c43 0%,#1f3f2f 100%);padding:32px 28px;text-align:center;">
            <div style="width:58px;height:58px;margin:0 auto 16px;border-radius:50%;background:rgba(255,255,255,0.14);display:flex;align-items:center;justify-content:center;font-size:28px;">📰</div>
            <div style="color:#f8fafc;font-size:24px;font-weight:700;margin-bottom:8px;">Novo artigo publicado</div>
            <div style="color:rgba(248,250,252,0.86);font-size:14px;">Um novo conteudo acabou de entrar em ${escapeHtml(input.categoryLabel)}.</div>
          </div>

          <div style="padding:28px;">
            <div style="background:#f7f4ee;border:1px solid #e7dfd1;border-radius:18px;padding:18px 20px;margin-bottom:20px;">
              <div style="font-size:11px;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:#6b7280;margin-bottom:6px;">Pasta</div>
              <div style="font-size:20px;font-weight:700;color:#1f2937;">${escapeHtml(input.categoryLabel)}</div>
            </div>

            <div style="border:1px solid #e7dfd1;border-radius:24px;overflow:hidden;background:#ffffff;margin-bottom:24px;">
              ${
                input.cardImageUrl
                  ? `<img src="${escapeHtml(input.cardImageUrl)}" alt="${escapeHtml(input.articleTitle)}" style="display:block;width:100%;height:224px;object-fit:cover;" />`
                  : ''
              }
              <div style="padding:22px 20px;">
                <div style="margin-bottom:14px;">${tagsMarkup}</div>
                <div style="font-size:24px;font-weight:700;color:#111827;line-height:1.35;margin-bottom:12px;">${escapeHtml(input.articleTitle)}</div>
                <div style="font-size:15px;color:#57534e;line-height:1.75;margin-bottom:18px;">${escapeHtml(input.articleExcerpt)}</div>
                <div style="display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap;font-size:13px;color:#78716c;">
                  <span>${escapeHtml(input.publishedAtLabel)}</span>
                  <a href="${escapeHtml(input.articleUrl)}" style="color:#111827;font-weight:700;text-decoration:none;">Ler artigo</a>
                </div>
              </div>
            </div>

            <div style="text-align:center;margin-bottom:20px;">
              <a href="${escapeHtml(input.articleUrl)}" style="display:inline-block;background:#315c43;color:#ffffff;text-decoration:none;padding:14px 24px;border-radius:999px;font-weight:700;font-size:15px;">
                Abrir artigo no ${escapeHtml(input.siteName)}
              </a>
            </div>

            <div style="background:#fbfdfc;border:1px solid #d6e2da;border-radius:20px;padding:18px 20px;margin-bottom:20px;">
              <div style="font-size:11px;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:#315c43;margin-bottom:12px;">Por que voce recebeu este email</div>
              <p style="margin:0;color:#334155;line-height:1.75;">Este aviso foi enviado porque seu email esta inscrito para receber notificacoes de novas publicacoes em ${escapeHtml(input.categoryLabel)}.</p>
            </div>
          </div>

          <div style="padding:22px 28px;background:#fafaf9;border-top:1px solid #ece7de;text-align:center;">
            <div style="font-size:13px;font-weight:700;color:#44403c;margin-bottom:8px;">${escapeHtml(input.siteName)}</div>
            <div style="font-size:12px;color:#78716c;line-height:1.6;margin-bottom:12px;">Voce pode continuar explorando esta pasta ou cancelar a inscricao quando quiser.</div>
            <div style="margin-bottom:10px;">
              <a href="${escapeHtml(input.categoryUrl)}" style="font-size:12px;color:#57534e;text-decoration:underline;">Ver todos os artigos de ${escapeHtml(input.categoryLabel)}</a>
            </div>
            <a href="${escapeHtml(input.unsubscribeUrl)}" style="font-size:12px;color:#57534e;text-decoration:underline;">Parar de receber avisos desta pasta</a>
          </div>
        </div>
      </body>
    </html>
  `
}
