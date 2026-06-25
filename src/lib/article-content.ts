const INLINE_MEDIA_PATTERN = /data:(image|video)\/[a-z0-9.+-]+;base64,/gi

export function countInlineMediaEmbeds(contentHtml: string) {
  return (contentHtml.match(INLINE_MEDIA_PATTERN) ?? []).length
}

export function hasInlineMediaEmbeds(contentHtml: string) {
  return INLINE_MEDIA_PATTERN.test(contentHtml)
}

export function getInlineMediaEmbedError(contentHtml: string) {
  const count = countInlineMediaEmbeds(contentHtml)

  if (count === 0) {
    return null
  }

  return count === 1
    ? 'O artigo ainda contém 1 arquivo embutido em base64. Reenvie a mídia pelo editor para salvar no storage antes de publicar.'
    : `O artigo ainda contém ${count} arquivos embutidos em base64. Reenvie as mídias pelo editor para salvar no storage antes de publicar.`
}
