// Catch-all route — every URL routes to pages/+Page.tsx, which then defers
// to React Router inside the app. Lower precedence means more specific
// Vike routes (if we add any in the future) take priority over this.

export default () => {
  return {
    precedence: -1,
    routeParams: {},
  }
}
