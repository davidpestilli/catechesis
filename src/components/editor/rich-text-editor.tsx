import { useEffect, useMemo, useRef, useState } from 'react'
import {
  AlignCenter,
  AlignJustify,
  AlignLeft,
  AlignRight,
  Bold,
  Eraser,
  ImagePlus,
  Italic,
  Link2,
  List,
  ListOrdered,
  Palette,
  Quote,
  Type,
  Underline,
  Video,
} from 'lucide-react'
import { cn, fileToDataUrl } from '@/lib/utils'

interface RichTextEditorProps {
  value: string
  onChange: (value: string) => void
  placeholder?: string
  className?: string
}

type TextAlignment = 'left' | 'center' | 'right' | 'justify'

interface ToolbarState {
  isBold: boolean
  isItalic: boolean
  isUnderline: boolean
  isBulletList: boolean
  isOrderedList: boolean
  isLink: boolean
  isBlockquote: boolean
  hasCustomColor: boolean
  currentFont: string
  currentHeading: string
  currentColor: string
  currentAlignment: TextAlignment
}

const fonts = [
  { label: 'Cormorant', value: '"Cormorant Garamond", serif' },
  { label: 'Fraunces', value: '"Fraunces", serif' },
  { label: 'Georgia', value: 'Georgia, serif' },
  { label: 'Arial', value: 'Arial, sans-serif' },
]

const headings = [
  { label: 'Paragrafo', value: 'p' },
  { label: 'Titulo 1', value: 'h1' },
  { label: 'Titulo 2', value: 'h2' },
  { label: 'Titulo 3', value: 'h3' },
]

const fallbackTextColor = '#292524'

const defaultToolbarState: ToolbarState = {
  isBold: false,
  isItalic: false,
  isUnderline: false,
  isBulletList: false,
  isOrderedList: false,
  isLink: false,
  isBlockquote: false,
  hasCustomColor: false,
  currentFont: fonts[0]?.value ?? 'inherit',
  currentHeading: 'p',
  currentColor: fallbackTextColor,
  currentAlignment: 'justify',
}

function getElementFromNode(node: Node | null) {
  if (!node) return null
  return node.nodeType === Node.ELEMENT_NODE ? (node as Element) : node.parentElement
}

function normalizeTagName(value: string) {
  return value.replace(/[<>]/g, '').trim().toLowerCase()
}

function hexFromRgbString(value: string) {
  const rgbMatch = value.match(/\d+/g)
  if (!rgbMatch || rgbMatch.length < 3) return null

  return `#${rgbMatch
    .slice(0, 3)
    .map((channel) => Number(channel).toString(16).padStart(2, '0'))
    .join('')}`.toLowerCase()
}

function normalizeColorValue(value: string | null | undefined) {
  if (!value) return null

  const trimmed = value.trim().toLowerCase()

  if (!trimmed) return null
  if (trimmed.startsWith('#')) {
    if (trimmed.length === 4) {
      return `#${trimmed
        .slice(1)
        .split('')
        .map((character) => character + character)
        .join('')}`
    }

    return trimmed
  }

  if (trimmed.startsWith('rgb')) {
    return hexFromRgbString(trimmed)
  }

  return null
}

function findClosestWithinEditor(element: Element | null, editor: HTMLDivElement, selector: string) {
  if (!element) return null

  const matched = element.closest(selector)
  return matched && editor.contains(matched) ? matched : null
}

