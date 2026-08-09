# Baby-shower Content & Copy Inventory (ES/EN)

Resolution of wayfinder ticket #5. Grilling session with @fveracoechea, 2026-08-09. All points confirmed by the user ("CONFIRM ALL surfaces").

This is the exact content the build hardcodes, organized for the hand-rolled dictionary approach locked in #9. Every guest-facing and admin-facing string lives here, EN canonical.

## Event facts (go to `src/lib/event.ts`, not translated)

| constant | value |
|---|---|
| `parents` | Nancy & Francisco |
| `eventDate` | 2026-10-10 (Saturday) |
| `eventStart` / `eventEnd` | 5:00 PM / 8:00 PM |
| `timezone` | America/New_York (EDT, UTC-4 on that date) |
| `cutoff` | 2026-10-03 23:59:59 EDT (event date minus 7 days, end of that calendar day, event timezone) |
| `venueName` | Provisions Boutique |
| `venueAddress` | 60 E Jefferson St Ste A, Hoschton, GA 30548 |
| `cityLine` | Hoschton, GA |
| `mapsLinkUrl` | `https://www.google.com/maps/search/?api=1&query=Provisions+Boutique,+60+E+Jefferson+St+Ste+A,+Hoschton,+GA+30548` |
| `mapsEmbedUrl` | `https://www.google.com/maps?q=Provisions+Boutique,+60+E+Jefferson+St+Ste+A,+Hoschton,+GA+30548&output=embed` (verified working without API key, 2026-08-09) |
| `hostContact` | Nancy, +1 (555) 123-4567 - **PLACEHOLDER, replace with the real phone before launch** |

## Locked decisions from this ticket

1. **Landing shows date + city** ("Saturday, October 10, 2026 · Hoschton, GA"). Only the exact venue/address stays behind confirmation. The prototype teaser copy changed accordingly ("The exact address is revealed when you RSVP").
2. **Reveal gains an embedded Google Map** (no-key `output=embed` iframe, `loading="lazy"`, `referrerpolicy="no-referrer-when-downgrade"`, `allowfullscreen`). The address-as-Maps-link stays as caption/fallback under the embed. **Amends #2** ("No embedded map iframe").
3. **Reveal gains the dress code**: casual; wear the color of your theory (pink/rose = girl, green/blue = boy, white/yellow = neutral).
4. **Reveal gains two venue photos**: `venue-exterior.jpg`, `venue-interior.jpg` (pulled from the Google Maps place gallery into `apps/baby-shower/assets/`).
5. **No gift notes, no registry link, no separate dress code on landing.**
6. **Parents-to-be are named** in copy: "Nancy & Francisco". Case number stays generic ("Case No. 2026").
7. **Locale strategy**: URL prefix. EN at `/`, ES at `/es/*`. Detection order path > cookie > Accept-Language header; **fallback EN**. The toggle is a plain link to the same page in the other locale. Supersedes the scaffold's `?lang=` links and ES fallback.
8. **Content module**: single typed module. Extend the existing `src/lib/i18n.ts` (flat camelCase keys, `Messages = typeof en`, ES satisfies the type, compile-time key parity test already exists). Event facts above go in a sibling `src/lib/event.ts`. Components never hardcode strings.
9. **Scaffold deltas for the build**: flip `Messages = typeof es` to `typeof en`; flip `asLanguage`/`fallbackLanguage` to EN; replace `?lang=` toggle with path-prefix links; replace the 17 scaffold keys with the deck below.

## Photo manifest

| file (ship) | source in `assets/` | used in | alt key |
|---|---|---|---|
| `secondary.jpg` | `secondary.jpeg` (**13 MB, resize**) | story, witness 1 | `altParentsEmbracing` |
| `ultrasound.jpg` | `baby-first-ultrasound.JPG` | story, witness 2 | `altUltrasound` |
| `hero-primary.jpg` | `primary.jpg` | story, witness 3 | `altParentsPark` |
| `venue-exterior.jpg` | `venue-exterior.jpg` | reveal | `venueExteriorAlt` |
| `venue-interior.jpg` | `venue-interior.jpg` | reveal | `venueInteriorAlt` |

