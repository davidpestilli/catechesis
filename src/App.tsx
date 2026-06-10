import { createHashRouter, RouterProvider } from 'react-router-dom'
import { ProtectedRoute } from '@/components/protected-route'
import { SiteShell } from '@/components/layout/site-shell'
import { AdminDashboardPage } from '@/pages/admin-dashboard-page'
import { ArticleViewPage } from '@/pages/article-view-page'
import { ArticlesPage } from '@/pages/articles-page'
import { EncounterAssetPage } from '@/pages/encounter-asset-page'
import { EncounterDetailPage } from '@/pages/encounter-detail-page'
import { EncounterQuizPage } from '@/pages/encounter-quiz-page'
import { EncountersPage } from '@/pages/encounters-page'
import { HomePage } from '@/pages/home-page'
import { LoginPage } from '@/pages/login-page'
import { NotFoundPage } from '@/pages/not-found-page'

const router = createHashRouter([
  {
    path: '/',
    element: <SiteShell />,
    children: [
      { index: true, element: <HomePage /> },
      { path: 'encontros', element: <EncountersPage /> },
      { path: 'encontros/:slug', element: <EncounterDetailPage /> },
      { path: 'encontros/:slug/resumo', element: <EncounterAssetPage /> },
      { path: 'encontros/:slug/material/:assetId', element: <EncounterAssetPage /> },
      { path: 'encontros/:slug/quiz', element: <EncounterQuizPage /> },
      { path: 'artigos', element: <ArticlesPage /> },
      { path: 'artigos/:slug', element: <ArticleViewPage /> },
      { path: 'login', element: <LoginPage /> },
      {
        element: <ProtectedRoute />,
        children: [{ path: 'admin', element: <AdminDashboardPage /> }],
      },
      { path: '*', element: <NotFoundPage /> },
    ],
  },
])

export default function App() {
  return <RouterProvider router={router} />
}
