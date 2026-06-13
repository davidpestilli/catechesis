interface CommentEmailTemplateInput {
  contentLabel: string
  contentTitle: string
  contentUrl: string
  replyAuthorName: string
  replyAuthorKind: 'guest' | 'admin'
  replyBody: string
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

export function buildCommentNotificationSubject(input: CommentEmailTemplateInput) {
  return `Nova resposta em ${input.contentTitle} | ${input.siteName}`
}

export function buildCommentNotificationHtml(input: CommentEmailTemplateInput) {
  const senderBadge = input.replyAuthorKind === 'admin' ? 'Equipe administrativa' : 'Participante da conversa'

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
