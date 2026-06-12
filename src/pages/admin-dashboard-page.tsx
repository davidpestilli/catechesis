import { useEffect, useMemo, useState, type ReactNode } from 'react'
import { ArrowDown, ArrowUp, ImagePlus, Plus, Trash2 } from 'lucide-react'
import { toast } from 'sonner'
import { DiversosPanel } from '@/components/admin/diversos-panel'
import { RichTextEditor } from '@/components/editor/rich-text-editor'
import { Button } from '@/components/ui/button'
import { Card, CardDescription, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Textarea } from '@/components/ui/textarea'
import {
  useCMSState,
  useSaveAsset,
  useSaveEncounter,
  useSaveGroup,
  useSaveQuiz,
  useSaveSettings,
} from '@/hooks/use-cms'
import { cmsService } from '@/services/cms-service'
import { materialCategoryConfigs } from '@/lib/encounter-materials'
import { cn, createId, fileToDataUrl, slugify } from '@/lib/utils'
import type {
  ClassGroup,
  Encounter,
  EncounterAsset,
  EncounterQuiz,
  LandingImageMotion,
  MaterialCategory,
  SiteSettings,
} from '@/types/content'

const adminSelectClassName =
  'h-11 w-full rounded-2xl border border-input bg-white/90 px-4 text-sm text-stone-900 outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/20'
const landingMotionOptions: { value: LandingImageMotion; label: string }[] = [
  { value: 'drift-a', label: 'Movimento A' },
  { value: 'drift-b', label: 'Movimento B' },
  { value: 'drift-c', label: 'Movimento C' },
]

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

function AdminField({
  label,
  hint,
  children,
  className,
}: {
  label: string
  hint?: string
  children: ReactNode
  className?: string
}) {
  return (
    <div className={cn('space-y-2.5', className)}>
      <div className="space-y-1">
        <Label>{label}</Label>
        {hint ? <p className="text-sm leading-5 text-stone-500">{hint}</p> : null}
      </div>
      {children}
    </div>
  )
}

