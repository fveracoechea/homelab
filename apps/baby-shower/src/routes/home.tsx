import { Hono } from "hono"
import RsvpForm from "../islands/RsvpForm"
import { asLanguage, t, type Messages } from "../lib/i18n"
import { renderPage } from "../main"

type HomePageProps = {
  lang: ReturnType<typeof asLanguage>
  messages: Messages
}

function HomePage({ lang, messages: m }: HomePageProps) {
  return (
    <main class="mx-auto flex min-h-screen max-w-xl flex-col gap-8 bg-base px-6 py-12 text-text">
      <header class="flex flex-col gap-4 border border-overlay bg-surface p-6">
        <p class="text-sm uppercase tracking-widest text-subtle">Case file</p>
        <h1 class="text-4xl font-bold text-iris">{m.caseFileHeading}</h1>
        <p>{m.caseFileIntro}</p>
        <nav aria-label={m.languageToggleLabel} class="flex gap-3 text-sm">
          <a href="?lang=es" aria-current={lang === "es" ? "true" : undefined} class="text-foam">
            ES
          </a>
          <a href="?lang=en" aria-current={lang === "en" ? "true" : undefined} class="text-foam">
            EN
          </a>
        </nav>
      </header>

      <section class="flex flex-col gap-4 border border-overlay bg-surface p-6">
        <h2 class="text-2xl font-semibold text-rose">{m.rsvpHeading}</h2>
        <RsvpForm lang={lang} />
      </section>
    </main>
  )
}

export const homeRoute = new Hono().get("/", async (c) => {
  const lang = asLanguage(c.get("language"))
  return c.html(await renderPage(<HomePage lang={lang} messages={t(lang)} />, lang))
})
