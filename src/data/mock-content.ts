import type { CMSState } from '@/types/content'
import { createId } from '@/lib/utils'

const groupOneId = createId()
const groupTwoId = createId()
const encounterOneId = createId()
const encounterTwoId = createId()
const quizOneId = createId()

export const defaultCMSState: CMSState = {
  settings: {
    heroVideoUrl:
      'https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4',
    heroPosterUrl:
      'https://images.unsplash.com/photo-1519494026892-80bbd2d6fd0d?auto=format&fit=crop&w=1200&q=80',
    homeLead: '',
  },
  groups: [
    {
      id: groupOneId,
      slug: 'turma-sao-pedro',
      name: 'Turma Sao Pedro',
      battleCry: 'Firmes na fe, alegres na missao.',
      order: 1,
    },
    {
      id: groupTwoId,
      slug: 'turma-sao-paulo',
      name: 'Turma Sao Paulo',
      battleCry: 'Anunciar, servir e caminhar juntos.',
      order: 2,
    },
  ],
  encounters: [
    {
      id: encounterOneId,
      groupId: groupOneId,
      slug: 'o-chamado-da-fe',
      title: 'O Chamado da Fe',
      illuminatedTitle: 'Encontros',
      summary:
        'Apresenta o primeiro encontro com foco no sentido da catequese, acolhida e caminhada em comunidade.',
      theme: 'Introducao a catequese',
      audience: 'Catequizandos iniciantes',
      order: 1,
      coverImageUrl:
        'https://images.unsplash.com/photo-1504052434569-70ad5836ab65?auto=format&fit=crop&w=1200&q=80',
      bodyHtml:
        '<h2>Boas-vindas</h2><p>Este encontro convida o grupo a reconhecer a fe como resposta viva ao amor de Deus, unindo escuta, oracao e convivio.</p><p>Use esta pagina como texto de apoio publicado no proprio sistema.</p>',
      assets: [
        {
          id: createId(),
          encounterId: encounterOneId,
          title: 'Resumo do Encontro',
          description: 'PDF com a estrutura principal do encontro.',
          kind: 'summary',
          view: 'pdf',
          url: 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
          downloadable: true,
          order: 1,
        },
        {
          id: createId(),
          encounterId: encounterOneId,
          title: 'Imagem de apoio',
          description: 'Imagem contemplativa para o momento de partilha.',
          kind: 'support',
          view: 'image',
          url: 'https://images.unsplash.com/photo-1529078155058-5d716f45d604?auto=format&fit=crop&w=1200&q=80',
          downloadable: true,
          order: 2,
        },
      ],
      quiz: {
        id: quizOneId,
        encounterId: encounterOneId,
        title: 'Quiz do Encontro 1',
        description: 'Revise as ideias centrais trabalhadas no encontro.',
        questions: [
          {
            id: createId(),
            prompt: 'Qual e a proposta principal deste primeiro encontro?',
            explanation:
              'O encontro apresenta a catequese como caminho de fe vivido em comunidade e resposta ao amor de Deus.',
            options: [
              { id: createId(), text: 'Memorizar datas historicas isoladas.', isCorrect: false },
              { id: createId(), text: 'Reconhecer a catequese como caminhada de fe em comunidade.', isCorrect: true },
              { id: createId(), text: 'Substituir a vida comunitaria por estudo individual.', isCorrect: false },
              { id: createId(), text: 'Tratar somente de regras disciplinares.', isCorrect: false },
              { id: createId(), text: 'Encerrar a preparacao liturgica do grupo.', isCorrect: false },
            ],
          },
        ],
      },
    },
    {
      id: encounterTwoId,
      groupId: groupTwoId,
      slug: 'a-palavra-que-ilumina',
      title: 'A Palavra que Ilumina',
      illuminatedTitle: 'Encontros',
      summary:
        'Explora a importancia da Sagrada Escritura na vida catequetica, com escuta, meditacao e resposta.',
      theme: 'Biblia e vida',
      audience: 'Turmas intermediarias',
      order: 2,
      coverImageUrl:
        'https://images.unsplash.com/photo-1507692049790-de58290a4334?auto=format&fit=crop&w=1200&q=80',
      bodyHtml:
        '<h2>Escuta e resposta</h2><p>A Palavra ilumina a historia pessoal e comunitaria. Cada leitura precisa abrir espaco para silencio, partilha e compromisso.</p>',
      assets: [
        {
          id: createId(),
          encounterId: encounterTwoId,
          title: 'Roteiro visual',
          description: 'Imagem para projetar durante a dinamica.',
          kind: 'summary',
          view: 'image',
          url: 'https://images.unsplash.com/photo-1481627834876-b7833e8f5570?auto=format&fit=crop&w=1200&q=80',
          downloadable: true,
          order: 1,
        },
      ],
    },
  ],
  articles: [
    {
      id: createId(),
      slug: 'como-organizar-um-encontro-catequetico',
      title: 'Como organizar um encontro catequetico',
      excerpt:
        'Um guia breve para preparar acolhida, proclamacao da Palavra, dinamica e envio com intencionalidade pastoral.',
      publishedAt: new Date().toISOString(),
      featured: true,
      tags: ['metodologia', 'planejamento', 'catequese'],
      coverImageUrl:
        'https://images.unsplash.com/photo-1517486808906-6ca8b3f04846?auto=format&fit=crop&w=1200&q=80',
      contentHtml:
        '<h2>Antes do encontro</h2><p>Planeje o objetivo, a passagem biblica central e o gesto concreto que ajudara a turma a guardar a experiencia.</p><h2>Durante o encontro</h2><p>Varie os ritmos entre escuta, conversa, silencio e celebracao.</p><blockquote>A catequese floresce quando o conteudo encontra a vida.</blockquote>',
    },
  ],
  updatedAt: new Date().toISOString(),
}
