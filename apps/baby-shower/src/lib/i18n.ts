export const supportedLanguages = ["es", "en"] as const

export type Language = (typeof supportedLanguages)[number]

const es = {
  pageTitle: "El Misterio · Baby Shower",
  caseFileHeading: "El Misterio",
  caseFileIntro:
    "Solo tres personas en el mundo conocen el sexo del bebé, y los futuros padres no están entre ellas. Ayúdanos a resolverlo.",
  languageToggleLabel: "Idioma",
  rsvpHeading: "Confirma tu asistencia",
  nameLabel: "Tu nombre",
  attendingYes: "Asistiré",
  attendingNo: "No podré asistir",
  plusOneLabel: "Traigo un plus-one",
  plusOneNameLabel: "Nombre de tu plus-one (opcional)",
  theoryLabel: "Tu teoría (opcional)",
  theoryGirl: "Niña",
  theoryBoy: "Niño",
  submitLabel: "Enviar RSVP",
  submittedMessage: "RSVP recibido. Gracias.",
  errorMessage: "Algo salió mal. Intenta de nuevo.",
}

export type Messages = typeof es

const en: Messages = {
  pageTitle: "The Mystery · Baby Shower",
  caseFileHeading: "The Mystery",
  caseFileIntro:
    "Only three people in the world know the baby's sex, and the parents-to-be are not among them. Help us solve it.",
  languageToggleLabel: "Language",
  rsvpHeading: "Confirm your attendance",
  nameLabel: "Your name",
  attendingYes: "I will attend",
  attendingNo: "I cannot make it",
  plusOneLabel: "I am bringing a plus-one",
  plusOneNameLabel: "Your plus-one's name (optional)",
  theoryLabel: "Your theory (optional)",
  theoryGirl: "Girl",
  theoryBoy: "Boy",
  submitLabel: "Send RSVP",
  submittedMessage: "RSVP received. Thank you.",
  errorMessage: "Something went wrong. Try again.",
}

const dictionaries: Record<Language, Messages> = { es, en }

export function asLanguage(lang: string | undefined): Language {
  return lang === "en" ? "en" : "es"
}

export function t(lang: Language): Messages {
  return dictionaries[lang]
}
