import { useEffect, useMemo, useState, type ReactNode } from 'react'
import { toast } from 'sonner'
import { RichTextEditor } from '@/components/editor/rich-text-editor'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardDescription, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Separator } from '@/components/ui/separator'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Textarea } from '@/components/ui/textarea'
import {
  useCMSState,
  useSaveArticle,
  useSaveAsset,
  useSaveEncounter,
  useSaveGroup,
  useSaveQuiz,
  useSaveSettings,
} from '@/hooks/use-cms'
import { createId, slugify } from '@/lib/utils'
import type {
  Article,
  ClassGroup,
  Encounter,
  EncounterAsset,
  EncounterQuiz,
  SiteSettings,
} from '@/types/content'

const adminSelectClassName =
  'h-11 w-full rounded-2xl border border-input bg-white/90 px-4 text-sm text-stone-900 outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/20'

function AdminFormSection({
  title,
  description,
  children,
}: {
  title: string
  description: string
  children: ReactNode
}) {
  return (
    <section className="rounded-[24px] border border-stone-200/80 bg-stone-50/60 p-4 md:p-5">
      <div className="mb-4">
        <h4 className="font-display text-2xl text-stone-900">{title}</h4>
        <p className="mt-1 text-sm leading-6 text-stone-600">{description}</p>
      </div>
      <div className="grid gap-4">{children}</div>
    </section>
  )
}

function emptyGroup(): ClassGroup {
  return {
    id: createId(),
    slug: '',
    name: '',
    battleCry: '',
    order: 1,
  }
}

function emptyEncounter(groupId = ''): Encounter {
  return {
    id: createId(),
    groupId,
    slug: '',
    title: '',
    illuminatedTitle: 'Encontros',
    summary: '',
    theme: '',
    audience: '',
    order: 1,
    coverImageUrl: '',
    bodyHtml: '',
    assets: [],
  }
}

function emptyArticle(): Article {
  return {
    id: createId(),
    slug: '',
    title: '',
    excerpt: '',
    contentHtml: '',
    tags: [],
    coverImageUrl: '',
    featured: false,
    publishedAt: new Date().toISOString(),
  }
}

function emptyQuiz(encounterId = ''): EncounterQuiz {
  return {
    id: createId(),
    encounterId,
    title: '',
    description: '',
    questions: [
      {
        id: createId(),
        prompt: '',
        explanation: '',
        options: Array.from({ length: 5 }, (_, optionIndex) => ({
          id: createId(),
          text: '',
          isCorrect: optionIndex === 0,
        })),
      },
    ],
  }
}