function emptyGroup(): ClassGroup {
  return {
    id: createId(),
    slug: '',
    name: '',
    battleCry: '',
    coverImageUrl: '',
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

function emptyLandingSlide() {
  return {
    id: createId(),
    src: '',
    alt: '',
    motion: 'drift-a' as LandingImageMotion,
  }
}

export function AdminDashboardPage() {
  const { data } = useCMSState()
  const saveGroup = useSaveGroup()
  const saveEncounter = useSaveEncounter()
  const saveAsset = useSaveAsset()
  const saveQuiz = useSaveQuiz()
  const saveSettings = useSaveSettings()

  const [groupForm, setGroupForm] = useState<ClassGroup>(emptyGroup())
  const [encounterForm, setEncounterForm] = useState<Encounter>(emptyEncounter())
  const [quizForm, setQuizForm] = useState<EncounterQuiz>(emptyQuiz())
  const [settingsForm, setSettingsForm] = useState<SiteSettings | null>(null)
  const [assetForm, setAssetForm] = useState<EncounterAsset>({
    id: createId(),
    encounterId: '',
    title: '',
    description: '',
    kind: 'support',
    view: 'link',
    url: '',
    materialCategory: 'website',
    downloadable: false,
    order: 1,
  })
  const [assetFile, setAssetFile] = useState<File | null>(null)
  const [pendingSlideFiles, setPendingSlideFiles] = useState<Record<string, { file: File; previewUrl: string }>>({})

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
      slug: slugify(encounterForm.title),
    })
    setEncounterForm(emptyEncounter(groupOptions[0]?.id ?? ''))
    toast.success('Encontro salvo.')
  }

  async function handleSaveAsset() {
    await saveAsset.mutateAsync({
      asset: assetForm,
      file: assetForm.kind === 'support' ? null : assetFile,
    })
    setAssetFile(null)
    setAssetForm({
      id: createId(),
      encounterId: encounterOptions[0]?.id ?? '',
      title: '',
      description: '',
      kind: 'support',
      view: 'link',
      url: '',
      materialCategory: 'website',
      downloadable: false,
      order: 1,
    })
    toast.success('Material salvo.')
  }

  async function handleSaveQuiz() {
    await saveQuiz.mutateAsync(quizForm)
    setQuizForm(emptyQuiz(encounterOptions[0]?.id ?? ''))
    toast.success('Quiz salvo.')
  }

  async function handleSelectSlideFile(slideId: string, file?: File | null) {
    if (!file) {
      setPendingSlideFiles((current) => {
        const next = { ...current }
        delete next[slideId]
        return next
      })
      return
    }

    const previewUrl = await fileToDataUrl(file)
    setPendingSlideFiles((current) => ({
      ...current,
      [slideId]: { file, previewUrl },
    }))
  }

  function updateLandingSlide(
    slideId: string,
    patch: Partial<SiteSettings['landingImages'][number]>,
  ) {
    setSettingsForm((current) =>
      current
        ? {
            ...current,
            landingImages: current.landingImages.map((slide) =>
              slide.id === slideId ? { ...slide, ...patch } : slide,
            ),
          }
        : current,
    )
  }

  function addLandingSlide() {
    setSettingsForm((current) =>
      current
        ? {
            ...current,
            landingImages: [...current.landingImages, emptyLandingSlide()],
          }
        : current,
    )
  }

  function removeLandingSlide(slideId: string) {
    setSettingsForm((current) =>
      current
        ? {
            ...current,
            landingImages: current.landingImages.filter((slide) => slide.id !== slideId),
          }
        : current,
    )
    setPendingSlideFiles((current) => {
      const next = { ...current }
      delete next[slideId]
      return next
    })
  }

  function moveLandingSlide(slideId: string, direction: -1 | 1) {
    setSettingsForm((current) => {
      if (!current) return current

      const index = current.landingImages.findIndex((slide) => slide.id === slideId)
      const nextIndex = index + direction

      if (index < 0 || nextIndex < 0 || nextIndex >= current.landingImages.length) {
        return current
      }

      const nextSlides = [...current.landingImages]
      const [slide] = nextSlides.splice(index, 1)
      nextSlides.splice(nextIndex, 0, slide)

      return {
        ...current,
        landingImages: nextSlides,
      }
    })
  }

  async function handleSaveSlideshow() {
    const currentSettings = settingsForm
    if (!currentSettings) return

    const uploadedSlides = await Promise.all(
      currentSettings.landingImages.map(async (slide) => {
        const pendingFile = pendingSlideFiles[slide.id]
        if (!pendingFile) return slide

        const src = await cmsService.uploadMedia(pendingFile.file, 'landing')
        return { ...slide, src }
      }),
    )

    const nextSettings: SiteSettings = {
      ...currentSettings,
      landingImages: uploadedSlides.filter((slide) => slide.src.trim().length > 0),
    }

    await saveSettings.mutateAsync(nextSettings)
    setSettingsForm(nextSettings)
    setPendingSlideFiles({})
    toast.success('Slideshow atualizado.')
  }

  const isSupportLink = assetForm.kind === 'support'

  return (
    <section className="mx-auto max-w-7xl px-4 py-8 pb-12 md:py-10">
      <div className="mb-8 flex flex-wrap items-start justify-between gap-4">
        <div className="max-w-2xl">
          <p className="text-sm font-bold uppercase tracking-[0.22em] text-stone-500">
            gestao de conteudo
          </p>
        </div>
      </div>

      <Tabs defaultValue="groups" className="space-y-6">
        <TabsList className="max-w-full flex-nowrap overflow-x-auto rounded-[24px] border border-stone-200/80 bg-white/80 p-1.5 shadow-[0_16px_40px_rgba(74,61,35,0.08)]">
          <TabsTrigger className="shrink-0" value="groups">Turmas</TabsTrigger>
          <TabsTrigger className="shrink-0" value="encounters">Encontros</TabsTrigger>
          <TabsTrigger className="shrink-0" value="assets">Materiais</TabsTrigger>
          <TabsTrigger className="shrink-0" value="quizzes">Quizzes</TabsTrigger>
          <TabsTrigger className="shrink-0" value="slideshow">Slideshow</TabsTrigger>
          <TabsTrigger className="shrink-0" value="misc">Diversos</TabsTrigger>
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
                <div className="grid gap-4 lg:grid-cols-[1.3fr_0.7fr]">
                  <div className="space-y-2">
                    <Label>Imagem da turma</Label>
                    <Input
                      value={groupForm.coverImageUrl ?? ''}
                      onChange={(event) =>
                        setGroupForm((current) => ({
                          ...current,
                          coverImageUrl: event.target.value,
                        }))
                      }
                      placeholder="https://..."
                    />
                  </div>

                  <div className="rounded-[22px] border border-dashed border-stone-300 bg-white/75 p-3">
                    <p className="text-xs font-semibold uppercase tracking-[0.18em] text-stone-500">
                      Preview da imagem
                    </p>
                    {groupForm.coverImageUrl ? (
                      <img
                        src={groupForm.coverImageUrl}
                        alt="Preview da imagem da turma"
                        className="mt-3 aspect-[4/3] w-full rounded-[18px] object-cover"
                      />
                    ) : (
                      <div className="mt-3 flex aspect-[4/3] items-center justify-center rounded-[18px] bg-stone-100 px-4 text-center text-sm text-stone-500">
                        Cole a URL da imagem para revisar a capa da turma aqui.
                      </div>
                    )}
                  </div>
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
                  description="Defina a turma, o titulo e o tema do encontro. O link interno e gerado automaticamente a partir do titulo."
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
                    <Label>Tema</Label>
                    <Input
                      value={encounterForm.theme}
                      onChange={(event) =>
                        setEncounterForm((current) => ({ ...current, theme: event.target.value }))
                      }
                    />
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
                  title="Resumo do encontro em HTML"
                  description="Este e o mesmo editor rico usado em Artigos. O texto salvo aqui abre no modal publico de Resumo do encontro."
                >
                  <div className="space-y-2">
                    <Label>Texto HTML do resumo</Label>
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
                      <div className="flex flex-wrap items-center gap-2">
                        <p className="font-semibold text-stone-900">{asset.title}</p>
                        {asset.kind === 'support' && asset.materialCategory ? (
                          <span className="rounded-full bg-primary/10 px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-primary">
                            {materialCategoryConfigs.find((category) => category.key === asset.materialCategory)?.label ?? asset.materialCategory}
                          </span>
                        ) : null}
                      </div>
                      <p className="mt-1 text-sm text-stone-600">
                        {(groupNameById.get(encounter.groupId) || 'Turma') + ' / ' + encounter.title}
                      </p>
                      {asset.description ? (
                        <p className="mt-2 text-sm leading-6 text-stone-500">{asset.description}</p>
                      ) : null}
                    </div>
                  )),
                )}
              </div>
            </Card>
            <Card>
              <CardTitle>Materiais e downloads</CardTitle>
              <CardDescription className="mt-2">
                Cadastre links por categoria para o modal publico de Materiais ou um arquivo opcional para download do resumo.
              </CardDescription>
              <div className="mt-6 space-y-5">
                <div className="rounded-[22px] border border-primary/15 bg-primary/5 p-4 text-sm leading-6 text-stone-700">
                  <p className="font-semibold text-stone-900">Como este bloco funciona</p>
                  <p className="mt-1">
                    O resumo em HTML continua na aba <strong>Encontros</strong>. Aqui voce escolhe entre um arquivo de resumo para download ou links que aparecerao no modal <strong>Materiais</strong>.
                  </p>
                </div>
                <AdminFormSection
                  title="Vinculo do material"
                  description="Primeiro escolha o encontro e o tipo de item para o sistema liberar apenas os campos relevantes."
                >
                  <div className="grid gap-5 xl:grid-cols-[1.15fr_0.85fr]">
                    <AdminField
                      label="Encontro"
                      hint="O material sera exibido somente dentro deste encontro."
                    >
                      <select
                        value={assetForm.encounterId}
                        onChange={(event) =>
                          setAssetForm((current) => ({ ...current, encounterId: event.target.value }))
                        }
                        className={adminSelectClassName}
                      >
                        {encounterOptions.map((encounter) => (
                          <option key={encounter.id} value={encounter.id}>
                            {(groupNameById.get(encounter.groupId) || 'Turma') + ' / ' + encounter.title}
                          </option>
                        ))}
                      </select>
                    </AdminField>

                    <AdminField
                      label="Tipo"
                      hint="Escolha se este item abre no modal Materiais ou vira um arquivo de download."
                    >
                      <select
                        value={assetForm.kind}
                        onChange={(event) => {
                          const nextKind = event.target.value as EncounterAsset['kind']
                          setAssetFile(null)
                          setAssetForm((current) => ({
                            ...current,
                            kind: nextKind,
                            view: nextKind === 'support' ? 'link' : 'pdf',
                            materialCategory: nextKind === 'support' ? current.materialCategory ?? 'website' : undefined,
                            downloadable: nextKind === 'support' ? false : true,
                          }))
                        }}
                        className={adminSelectClassName}
                      >
                        <option value="summary">Arquivo para download do resumo</option>
                        <option value="support">Link para o modal Materiais</option>
                      </select>
                    </AdminField>
                  </div>
                </AdminFormSection>

                <AdminFormSection
                  title="Conteudo e exibicao"
                  description="Defina o titulo, a categoria visual do material e os textos de apoio com mais espaco para leitura."
                >
                  <div className="grid gap-5 md:grid-cols-2">
                    <AdminField
                      label="Titulo"
                      hint={isSupportLink ? 'Este nome aparece no card do modal publico.' : 'Use um nome claro para o download.'}
                    >
                      <Input
                        value={assetForm.title}
                        onChange={(event) => setAssetForm((current) => ({ ...current, title: event.target.value }))}
                        placeholder={isSupportLink ? 'Nome exibido para o link' : 'Nome do arquivo para o usuario'}
                      />
                    </AdminField>

                    {isSupportLink ? (
                      <AdminField
                        label="Campo do modal Materiais"
                        hint="Organiza o link no grupo correto dentro do modal."
                      >
                        <select
                          value={assetForm.materialCategory ?? 'website'}
                          onChange={(event) =>
                            setAssetForm((current) => ({
                              ...current,
                              materialCategory: event.target.value as MaterialCategory,
                            }))
                          }
                          className={adminSelectClassName}
                        >
                          {materialCategoryConfigs.map((category) => (
                            <option key={category.key} value={category.key}>
                              {category.label}
                            </option>
                          ))}
                        </select>
                      </AdminField>
                    ) : (
                      <AdminField
                        label="Arquivo"
                        hint="Envie o arquivo que ficara disponivel para download neste encontro."
                      >
                        <Input type="file" onChange={(event) => setAssetFile(event.target.files?.[0] ?? null)} />
                      </AdminField>
                    )}
                  </div>

                  <div className="grid gap-5 xl:grid-cols-2">
                    <AdminField
                      label={isSupportLink ? 'Weblink' : 'URL do arquivo'}
                      hint={
                        isSupportLink
                          ? 'Cole a URL completa do site, video ou documento externo.'
                          : 'Preencha apenas se quiser registrar uma URL manualmente em vez de enviar um arquivo.'
                      }
                    >
                      <Textarea
                        className="min-h-[132px]"
                        value={assetForm.url}
                        onChange={(event) => setAssetForm((current) => ({ ...current, url: event.target.value }))}
                        placeholder={isSupportLink ? 'https://...' : 'https://...'}
                      />
                    </AdminField>

                    <AdminField
                      label="Descricao"
                      hint="Um texto curto ajuda a pessoa a entender por que vale abrir este material."
                    >
                      <Textarea
                        className="min-h-[132px]"
                        value={assetForm.description}
                        onChange={(event) =>
                          setAssetForm((current) => ({ ...current, description: event.target.value }))
                        }
                        placeholder={
                          isSupportLink
                            ? 'Explique rapidamente por que este link vale a consulta.'
                            : 'Descreva o arquivo de download.'
                        }
                      />
                    </AdminField>
                  </div>
                </AdminFormSection>

                <div className="sticky bottom-4 z-20">
                  <div className="flex flex-col gap-3 rounded-[24px] border border-stone-200/80 bg-white/92 p-3 shadow-[0_18px_42px_rgba(74,61,35,0.12)] backdrop-blur md:flex-row md:items-center md:justify-between">
                    <div>
                      <p className="text-sm font-semibold text-stone-800">
                        {isSupportLink ? 'Pronto para salvar o link do modal Materiais.' : 'Pronto para salvar o arquivo de download.'}
                      </p>
                      <p className="text-xs text-stone-500">
                        Revise encontro, tipo, titulo e descricao antes de publicar.
                      </p>
                    </div>
                    <Button
                      className="w-full md:w-auto"
                      onClick={() => void handleSaveAsset()}
                      disabled={saveAsset.isPending || !assetForm.encounterId}
                    >
                      {saveAsset.isPending ? 'Salvando...' : 'Salvar material'}
                    </Button>
                  </div>
                </div>
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

        <TabsContent value="slideshow">
          <Card>
            <CardTitle>Imagens do slideshow</CardTitle>
            <CardDescription className="mt-2">
              Administre as imagens da abertura da home sem mexer em codigo. A ordem aqui e a ordem exibida no banner.
            </CardDescription>
            <div className="mt-6 space-y-5">
              <div className="rounded-[22px] border border-primary/15 bg-primary/5 p-4 text-sm leading-6 text-stone-700">
                <p className="font-semibold text-stone-900">Como este bloco funciona</p>
                <p className="mt-1">
                  Voce pode enviar uma nova imagem, colar uma URL publica, ajustar o texto alternativo e escolher o movimento de cada slide. Se a lista ficar vazia, a home volta a usar o conjunto padrao do projeto.
                </p>
              </div>

              {settingsForm.landingImages.length > 0 ? (
                <div className="space-y-4">
                  {settingsForm.landingImages.map((slide, index) => {
                    const previewUrl = pendingSlideFiles[slide.id]?.previewUrl ?? slide.src

                    return (
                      <div
                        key={slide.id}
                        className="rounded-[28px] border border-stone-200 bg-stone-50/80 p-4 md:p-5"
                      >
                        <div className="flex flex-wrap items-center justify-between gap-3">
                          <div>
                            <p className="text-sm font-semibold text-stone-900">Slide {index + 1}</p>
                            <p className="text-sm text-stone-500">
                              {previewUrl ? 'Imagem pronta para o banner.' : 'Defina uma URL ou envie uma imagem.'}
                            </p>
                          </div>
                          <div className="flex flex-wrap items-center gap-2">
                            <Button
                              type="button"
                              variant="outline"
                              size="sm"
                              onClick={() => moveLandingSlide(slide.id, -1)}
                              disabled={index === 0}
                            >
                              <ArrowUp className="mr-2 h-4 w-4" />
                              Subir
                            </Button>
                            <Button
                              type="button"
                              variant="outline"
                              size="sm"
                              onClick={() => moveLandingSlide(slide.id, 1)}
                              disabled={index === settingsForm.landingImages.length - 1}
                            >
                              <ArrowDown className="mr-2 h-4 w-4" />
                              Descer
                            </Button>
                            <Button
                              type="button"
                              variant="ghost"
                              size="sm"
                              onClick={() => removeLandingSlide(slide.id)}
                            >
                              <Trash2 className="mr-2 h-4 w-4" />
                              Remover
                            </Button>
                          </div>
                        </div>

                        <div className="mt-4 grid gap-5 lg:grid-cols-[0.72fr_1.28fr]">
                          <div className="rounded-[22px] border border-dashed border-stone-300 bg-white/80 p-3">
                            <p className="text-xs font-semibold uppercase tracking-[0.18em] text-stone-500">
                              Preview do slide
                            </p>
                            {previewUrl ? (
                              <img
                                src={previewUrl}
                                alt={slide.alt || `Preview do slide ${index + 1}`}
                                className="mt-3 aspect-[4/5] w-full rounded-[18px] object-cover"
                              />
                            ) : (
                              <div className="mt-3 flex aspect-[4/5] items-center justify-center rounded-[18px] bg-stone-100 px-4 text-center text-sm text-stone-500">
                                Envie uma imagem ou cole a URL para visualizar o slide.
                              </div>
                            )}
                          </div>

                          <div className="space-y-5">
                            <AdminFormSection
                              title="Imagem"
                              description="Use uma URL publica ou envie um arquivo diretamente para substituir este slide."
                            >
                              <AdminField
                                label="URL da imagem"
                                hint="Se voce preencher uma URL e tambem enviar um arquivo, o arquivo enviado sera usado no salvamento."
                              >
                                <Input
                                  value={slide.src}
                                  onChange={(event) =>
                                    updateLandingSlide(slide.id, { src: event.target.value })
                                  }
                                  placeholder="https://..."
                                />
                              </AdminField>

                              <AdminField
                                label="Arquivo"
                                hint="Aceita imagens locais para upload direto ao salvar o slideshow."
                              >
                                <Input
                                  type="file"
                                  accept="image/*"
                                  onChange={(event) =>
                                    void handleSelectSlideFile(slide.id, event.target.files?.[0] ?? null)
                                  }
                                />
                                {pendingSlideFiles[slide.id] ? (
                                  <p className="text-xs text-stone-500">
                                    Nova imagem selecionada. Ela sera enviada quando voce clicar em salvar.
                                  </p>
                                ) : null}
                              </AdminField>
                            </AdminFormSection>

                            <div className="grid gap-5 md:grid-cols-[1.2fr_0.8fr]">
                              <AdminField
                                label="Texto alternativo"
                                hint="Descreva a imagem para acessibilidade e contexto."
                              >
                                <Textarea
                                  className="min-h-[112px]"
                                  value={slide.alt}
                                  onChange={(event) =>
                                    updateLandingSlide(slide.id, { alt: event.target.value })
                                  }
                                  placeholder="Descreva brevemente a cena exibida neste slide."
                                />
                              </AdminField>

                              <AdminField
                                label="Movimento"
                                hint="Controla o tipo de deslocamento suave aplicado no banner."
                              >
                                <select
                                  value={slide.motion}
                                  onChange={(event) =>
                                    updateLandingSlide(slide.id, {
                                      motion: event.target.value as LandingImageMotion,
                                    })
                                  }
                                  className={adminSelectClassName}
                                >
                                  {landingMotionOptions.map((option) => (
                                    <option key={option.value} value={option.value}>
                                      {option.label}
                                    </option>
                                  ))}
                                </select>
                              </AdminField>
                            </div>
                          </div>
                        </div>
                      </div>
                    )
                  })}
                </div>
              ) : (
                <div className="rounded-[24px] border border-dashed border-stone-300 bg-white/70 p-6 text-sm leading-6 text-stone-600">
                  Nenhum slide personalizado foi salvo. Ao adicionar e salvar pelo menos uma imagem aqui, a home passa a usar esta lista no lugar do conjunto padrao.
                </div>
              )}

              <Button type="button" variant="outline" onClick={addLandingSlide}>
                <Plus className="mr-2 h-4 w-4" />
                Adicionar slide
              </Button>

              <div className="sticky bottom-4 z-20">
                <div className="flex flex-col gap-3 rounded-[24px] border border-stone-200/80 bg-white/92 p-3 shadow-[0_18px_42px_rgba(74,61,35,0.12)] backdrop-blur md:flex-row md:items-center md:justify-between">
                  <div>
                    <p className="text-sm font-semibold text-stone-800">
                      {settingsForm.landingImages.length > 0
                        ? 'Pronto para atualizar o slideshow da home.'
                        : 'Sem slides personalizados. O fallback padrao sera mantido.'}
                    </p>
                    <p className="text-xs text-stone-500">
                      Salve para publicar a ordem, os textos alternativos e as novas imagens enviadas.
                    </p>
                  </div>
                  <Button
                    className="w-full md:w-auto"
                    onClick={() => void handleSaveSlideshow()}
                    disabled={saveSettings.isPending}
                  >
                    <ImagePlus className="mr-2 h-4 w-4" />
                    {saveSettings.isPending ? 'Salvando...' : 'Salvar slideshow'}
                  </Button>
                </div>
              </div>
            </div>
          </Card>
        </TabsContent>

        <TabsContent value="misc">
          <DiversosPanel />
        </TabsContent>

      </Tabs>
    </section>
  )
}
