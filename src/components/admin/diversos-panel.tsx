import { useEffect, useMemo, useState } from 'react'
import { toast } from 'sonner'
import { RichTextEditor } from '@/components/editor/rich-text-editor'
import { Button } from '@/components/ui/button'
import { Card, CardDescription, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Textarea } from '@/components/ui/textarea'
import { useCMSState, useSaveArticle, useSaveUsefulLink } from '@/hooks/use-cms'
import { articleCategoryOptions, getArticleCategoryMeta } from '@/lib/diversos'
import { createId, slugify } from '@/lib/utils'
import type { Article, UsefulLink } from '@/types/content'

const adminSelectClassName =
  'h-11 w-full rounded-2xl border border-input bg-white/90 px-4 text-sm text-stone-900 outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/20'

function emptyArticle(): Article {
  return {
    id: createId(),
    slug: '',
    title: '',
    excerpt: '',
    contentHtml: '',
    category: 'general',
    tags: [],
    coverImageUrl: '',
    featured: false,
    publishedAt: new Date().toISOString(),
  }
}

function emptyUsefulLink(): UsefulLink {
  return {
    id: createId(),
    title: '',
    description: '',
    url: '',
    tags: [],
    coverImageUrl: '',
    order: 1,
  }
}

export function DiversosPanel() {
  const { data } = useCMSState()
  const saveArticle = useSaveArticle()
  const saveUsefulLink = useSaveUsefulLink()
  const [articleForm, setArticleForm] = useState<Article>(emptyArticle())
  const [usefulLinkForm, setUsefulLinkForm] = useState<UsefulLink>(emptyUsefulLink())

  const usefulLinks = useMemo(
    () => [...(data?.usefulLinks ?? [])].sort((first, second) => first.order - second.order),
    [data],
  )

  useEffect(() => {
    if (!data) return

    setUsefulLinkForm((current) =>
      current.order > 1 || data.usefulLinks.length === 0
        ? current
        : { ...current, order: data.usefulLinks.length + 1 },
    )
  }, [data])

  if (!data) {
    return <div className="px-4 py-16 text-stone-700">Carregando conteudos diversos...</div>
  }

  async function handleSaveArticle() {
    await saveArticle.mutateAsync({
      ...articleForm,
      slug: slugify(articleForm.slug || articleForm.title),
      tags: articleForm.tags,
    })
    setArticleForm(emptyArticle())
    toast.success('Artigo salvo.')
  }

  async function handleSaveUsefulLink() {
    try {
      await saveUsefulLink.mutateAsync({
        ...usefulLinkForm,
        tags: usefulLinkForm.tags,
      })
      setUsefulLinkForm({
        ...emptyUsefulLink(),
        order: usefulLinks.length + 1,
      })
      toast.success('Link util salvo.')
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Nao foi possivel salvar o link util.'
      toast.error(message)
    }
  }

  return (
    <Tabs defaultValue="articles" className="space-y-6">
      <TabsList className="max-w-full flex-nowrap overflow-x-auto rounded-[24px] border border-stone-200/80 bg-white/80 p-1.5">
        <TabsTrigger className="shrink-0" value="articles">Artigos</TabsTrigger>
        <TabsTrigger className="shrink-0" value="links">Links Uteis</TabsTrigger>
      </TabsList>

      <TabsContent value="articles">
        <div className="grid gap-6 lg:grid-cols-[0.85fr_1.15fr]">
          <Card>
            <CardTitle>Artigos publicados</CardTitle>
            <CardDescription className="mt-2">
              Selecione um artigo para editar ou acompanhe em qual pasta ele sera exibido.
            </CardDescription>
            <div className="mt-5 space-y-3">
              {data.articles.map((article) => {
                const categoryMeta = getArticleCategoryMeta(article.category)

                return (
                  <button
                    key={article.id}
                    type="button"
                    onClick={() => setArticleForm(article)}
                    className="w-full rounded-[22px] border border-stone-200 bg-stone-50 p-4 text-left"
                  >
                    <p className="font-semibold text-stone-900">{article.title}</p>
                    <p className="mt-1 text-sm text-stone-600">{article.excerpt}</p>
                    <p className="mt-2 text-xs font-semibold uppercase tracking-[0.18em] text-stone-500">
                      Pasta: {categoryMeta.label}
                    </p>
                  </button>
                )
              })}
            </div>
          </Card>

          <Card>
            <CardTitle>{articleForm.title ? 'Editar artigo' : 'Novo artigo'}</CardTitle>
            <CardDescription className="mt-2">
              O editor rico segue o mesmo padrao do sistema, agora com escolha explicita da pasta do artigo.
            </CardDescription>
            <div className="mt-5 grid gap-4">
              <div className="grid gap-4 md:grid-cols-2">
                <div className="space-y-2">
                  <Label>Titulo</Label>
                  <Input
                    value={articleForm.title}
                    onChange={(event) =>
                      setArticleForm((current) => ({ ...current, title: event.target.value }))
                    }
                  />
                </div>
                <div className="space-y-2">
                  <Label>Slug</Label>
                  <Input
                    value={articleForm.slug}
                    onChange={(event) =>
                      setArticleForm((current) => ({ ...current, slug: event.target.value }))
                    }
                  />
                </div>
              </div>

              <div className="grid gap-4 md:grid-cols-2">
                <div className="space-y-2">
                  <Label>Pasta</Label>
                  <select
                    value={articleForm.category}
                    onChange={(event) =>
                      setArticleForm((current) => ({
                        ...current,
                        category: event.target.value as Article['category'],
                      }))
                    }
                    className={adminSelectClassName}
                  >
                    {articleCategoryOptions.map((option) => (
                      <option key={option.value} value={option.value}>
                        {option.label}
                      </option>
                    ))}
                  </select>
                </div>

                <div className="space-y-2">
                  <Label>Imagem de capa</Label>
                  <Input
                    value={articleForm.coverImageUrl ?? ''}
                    onChange={(event) =>
                      setArticleForm((current) => ({ ...current, coverImageUrl: event.target.value }))
                    }
                  />
                </div>
              </div>

              <div className="grid gap-4 md:grid-cols-2">
                <div className="space-y-2">
                  <Label>Resumo</Label>
                  <Textarea
                    value={articleForm.excerpt}
                    onChange={(event) =>
                      setArticleForm((current) => ({ ...current, excerpt: event.target.value }))
                    }
                  />
                </div>
                <div className="space-y-2">
                  <Label>Tags</Label>
                  <Textarea
                    value={articleForm.tags.join(', ')}
                    onChange={(event) =>
                      setArticleForm((current) => ({
                        ...current,
                        tags: event.target.value
                          .split(',')
                          .map((tag) => tag.trim())
                          .filter(Boolean),
                      }))
                    }
                  />
                </div>
              </div>

              <div className="space-y-2">
                <Label>Conteudo</Label>
                <RichTextEditor
                  value={articleForm.contentHtml}
                  onChange={(contentHtml) =>
                    setArticleForm((current) => ({ ...current, contentHtml }))
                  }
                />
              </div>

              <Button onClick={() => void handleSaveArticle()} disabled={saveArticle.isPending}>
                {saveArticle.isPending ? 'Salvando...' : 'Salvar artigo'}
              </Button>
            </div>
          </Card>
        </div>
      </TabsContent>

      <TabsContent value="links">
        <div className="grid gap-6 lg:grid-cols-[0.85fr_1.15fr]">
          <Card>
            <CardTitle>Links publicados</CardTitle>
            <CardDescription className="mt-2">
              Estes links aparecem na visualizacao publica de Links Uteis.
            </CardDescription>
            <div className="mt-5 space-y-3">
              {usefulLinks.map((usefulLink) => (
                <button
                  key={usefulLink.id}
                  type="button"
                  onClick={() => setUsefulLinkForm(usefulLink)}
                  className="w-full rounded-[22px] border border-stone-200 bg-stone-50 p-4 text-left"
                >
                  <p className="font-semibold text-stone-900">{usefulLink.title}</p>
                  <p className="mt-1 text-sm text-stone-600">{usefulLink.description}</p>
                  <p className="mt-2 text-xs font-semibold uppercase tracking-[0.18em] text-stone-500">
                    Ordem: {usefulLink.order}
                  </p>
                </button>
              ))}
            </div>
          </Card>

          <Card>
            <CardTitle>{usefulLinkForm.title ? 'Editar link util' : 'Novo link util'}</CardTitle>
            <CardDescription className="mt-2">
              Este formulario segue a mesma logica do sistema para cadastros simples baseados em links.
            </CardDescription>
            <div className="mt-5 grid gap-4">
              <div className="grid gap-4 md:grid-cols-2">
                <div className="space-y-2">
                  <Label>Titulo</Label>
                  <Input
                    value={usefulLinkForm.title}
                    onChange={(event) =>
                      setUsefulLinkForm((current) => ({ ...current, title: event.target.value }))
                    }
                  />
                </div>
                <div className="space-y-2">
                  <Label>URL</Label>
                  <Input
                    value={usefulLinkForm.url}
                    onChange={(event) =>
                      setUsefulLinkForm((current) => ({ ...current, url: event.target.value }))
                    }
                  />
                </div>
              </div>

              <div className="grid gap-4 md:grid-cols-2">
                <div className="space-y-2">
                  <Label>Descricao</Label>
                  <Textarea
                    value={usefulLinkForm.description}
                    onChange={(event) =>
                      setUsefulLinkForm((current) => ({
                        ...current,
                        description: event.target.value,
                      }))
                    }
                  />
                </div>
                <div className="space-y-2">
                  <Label>Tags</Label>
                  <Textarea
                    value={usefulLinkForm.tags.join(', ')}
                    onChange={(event) =>
                      setUsefulLinkForm((current) => ({
                        ...current,
                        tags: event.target.value
                          .split(',')
                          .map((tag) => tag.trim())
                          .filter(Boolean),
                      }))
                    }
                  />
                </div>
              </div>

              <div className="grid gap-4 md:grid-cols-2">
                <div className="space-y-2">
                  <Label>Imagem de capa</Label>
                  <Input
                    value={usefulLinkForm.coverImageUrl ?? ''}
                    onChange={(event) =>
                      setUsefulLinkForm((current) => ({
                        ...current,
                        coverImageUrl: event.target.value,
                      }))
                    }
                    placeholder="https://..."
                  />
                </div>
                <div className="rounded-[22px] border border-dashed border-stone-300 bg-white/75 p-3">
                  <p className="text-xs font-semibold uppercase tracking-[0.18em] text-stone-500">
                    Preview da capa
                  </p>
                  {usefulLinkForm.coverImageUrl ? (
                    <img
                      src={usefulLinkForm.coverImageUrl}
                      alt="Preview da capa do link util"
                      referrerPolicy="no-referrer"
                      className="mt-3 aspect-[16/9] w-full rounded-[18px] object-cover"
                    />
                  ) : (
                    <div className="mt-3 flex aspect-[16/9] items-center justify-center rounded-[18px] bg-stone-100 px-4 text-center text-sm text-stone-500">
                      Cole a URL da imagem para revisar a capa do link aqui.
                    </div>
                  )}
                </div>
              </div>

              <div className="space-y-2">
                <Label>Ordem</Label>
                <Input
                  type="number"
                  min={1}
                  value={usefulLinkForm.order}
                  onChange={(event) =>
                    setUsefulLinkForm((current) => ({
                      ...current,
                      order: Number(event.target.value) || 1,
                    }))
                  }
                />
              </div>

              <Button onClick={() => void handleSaveUsefulLink()} disabled={saveUsefulLink.isPending}>
                {saveUsefulLink.isPending ? 'Salvando...' : 'Salvar link util'}
              </Button>
            </div>
          </Card>
        </div>
      </TabsContent>
    </Tabs>
  )
}
