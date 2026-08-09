import { serveStatic } from "hono/bun"
import { languageDetector } from "hono/language"
import { Hono } from "hono"
import { h, type VNode } from "preact"
import { renderToStringAsync } from "preact-render-to-string"
import { Document } from "./components/Document"
import { supportedLanguages, type Language } from "./lib/i18n"
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
  const html = await renderToStringAsync(h(Document, { lang }, page))
  return `<!doctype html>${html}`
}

export default app
