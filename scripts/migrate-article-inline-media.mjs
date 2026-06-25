import { createHash } from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'
import { createClient } from '@supabase/supabase-js'

const STORAGE_BUCKET = 'catechesis-media'
const DATA_URL_PATTERN = /src=(['"])(data:image\/[a-z0-9.+-]+;base64,[^'"]+)\1/gi

function readEnvFile() {
  const envPath = path.join(process.cwd(), '.env')
  const envText = fs.readFileSync(envPath, 'utf8')
  const env = {}

  for (const rawLine of envText.split(/\r?\n/)) {
    const line = rawLine.trim()
    if (!line || line.startsWith('#')) continue

    const separatorIndex = line.indexOf('=')
    if (separatorIndex < 0) continue

    const key = line.slice(0, separatorIndex).trim()
    const value = line.slice(separatorIndex + 1).trim().replace(/^['"]|['"]$/g, '')
    env[key] = value
  }

  return env
}

function sanitizeSegment(value) {
  return value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
}

function extensionFromMime(mimeType) {
  if (mimeType === 'image/jpeg') return 'jpg'
  if (mimeType === 'image/png') return 'png'
  if (mimeType === 'image/webp') return 'webp'
  if (mimeType === 'image/gif') return 'gif'
  if (mimeType === 'image/avif') return 'avif'
  return mimeType.split('/')[1] || 'bin'
}

function parseDataUrl(dataUrl) {
  const match = /^data:(image\/[a-z0-9.+-]+);base64,([\s\S]+)$/i.exec(dataUrl)

  if (!match) {
    throw new Error('Data URL de imagem inválida.')
  }

  const mimeType = match[1].toLowerCase()
  const base64Payload = match[2].replace(/\s+/g, '')
  const bytes = Buffer.from(base64Payload, 'base64')

  return {
    mimeType,
    bytes,
    hash: createHash('sha1').update(bytes).digest('hex').slice(0, 16),
    extension: extensionFromMime(mimeType),
  }
}

function extractInlineImageSources(contentHtml) {
  const matches = [...contentHtml.matchAll(DATA_URL_PATTERN)]
  return [...new Set(matches.map((match) => match[2]))]
}

async function uploadInlineImage(supabase, articleSlug, dataUrl, imageIndex) {
  const parsed = parseDataUrl(dataUrl)
  const slugSegment = sanitizeSegment(articleSlug) || 'article'
  const filePath = `article-inline/${slugSegment}/${String(imageIndex + 1).padStart(2, '0')}-${parsed.hash}.${parsed.extension}`

  const { error: uploadError } = await supabase.storage
    .from(STORAGE_BUCKET)
    .upload(filePath, parsed.bytes, {
      contentType: parsed.mimeType,
      upsert: true,
    })

  if (uploadError) {
    throw new Error(uploadError.message)
  }

  const { data } = supabase.storage.from(STORAGE_BUCKET).getPublicUrl(filePath)
  return data.publicUrl
}

async function main() {
  const env = readEnvFile()
  const supabaseUrl = env.VITE_SUPABASE_URL
  const serviceRoleKey = env.VITE_SUPABASE_SERVICE_ROLE_KEY

  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error('VITE_SUPABASE_URL ou VITE_SUPABASE_SERVICE_ROLE_KEY ausente no .env.')
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const { data: articles, error } = await supabase
    .from('articles')
    .select('id,slug,title,content_html,status')
    .eq('status', 'published')
    .order('published_at', { ascending: false })

  if (error) {
    throw new Error(error.message)
  }

  let scannedArticles = 0
  let migratedArticles = 0
  let migratedImages = 0

  for (const article of articles ?? []) {
    scannedArticles += 1

    const originalHtml = String(article.content_html ?? '')
    const inlineSources = extractInlineImageSources(originalHtml)

    if (inlineSources.length === 0) {
      continue
    }

    const replacementMap = new Map()

    for (const [index, dataUrl] of inlineSources.entries()) {
      const publicUrl = await uploadInlineImage(supabase, article.slug, dataUrl, index)
      replacementMap.set(dataUrl, publicUrl)
      migratedImages += 1
    }

    let nextHtml = originalHtml
    for (const [dataUrl, publicUrl] of replacementMap.entries()) {
      nextHtml = nextHtml.split(dataUrl).join(publicUrl)
    }

    const { error: updateError } = await supabase
      .from('articles')
      .update({ content_html: nextHtml })
      .eq('id', article.id)

    if (updateError) {
      throw new Error(`Falha ao atualizar artigo "${article.slug}": ${updateError.message}`)
    }

    migratedArticles += 1
    console.log(
      JSON.stringify({
        slug: article.slug,
        title: article.title,
        migratedImages: inlineSources.length,
        originalHtmlLength: originalHtml.length,
        nextHtmlLength: nextHtml.length,
      }),
    )
  }

  console.log(
    JSON.stringify({
      scannedArticles,
      migratedArticles,
      migratedImages,
      bucket: STORAGE_BUCKET,
    }),
  )
}

await main()
