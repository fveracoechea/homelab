import { serveStatic } from "hono/bun"
import { languageDetector } from "hono/language"
import { Hono } from "hono"
import type { VNode } from "preact"
import { renderToStringAsync } from "preact-render-to-string"
import { supportedLanguages, t, type Language } from "./lib/i18n"
import { homeRoute } from "./routes/home"
import { rsvpRoute } from "./routes/rsvp"

const app = new Hono()

app.use(
  languageDetector({
    supportedLanguages: [...supportedLanguages],
    fallbackLanguage: "es",
  }),
)

app.use("/static/*", serveStatic({ root: "./" }))

app.route("/", homeRoute)
app.route("/", rsvpRoute)

export async function renderPage(page: VNode, lang: Language): Promise<string> {
  const body = await renderToStringAsync(page)
  return `<!doctype html>
<html lang="${lang}">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${t(lang).pageTitle}</title>
    <link rel="stylesheet" href="/static/global.css" />
    <script type="module" src="/static/islands.js"></script>
  </head>
  <body>${body}</body>
</html>`
}

export default app