`primary-detail.jpg` remains available, unused (the winning variant C has no exhibits grid).

## Copy deck

`{name}`, `{girl}`, `{boy}` mark typed interpolation functions in the dictionary. `venueValue` and `addressValue` are identical in both locales by design.

### Page chrome

| key | EN (canonical) | ES |
|---|---|---|
| `pageTitle` | Nancy & Francisco's Baby Shower | Baby shower de Nancy & Francisco |
| `pageDescription` | A baby shower wrapped in a mystery. October 10, 2026 · Hoschton, GA | Un baby shower envuelto en misterio. 10 de octubre de 2026 · Hoschton, GA |
| `languageToggleLabel` | Language | Idioma |

### Landing (variant C, The Envelope)

| key | EN | ES |
|---|---|---|
| `caseNo` | Case No. 2026 | Caso N.º 2026 |
| `confidential` | Confidential | Confidencial |
| `envOpen` | Open the case file | Abrir el expediente |
| `rumorHead` | Rumor has it only three people know the baby's sex | Se rumora que solo tres personas conocen el sexo del bebé |
| `rumorSub` | And neither of them is us. Here is what we know about the case. | Y ninguna de ellas somos nosotros. Esto es lo que sabemos del caso. |
| `parentsLine` | A baby shower for Nancy & Francisco | Un baby shower para Nancy & Francisco |
| `basicsLine` | Saturday, October 10, 2026 · Hoschton, GA | Sábado 10 de octubre de 2026 · Hoschton, GA |
| `videoK` | Video evidence | Prueba videográfica |
| `st1` | RUMOR HAS IT... | SE RUMORA... |
| `st2a` / `st2b` / `st2c` | that only / THREE PEOPLE / in the whole world know the sex of our baby. | que solo / TRES PERSONAS / en todo el mundo conocen el sexo de nuestro bebé. |
| `sw1t` / `sw1s` | WITNESS #1 / The doctor: discovered the secret and sealed it in an envelope. | TESTIGO N.º 1 / El doctor: descubrió el secreto y lo selló en un sobre. |
| `sw2t` / `sw2s` | WITNESS #2 / The balloon store: read the envelope and chose the confetti color. | TESTIGO N.º 2 / La tienda de globos: leyó el sobre y eligió el color del confeti. |
| `sw3t` / `sw3s` | WITNESS #3 / The cake shop: received the code and chose the cake filling. | TESTIGO N.º 3 / La pastelería: recibió el código y eligió el relleno del pastel. |
| `st6a` / `st6b` | The parents-to-be / DO NOT KNOW | Los futuros papás / NO LO SABEN |
| `st7a` / `st7b` | And if even one guest knew... / EVERYONE WOULD KNOW | Y si un invitado lo supiera... / TODOS LO SABRÍAN |
| `st8a` / `st8s` | Girl or boy? / Help us solve the mystery. | ¿Niña o niño? / Ayúdanos a resolver el misterio. |
| `st9a` / `st9s` | The reveal: at the party. / The exact address is revealed when you RSVP. | La revelación: en la fiesta. / La dirección exacta se revela al confirmar tu asistencia. |
| `secret` / `coded` / `replay` | SECRET / CODED / Watch again | SECRETO / EN CLAVE / Ver de nuevo |
| `altParentsEmbracing` | Nancy and Francisco embracing | Nancy y Francisco abrazados |
| `altUltrasound` | The baby's first ultrasound | La primera ecografía del bebé |
| `altParentsPark` | Nancy and Francisco in the park | Nancy y Francisco en el parque |
| `witnessesK` | The witnesses | Los testigos |
| `w1Role` / `w1Desc` | The doctor / Discovered the secret and sealed it in an envelope. | El doctor / Descubrió el secreto y lo selló en un sobre. |
| `w2Role` / `w2Desc` | The balloon store / Read the envelope and chose the confetti color. | La tienda de globos / Leyó el sobre y eligió el color del confeti. |
| `codeChip` | coded: ▮▮-▮▮▮ | en clave: ▮▮-▮▮▮ |
| `w3Role` / `w3Desc` | The cake shop / Decoded it and chose the cake filling. | La pastelería / Descifró el código y eligió el relleno del pastel. |
| `twistA` / `twistB` | The parents-to-be / DO NOT KNOW | Los futuros papás / NO LO SABEN |
| `teaser` | The exact address is revealed when you RSVP | La dirección exacta se revela al confirmar tu asistencia |
| `cta` | RSVP | Confirmar asistencia |
| `alreadyLink` | Already confirmed? | ¿Ya confirmaste? |

