import { useState } from "preact/hooks"
import { hc } from "hono/client"
import { asLanguage, t, type Language } from "../lib/i18n"
import { island } from "../lib/preact-islands"
import type { RsvpRoute } from "../routes/rsvp"

type RsvpFormProps = {
  lang?: Language
}

function RsvpForm({ lang }: RsvpFormProps) {
  const resolvedLang =
    lang ?? asLanguage(typeof document === "undefined" ? undefined : document.documentElement.lang)
  const m = t(resolvedLang)
  const [status, setStatus] = useState<"idle" | "submitting" | "done" | "error">("idle")

  async function handleSubmit(event: Event) {
    event.preventDefault()
    const data = new FormData(event.currentTarget as HTMLFormElement)
    setStatus("submitting")
    try {
      const client = hc<RsvpRoute>("/")
      const res = await client.api.rsvp.$post({
        json: {
          name: String(data.get("name") ?? ""),
          attending: data.get("attending") === "yes",
          plusOne: data.get("plusOne") === "on",
          plusOneName: String(data.get("plusOneName") ?? "").trim() || undefined,
          theory: (data.get("theory") as "girl" | "boy" | null) ?? undefined,
        },
      })
      setStatus(res.ok ? "done" : "error")
    } catch {
      setStatus("error")
    }
  }

  if (status === "done") {
    return <p class="text-foam">{m.submittedMessage}</p>
  }

  return (
    <form onSubmit={handleSubmit} class="flex flex-col gap-4">
      <label class="flex flex-col gap-1">
        <span>{m.nameLabel}</span>
        <input name="name" required class="border border-overlay bg-base px-2 py-1" />
      </label>

      <fieldset class="flex gap-4">
        <label class="flex items-center gap-2">
          <input type="radio" name="attending" value="yes" checked />
          <span>{m.attendingYes}</span>
        </label>
        <label class="flex items-center gap-2">
          <input type="radio" name="attending" value="no" />
          <span>{m.attendingNo}</span>
        </label>
      </fieldset>

      <label class="flex items-center gap-2">
        <input type="checkbox" name="plusOne" />
        <span>{m.plusOneLabel}</span>
      </label>

      <label class="flex flex-col gap-1">
        <span>{m.plusOneNameLabel}</span>
        <input name="plusOneName" class="border border-overlay bg-base px-2 py-1" />
      </label>

      <fieldset class="flex gap-4">
        <legend class="text-subtle">{m.theoryLabel}</legend>
        <label class="flex items-center gap-2">
          <input type="radio" name="theory" value="girl" />
          <span>{m.theoryGirl}</span>
        </label>
        <label class="flex items-center gap-2">
          <input type="radio" name="theory" value="boy" />
          <span>{m.theoryBoy}</span>
        </label>
      </fieldset>

      <button type="submit" disabled={status === "submitting"} class="bg-iris px-4 py-2 text-base">
        {m.submitLabel}
      </button>

      {status === "error" && (
        <p role="alert" class="text-rose">
          {m.errorMessage}
        </p>
      )}
    </form>
  )
}

export default island(RsvpForm, "RsvpForm")
