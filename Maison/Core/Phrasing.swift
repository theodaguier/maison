import Foundation

/// Small helpers for writing sentences the way people do, rather than the way data is stored.
enum Phrasing {
    static var isFrench: Bool { Locale.current.language.languageCode == .french }

    /// "8 h 12" in French, "8:12 AM" in English.
    static func time(_ date: Date) -> String {
        let text = date.formatted(date: .omitted, time: .shortened)
        guard isFrench else { return text }
        let parts = text.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]) else { return text }
        return "\(hour) h \(parts[1])"
    }

    /// "15 h" in French, "3 PM" in English.
    static func hour(_ date: Date) -> String {
        guard isFrench else { return date.formatted(.dateTime.hour()) }
        return "\(Calendar.current.component(.hour, from: date))\u{00A0}h"
    }

    /// "Three" for small counts, digits beyond ten, capitalized to open a sentence.
    static func count(_ value: Int, capitalized: Bool = false) -> String {
        guard (0...10).contains(value) else { return value.formatted() }
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = .current
        let word = formatter.string(from: value as NSNumber) ?? value.formatted()
        return capitalized ? word.prefix(1).localizedUppercase + word.dropFirst() : word
    }

    /// "La porte d’entrée", "Le thermostat", "L’entrée" in French; the name as-is otherwise
    /// or when its gender can't be guessed from the first word.
    static func subject(_ name: String) -> String {
        guard isFrench, let article = frenchArticle(for: name) else { return name }
        return article.capitalizedFirst + lowercasedFirst(name)
    }

    /// The same, inside a sentence: "la porte d’entrée", "les volets du salon".
    static func object(_ name: String) -> String {
        guard isFrench, let article = frenchArticle(for: name) else { return name }
        return article + lowercasedFirst(name)
    }

    /// Where something is: "au salon", "dans la cuisine", "dans l’entrée" in French; "in Salon" otherwise.
    static func location(_ room: String) -> String {
        guard isFrench else { return String(localized: "in \(room)") }
        switch frenchArticle(for: room) {
        case "le "?: return "au " + lowercasedFirst(room)
        case "les "?: return "aux " + lowercasedFirst(room)
        case let article?: return "dans " + article + lowercasedFirst(room)
        case nil: return "dans « \(room) »"
        }
    }

    /// Makes a French state agree with the device: "Allumée" for "Prise café", "Ouverts" for "Volets du salon".
    /// Other languages, and names whose gender can't be guessed, keep the label as it is.
    static func agree(_ label: String, with name: String) -> String {
        guard isFrench, let article = frenchArticle(for: name) else { return label }
        let masculine = agreeing.first { $0 == label || $0 + "e" == label }
        guard let masculine else { return label }
        let isFeminine = article == "la " || (article != "le " && isFeminineNoun(name))
        let isPlural = article == "les "
        return masculine + (isFeminine ? "e" : "") + (isPlural ? "s" : "")
    }

    /// Past participles and adjectives used as device states, in their masculine singular form.
    private static let agreeing = ["Allumé", "Éteint", "Ouvert", "Fermé", "Verrouillé", "Déverrouillé", "Bloqué", "Détecté"]

    private static func isFeminineNoun(_ name: String) -> Bool {
        let first = firstWord(name)
        return feminine.contains(first) || feminine.contains(String(first.dropLast()))
    }

    private static func firstWord(_ name: String) -> String {
        name.split(whereSeparator: { $0 == " " || $0 == "’" || $0 == "'" }).first.map { $0.lowercased() } ?? ""
    }

    // MARK: French articles

    private static let feminine: Set<String> = [
        "porte", "serrure", "cuisine", "chambre", "salle", "buanderie", "cave", "terrasse", "véranda", "mezzanine",
        "pièce", "maison", "lampe", "lumière", "prise", "fenêtre", "baie", "suspension", "applique", "guirlande", "enceinte",
        "télé", "télévision", "box", "alarme", "caméra", "sonnette", "bibliothèque", "douche", "baignoire", "piscine",
    ]
    private static let masculine: Set<String> = [
        "salon", "appartement", "studio", "étage", "rez-de-chaussée", "bureau", "garage", "couloir", "cellier", "grenier", "sous-sol", "jardin", "dressing", "séjour",
        "hall", "palier", "portail", "verrou", "volet", "volets", "store", "stores", "lampadaire", "plafonnier",
        "bandeau", "thermostat", "climatiseur", "chauffage", "radiateur", "ventilateur", "spot", "spots", "balcon",
        "grille-pain", "frigo", "réfrigérateur", "four", "lave-linge", "sèche-linge", "lave-vaisselle", "capteur",
        "détecteur", "chauffe-eau", "purificateur", "aspirateur", "rideau", "rideaux",
    ]

    private static func frenchArticle(for name: String) -> String? {
        let first = firstWord(name)
        let startsWithVowel = first.first.map { "aeiouyàâéèêëîïôûüh".contains($0) } ?? false
        let plural = first.hasSuffix("s") && !["box", "bus"].contains(first) && first != "sous-sol"
        if feminine.contains(first) || masculine.contains(first) || feminine.contains(String(first.dropLast())) || masculine.contains(String(first.dropLast())) {
            if plural { return "les " }
            if startsWithVowel { return "l’" }
            return feminine.contains(first) || feminine.contains(String(first.dropLast())) ? "la " : "le "
        }
        return nil
    }

    private static func lowercasedFirst(_ text: String) -> String {
        text.prefix(1).lowercased() + text.dropFirst()
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