### RSVP form

| key | EN | ES |
|---|---|---|
| `guestFileTag` | Guest file | Expediente de invitado |
| `formTitle` | Confirm your attendance | Confirma tu asistencia |
| `nameLabel` | Your name | Tu nombre |
| `namePlaceholder` | Mary Smith | María García |
| `nameHelp` | If your name is common, add something to tell you apart (e.g. Mary S. - Aunt). | Si tu nombre es común, agrega algo que te distinga (ej. María G. - Tía). |
| `attendingLabel` | Will you attend? | ¿Asistirás? |
| `attendingYes` | Yes, I'll be there | Sí, ahí estaré |
| `attendingNo` | Can't make it | No podré |
| `theoryLabel` | Your theory (optional) | Tu teoría (opcional) |
| `theoryGirl` / `theoryBoy` | Girl / Boy | Niña / Niño |
| `plusOneLabel` | Bringing someone with you? | ¿Vienes con alguien? |
| `plusOneNamePlaceholder` | Your plus-one's name (optional) | El nombre de tu plus-one (opcional) |
| `submitLabel` | Confirm | Confirmar |

### Form errors (inline + transient)

| key | EN | ES |
|---|---|---|
| `errorNameRequired` | Please tell us your name. | Cuéntanos tu nombre. |
| `errorNameInvalid` | Use only letters, spaces, hyphens and apostrophes (2 to 80 characters). | Usa solo letras, espacios, guiones y apóstrofes (2 a 80 caracteres). |
| `errorPlusOneSameName` | Your plus-one's name must be different from yours. | El nombre de tu plus-one debe ser distinto al tuyo. |
| `errorAttendingRequired` | Please choose yes or no. | Elige sí o no. |
| `errorServer` | Something went wrong. Your answers are still here, please try again. | Algo salió mal. Tus respuestas siguen aquí, intenta de nuevo. |
| `errorRateLimited` | Too many attempts. Wait a minute and try again. | Demasiados intentos. Espera un minuto e intenta de nuevo. |

### Reveal (post-confirmation, attending)

| key | EN | ES |
|---|---|---|
| `caseStatusTag` | Open case | Caso abierto |
| `revealTitle` | The case breaks at the party | El caso se revela en la fiesta |
| `venueLabel` | The scene | La escena |
| `venueValue` | Provisions Boutique | Provisions Boutique |
| `addressLabel` | Address | Dirección |
| `addressValue` | 60 E Jefferson St Ste A, Hoschton, GA 30548 | 60 E Jefferson St Ste A, Hoschton, GA 30548 |
| `dateLabel` | Date & time | Fecha y hora |
| `dateValue` | Saturday, October 10, 2026 · 5:00 - 8:00 PM | Sábado 10 de octubre de 2026 · 5:00 - 8:00 PM |
| `dressCodeLabel` | Dress code | Código de vestimenta |
| `dressCodeValue` | Casual. Recommended: wear the color of your theory - pink or rose if you think girl, green or blue if you think boy, or neutral white and yellow. | Casual. Recomendado: viste el color de tu teoría - rosa o fucsia si crees que es niña, verde o azul si crees que es niño, o blanco y amarillo si prefieres algo neutral. |
| `yourTheory` | Your theory on file: | Tu teoría registrada: |
| `theoryNone` | You filed no theory. There is still time to pick a side. | No registraste una teoría. Aún hay tiempo para elegir un bando. |
| `mapOpen` | Open in Google Maps | Abrir en Google Maps |
| `mapEmbedTitle` | Map to Provisions Boutique | Mapa a Provisions Boutique |
| `venueExteriorAlt` | Provisions Boutique storefront, a black brick building | Fachada de Provisions Boutique, un edificio de ladrillo negro |
| `venueInteriorAlt` | The event space inside Provisions Boutique | El espacio del evento dentro de Provisions Boutique |
| `changeRsvp` | Change my RSVP | Cambiar mi RSVP |

