Bioinformatician <- new_class("Bioinformatician",
properties = list(
  name = class_character,
  favourite_language = class_character
))



Developer <- new_class("Developer",
properties = list(
  name = class_character,
  favourite_language = class_character
))




Bailey <- Bioinformatician("Bailey", favourite_language = "python")
Ian <- Developer("Ian", favourite_language = "python")

Bailey@name <- "Bailey Francis"
Bailey@favourite_language




Language <- new_generic("Language", "x")

method(Language, Bioinformatician) <- function(x) {
  cat("Bioinformatician", x@name, "is working on a project.\n")
}

method(Language, Developer) <- function(x) {
  cat("Developers like all languages except the one they are told to do the project in\n")
}


Language(Ian)
Language(Bailey)