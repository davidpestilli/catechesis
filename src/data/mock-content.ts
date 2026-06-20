import type { CMSState } from '@/types/content'
import { createDefaultLandingImages } from '@/data/landing-images'
import { createId } from '@/lib/utils'

const groupOneId = createId()
const groupTwoId = createId()
const encounterOneId = createId()
const encounterTwoId = createId()
const encounterThreeId = createId()
const encounterFourId = createId()
const encounterFiveId = createId()
const quizOneId = createId()
const quizThreeId = createId()

export const defaultCMSState: CMSState = {
  settings: {
    heroVideoUrl:
      'https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4',
    heroPosterUrl:
      'https://images.unsplash.com/photo-1519494026892-80bbd2d6fd0d?auto=format&fit=crop&w=1200&q=80',
    homeLead: '',
    landingImages: createDefaultLandingImages(),
  },
  groups: [
    {
      id: groupOneId,
      slug: 'turma-sao-pedro',
      name: 'Turma São Pedro',
      battleCry: 'Firmes na fé, alegres na missão.',
      coverImageUrl:
        'https://images.unsplash.com/photo-1504052434569-70ad5836ab65?auto=format&fit=crop&w=1200&q=80',
      order: 1,
    },
    {
      id: groupTwoId,
      slug: 'turma-sao-paulo',
      name: 'Turma São Paulo',
      battleCry: 'Anunciar, servir e caminhar juntos.',
      coverImageUrl:
        'https://images.unsplash.com/photo-1507692049790-de58290a4334?auto=format&fit=crop&w=1200&q=80',
      order: 2,
    },
  ],
  encounters: [
    {
      id: encounterOneId,
      groupId: groupOneId,
      slug: 'o-chamado-da-fe',
      title: 'O Chamado da Fé',
      illuminatedTitle: 'Encontros',
      summary:
        'Apresenta o primeiro encontro com foco no sentido da catequese, acolhida e caminhada em comunidade.',
      theme: 'Introdução à catequese',
      audience: 'Catequizandos iniciantes',
      order: 1,
      coverImageUrl:
        'https://images.unsplash.com/photo-1504052434569-70ad5836ab65?auto=format&fit=crop&w=1200&q=80',
      bodyHtml:
        '<h2>Boas-vindas</h2><p>Este encontro convida o grupo a reconhecer a fé como resposta viva ao amor de Deus, unindo escuta, oração e convívio.</p><p>Use esta página como texto de apoio publicado no próprio sistema.</p>',
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
          title: 'Vídeo de acolhida',
          description: 'Breve introdução em vídeo para abrir a conversa do encontro.',
          kind: 'support',
          view: 'link',
          url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
          materialCategory: 'video',
          downloadable: false,
          order: 2,
        },
        {
          id: createId(),
          encounterId: encounterOneId,
          title: 'Texto sobre catequese e comunidade',
          description: 'Leitura curta para aprofundar a ideia de caminhada comunitária.',
          kind: 'support',
          view: 'link',
          url: 'https://www.vatican.va',
          materialCategory: 'text',
          downloadable: false,
          order: 3,
        },
        {
          id: createId(),
          encounterId: encounterOneId,
          title: 'Imagem simbólica da Palavra',
          description: 'Referência visual para projetar ou compartilhar com a turma.',
          kind: 'support',
          view: 'link',
          url: 'https://images.unsplash.com/photo-1504052434569-70ad5836ab65?auto=format&fit=crop&w=1200&q=80',
          materialCategory: 'image',
          downloadable: false,
          order: 4,
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
            prompt: 'Qual é a proposta principal deste primeiro encontro?',
            explanation:
              'O encontro apresenta a catequese como caminho de fé vivido em comunidade e resposta ao amor de Deus.',
            options: [
              { id: createId(), text: 'Memorizar datas historicas isoladas.', isCorrect: false },
              { id: createId(), text: 'Reconhecer a catequese como caminhada de fé em comunidade.', isCorrect: true },
              { id: createId(), text: 'Substituir a vida comunitária por estudo individual.', isCorrect: false },
              { id: createId(), text: 'Tratar somente de regras disciplinares.', isCorrect: false },
              { id: createId(), text: 'Encerrar a preparação litúrgica do grupo.', isCorrect: false },
            ],
          },
        ],
      },
    },
    {
      id: encounterThreeId,
      groupId: groupOneId,
      slug: 'jesus-nos-chama-pelo-nome',
      title: 'Jesus nos Chama pelo Nome',
      illuminatedTitle: 'Encontros',
      summary:
        'Aprofunda o chamado pessoal de cada catequizando, com escuta do Evangelho e partilha da própria história.',
      theme: 'Identidade e vocação',
      audience: 'Catequizandos iniciantes',
      order: 2,
      coverImageUrl:
        'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=1200&q=80',
      bodyHtml:
        '<h2>Chamado pessoal</h2><p>Jesus conhece cada pessoa pelo nome e chama para uma resposta livre, concreta e comunitária.</p><p>Este encontro favorece testemunhos, escuta e um pequeno gesto de envio.</p>',
      assets: [
        {
          id: createId(),
          encounterId: encounterThreeId,
          title: 'Roteiro do catequista',
          description: 'Sequência sugerida para acolhida, Palavra e dinâmica.',
          kind: 'summary',
          view: 'pdf',
          url: 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
          downloadable: true,
          order: 1,
        },
      ],
      quiz: {
        id: quizThreeId,
        encounterId: encounterThreeId,
        title: 'Quiz do chamado',
        description: 'Revise os pontos principais sobre vocação e resposta.',
        questions: [
          {
            id: createId(),
            prompt: 'O que significa dizer que Jesus chama cada pessoa pelo nome?',
            explanation:
              'Significa que a fé não é genérica: ela toca a história pessoal de cada catequizando e pede resposta concreta.',
            options: [
              { id: createId(), text: 'Que a fé dispensa a comunidade.', isCorrect: false },
              { id: createId(), text: 'Que o chamado de Deus alcança a história pessoal de cada um.', isCorrect: true },
              { id: createId(), text: 'Que somente os catequistas são chamados.', isCorrect: false },
              { id: createId(), text: 'Que basta decorar conteúdos.', isCorrect: false },
              { id: createId(), text: 'Que não há necessidade de resposta.', isCorrect: false },
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
        'Explora a importância da Sagrada Escritura na vida catequética, com escuta, meditação e resposta.',
      theme: 'Bíblia e vida',
      audience: 'Turmas intermediárias',
      order: 2,
      coverImageUrl:
        'https://images.unsplash.com/photo-1507692049790-de58290a4334?auto=format&fit=crop&w=1200&q=80',
      bodyHtml:
        '<h2>Escuta e resposta</h2><p>A Palavra ilumina a história pessoal e comunitária. Cada leitura precisa abrir espaço para silêncio, partilha e compromisso.</p>',
      assets: [
        {
          id: createId(),
          encounterId: encounterTwoId,
          title: 'Roteiro visual',
          description: 'Imagem para projetar durante a dinâmica.',
          kind: 'summary',
          view: 'image',
          url: 'https://images.unsplash.com/photo-1481627834876-b7833e8f5570?auto=format&fit=crop&w=1200&q=80',
          downloadable: true,
          order: 1,
        },
      ],
    },
    {
      id: encounterFourId,
      groupId: groupTwoId,
      slug: 'celebrar-e-fazer-memoria',
      title: 'Celebrar e Fazer Memória',
      illuminatedTitle: 'Encontros',
      summary:
        'Convida a turma a compreender a celebração como memória viva da fé e experiência comunitária.',
      theme: 'Liturgia e comunidade',
      audience: 'Turmas intermediárias',
      order: 2,
      coverImageUrl:
        'https://images.unsplash.com/photo-1464638681273-0962e9b53566?auto=format&fit=crop&w=1200&q=80',
      bodyHtml:
        '<h2>Memória viva</h2><p>A celebração ajuda a comunidade a recordar a ação de Deus e responder com louvor, escuta e compromisso.</p>',
      assets: [
        {
          id: createId(),
          encounterId: encounterFourId,
          title: 'Esquema celebrativo',
          description: 'Sugestão simples para conduzir um momento orante com a turma.',
          kind: 'summary',
          view: 'html',
          url: '<h2>Momento celebrativo</h2><p>Inicie com um refrão, proclame a Palavra, abra uma breve partilha e conclua com uma prece comum.</p>',
          downloadable: false,
          order: 1,
        },
      ],
    },
    {
      id: encounterFiveId,
      groupId: groupTwoId,
      slug: 'servico-e-envio',
      title: 'Serviço e Envio',
      illuminatedTitle: 'Encontros',
      summary:
        'Organiza a passagem do encontro para a vida concreta, com foco em caridade, serviço e testemunho.',
      theme: 'Missão cristã',
      audience: 'Turmas intermediárias',
      order: 3,
      coverImageUrl:
        'https://images.unsplash.com/photo-1469571486292-b53601020f35?auto=format&fit=crop&w=1200&q=80',
      bodyHtml:
        '<h2>Fé que se torna gesto</h2><p>O encontro termina com um compromisso simples para a semana e com a recordação de que a catequese continua fora da sala.</p>',
      assets: [
        {
          id: createId(),
          encounterId: encounterFiveId,
          title: 'Proposta de gesto concreto',
          description: 'Sugestões de serviço para viver durante a semana.',
          kind: 'support',
          view: 'link',
          url: 'https://www.vatican.va',
          materialCategory: 'website',
          downloadable: false,
          order: 1,
        },
        {
          id: createId(),
          encounterId: encounterFiveId,
          title: 'Livro para aprofundamento',
          description: 'Referência bibliográfica para continuar o estudo sobre missão e serviço.',
          kind: 'support',
          view: 'link',
          url: 'https://books.google.com',
          materialCategory: 'book',
          downloadable: false,
          order: 2,
        },
      ],
    },
  ],
  articles: [
    {
      id: createId(),
      slug: 'como-organizar-um-encontro-catequetico',
      title: 'Como organizar um encontro catequético',
      excerpt:
        'Um guia breve para preparar acolhida, proclamação da Palavra, dinâmica e envio com intencionalidade pastoral.',
      status: 'published',
      publishedAt: new Date().toISOString(),
      category: 'general',
      featured: true,
      tags: ['metodologia', 'planejamento', 'catequese'],
      coverImageUrl:
        'https://images.unsplash.com/photo-1517486808906-6ca8b3f04846?auto=format&fit=crop&w=1200&q=80',
      cardImageUrl:
        'https://images.unsplash.com/photo-1517486808906-6ca8b3f04846?auto=format&fit=crop&w=1200&q=80',
      sources: ['Diretório Nacional de Catequese', 'https://www.vatican.va'],
      contentHtml:
        '<h2>Antes do encontro</h2><p>Planeje o objetivo, a passagem bíblica central e o gesto concreto que ajudará a turma a guardar a experiência.</p><h2>Durante o encontro</h2><p>Varie os ritmos entre escuta, conversa, silêncio e celebração.</p><blockquote>A catequese floresce quando o conteúdo encontra a vida.</blockquote>',
    },
    {
      id: createId(),
      slug: 'sao-francisco-de-assis-e-a-alegria-do-evangelho',
      title: 'São Francisco de Assis e a alegria do Evangelho',
      excerpt:
        'Uma leitura breve sobre simplicidade, louvor e testemunho a partir da vida de São Francisco.',
      status: 'published',
      publishedAt: new Date().toISOString(),
      category: 'saints-life',
      featured: false,
      tags: ['santos', 'testemunho', 'espiritualidade'],
      coverImageUrl:
        'https://images.unsplash.com/photo-1520637836862-4d197d17c11a?auto=format&fit=crop&w=1200&q=80',
      cardImageUrl:
        'https://images.unsplash.com/photo-1520637836862-4d197d17c11a?auto=format&fit=crop&w=1200&q=80',
      sources: ['https://www.vatican.va'],
      contentHtml:
        '<h2>Um coração livre</h2><p>São Francisco descobriu no Evangelho um caminho de liberdade, pobreza e fraternidade.</p><h2>Para a catequese</h2><p>Sua vida ajuda a aproximar os catequizandos da alegria simples de seguir Jesus com inteireza.</p>',
    },
  ],
  usefulLinks: [
    {
      id: createId(),
      title: 'Portal do Vaticano',
      description: 'Documentos, notícias e textos oficiais para consulta e aprofundamento.',
      url: 'https://www.vatican.va',
      tags: ['igreja', 'documentos', 'vaticano'],
      coverImageUrl:
        'https://images.unsplash.com/photo-1531572753322-ad063cecc140?auto=format&fit=crop&w=1200&q=80',
      order: 1,
    },
    {
      id: createId(),
      title: 'Bíblia Online - CNBB',
      description: 'Leitura e pesquisa das Sagradas Escrituras em ambiente digital.',
      url: 'https://www.bibliacatolica.com.br',
      tags: ['biblia', 'leitura', 'estudo'],
      coverImageUrl:
        'https://images.unsplash.com/photo-1504052434569-70ad5836ab65?auto=format&fit=crop&w=1200&q=80',
      order: 2,
    },
  ],
  updatedAt: new Date().toISOString(),
}