### Declined state (no reveal)

| key | EN | ES |
|---|---|---|
| `declinedTitle` | A shame, detective | Qué lástima, detective |
| `declinedBody(name)` | Thank you for letting us know, {name}. You will be missed on October 10. If your plans change, you can update your RSVP here until October 3. | Gracias por avisarnos, {name}. Te extrañaremos el 10 de octubre. Si tus planes cambian, puedes actualizar tu RSVP aquí hasta el 3 de octubre. |
| `contactLine` | Questions? Text Nancy at +1 (555) 123-4567. **(PLACEHOLDER phone)** | ¿Preguntas? Escríbele a Nancy al +1 (555) 123-4567. **(PLACEHOLDER phone)** |

### Retrieval ("Already confirmed?" path)

| key | EN | ES |
|---|---|---|
| `retrievalTitle` | Already confirmed? | ¿Ya confirmaste? |
| `retrievalNameHelp` | Type it exactly as you did the first time. | Escríbelo exactamente como la primera vez. |
| `retrievalSubmit` | Find my RSVP | Buscar mi RSVP |
| `retrievalNotFound` | We could not find that name. Check the spelling, or confirm your attendance below. | No encontramos ese nombre. Revisa la ortografía o confirma tu asistencia abajo. |
| `alreadyOnFile` | This name already has an RSVP on file. Here it is. | Este nombre ya tiene una confirmación registrada. Aquí está. |

### Closed state (post-cutoff)

| key | EN | ES |
|---|---|---|
| `closedTitle` | The case file is sealed | El expediente está sellado |
| `closedBody` | Confirmations closed on October 3, one week before the party. | Las confirmaciones cerraron el 3 de octubre, una semana antes de la fiesta. |
| `closedContact` | Last-minute change? Text Nancy at +1 (555) 123-4567. **(PLACEHOLDER phone)** | ¿Cambio de último minuto? Escríbele a Nancy al +1 (555) 123-4567. **(PLACEHOLDER phone)** |
| `closedRetrievalNote` | Already on the list? You can still look up your RSVP. | ¿Ya estás en la lista? Aún puedes consultar tu confirmación. |

### Admin view (tailnet-gated `/admin`)

| key | EN | ES |
|---|---|---|
| `adminTitle` | Guest ledger | Registro de invitados |
| `statHeadcount` | Headcount (attending) | Total de personas (asisten) |
| `statParties` | Parties attending | Grupos que asisten |
| `statDeclined` | Declined | No asisten |
| `statTheories(girl, boy)` | Theories: {girl} girl · {boy} boy | Teorías: {girl} niña · {boy} niño |
| `colName` | Name | Nombre |
| `colStatus` | Status | Estado |
| `colPlusOne` | Plus-one | Plus-one |
| `colTheory` | Theory | Teoría |
| `colUpdated` | Last updated | Última actualización |
| `statusAttending` / `statusDeclined` | Attending / Declined | Asiste / No asiste |
| `plusOneAnonymous(name)` | {name}'s +1 | el +1 de {name} |
| `deleteAction` | Delete | Eliminar |
| `deleteConfirm(name)` | Delete {name}'s RSVP? This cannot be undone. | ¿Eliminar la confirmación de {name}? No se puede deshacer. |
| `adminEmpty` | No RSVPs yet. | Aún no hay confirmaciones. |

The 403 shown to non-tailnet visitors is a bare Caddy response (per #3); the app renders no copy for it.

## Open placeholder

- **Host phone number**: +1 (555) 123-4567 is a placeholder. Replace in `event.ts` before launch (used by `contactLine` and `closedContact`).
