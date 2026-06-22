import {
  SELF,
  createExecutionContext,
  env,
  waitOnExecutionContext,
} from 'cloudflare:test'
import { describe, expect, it } from 'vitest'
import {
  buildArticleCategorySubscriptionHtml,
  buildArticleCategorySubscriptionSubject,
  buildArticlePublicationHtml,
  buildArticlePublicationSubject,
  buildThreadSubscriptionHtml,
  buildThreadSubscriptionSubject,
} from '../src/comment-email'
import worker, { parseArticleStatus } from '../src'

describe('catechesis gateway worker', () => {
  it('responde /health no modo unitario', async () => {
    const request = new Request<unknown, IncomingRequestCfProperties>('http://example.com/health')
    const ctx = createExecutionContext()
    const response = await worker.fetch(request, env, ctx)

    await waitOnExecutionContext(ctx)

    expect(response.status).toBe(200)
    await expect(response.json()).resolves.toEqual({
      ok: true,
      service: 'catechesis-gateway',
    })
  })

  it('responde /config no modo integracao', async () => {
    const response = await SELF.fetch('http://example.com/config')
    const payload = (await response.json()) as {
      ok: boolean
      site: string
      storageBucket: string
      note: string
    }

    expect(response.status).toBe(200)
    expect(payload.ok).toBe(true)
    expect(payload.site).toBe('Catequético')
    expect(payload.storageBucket).toBe(env.SUPABASE_STORAGE_BUCKET)
  })

  it('rejeita token invalido de descadastro', async () => {
    const response = await SELF.fetch('http://example.com/comments/unsubscribe?token=invalido')
    const body = await response.text()

    expect(response.status).toBe(400)
    expect(body).toContain('Link inválido')
  })

  it('mantem 404 para rotas desconhecidas', async () => {
    const response = await SELF.fetch('http://example.com/rota-inexistente')

    expect(response.status).toBe(404)
    await expect(response.json()).resolves.toEqual({
      error: 'Rota não encontrada.',
    })
  })

  it('trata status de artigo ausente ou invalido de forma conservadora', () => {
    expect(parseArticleStatus('draft')).toBe('draft')
    expect(parseArticleStatus('published')).toBe('published')
    expect(parseArticleStatus(undefined)).toBeNull()
    expect(parseArticleStatus('publicado')).toBeNull()
  })

  it('monta o email de confirmacao de assinatura da thread', () => {
    const subject = buildThreadSubscriptionSubject({
      contentLabel: 'Artigo',
      contentTitle: 'Como organizar um encontro catequético',
      contentUrl: 'https://catequetico.org/#/artigos/como-organizar-um-encontro-catequetico?thread=abc',
      subscriberName: 'Maria',
      unsubscribeUrl: 'https://worker.example/comments/unsubscribe?token=abc',
      siteName: 'Catequético',
    })
    const html = buildThreadSubscriptionHtml({
      contentLabel: 'Artigo',
      contentTitle: 'Como organizar um encontro catequético',
      contentUrl: 'https://catequetico.org/#/artigos/como-organizar-um-encontro-catequetico?thread=abc',
      subscriberName: 'Maria',
      unsubscribeUrl: 'https://worker.example/comments/unsubscribe?token=abc',
      siteName: 'Catequético',
    })

    expect(subject).toContain('Você está acompanhando a conversa')
    expect(subject).toContain('Como organizar um encontro catequético')
    expect(html).toContain('Assinatura confirmada')
    expect(html).toContain('Maria')
    expect(html).toContain('Esta assinatura vale apenas para esta thread específica.')
    expect(html).toContain('https://worker.example/comments/unsubscribe?token=abc')
  })

  it('monta o email de confirmacao de assinatura da pasta de artigos', () => {
    const subject = buildArticleCategorySubscriptionSubject({
      categoryLabel: 'Vida dos Santos',
      categoryUrl: 'https://catequetico.org/#/artigos/pasta/vida-dos-santos',
      subscriberName: 'Maria',
      unsubscribeUrl: 'https://worker.example/article-subscriptions/unsubscribe?token=abc',
      siteName: 'Catequético',
    })
    const html = buildArticleCategorySubscriptionHtml({
      categoryLabel: 'Vida dos Santos',
      categoryUrl: 'https://catequetico.org/#/artigos/pasta/vida-dos-santos',
      subscriberName: 'Maria',
      unsubscribeUrl: 'https://worker.example/article-subscriptions/unsubscribe?token=abc',
      siteName: 'Catequético',
    })

    expect(subject).toContain('Inscrição confirmada em Vida dos Santos')
    expect(html).toContain('Inscrição confirmada')
    expect(html).toContain('Maria')
    expect(html).toContain('Vida dos Santos')
    expect(html).toContain('https://worker.example/article-subscriptions/unsubscribe?token=abc')
  })

  it('monta o email de nova publicacao de artigo com card', () => {
    const subject = buildArticlePublicationSubject({
      articleTitle: 'Santa Teresinha e a pequena via',
      articleExcerpt: 'Um resumo sobre a espiritualidade simples e profunda de Santa Teresinha.',
      articleUrl: 'https://catequetico.org/#/artigos/santa-teresinha-e-a-pequena-via',
      categoryLabel: 'Vida dos Santos',
      categoryUrl: 'https://catequetico.org/#/artigos/pasta/vida-dos-santos',
      cardImageUrl: 'https://example.com/card.jpg',
      publishedAtLabel: '15/06/2026',
      featured: true,
      tags: ['santos', 'espiritualidade'],
      unsubscribeUrl: 'https://worker.example/article-subscriptions/unsubscribe?token=abc',
      siteName: 'Catequético',
    })
    const html = buildArticlePublicationHtml({
      articleTitle: 'Santa Teresinha e a pequena via',
      articleExcerpt: 'Um resumo sobre a espiritualidade simples e profunda de Santa Teresinha.',
      articleUrl: 'https://catequetico.org/#/artigos/santa-teresinha-e-a-pequena-via',
      categoryLabel: 'Vida dos Santos',
      categoryUrl: 'https://catequetico.org/#/artigos/pasta/vida-dos-santos',
      cardImageUrl: 'https://example.com/card.jpg',
      publishedAtLabel: '15/06/2026',
      featured: true,
      tags: ['santos', 'espiritualidade'],
      unsubscribeUrl: 'https://worker.example/article-subscriptions/unsubscribe?token=abc',
      siteName: 'Catequético',
    })

    expect(subject).toContain('Novo artigo em Vida dos Santos')
    expect(subject).toContain('Santa Teresinha e a pequena via')
    expect(html).toContain('Novo artigo publicado')
    expect(html).toContain('Santa Teresinha e a pequena via')
    expect(html).toContain('https://example.com/card.jpg')
    expect(html).toContain('Destaque')
    expect(html).toContain('https://worker.example/article-subscriptions/unsubscribe?token=abc')
  })
})
