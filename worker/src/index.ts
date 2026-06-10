interface GatewayEnv {
  ALLOWED_ORIGINS: string
  SUPABASE_STORAGE_BUCKET: string
  VITE_SUPABASE_URL: string
  VITE_SUPABASE_ANON_KEY: string
  VITE_SUPABASE_SERVICE_ROLE_KEY: string
}

function corsHeaders(origin: string | null, env: GatewayEnv) {
  const allowedOrigins = env.ALLOWED_ORIGINS.split(',').map((item) => item.trim())
  const allowOrigin = origin && allowedOrigins.includes(origin) ? origin : allowedOrigins[0] ?? '*'

  return {
    'Access-Control-Allow-Origin': allowOrigin,
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type,Authorization',
  }
}

function json(data: unknown, status: number, headers: Record<string, string>) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
      ...headers,
    },
  })
}

export default {
  async fetch(request, env): Promise<Response> {
    const runtimeEnv = env as GatewayEnv
    const url = new URL(request.url)
    const headers = corsHeaders(request.headers.get('Origin'), runtimeEnv)

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers })
    }

    if (url.pathname === '/health') {
      return json({ ok: true, service: 'catechesis-gateway' }, 200, headers)
    }

    if (url.pathname === '/config') {
      return json(
        {
          ok: true,
          site: 'Catechesis',
          storageBucket: runtimeEnv.SUPABASE_STORAGE_BUCKET,
          note: 'A service_role permanece no Worker. A anon key nao e devolvida por este endpoint.',
        },
        200,
        headers,
      )
    }

    if (url.pathname === '/media') {
      const path = url.searchParams.get('path')

      if (!path) {
        return json({ error: 'Informe ?path=...' }, 400, headers)
      }

      const mediaUrl = `${runtimeEnv.VITE_SUPABASE_URL}/storage/v1/object/public/${runtimeEnv.SUPABASE_STORAGE_BUCKET}/${path}`
      const response = await fetch(mediaUrl, {
        headers: {
          apikey: runtimeEnv.VITE_SUPABASE_ANON_KEY,
        },
      })

      return new Response(response.body, {
        status: response.status,
        headers: {
          ...headers,
          'Content-Type': response.headers.get('Content-Type') ?? 'application/octet-stream',
          'Cache-Control': 'public, max-age=300',
        },
      })
    }

    if (url.pathname === '/signed-download' && request.method === 'GET') {
      const path = url.searchParams.get('path')
      if (!path) {
        return json({ error: 'Informe ?path=...' }, 400, headers)
      }

      const signedUrlResponse = await fetch(
        `${runtimeEnv.VITE_SUPABASE_URL}/storage/v1/object/sign/${runtimeEnv.SUPABASE_STORAGE_BUCKET}/${path}`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            apikey: runtimeEnv.VITE_SUPABASE_SERVICE_ROLE_KEY,
            Authorization: `Bearer ${runtimeEnv.VITE_SUPABASE_SERVICE_ROLE_KEY}`,
          },
          body: JSON.stringify({ expiresIn: 120 }),
        },
      )

      const payload = (await signedUrlResponse.json()) as { signedURL?: string; error?: string }

      if (!signedUrlResponse.ok || !payload.signedURL) {
        return json({ error: payload.error ?? 'Nao foi possivel assinar o download.' }, 400, headers)
      }

      return json(
        {
          url: `${runtimeEnv.VITE_SUPABASE_URL}/storage/v1${payload.signedURL}`,
        },
        200,
        headers,
      )
    }

    return json({ error: 'Rota nao encontrada.' }, 404, headers)
  },
} satisfies ExportedHandler<GatewayEnv>