export function AdminDashboardPage() {
  const { data } = useCMSState()
  const saveGroup = useSaveGroup()
  const saveEncounter = useSaveEncounter()
  const saveArticle = useSaveArticle()
  const saveAsset = useSaveAsset()
  const saveQuiz = useSaveQuiz()
  const saveSettings = useSaveSettings()

  const [groupForm, setGroupForm] = useState<ClassGroup>(emptyGroup())
  const [encounterForm, setEncounterForm] = useState<Encounter>(emptyEncounter())
  const [articleForm, setArticleForm] = useState<Article>(emptyArticle())
  const [quizForm, setQuizForm] = useState<EncounterQuiz>(emptyQuiz())
  const [settingsForm, setSettingsForm] = useState<SiteSettings | null>(null)
  const [assetForm, setAssetForm] = useState<EncounterAsset>({
    id: createId(),
    encounterId: '',
    title: '',
    description: '',
    kind: 'summary',
    view: 'pdf',
    url: '',
    downloadable: true,
    order: 1,
  })
  const [assetFile, setAssetFile] = useState<File | null>(null)

  const groupOptions = useMemo(
    () => [...(data?.groups ?? [])].sort((first, second) => first.order - second.order),
    [data],
  )
  const encounterOptions = useMemo(
    () =>
      [...(data?.encounters ?? [])].sort((first, second) => {
        if (first.groupId === second.groupId) {
          return first.order - second.order
        }

        return first.groupId.localeCompare(second.groupId)
      }),
    [data],
  )
  const groupNameById = useMemo(
    () => new Map(groupOptions.map((group) => [group.id, group.name])),
    [groupOptions],
  )

  useEffect(() => {
    if (!data) return
    if (!settingsForm) setSettingsForm(data.settings)

    const firstGroupId = groupOptions[0]?.id ?? ''
    const firstEncounterId = encounterOptions[0]?.id ?? ''

    setEncounterForm((current) =>
      current.groupId || !firstGroupId ? current : { ...current, groupId: firstGroupId },
    )
    setAssetForm((current) =>
      current.encounterId || !firstEncounterId ? current : { ...current, encounterId: firstEncounterId },
    )
    setQuizForm((current) =>
      current.encounterId || !firstEncounterId ? current : { ...current, encounterId: firstEncounterId },
    )
  }, [data, encounterOptions, groupOptions, settingsForm])

  if (!data || !settingsForm) {
    return <div className="px-4 py-16 text-stone-700">Carregando painel...</div>
  }

  async function handleSaveGroup() {
    await saveGroup.mutateAsync({
      ...groupForm,
      slug: slugify(groupForm.slug || groupForm.name),
    })
    setGroupForm(emptyGroup())
    toast.success('Turma salva.')
  }

  async function handleSaveEncounter() {
    await saveEncounter.mutateAsync({
      ...encounterForm,
      slug: slugify(encounterForm.slug || encounterForm.title),
    })
    setEncounterForm(emptyEncounter(groupOptions[0]?.id ?? ''))
    toast.success('Encontro salvo.')
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

  async function handleSaveAsset() {
    await saveAsset.mutateAsync({
      asset: assetForm,
      file: assetFile,
    })
    setAssetFile(null)
    setAssetForm({
      id: createId(),
      encounterId: encounterOptions[0]?.id ?? '',
      title: '',
      description: '',
      kind: 'summary',
      view: 'pdf',
      url: '',
      downloadable: true,
      order: 1,
    })
    toast.success('Material salvo.')
  }

  async function handleSaveQuiz() {
    await saveQuiz.mutateAsync(quizForm)
    setQuizForm(emptyQuiz(encounterOptions[0]?.id ?? ''))
    toast.success('Quiz salvo.')
  }

  async function handleSaveSettings() {
    if (!settingsForm) return
    await saveSettings.mutateAsync(settingsForm)
    toast.success('Configuracoes atualizadas.')
  }

  return (
    <section className="mx-auto max-w-7xl px-4 py-8 pb-12 md:py-10">
      <div className="mb-8 flex flex-wrap items-start justify-between gap-4">
        <div className="max-w-2xl">
          <p className="text-xs font-semibold uppercase tracking-[0.22em] text-stone-500">
            gestao de conteudo
          </p>
          <h1 className="font-display text-4xl text-stone-900">Edicao do Catechesis</h1>
          <p className="mt-2 text-sm leading-6 text-stone-600">
            O painel administrativo agora fica separado da navegacao publica e concentra a edicao em
            blocos mais claros para reduzir ruido visual no mobile.
          </p>
        </div>
        <Badge>Local-first com fallback em demo</Badge>
      </div>

      <Tabs defaultValue="groups" className="space-y-6">
        <TabsList className="max-w-full flex-nowrap overflow-x-auto rounded-[24px] border border-stone-200/80 bg-white/80 p-1.5 shadow-[0_16px_40px_rgba(74,61,35,0.08)]">
          <TabsTrigger className="shrink-0" value="groups">Turmas</TabsTrigger>
          <TabsTrigger className="shrink-0" value="encounters">Encontros</TabsTrigger>
          <TabsTrigger className="shrink-0" value="assets">Materiais</TabsTrigger>
          <TabsTrigger className="shrink-0" value="quizzes">Quizzes</TabsTrigger>
          <TabsTrigger className="shrink-0" value="articles">Artigos</TabsTrigger>
          <TabsTrigger className="shrink-0" value="settings">Landing</TabsTrigger>
        </TabsList>

        <TabsContent value="groups">
          <div className="grid gap-6 lg:grid-cols-[0.82fr_1.18fr]">
            <Card>
              <CardTitle>Turmas existentes</CardTitle>
              <div className="mt-5 space-y-3">
                {groupOptions.map((group) => (
                  <button
                    key={group.id}
                    type="button"
                    onClick={() => setGroupForm(group)}
                    className="w-full rounded-[22px] border border-stone-200 bg-stone-50 p-4 text-left"
                  >
                    <p className="font-semibold text-stone-900">{group.name}</p>
                    <p className="mt-1 text-sm text-stone-600">
                      {group.battleCry || 'Sem brado cadastrado.'}
                    </p>
                  </button>
                ))}
              </div>
            </Card>

            <Card>
              <CardTitle>{groupForm.name ? 'Editar turma' : 'Criar nova turma'}</CardTitle>
              <CardDescription className="mt-2">
                Cada turma concentra seus proprios encontros e exibe um brado proprio na pagina publica.
              </CardDescription>
              <div className="mt-5 grid gap-4">
                <div className="grid gap-4 md:grid-cols-2">
                  <div className="space-y-2">
                    <Label>Nome da turma</Label>
                    <Input
                      value={groupForm.name}
                      onChange={(event) =>
                        setGroupForm((current) => ({ ...current, name: event.target.value }))
                      }
                    />
                  </div>
                  <div className="space-y-2">
                    <Label>Slug</Label>
                    <Input
                      value={groupForm.slug}
                      onChange={(event) =>
                        setGroupForm((current) => ({ ...current, slug: event.target.value }))
                      }
                      placeholder="gerado a partir do nome"
                    />
                  </div>
                </div>
                <div className="space-y-2">
                  <Label>Brado</Label>
                  <Textarea
                    value={groupForm.battleCry}
                    onChange={(event) =>
                      setGroupForm((current) => ({ ...current, battleCry: event.target.value }))
                    }
                  />
                </div>
                <Button onClick={() => void handleSaveGroup()} disabled={saveGroup.isPending}>
                  {saveGroup.isPending ? 'Salvando...' : 'Salvar turma'}
                </Button>
              </div>
            </Card>
          </div>
        </TabsContent>

        <TabsContent value="encounters">
          <div className="grid gap-6 lg:grid-cols-[0.85fr_1.15fr]">
            <Card>
              <CardTitle>Encontros existentes</CardTitle>
              <div className="mt-5 space-y-3">
                {encounterOptions.map((encounter) => (
                  <button
                    key={encounter.id}
                    type="button"
                    onClick={() => setEncounterForm(encounter)}
                    className="w-full rounded-[22px] border border-stone-200 bg-stone-50 p-4 text-left"
                  >
                    <p className="font-semibold text-stone-900">{encounter.title}</p>
                    <p className="mt-1 text-sm text-stone-600">
                      {groupNameById.get(encounter.groupId) || 'Turma nao localizada'}
                    </p>
                  </button>
                ))}
              </div>
            </Card>
            <Card>
              <CardTitle>{encounterForm.title ? 'Editar encontro' : 'Criar novo encontro'}</CardTitle>
              <CardDescription className="mt-2">
                O encontro agora pertence a uma turma antes de receber resumo, material de apoio e quiz.
              </CardDescription>
              <div className="mt-6 space-y-5">
                <AdminFormSection
                  title="Identidade do encontro"
                  description="Defina a turma, o titulo e os dados que ajudam a localizar o encontro no painel e no site."
                >
                  <div className="space-y-2">
                    <Label>Turma</Label>
                    <select
                      value={encounterForm.groupId}
                      onChange={(event) =>
                        setEncounterForm((current) => ({ ...current, groupId: event.target.value }))
                      }
                      className={adminSelectClassName}
                    >
                      {groupOptions.map((group) => (
                        <option key={group.id} value={group.id}>
                          {group.name}
                        </option>
                      ))}
                    </select>
                  </div>
                  <div className="grid gap-4 md:grid-cols-2">
                    <div className="space-y-2">
                      <Label>Titulo</Label>
                      <Input
                        value={encounterForm.title}
                        onChange={(event) =>
                          setEncounterForm((current) => ({ ...current, title: event.target.value }))
                        }
                      />
                    </div>
                    <div className="space-y-2">
                      <Label>Slug</Label>
                      <Input
                        value={encounterForm.slug}
                        onChange={(event) =>
                          setEncounterForm((current) => ({ ...current, slug: event.target.value }))
                        }
                        placeholder="gerado a partir do titulo"
                      />
                    </div>
                  </div>
                  <div className="grid gap-4 md:grid-cols-2">
                    <div className="space-y-2">
                      <Label>Tema</Label>
                      <Input
                        value={encounterForm.theme}
                        onChange={(event) =>
                          setEncounterForm((current) => ({ ...current, theme: event.target.value }))
                        }
                      />
                    </div>
                    <div className="space-y-2">
                      <Label>Publico</Label>
                      <Input
                        value={encounterForm.audience}
                        onChange={(event) =>
                          setEncounterForm((current) => ({ ...current, audience: event.target.value }))
                        }
                      />
                    </div>
                  </div>
                </AdminFormSection>

                <AdminFormSection
                  title="Apresentacao"
                  description="Resumo e capa ficam juntos para facilitar a revisao do material antes de publicar."
                >
                  <div className="space-y-2">
                    <Label>Resumo curto</Label>
                    <Textarea
                      value={encounterForm.summary}
                      onChange={(event) =>
                        setEncounterForm((current) => ({ ...current, summary: event.target.value }))
                      }
                    />
                  </div>
                  <div className="grid gap-4 lg:grid-cols-[1.3fr_0.7fr]">
                    <div className="space-y-2">
                      <Label>Imagem de capa</Label>
                      <Input
                        value={encounterForm.coverImageUrl ?? ''}
                        onChange={(event) =>
                          setEncounterForm((current) => ({
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
                      {encounterForm.coverImageUrl ? (
                        <img
                          src={encounterForm.coverImageUrl}
                          alt="Preview da capa do encontro"
                          className="mt-3 aspect-[4/3] w-full rounded-[18px] object-cover"
                        />
                      ) : (
                        <div className="mt-3 flex aspect-[4/3] items-center justify-center rounded-[18px] bg-stone-100 px-4 text-center text-sm text-stone-500">
                          Cole a URL da imagem para revisar a capa aqui.
                        </div>
                      )}
                    </div>
                  </div>
                </AdminFormSection>

                <AdminFormSection
                  title="Conteudo principal"
                  description="A barra de ferramentas foi compactada para mobile e o editor agora segue a mesma linguagem visual do painel."
                >
                  <div className="space-y-2">
                    <Label>Texto HTML do encontro</Label>
                    <RichTextEditor
                      value={encounterForm.bodyHtml ?? ''}
                      onChange={(bodyHtml) =>
                        setEncounterForm((current) => ({ ...current, bodyHtml }))
                      }
                    />
                  </div>
                </AdminFormSection>

                <div className="sticky bottom-4 z-20">
                  <div className="flex flex-col gap-3 rounded-[24px] border border-stone-200/80 bg-white/92 p-3 shadow-[0_18px_42px_rgba(74,61,35,0.12)] backdrop-blur md:flex-row md:items-center md:justify-between">
                    <div>
                      <p className="text-sm font-semibold text-stone-800">
                        {encounterForm.title ? 'Pronto para atualizar o encontro.' : 'Pronto para criar o encontro.'}
                      </p>
                      <p className="text-xs text-stone-500">
                        Salve depois de revisar titulo, capa e HTML do conteudo.
                      </p>
                    </div>
                    <Button
                      className="w-full md:w-auto"
                      onClick={() => void handleSaveEncounter()}
                      disabled={saveEncounter.isPending || !encounterForm.groupId}
                    >
                      {saveEncounter.isPending ? 'Salvando...' : 'Salvar encontro'}
                    </Button>
                  </div>
                </div>
              </div>
            </Card>
          </div>
        </TabsContent>

        <TabsContent value="assets">
          <div className="grid gap-6 lg:grid-cols-[0.88fr_1.12fr]">
            <Card>
              <CardTitle>Materiais ja cadastrados</CardTitle>
              <div className="mt-5 space-y-4">
                {encounterOptions.flatMap((encounter) =>
                  encounter.assets.map((asset) => (
                    <div key={asset.id} className="rounded-[22px] border border-stone-200 bg-stone-50 p-4">
                      <p className="font-semibold text-stone-900">{asset.title}</p>
                      <p className="mt-1 text-sm text-stone-600">
                        {(groupNameById.get(encounter.groupId) || 'Turma') + ' / ' + encounter.title}
                      </p>
                    </div>
                  )),
                )}
              </div>
            </Card>
            <Card>
              <CardTitle>Subir PDF, imagem ou link</CardTitle>
              <CardDescription className="mt-2">
                Salve o resumo do encontro ou materiais de apoio separados para consulta e download.
              </CardDescription>
              <div className="mt-5 grid gap-4">
                <div className="space-y-2">
                  <Label>Encontro</Label>
                  <select
                    value={assetForm.encounterId}
                    onChange={(event) =>
                      setAssetForm((current) => ({ ...current, encounterId: event.target.value }))
                    }
                    className="h-11 rounded-2xl border border-input bg-white px-4"
                  >
                    {encounterOptions.map((encounter) => (
                      <option key={encounter.id} value={encounter.id}>
                        {(groupNameById.get(encounter.groupId) || 'Turma') + ' / ' + encounter.title}
                      </option>
                    ))}
                  </select>
                </div>
                <div className="grid gap-4 md:grid-cols-2">
                  <div className="space-y-2">
                    <Label>Titulo</Label>
                    <Input
                      value={assetForm.title}
                      onChange={(event) => setAssetForm((current) => ({ ...current, title: event.target.value }))}
                    />
                  </div>
                  <div className="space-y-2">
                    <Label>Tipo</Label>
                    <select
                      value={assetForm.kind}
                      onChange={(event) =>
                        setAssetForm((current) => ({
                          ...current,
                          kind: event.target.value as EncounterAsset['kind'],
                        }))
                      }
                      className="h-11 rounded-2xl border border-input bg-white px-4"
                    >
                      <option value="summary">Resumo do encontro</option>
                      <option value="support">Material de apoio</option>
                    </select>
                  </div>
                </div>
                <div className="grid gap-4 md:grid-cols-2">
                  <div className="space-y-2">
                    <Label>Visualizacao</Label>
                    <select
                      value={assetForm.view}
                      onChange={(event) =>
                        setAssetForm((current) => ({
                          ...current,
                          view: event.target.value as EncounterAsset['view'],
                        }))
                      }
                      className="h-11 rounded-2xl border border-input bg-white px-4"
                    >
                      <option value="pdf">PDF</option>
                      <option value="image">Imagem</option>
                      <option value="video">Video</option>
                      <option value="link">Link</option>
                      <option value="html">HTML</option>
                    </select>
                  </div>
                  <div className="space-y-2">
                    <Label>Arquivo</Label>
                    <Input type="file" onChange={(event) => setAssetFile(event.target.files?.[0] ?? null)} />
                  </div>
                </div>
                <div className="space-y-2">
                  <Label>URL ou HTML</Label>
                  <Textarea
                    value={assetForm.url}
                    onChange={(event) => setAssetForm((current) => ({ ...current, url: event.target.value }))}
                  />
                </div>
                <div className="space-y-2">
                  <Label>Descricao</Label>
                  <Textarea
                    value={assetForm.description}
                    onChange={(event) =>
                      setAssetForm((current) => ({ ...current, description: event.target.value }))
                    }
                  />
                </div>
                <Button onClick={() => void handleSaveAsset()} disabled={saveAsset.isPending || !assetForm.encounterId}>
                  {saveAsset.isPending ? 'Salvando...' : 'Salvar material'}
                </Button>
              </div>
            </Card>
          </div>
        </TabsContent>

        <TabsContent value="quizzes">
          <Card>
            <CardTitle>Quiz do encontro</CardTitle>
            <CardDescription className="mt-2">
              Cada pergunta recebe cinco alternativas, uma correta e explicacao exibida apos o envio.
            </CardDescription>
            <div className="mt-5 grid gap-4">
              <div className="space-y-2">
                <Label>Encontro</Label>
                <select
                  value={quizForm.encounterId}
                  onChange={(event) => setQuizForm((current) => ({ ...current, encounterId: event.target.value }))}
                  className="h-11 rounded-2xl border border-input bg-white px-4"
                >
                  {encounterOptions.map((encounter) => (
                    <option key={encounter.id} value={encounter.id}>
                      {(groupNameById.get(encounter.groupId) || 'Turma') + ' / ' + encounter.title}
                    </option>
                  ))}
                </select>
              </div>
              <div className="grid gap-4 md:grid-cols-2">
                <div className="space-y-2">
                  <Label>Titulo do quiz</Label>
                  <Input
                    value={quizForm.title}
                    onChange={(event) => setQuizForm((current) => ({ ...current, title: event.target.value }))}
                  />
                </div>
                <div className="space-y-2">
                  <Label>Descricao</Label>
                  <Input
                    value={quizForm.description}
                    onChange={(event) =>
                      setQuizForm((current) => ({ ...current, description: event.target.value }))
                    }
                  />
                </div>
              </div>
              {quizForm.questions.map((question, questionIndex) => (
                <div key={question.id} className="rounded-[28px] border border-stone-200 bg-stone-50/80 p-5">
                  <div className="space-y-2">
                    <Label>Pergunta {questionIndex + 1}</Label>
                    <Textarea
                      value={question.prompt}
                      onChange={(event) =>
                        setQuizForm((current) => ({
                          ...current,
                          questions: current.questions.map((item) =>
                            item.id === question.id ? { ...item, prompt: event.target.value } : item,
                          ),
                        }))
                      }
                    />
                  </div>
                  <div className="mt-4 space-y-3">
                    {question.options.map((option) => (
                      <div key={option.id} className="grid gap-3 md:grid-cols-[1fr_auto] md:items-center">
                        <Input
                          value={option.text}
                          onChange={(event) =>
                            setQuizForm((current) => ({
                              ...current,
                              questions: current.questions.map((item) =>
                                item.id === question.id
                                  ? {
                                      ...item,
                                      options: item.options.map((choice) =>
                                        choice.id === option.id ? { ...choice, text: event.target.value } : choice,
                                      ),
                                    }
                                  : item,
                              ),
                            }))
                          }
                          placeholder="Alternativa"
                        />
                        <label className="inline-flex items-center gap-2 text-sm text-stone-700">
                          <input
                            type="radio"
                            name={`correct-${question.id}`}
                            checked={option.isCorrect}
                            onChange={() =>
                              setQuizForm((current) => ({
                                ...current,
                                questions: current.questions.map((item) =>
                                  item.id === question.id
                                    ? {
                                        ...item,
                                        options: item.options.map((choice) => ({
                                          ...choice,
                                          isCorrect: choice.id === option.id,
                                        })),
                                      }
                                    : item,
                                ),
                              }))
                            }
                          />
                          Correta
                        </label>
                      </div>
                    ))}
                  </div>
                  <div className="mt-4 space-y-2">
                    <Label>Explicacao apos a resposta</Label>
                    <Textarea
                      value={question.explanation}
                      onChange={(event) =>
                        setQuizForm((current) => ({
                          ...current,
                          questions: current.questions.map((item) =>
                            item.id === question.id ? { ...item, explanation: event.target.value } : item,
                          ),
                        }))
                      }
                    />
                  </div>
                </div>
              ))}
              <Button
                variant="outline"
                onClick={() =>
                  setQuizForm((current) => ({
                    ...current,
                    questions: [
                      ...current.questions,
                      {
                        id: createId(),
                        prompt: '',
                        explanation: '',
                        options: Array.from({ length: 5 }, (_, index) => ({
                          id: createId(),
                          text: '',
                          isCorrect: index === 0,
                        })),
                      },
                    ],
                  }))
                }
              >
                Adicionar pergunta
              </Button>
              <Button onClick={() => void handleSaveQuiz()} disabled={saveQuiz.isPending || !quizForm.encounterId}>
                {saveQuiz.isPending ? 'Salvando...' : 'Salvar quiz'}
              </Button>
            </div>
          </Card>
        </TabsContent>

        <TabsContent value="articles">
          <div className="grid gap-6 lg:grid-cols-[0.85fr_1.15fr]">
            <Card>
              <CardTitle>Artigos publicados</CardTitle>
              <div className="mt-5 space-y-3">
                {data.articles.map((article) => (
                  <button
                    key={article.id}
                    type="button"
                    onClick={() => setArticleForm(article)}
                    className="w-full rounded-[22px] border border-stone-200 bg-stone-50 p-4 text-left"
                  >
                    <p className="font-semibold text-stone-900">{article.title}</p>
                    <p className="mt-1 text-sm text-stone-600">{article.excerpt}</p>
                  </button>
                ))}
              </div>
            </Card>
            <Card>
              <CardTitle>{articleForm.title ? 'Editar artigo' : 'Novo artigo'}</CardTitle>
              <CardDescription className="mt-2">
                O editor gera HTML rico no proprio sistema e pode ser publicado em rota independente.
              </CardDescription>
              <div className="mt-5 grid gap-4">
                <div className="grid gap-4 md:grid-cols-2">
                  <div className="space-y-2">
                    <Label>Titulo</Label>
                    <Input
                      value={articleForm.title}
                      onChange={(event) => setArticleForm((current) => ({ ...current, title: event.target.value }))}
                    />
                  </div>
                  <div className="space-y-2">
                    <Label>Slug</Label>
                    <Input
                      value={articleForm.slug}
                      onChange={(event) => setArticleForm((current) => ({ ...current, slug: event.target.value }))}
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
                  <Label>Imagem de capa</Label>
                  <Input
                    value={articleForm.coverImageUrl ?? ''}
                    onChange={(event) =>
                      setArticleForm((current) => ({ ...current, coverImageUrl: event.target.value }))
                    }
                  />
                </div>
                <div className="space-y-2">
                  <Label>Conteudo</Label>
                  <RichTextEditor
                    value={articleForm.contentHtml}
                    onChange={(contentHtml) => setArticleForm((current) => ({ ...current, contentHtml }))}
                  />
                </div>
                <Button onClick={() => void handleSaveArticle()} disabled={saveArticle.isPending}>
                  {saveArticle.isPending ? 'Salvando...' : 'Salvar artigo'}
                </Button>
              </div>
            </Card>
          </div>
        </TabsContent>

        <TabsContent value="settings">
          <Card>
            <CardTitle>Landing page</CardTitle>
            <CardDescription className="mt-2">
              Configure o video da abertura e a mensagem principal da home.
            </CardDescription>
            <div className="mt-5 grid gap-4">
              <div className="space-y-2">
                <Label>URL do video hero</Label>
                <Input
                  value={settingsForm.heroVideoUrl}
                  onChange={(event) =>
                    setSettingsForm((current) => (current ? { ...current, heroVideoUrl: event.target.value } : current))
                  }
                />
              </div>
              <div className="space-y-2">
                <Label>Poster do video</Label>
                <Input
                  value={settingsForm.heroPosterUrl}
                  onChange={(event) =>
                    setSettingsForm((current) =>
                      current ? { ...current, heroPosterUrl: event.target.value } : current,
                    )
                  }
                />
              </div>
              <div className="space-y-2">
                <Label>Texto principal</Label>
                <Textarea
                  value={settingsForm.homeLead}
                  onChange={(event) =>
                    setSettingsForm((current) => (current ? { ...current, homeLead: event.target.value } : current))
                  }
                />
              </div>
              <Separator />
              <Button onClick={() => void handleSaveSettings()} disabled={saveSettings.isPending}>
                {saveSettings.isPending ? 'Salvando...' : 'Salvar configuracoes'}
              </Button>
            </div>
          </Card>
        </TabsContent>
      </Tabs>
    </section>
  )
}