function matchFontValue(fontFamily: string) {
  const normalizedFont = fontFamily.replace(/["']/g, '').toLowerCase()

  return (
    fonts.find((font) => {
      const fontTokens = font.value
        .split(',')
        .map((token) => token.replace(/["']/g, '').trim().toLowerCase())
        .filter(Boolean)

      return fontTokens.some((token) => normalizedFont.includes(token))
    })?.value ?? fonts[0]?.value ?? 'inherit'
  )
}

function normalizeTextAlignment(value: string | null | undefined): TextAlignment {
  const normalizedValue = value?.trim().toLowerCase() ?? ''

  if (normalizedValue === 'center') return 'center'
  if (normalizedValue === 'right' || normalizedValue === 'end') return 'right'
  if (normalizedValue === 'justify') return 'justify'
  return 'left'
}

export function RichTextEditor({
  value,
  onChange,
  placeholder = 'Digite ou cole o conteudo aqui...',
  className,
}: RichTextEditorProps) {
  const editorRef = useRef<HTMLDivElement>(null)
  const imageInputRef = useRef<HTMLInputElement>(null)
  const videoInputRef = useRef<HTMLInputElement>(null)
  const selectionRangeRef = useRef<Range | null>(null)
  const [mounted, setMounted] = useState(false)
  const [toolbarState, setToolbarState] = useState<ToolbarState>(defaultToolbarState)

  useEffect(() => {
    setMounted(true)
  }, [])

  useEffect(() => {
    if (!mounted || !editorRef.current) return
    if (editorRef.current.innerHTML !== value) {
      editorRef.current.innerHTML = value
    }

    window.requestAnimationFrame(() => {
      syncToolbarState()
    })
  }, [mounted, value])

  useEffect(() => {
    if (!mounted) return

    const handleSelectionChange = () => {
      persistSelection()
      syncToolbarState()
    }

    document.addEventListener('selectionchange', handleSelectionChange)

    return () => {
      document.removeEventListener('selectionchange', handleSelectionChange)
    }
  }, [mounted])

  function getDefaultTextColor() {
    if (!editorRef.current) return fallbackTextColor

    return normalizeColorValue(window.getComputedStyle(editorRef.current).color) ?? fallbackTextColor
  }

  function getSelection() {
    return window.getSelection()
  }

  function isSelectionInsideEditor(selection = getSelection()) {
    if (!selection || selection.rangeCount === 0 || !editorRef.current) return false

    const range = selection.getRangeAt(0)
    const target =
      range.commonAncestorContainer.nodeType === Node.TEXT_NODE
        ? range.commonAncestorContainer.parentNode
        : range.commonAncestorContainer

    return !!target && editorRef.current.contains(target)
  }

  function persistSelection(selection = getSelection()) {
    if (!selection || selection.rangeCount === 0 || !isSelectionInsideEditor(selection)) return
    selectionRangeRef.current = selection.getRangeAt(0).cloneRange()
  }

  function restoreSelection() {
    if (!selectionRangeRef.current) return

    const selection = getSelection()
    if (!selection) return

    selection.removeAllRanges()
    selection.addRange(selectionRangeRef.current)
  }

  function syncToolbarState(selection = getSelection()) {
    if (!editorRef.current || !selection || !selection.rangeCount || !isSelectionInsideEditor(selection)) {
      return
    }

    const editor = editorRef.current
    const anchorElement = getElementFromNode(selection.anchorNode)
    const blockElement = findClosestWithinEditor(anchorElement, editor, 'h1, h2, h3, p, ul, ol, blockquote, div')
    const closestLink = findClosestWithinEditor(anchorElement, editor, 'a')
    const closestBlockquote = findClosestWithinEditor(anchorElement, editor, 'blockquote')
    const closestBulletList = findClosestWithinEditor(anchorElement, editor, 'ul')
    const closestOrderedList = findClosestWithinEditor(anchorElement, editor, 'ol')
    const explicitColor =
      normalizeColorValue(
        anchorElement?.closest('[style*="color"], font[color]') instanceof HTMLElement
          ? (
              anchorElement.closest('[style*="color"], font[color]') as HTMLElement
            ).style.color ||
            anchorElement.closest('font[color]')?.getAttribute('color')
          : anchorElement?.closest('font[color]')?.getAttribute('color'),
      ) ?? null

    const effectiveColor =
      explicitColor ??
      normalizeColorValue(document.queryCommandValue('foreColor')) ??
      normalizeColorValue(anchorElement ? window.getComputedStyle(anchorElement).color : null) ??
      getDefaultTextColor()

    const effectiveFont =
      anchorElement?.closest('[style*="font-family"], font[face]') instanceof HTMLElement
        ? (
            anchorElement.closest('[style*="font-family"], font[face]') as HTMLElement
          ).style.fontFamily ||
          anchorElement.closest('font[face]')?.getAttribute('face') ||
          window.getComputedStyle(anchorElement).fontFamily
        : anchorElement
          ? window.getComputedStyle(anchorElement).fontFamily
          : fonts[0]?.value

    const blockTextAlign = window.getComputedStyle(blockElement ?? editor).textAlign
    const effectiveAlignment = normalizeTextAlignment(
      blockTextAlign === 'start' ? window.getComputedStyle(editor).textAlign : blockTextAlign,
    )
    const currentHeading = normalizeTagName(blockElement?.tagName ?? 'p')

    setToolbarState({
      isBold: document.queryCommandState('bold'),
      isItalic: document.queryCommandState('italic'),
      isUnderline: document.queryCommandState('underline'),
      isBulletList: !!closestBulletList,
      isOrderedList: !!closestOrderedList,
      isLink: !!closestLink,
      isBlockquote: !!closestBlockquote,
      hasCustomColor: explicitColor !== null && explicitColor !== getDefaultTextColor(),
      currentFont: matchFontValue(effectiveFont ?? ''),
      currentHeading: headings.some((heading) => heading.value === currentHeading) ? currentHeading : 'p',
      currentColor: effectiveColor,
      currentAlignment: effectiveAlignment,
    })
  }

  function emitChange() {
    onChange(editorRef.current?.innerHTML ?? '')
  }

  function exec(command: string, commandValue?: string) {
    editorRef.current?.focus()
    restoreSelection()

    if (command === 'foreColor') {
      document.execCommand('styleWithCSS', false, 'true')
    }

    document.execCommand(command, false, commandValue)

    if (command === 'foreColor') {
      document.execCommand('styleWithCSS', false, 'false')
    }

    emitChange()

    window.requestAnimationFrame(() => {
      persistSelection()
      syncToolbarState()
    })
  }

  function applyBlockFormat(tagName: string) {
    exec('formatBlock', `<${tagName}>`)
  }

  async function handleFileInsert(file: File, tag: 'image' | 'video') {
    const dataUrl = await fileToDataUrl(file)
    editorRef.current?.focus()
    restoreSelection()

    const markup =
      tag === 'image'
        ? `<img alt="" class="my-4 mx-auto h-auto max-w-full rounded-[24px]" src="${dataUrl}" />`
        : `<video controls class="my-4 mx-auto w-full rounded-[24px]" src="${dataUrl}"></video>`

    document.execCommand('insertHTML', false, markup)
    emitChange()

    window.requestAnimationFrame(() => {
      persistSelection()
      syncToolbarState()
    })
  }

  const plainText = useMemo(
    () =>
      value
        .replace(/<[^>]+>/g, ' ')
        .replace(/\s+/g, ' ')
        .trim(),
    [value],
  )

  const toolbarButtons = useMemo(
    () => [
      { icon: Bold, label: 'Negrito', active: toolbarState.isBold, action: () => exec('bold') },
      { icon: Italic, label: 'Italico', active: toolbarState.isItalic, action: () => exec('italic') },
      {
        icon: Underline,
        label: 'Sublinhado',
        active: toolbarState.isUnderline,
        action: () => exec('underline'),
      },
      {
        icon: Quote,
        label: 'Citacao',
        active: toolbarState.isBlockquote,
        action: () => applyBlockFormat(toolbarState.isBlockquote ? 'p' : 'blockquote'),
      },
      {
        icon: List,
        label: 'Lista',
        active: toolbarState.isBulletList,
        action: () => exec('insertUnorderedList'),
      },
      {
        icon: ListOrdered,
        label: 'Lista numerada',
        active: toolbarState.isOrderedList,
        action: () => exec('insertOrderedList'),
      },
      {
        icon: Link2,
        label: 'Link',
        active: toolbarState.isLink,
        action: () => {
          const selection = getSelection()
          const currentLink =
            getElementFromNode(selection ? selection.anchorNode : null)?.closest('a')?.getAttribute('href') ?? ''
          const url = window.prompt('Informe a URL do link:', currentLink)
          if (url) exec('createLink', url)
        },
      },
      {
        icon: AlignLeft,
        label: 'Alinhar a esquerda',
        active: toolbarState.currentAlignment === 'left',
        action: () => exec('justifyLeft'),
      },
      {
        icon: AlignCenter,
        label: 'Centralizar',
        active: toolbarState.currentAlignment === 'center',
        action: () => exec('justifyCenter'),
      },
      {
        icon: AlignRight,
        label: 'Alinhar a direita',
        active: toolbarState.currentAlignment === 'right',
        action: () => exec('justifyRight'),
      },
      {
        icon: AlignJustify,
        label: 'Justificar',
        active: toolbarState.currentAlignment === 'justify',
        action: () => exec('justifyFull'),
      },
      { icon: ImagePlus, label: 'Imagem', active: false, action: () => imageInputRef.current?.click() },
      { icon: Video, label: 'Video', active: false, action: () => videoInputRef.current?.click() },
    ],
    [toolbarState],
  )

  return (
    <div
      className={cn(
        'overflow-hidden rounded-[28px] border border-stone-200/80 bg-[linear-gradient(180deg,rgba(255,255,255,0.96),rgba(246,241,230,0.92))] text-stone-800 shadow-[0_18px_45px_rgba(74,61,35,0.09)] transition focus-within:border-primary/30 focus-within:ring-4 focus-within:ring-primary/10',
        className,
      )}
    >
      <div className="border-b border-stone-200/90 bg-stone-50/80 px-3 py-3 md:px-4">
        <div className="grid gap-3">
          <div className="grid gap-2 sm:grid-cols-2 xl:flex xl:flex-wrap xl:items-center">
            <select
              className="h-11 rounded-2xl border border-stone-200 bg-white px-4 text-sm text-stone-700 outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/20"
              onChange={(event) => {
                exec('fontName', event.target.value)
              }}
              value={toolbarState.currentFont}
            >
              {fonts.map((font) => (
                <option key={font.value} value={font.value}>
                  {font.label}
                </option>
              ))}
            </select>

            <select
              className="h-11 rounded-2xl border border-stone-200 bg-white px-4 text-sm text-stone-700 outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/20"
              value={toolbarState.currentHeading}
              onChange={(event) => {
                applyBlockFormat(event.target.value)
              }}
            >
              {headings.map((heading) => (
                <option key={heading.value} value={heading.value}>
                  {heading.label}
                </option>
              ))}
            </select>
          </div>

          <div className="overflow-x-auto pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
            <div className="flex min-w-max flex-wrap gap-2">
              {toolbarButtons.map(({ icon: Icon, label, action, active }) => (
                <button
                  key={label}
                  type="button"
                  onMouseDown={(event) => event.preventDefault()}
                  onClick={action}
                  className={cn(
                    'inline-flex h-11 w-11 items-center justify-center rounded-2xl border shadow-sm transition',
                    active
                      ? 'border-primary bg-primary text-primary-foreground shadow-[0_10px_24px_rgba(49,92,67,0.2)]'
                      : 'border-stone-200 bg-white text-stone-600 hover:border-stone-300 hover:bg-stone-50 hover:text-stone-900',
                  )}
                  title={label}
                  aria-label={label}
                  aria-pressed={active}
                >
                  <Icon className="h-4 w-4" />
                </button>
              ))}

              <div
                className={cn(
                  'inline-flex h-11 items-center gap-2 rounded-2xl border px-3 shadow-sm transition',
                  toolbarState.hasCustomColor
                    ? 'border-primary bg-primary/10 text-primary'
                    : 'border-stone-200 bg-white text-stone-600',
                )}
                title="Cor do texto"
              >
                <Palette className="h-4 w-4" />
                <input
                  type="color"
                  aria-label="Cor do texto"
                  value={toolbarState.currentColor}
                  onChange={(event) => {
                    exec('foreColor', event.target.value)
                  }}
                  className="h-6 w-6 cursor-pointer rounded-full border-0 bg-transparent p-0"
                />
                <button
                  type="button"
                  onMouseDown={(event) => event.preventDefault()}
                  onClick={() => exec('foreColor', getDefaultTextColor())}
                  className="inline-flex h-7 w-7 items-center justify-center rounded-full text-stone-500 transition hover:bg-stone-100 hover:text-stone-900"
                  aria-label="Remover cor personalizada"
                  title="Remover cor personalizada"
                >
                  <Eraser className="h-3.5 w-3.5" />
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div className="bg-white">
        <div
          ref={editorRef}
          contentEditable
          suppressContentEditableWarning
          onInput={emitChange}
          onBlur={() => {
            persistSelection()
          }}
          onKeyUp={() => {
            persistSelection()
            syncToolbarState()
          }}
          onMouseUp={() => {
            persistSelection()
            syncToolbarState()
          }}
          className="rich-text-editor-content min-h-[260px] w-full px-4 py-4 text-[15px] leading-7 text-stone-800 outline-none md:min-h-[340px] md:px-5"
          data-placeholder={placeholder}
        />
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3 border-t border-stone-200 bg-stone-50/70 px-4 py-3 text-xs text-stone-500">
        <span className="inline-flex items-center gap-2 font-medium">
          <Type className="h-3.5 w-3.5" />
          HTML publicado no proprio sistema
        </span>
        <span>
          {plainText
            ? `${plainText.length} caracteres no conteudo`
            : 'Editor pronto para receber texto, imagens, video, citacoes e cor'}
        </span>
      </div>

      <input
        ref={imageInputRef}
        type="file"
        accept="image/*"
        className="hidden"
        onChange={async (event) => {
          const file = event.target.files?.[0]
          if (file) await handleFileInsert(file, 'image')
          event.target.value = ''
        }}
      />
      <input
        ref={videoInputRef}
        type="file"
        accept="video/*"
        className="hidden"
        onChange={async (event) => {
          const file = event.target.files?.[0]
          if (file) await handleFileInsert(file, 'video')
          event.target.value = ''
        }}
      />
    </div>
  )
}
