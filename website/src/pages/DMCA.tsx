import SEO from '../components/SEO'
import './Legal.css'

export default function DMCA() {
  return (
    <div className="legal-page">
      <SEO
        title="DMCA Copyright Policy"
        description="How to submit a copyright takedown notice or counter-notice for content on Daily OK."
        path="/dmca"
      />
      <div className="container">
        <div className="legal-content">
          <h1>DMCA Copyright Policy</h1>
          <p className="legal-updated">Last updated: April 13, 2026</p>

          <section>
            <h2>Our Commitment</h2>
            <p>
              Pearson Media LLC d/b/a Daily OK ("Daily OK") respects the intellectual
              property rights of others and expects users of our service to do the same. In
              accordance with the Digital Millennium Copyright Act of 1998 ("DMCA"), 17 U.S.C.
              § 512, we will respond promptly to clear and complete notices of alleged
              copyright infringement.
            </p>
          </section>

          <section>
            <h2>Submitting a Notice of Infringement</h2>
            <p>
              If you believe that material made available through the Daily OK service
              infringes a copyright that you own or control, please send a written notice to
              our designated DMCA agent containing the following:
            </p>
            <ol>
              <li>A physical or electronic signature of the copyright owner or a person authorized to act on their behalf;</li>
              <li>Identification of the copyrighted work claimed to have been infringed (or a representative list if multiple works);</li>
              <li>Identification of the material claimed to be infringing, with information reasonably sufficient to permit us to locate it (for example, a screenshot, account name, and direct link);</li>
              <li>Your contact information, including your name, mailing address, telephone number, and email address;</li>
              <li>A statement that you have a good-faith belief that the use of the material is not authorized by the copyright owner, its agent, or the law;</li>
              <li>A statement made under penalty of perjury that the information in the notice is accurate and that you are the copyright owner or authorized to act on the owner's behalf.</li>
            </ol>
          </section>

          <section>
            <h2>Designated DMCA Agent</h2>
            <p>
              <strong>DMCA Agent</strong>
              <br />
              Pearson Media LLC d/b/a Daily OK
              <br />
              Attn: DMCA Agent
              <br />
              7889 Beechtree Ln, West Des Moines, IA 50266, USA
              <br />
              Email: <a href="mailto:dmca@dailyok.net">dmca@dailyok.net</a>
            </p>
            <p>
              Our designated agent is also registered with the U.S. Copyright Office and may
              be located through the public DMCA Designated Agent Directory.
            </p>
          </section>

          <section>
            <h2>Counter-Notice Procedure</h2>
            <p>
              If you believe that material you posted was removed or disabled in error, you
              may submit a counter-notice to our DMCA agent containing:
            </p>
            <ol>
              <li>Your physical or electronic signature;</li>
              <li>Identification of the material that was removed or disabled and the location at which it appeared before it was removed or disabled;</li>
              <li>A statement under penalty of perjury that you have a good-faith belief that the material was removed or disabled as a result of mistake or misidentification;</li>
              <li>Your name, mailing address, and telephone number, and a statement that you consent to the jurisdiction of the U.S. District Court for the district in which your address is located (or, if outside the U.S., the U.S. District Court for the District of Utah), and that you will accept service of process from the person who provided the original notice.</li>
            </ol>
            <p>
              Upon receipt of a valid counter-notice, we will forward it to the original
              complainant and may restore the removed material in 10–14 business days unless
              the complainant notifies us that they have filed a court action seeking to
              restrain further use of the material.
            </p>
          </section>

          <section>
            <h2>Repeat-Infringer Policy</h2>
            <p>
              We will, in appropriate circumstances, terminate the accounts of users who are
              found to be repeat infringers of copyright.
            </p>
          </section>

          <section>
            <h2>False Claims</h2>
            <p>
              Under 17 U.S.C. § 512(f), any person who knowingly materially misrepresents
              that material is infringing, or that material was removed or disabled by
              mistake or misidentification, may be liable for damages. Please do not make
              false claims.
            </p>
          </section>

          <section>
            <h2>Other Intellectual-Property Concerns</h2>
            <p>
              For trademark, trade-secret, or other non-copyright intellectual-property
              concerns, please contact{' '}
              <a href="mailto:legal@dailyok.net">legal@dailyok.net</a>.
            </p>
          </section>
        </div>
      </div>
    </div>
  )
}
