import { describe, expect, test } from "bun:test"
import { asLanguage, supportedLanguages, t } from "./i18n"

describe("i18n", () => {
  test("supports es and en", () => {
    expect(supportedLanguages).toEqual(["es", "en"])
  })

  test("falls back to es", () => {
    expect(asLanguage(undefined)).toBe("es")
    expect(asLanguage("fr")).toBe("es")
  })

  test("accepts en", () => {
    expect(asLanguage("en")).toBe("en")
  })

  test("both dictionaries expose the same keys", () => {
    expect(Object.keys(t("es")).sort()).toEqual(Object.keys(t("en")).sort())
  })

  test("t returns the requested dictionary", () => {
    expect(t("es").caseFileHeading).toBe("El Misterio")
    expect(t("en").caseFileHeading).toBe("The Mystery")
  })
})
