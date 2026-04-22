import App from '../src/App'

// Every URL hits this component. React Router inside App resolves the
// actual route and renders the appropriate page. Both the server-side
// renderer (+onRenderHtml.tsx) and the client-side hydrator
// (+onRenderClient.tsx) wrap this with a Router of the right flavor.
export default function Page() {
  return <App />
}
