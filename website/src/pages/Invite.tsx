import { useMemo, useSyncExternalStore } from 'react'
import { useLocation, useParams } from 'react-router-dom'
import SEO from '../components/SEO'
import { APP_STORE_URL, PLAY_STORE_URL, detectPlatform, readInvite, type Platform } from '../lib/invite'
import './Invite.css'

/**
 * Landing page for the link an owner texts to a receiver:
 * https://dailyok.net/invite/<token>?code=<6-digit setup code>
 *
 * When Universal Links / App Links are set up and the app is installed, the OS
 * opens the app directly and this page is never seen. Otherwise this is where
 * the receiver lands, so it has one job: get them into the app, already linked.
 *   1. Get the app — the store for their phone first.
 *   2. Open it — a `dailyok://invite?token=…` button hands the invite to the
 *      app (works without any domain association).
 *   3. The setup code, large, for when the app asks for it.
 *
 * The token is never sent anywhere from this page; it only goes into the
 * app-open link. Older texts used `/invite?token=…`, so that form is read too.
 */

const noSubscribe = () => () => {}

export default function Invite() {
  const { token: pathToken } = useParams()
  const { search } = useLocation()
  const { token, code } = useMemo(() => readInvite(pathToken, search), [pathToken, search])

  // Prerendered HTML can't know the visitor's phone, so the server snapshot
  // shows both stores; after hydration the matching one moves first.
  const platform: Platform = useSyncExternalStore(
    noSubscribe,
    () => detectPlatform(navigator.userAgent),
    () => 'other',
  )

  const openInAppHref = token ? `dailyok://invite?token=${token}` : 'dailyok://'

  const appStore = (
    <a
      className={`btn ${platform === 'android' ? 'btn-outline' : 'btn-primary'} invite-store`}
      href={APP_STORE_URL}
      key="ios"
    >
      Get it on the App Store
    </a>
  )
  const playStore = (
    <a
      className={`btn ${platform === 'android' ? 'btn-primary' : 'btn-outline'} invite-store`}
      href={PLAY_STORE_URL}
      key="android"
    >
      Get it on Google Play
    </a>
  )
  const stores = platform === 'android' ? [playStore, appStore] : [appStore, playStore]

  return (
    <div className="invite section">
      <SEO
        title="You're invited to Daily OK"
        description="Someone in your family would like a quick daily check-in with you. Get the Daily OK app and tap once a day to say you're OK."
        path="/invite"
        noindex
      />

      <div className="container invite-inner">
        <h1>You're invited to Daily OK</h1>
        <p className="invite-lead">
          Someone in your family would like a quick check-in with you each day.
          You tap <strong>I'm OK</strong> once — that's it.
        </p>

        <ol className="invite-steps">
          <li>
            <h2>Get the app</h2>
            <div className="invite-stores">{stores}</div>
          </li>

          <li>
            <h2>Open it</h2>
            <p>
              Sign in with Apple, Google, or your email. Then tap Open Daily OK
              below (or the link in your text again) to see whose family it is
              and join.
            </p>
            <a className="btn btn-secondary" href={openInAppHref}>
              Open Daily OK
            </a>
          </li>

          <li>
            <h2>If the app asks for a code</h2>
            {code ? (
              <>
                <p className="invite-code" aria-label={`Setup code ${code.split('').join(' ')}`}>
                  {code}
                </p>
                <p className="invite-note">
                  Use it on an iPad, or if the link doesn't open the app.
                </p>
              </>
            ) : (
              <p className="invite-note">
                Your invitation text includes a 6-digit setup code. Enter it in the
                app if the link doesn't open it.
              </p>
            )}
          </li>
        </ol>

        <p className="invite-help">
          Stuck? <a href="/support">We can help</a>, or ask the person who invited
          you to send the invite again.
        </p>
      </div>
    </div>
  )
}
