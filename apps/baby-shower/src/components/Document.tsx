import type { ComponentChildren } from "preact"
import { t, type Language } from "../lib/i18n"

type DocumentProps = {
  lang: Language
  children?: ComponentChildren
}

export function Document({ lang, children }: DocumentProps) {
  return (
    <html lang={lang}>
      <head>
        <meta charSet="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{t(lang).pageTitle}</title>
        <link rel="stylesheet" href="/static/global.css" />
        <script type="module" src="/static/islands.js"></script>
      </head>
      <body>{children}</body>
    </html>
  )
}
