import {
  SELF,
  createExecutionContext,
  env,
  waitOnExecutionContext,
} from 'cloudflare:test'
import { describe, expect, it } from 'vitest'
import worker from '../src'

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
    expect(body).toContain('Link invalido')
  })

  it('mantem 404 para rotas desconhecidas', async () => {
    const response = await SELF.fetch('http://example.com/rota-inexistente')

    expect(response.status).toBe(404)
    await expect(response.json()).resolves.toEqual({
      error: 'Rota nao encontrada.',
    })
  })
})
