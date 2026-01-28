import Foundation

/// Extracts declared outputs from Claude's response text
public struct OutputExtractor {
    public init() {}

    /// Extract outputs from a Claude response based on declared output names
    /// - Parameters:
    ///   - response: The raw text response from Claude
    ///   - declaredOutputs: The list of output names to extract
    /// - Returns: A dictionary of output name to extracted value
    public func extract(from response: String, declaredOutputs: [String]?) -> [String: String] {
        guard let outputs = declaredOutputs, !outputs.isEmpty else {
            return [:]
        }

        var results: [String: String] = [:]

        // Try multiple extraction strategies
        for output in outputs {
            if let value = extractStructuredOutput(output, from: response) {
                results[output] = value
            } else if let value = extractTaggedOutput(output, from: response) {
                results[output] = value
            } else if let value = extractKeyValueOutput(output, from: response) {
                results[output] = value
            } else if let value = extractInlineOutput(output, from: response) {
                results[output] = value
            }
        }

        return results
    }

    /// Extract output from structured format like <output name="key">value</output>
    private func extractStructuredOutput(_ name: String, from response: String) -> String? {
        // Pattern: <output name="outputName">value</output>
        let pattern = #"<output\s+name\s*=\s*["']\#(name)["']\s*>(.*?)</output>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }

        let range = NSRange(response.startIndex..., in: response)
        guard let match = regex.firstMatch(in: response, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: response) else {
            return nil
        }

        return String(response[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract output from simple tagged format like <key>value</key>
    private func extractTaggedOutput(_ name: String, from response: String) -> String? {
        // Pattern: <outputName>value</outputName>
        let pattern = #"<\#(name)>(.*?)</\#(name)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }

        let range = NSRange(response.startIndex..., in: response)
        guard let match = regex.firstMatch(in: response, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: response) else {
            return nil
        }

        return String(response[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract output from key-value format like "key: value" or "**key**: value"
    private func extractKeyValueOutput(_ name: String, from response: String) -> String? {
        // Try various key-value patterns
        let patterns = [
            // **key**: value
            #"\*\*\#(name)\*\*\s*:\s*(.+?)(?:\n|$)"#,
            // key: value
            #"(?:^|\n)\#(name)\s*:\s*(.+?)(?:\n|$)"#,
            // - key: value
            #"[-•]\s*\#(name)\s*:\s*(.+?)(?:\n|$)"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            let range = NSRange(response.startIndex..., in: response)
            guard let match = regex.firstMatch(in: response, options: [], range: range),
                  let valueRange = Range(match.range(at: 1), in: response) else {
                continue
            }

            let value = String(response[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }

        return nil
    }

    /// Extract output from inline mentions like "the result is X"
    private func extractInlineOutput(_ name: String, from response: String) -> String? {
        // Look for patterns like "the [name] is X" or "[name] = X"
        let patterns = [
            // the name is value
            #"the\s+\#(name)\s+is\s+[`"']?(.+?)[`"']?(?:\.|,|\n|$)"#,
            // name = value
            #"\#(name)\s*=\s*[`"']?(.+?)[`"']?(?:\.|,|\n|$)"#,
            // name: `value`
            #"\#(name):\s*`(.+?)`"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            let range = NSRange(response.startIndex..., in: response)
            guard let match = regex.firstMatch(in: response, options: [], range: range),
                  let valueRange = Range(match.range(at: 1), in: response) else {
                continue
            }

            let value = String(response[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty && value.count < 500 {  // Sanity check on length
                return value
            }
        }

        return nil
    }

    /// Extract all outputs from a JSON block in the response
    public func extractFromJSON(_ response: String) -> [String: String]? {
        // Look for JSON blocks
        let patterns = [
            #"```json\s*\n(.*?)\n```"#,
            #"\{[^{}]*"outputs"[^{}]*\}"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
                continue
            }

            let range = NSRange(response.startIndex..., in: response)
            guard let match = regex.firstMatch(in: response, options: [], range: range),
                  let jsonRange = Range(match.range(at: match.numberOfRanges > 1 ? 1 : 0), in: response) else {
                continue
            }

            let jsonStr = String(response[jsonRange])

            // Try to parse as JSON
            guard let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                continue
            }

            // Look for an "outputs" key or treat the whole thing as outputs
            if let outputs = json["outputs"] as? [String: Any] {
                return outputs.compactMapValues { value -> String? in
                    if let str = value as? String { return str }
                    if let num = value as? NSNumber { return num.stringValue }
                    if let bool = value as? Bool { return bool ? "true" : "false" }
                    return nil
                }
            }

            // Try to convert all string values
            return json.compactMapValues { value -> String? in
                if let str = value as? String { return str }
                if let num = value as? NSNumber { return num.stringValue }
                if let bool = value as? Bool { return bool ? "true" : "false" }
                return nil
            }
        }

        return nil
    }
}

// MARK: - Output Prompt Injection

public extension OutputExtractor {
    /// Generate prompt text instructing Claude how to format outputs
    static func outputInstructions(for outputs: [String]) -> String {
        guard !outputs.isEmpty else { return "" }

        let outputList = outputs.map { "- \($0)" }.joined(separator: "\n")

        return """

            IMPORTANT: At the end of your response, provide the following outputs in this exact format:

            \(outputs.map { "<\($0)>your value here</\($0)>" }.joined(separator: "\n"))

            Required outputs:
            \(outputList)
            """
    }
}
