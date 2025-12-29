//
//  XMLTVParser.swift
//  Rivulet
//
//  Parses XMLTV format EPG (Electronic Program Guide) data
//

import Foundation

/// Actor for parsing XMLTV EPG data
actor XMLTVParser {

    // MARK: - Parsed Types

    /// Represents a channel from XMLTV
    struct ParsedXMLTVChannel: Sendable {
        let id: String
        let displayName: String
        let iconURL: String?
    }

    /// Represents a program from XMLTV
    struct ParsedProgram: Sendable {
        let channelId: String
        let start: Date
        let stop: Date
        let title: String
        let subtitle: String?
        let description: String?
        let category: String?
        let icon: String?
        let episodeNum: String?
        let isNew: Bool
    }

    // MARK: - Parse Result

    struct ParseResult: Sendable {
        let channels: [String: ParsedXMLTVChannel]  // id -> channel
        let programs: [String: [ParsedProgram]]      // channelId -> programs
    }

    // MARK: - Public Methods

    /// Parse XMLTV data from a URL
    func parse(from url: URL) async throws -> ParseResult {
        let (data, response) = try await URLSession.shared.data(from: url)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw XMLTVParseError.httpError(httpResponse.statusCode)
        }

        return try await parse(data: data)
    }

    /// Parse XMLTV data from raw data
    func parse(data: Data) async throws -> ParseResult {
        // XMLParser and its delegate require main actor
        try await MainActor.run {
            let parser = XMLTVInternalParser()
            return try parser.parse(data: data)
        }
    }

    /// Get programs for a specific channel within a time range
    func getPrograms(
        from result: ParseResult,
        channelId: String,
        startDate: Date,
        endDate: Date
    ) -> [ParsedProgram] {
        guard let programs = result.programs[channelId] else {
            return []
        }

        return programs.filter { program in
            // Include if program overlaps with the time range
            program.stop > startDate && program.start < endDate
        }
    }
}

// MARK: - XMLTV Internal Parser (XMLParserDelegate)

private class XMLTVInternalParser: NSObject, XMLParserDelegate {
    private var channels: [String: XMLTVParser.ParsedXMLTVChannel] = [:]
    private var programs: [String: [XMLTVParser.ParsedProgram]] = [:]

    // Current parsing state
    private var currentElement: String = ""
    private var currentChannelId: String?
    private var currentDisplayName: String = ""
    private var currentIconURL: String?

    // Program parsing state
    private var currentProgramChannelId: String?
    private var currentProgramStart: Date?
    private var currentProgramStop: Date?
    private var currentTitle: String = ""
    private var currentSubtitle: String = ""
    private var currentDescription: String = ""
    private var currentCategory: String = ""
    private var currentProgramIcon: String?
    private var currentEpisodeNum: String = ""
    private var currentIsNew: Bool = false

    private var parseError: Error?

    // Date formatter for XMLTV dates (yyyyMMddHHmmss +0000)
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss Z"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // Alternative date format without timezone
    private let dateFormatterNoTZ: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    func parse(data: Data) throws -> XMLTVParser.ParseResult {
        let parser = XMLParser(data: data)
        parser.delegate = self

        if !parser.parse() {
            if let error = parseError {
                throw error
            }
            throw XMLTVParseError.parseFailed
        }

        return XMLTVParser.ParseResult(channels: channels, programs: programs)
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName

        switch elementName {
        case "channel":
            currentChannelId = attributeDict["id"]
            currentDisplayName = ""
            currentIconURL = nil

        case "programme":
            currentProgramChannelId = attributeDict["channel"]
            currentProgramStart = parseDate(attributeDict["start"])
            currentProgramStop = parseDate(attributeDict["stop"])
            currentTitle = ""
            currentSubtitle = ""
            currentDescription = ""
            currentCategory = ""
            currentProgramIcon = nil
            currentEpisodeNum = ""
            currentIsNew = false

        case "icon":
            let src = attributeDict["src"]
            if currentChannelId != nil {
                currentIconURL = src
            } else if currentProgramChannelId != nil {
                currentProgramIcon = src
            }

        case "new":
            currentIsNew = true

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch currentElement {
        case "display-name":
            currentDisplayName += trimmed
        case "title":
            currentTitle += trimmed
        case "sub-title":
            currentSubtitle += trimmed
        case "desc":
            currentDescription += trimmed
        case "category":
            if !currentCategory.isEmpty {
                currentCategory += ", "
            }
            currentCategory += trimmed
        case "episode-num":
            currentEpisodeNum += trimmed
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "channel":
            if let id = currentChannelId, !currentDisplayName.isEmpty {
                channels[id] = XMLTVParser.ParsedXMLTVChannel(
                    id: id,
                    displayName: currentDisplayName,
                    iconURL: currentIconURL
                )
            }
            currentChannelId = nil

        case "programme":
            if let channelId = currentProgramChannelId,
               let start = currentProgramStart,
               let stop = currentProgramStop,
               !currentTitle.isEmpty {
                let program = XMLTVParser.ParsedProgram(
                    channelId: channelId,
                    start: start,
                    stop: stop,
                    title: currentTitle,
                    subtitle: currentSubtitle.isEmpty ? nil : currentSubtitle,
                    description: currentDescription.isEmpty ? nil : currentDescription,
                    category: currentCategory.isEmpty ? nil : currentCategory,
                    icon: currentProgramIcon,
                    episodeNum: currentEpisodeNum.isEmpty ? nil : currentEpisodeNum,
                    isNew: currentIsNew
                )

                if programs[channelId] == nil {
                    programs[channelId] = []
                }
                programs[channelId]?.append(program)
            }
            currentProgramChannelId = nil

        default:
            break
        }

        currentElement = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }

    // MARK: - Helpers

    private func parseDate(_ string: String?) -> Date? {
        guard let string = string else { return nil }

        // Try with timezone first
        if let date = dateFormatter.date(from: string) {
            return date
        }

        // Try without timezone (first 14 characters)
        let cleanString = String(string.prefix(14))
        return dateFormatterNoTZ.date(from: cleanString)
    }
}

// MARK: - Errors

enum XMLTVParseError: LocalizedError {
    case httpError(Int)
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .httpError(let code):
            return "HTTP error \(code)"
        case .parseFailed:
            return "Failed to parse XMLTV data"
        }
    }
}

// MARK: - Convenience Extensions

extension XMLTVParser.ParsedProgram {
    /// Convert to UnifiedProgram
    func toUnifiedProgram(unifiedChannelId: String) -> UnifiedProgram {
        // Create unique ID from channel and start time
        let id = "\(unifiedChannelId):\(Int(start.timeIntervalSince1970))"

        return UnifiedProgram(
            id: id,
            channelId: unifiedChannelId,
            title: title,
            subtitle: subtitle,
            description: description,
            startTime: start,
            endTime: stop,
            category: category,
            iconURL: icon.flatMap { URL(string: $0) },
            episodeNumber: episodeNum,
            isNew: isNew
        )
    }
}
