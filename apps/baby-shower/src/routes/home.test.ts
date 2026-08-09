import { describe, expect, test } from "bun:test"
import app from "../main"

describe("home route", () => {
  test("GET / renders the case file in Spanish by default", async () => {
    const res = await app.request("/")
    expect(res.status).toBe(200)
    const html = await res.text()
    expect(html.startsWith("<!doctype html>")).toBe(true)
    expect(html).toContain('<html lang="es">')
    expect(html).toContain("El Misterio")
    expect(html).toContain('<preact-island src="RsvpForm"')
    expect(html).toContain("/static/global.css")
    expect(html).toContain("/static/islands.js")
  })

  test("GET /?lang=en renders in English", async () => {
    const res = await app.request("/?lang=en")
    expect(res.status).toBe(200)
    const html = await res.text()
    expect(html).toContain('<html lang="en">')
    expect(html).toContain("The Mystery")
    expect(html).toContain('<preact-island src="RsvpForm"')
  })
})
