import { afterAll, afterEach, describe, expect, test } from "bun:test"
import "../happydom"
import { GlobalRegistrator } from "@happy-dom/global-registrator"
import { cleanup, fireEvent, render, waitFor } from "@testing-library/preact"
import RsvpForm from "./RsvpForm"
import { registerIslands } from "../lib/preact-islands"
import app from "../main"

const registeredFetch = globalThis.fetch

afterEach(() => {
  cleanup()
  document.body.innerHTML = ""
  globalThis.fetch = registeredFetch
})

afterAll(async () => {
  await GlobalRegistrator.unregister()
})

function stubFetchThroughApp() {
  const calls: { url: string; body: unknown }[] = []
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    calls.push({ url: String(input), body: init?.body ? JSON.parse(String(init.body)) : undefined })
    return app.request(String(input), init)
  }) as typeof fetch
  return calls
}

describe("RsvpForm island", () => {
  test("submits the rsvp through the hono rpc client", async () => {
    const calls = stubFetchThroughApp()
    const { container, findByText, getByLabelText, getByRole } = render(<RsvpForm lang="en" />)

    fireEvent.input(getByLabelText("Your name"), { target: { value: "Ada Lovelace" } })
    fireEvent.click(getByRole("radio", { name: "I cannot make it" }))
    fireEvent.click(getByRole("checkbox", { name: "I am bringing a plus-one" }))
    fireEvent.input(getByLabelText("Your plus-one's name (optional)"), {
      target: { value: "Grace" },
    })
    fireEvent.click(getByRole("radio", { name: "Girl" }))

    fireEvent.submit(container.querySelector("form")!)

    await findByText("RSVP received. Thank you.")
    expect(calls).toHaveLength(1)
    expect(calls[0].url).toBe("/api/rsvp")
    expect(calls[0].body).toEqual({
      name: "Ada Lovelace",
      attending: false,
      plusOne: true,
      plusOneName: "Grace",
      theory: "girl",
    })
  })

  test("shows an error when the rsvp is rejected", async () => {
    stubFetchThroughApp()
    const { container, findByRole } = render(<RsvpForm lang="en" />)

    fireEvent.submit(container.querySelector("form")!)

    const alert = await findByRole("alert")
    expect(alert.textContent).toBe("Something went wrong. Try again.")
  })

  test("hydrates preact-island custom elements", async () => {
    registerIslands()
    document.body.innerHTML = `<preact-island src="RsvpForm"></preact-island>`
    const element = document.querySelector("preact-island")!

    await waitFor(() => {
      expect(element.querySelector("button")?.textContent).toBe("Enviar RSVP")
    })
  })
})
