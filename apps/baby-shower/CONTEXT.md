# Baby-shower Invitation App

One-off invitation app for one combined baby-shower + gender-reveal event: landing page with photos, name-only RSVP, post-confirmation location/time reveal, tailnet-gated admin view. Bilingual ES/EN.

## Language

**Guest**:
A person who interacts with the invitation page. Identified solely by their name - no accounts, no invite tokens.
_Avoid_: user, account, invitee

**RSVP**:
A guest's single response: attending yes/no plus an optional plus-one. One per guest; editable until the cutoff.
_Avoid_: signup, registration, booking

**nameKey**:
The identity key of a guest, derived from their name: trimmed, internal whitespace collapsed to single spaces, Unicode case-folded; accents significant. Unique across RSVPs.
_Avoid_: username, login

**Plus-one**:
The one extra person a guest may bring. An explicit toggle on the RSVP; naming them is optional. An unnamed plus-one reads "<Guest>'s +1".
_Avoid_: companion, "+1" as a noun in prose

**Reveal**:
The post-confirmation content shown only to attending guests: venue name, address (as a Google Maps link), date, start-end time.
_Avoid_: details section, location block

**Cutoff**:
Event date minus 7 days. New RSVPs and edits freeze at this moment; retrieval stays available read-only.
_Avoid_: deadline, lock date

**Retrieval**:
The "Already confirmed?" path: a guest re-enters their name to re-show their RSVP (and the reveal, if attending). Read-only after the cutoff.
_Avoid_: login, session

**Admin view**:
The tailnet-gated page at `/admin`: summary strip plus a single newest-first table of RSVPs. Network-level gating only (Caddy tailnet matcher) - no app-level auth. The admin's sole action is deleting a row, behind a confirm.
_Avoid_: dashboard, backoffice

**Headcount**:
The sum of party sizes over attending RSVPs - the number the hosts report to the venue. Declined RSVPs never count.
_Avoid_: total guests, attendance figure

**The Mystery**:
The invitation's conceit: only three people in the world know the baby's sex, and the parents-to-be are not among them. Guests are asked to help solve it. The page is styled as a case file; the reveal happens live at the party (balloon + cake).
_Avoid_: theme, gimmick

**Witness**:
One of the three people who know the secret: the doctor (discovered it, sealed it in the Secret Envelope), the balloon store (chose the confetti color), the cake shop (chose the cake filling). Never the parents.
_Avoid_: suspect, informant

**Secret Envelope**:
The sealed message carrying the secret from the doctor to the balloon store, then passed in code to the cake shop. Also the invitation's opening motif: a sealed envelope the guest opens.
_Avoid_: letter, note

**Theory**:
A guest's optional girl/boy guess filed with their RSVP. Tallied in the Admin view. Not required; a guest may file no theory.
_Avoid_: vote, prediction, bet
