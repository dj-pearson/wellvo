import { lazy, Suspense } from 'react'
import { Routes, Route } from 'react-router-dom'
import Layout from './components/Layout'
import { AdminAuthProvider } from './admin/AdminAuthProvider'

const Home = lazy(() => import('./pages/Home'))
const Privacy = lazy(() => import('./pages/Privacy'))
const Terms = lazy(() => import('./pages/Terms'))
const Support = lazy(() => import('./pages/Support'))
const Pricing = lazy(() => import('./pages/Pricing'))
const Accessibility = lazy(() => import('./pages/Accessibility'))
const ElderlyCare = lazy(() => import('./pages/ElderlyCare'))
const ChildSafety = lazy(() => import('./pages/ChildSafety'))
const Cookies = lazy(() => import('./pages/Cookies'))
const DMCA = lazy(() => import('./pages/DMCA'))
const NotFound = lazy(() => import('./pages/NotFound'))
const Blog = lazy(() => import('./pages/Blog'))
const BlogPost = lazy(() => import('./pages/BlogPost'))
const Compare = lazy(() => import('./pages/Compare'))
const ComparePost = lazy(() => import('./pages/ComparePost'))

const AdminLogin = lazy(() => import('./admin/AdminLogin'))
const AdminLayout = lazy(() => import('./admin/AdminLayout'))
const AdminDashboard = lazy(() => import('./admin/AdminDashboard'))
const AdminUsers = lazy(() => import('./admin/AdminUsers'))
const AdminBlog = lazy(() => import('./admin/AdminBlog'))
const AdminBlogEditor = lazy(() => import('./admin/AdminBlogEditor'))
const AdminBlogHistory = lazy(() => import('./admin/AdminBlogHistory'))
const AdminBlogRefresh = lazy(() => import('./admin/AdminBlogRefresh'))
const AdminBlogAssets = lazy(() => import('./admin/AdminBlogAssets'))
const AdminBlogTemplates = lazy(() => import('./admin/AdminBlogTemplates'))
const AdminSocial = lazy(() => import('./admin/AdminSocial'))
const AdminAnalytics = lazy(() => import('./admin/AdminAnalytics'))

function LoadingSpinner() {
  return (
    <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: '60vh' }}>
      <div style={{
        width: 36, height: 36,
        border: '3px solid #dcfce7',
        borderTopColor: '#2ECC71',
        borderRadius: '50%',
        animation: 'spin 0.8s linear infinite',
      }} />
      <style>{`@keyframes spin { to { transform: rotate(360deg) } }`}</style>
    </div>
  )
}

function App() {
  return (
    <AdminAuthProvider>
      <Suspense fallback={<LoadingSpinner />}>
        <Routes>
          {/* Public marketing + blog */}
          <Route element={<Layout />}>
            <Route path="/" element={<Home />} />
            <Route path="/privacy" element={<Privacy />} />
            <Route path="/terms" element={<Terms />} />
            <Route path="/support" element={<Support />} />
            <Route path="/pricing" element={<Pricing />} />
            <Route path="/accessibility" element={<Accessibility />} />
            <Route path="/elderly-care" element={<ElderlyCare />} />
            <Route path="/child-safety" element={<ChildSafety />} />
            <Route path="/cookies" element={<Cookies />} />
            <Route path="/dmca" element={<DMCA />} />
            <Route path="/blog" element={<Blog />} />
            <Route path="/blog/:slug" element={<BlogPost />} />
            <Route path="/compare" element={<Compare />} />
            <Route path="/compare/:fullSlug" element={<ComparePost />} />
            <Route path="*" element={<NotFound />} />
          </Route>

          {/* Admin — standalone chrome, its own auth guard */}
          <Route path="/admin/login" element={<AdminLogin />} />
          <Route path="/admin" element={<AdminLayout />}>
            <Route index element={<AdminDashboard />} />
            <Route path="users" element={<AdminUsers />} />
            <Route path="blog" element={<AdminBlog />} />
            <Route path="blog/templates" element={<AdminBlogTemplates />} />
            <Route path="blog/refresh" element={<AdminBlogRefresh />} />
            <Route path="blog/assets" element={<AdminBlogAssets />} />
            <Route path="blog/new" element={<AdminBlogEditor />} />
            <Route path="blog/:id" element={<AdminBlogEditor />} />
            <Route path="blog/:id/history" element={<AdminBlogHistory />} />
            <Route path="social" element={<AdminSocial />} />
            <Route path="analytics" element={<AdminAnalytics />} />
          </Route>
        </Routes>
      </Suspense>
    </AdminAuthProvider>
  )
}

export default App
