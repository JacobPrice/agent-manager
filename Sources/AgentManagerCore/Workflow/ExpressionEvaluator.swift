import Foundation

/// Evaluates GitHub Actions-style expressions like ${{ jobs.lint.outputs.has_errors == 'true' }}
public struct ExpressionEvaluator {
    /// The context available for expression evaluation
    public struct Context {
        /// Job outputs keyed by "jobs.{jobName}.outputs.{outputName}"
        public var jobOutputs: [String: [String: String]]

        /// Job statuses keyed by "jobs.{jobName}.status"
        public var jobStatuses: [String: String]

        /// Workflow-level variables
        public var variables: [String: String]

        public init(
            jobOutputs: [String: [String: String]] = [:],
            jobStatuses: [String: String] = [:],
            variables: [String: String] = [:]
        ) {
            self.jobOutputs = jobOutputs
            self.jobStatuses = jobStatuses
            self.variables = variables
        }

        /// Set outputs for a job
        public mutating func setOutputs(job: String, outputs: [String: String]) {
            jobOutputs[job] = outputs
        }

        /// Set status for a job
        public mutating func setStatus(job: String, status: String) {
            jobStatuses[job] = status
        }

        /// Resolve a variable path like "jobs.lint.outputs.has_errors"
        func resolve(_ path: String) -> String? {
            let parts = path.components(separatedBy: ".")

            // Handle jobs.X.outputs.Y pattern
            if parts.count == 4, parts[0] == "jobs", parts[2] == "outputs" {
                let jobName = parts[1]
                let outputName = parts[3]
                return jobOutputs[jobName]?[outputName]
            }

            // Handle jobs.X.status pattern
            if parts.count == 3, parts[0] == "jobs", parts[2] == "status" {
                let jobName = parts[1]
                return jobStatuses[jobName]
            }

            // Handle simple variable
            return variables[path]
        }
    }

    public init() {}

    /// Evaluate an expression string and return the result as a boolean
    /// - Parameters:
    ///   - expression: The expression to evaluate, may include ${{ }} wrapper
    ///   - context: The context containing variable values
    /// - Returns: The boolean result of the expression
    public func evaluate(_ expression: String, context: Context) throws -> Bool {
        let trimmed = extractExpression(expression)

        // Handle empty expression (defaults to true)
        if trimmed.isEmpty {
            return true
        }

        // Parse and evaluate the expression
        return try evaluateExpression(trimmed, context: context)
    }

    /// Evaluate an expression and return its string value
    public func evaluateToString(_ expression: String, context: Context) throws -> String {
        let trimmed = extractExpression(expression)

        if trimmed.isEmpty {
            return ""
        }

        // If it's a simple variable reference, return its value
        if let value = context.resolve(trimmed) {
            return value
        }

        // Otherwise evaluate as expression and return string
        let result = try evaluateExpression(trimmed, context: context)
        return result ? "true" : "false"
    }

    /// Extract the expression from ${{ ... }} wrapper
    private func extractExpression(_ expression: String) -> String {
        var result = expression.trimmingCharacters(in: .whitespaces)

        // Remove ${{ and }} wrapper if present
        if result.hasPrefix("${{") && result.hasSuffix("}}") {
            result = String(result.dropFirst(3).dropLast(2))
        }

        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Evaluate a parsed expression
    private func evaluateExpression(_ expression: String, context: Context) throws -> Bool {
        let trimmed = expression.trimmingCharacters(in: .whitespaces)

        // Handle logical operators (&&, ||)
        if let result = try evaluateLogicalOr(trimmed, context: context) {
            return result
        }

        throw ExpressionError.invalidExpression(expression)
    }

    /// Evaluate || expressions
    private func evaluateLogicalOr(_ expression: String, context: Context) throws -> Bool? {
        // Split by || but be careful not to split inside quotes
        let parts = splitByOperator(expression, operator: "||")

        if parts.count > 1 {
            for part in parts {
                if let result = try evaluateLogicalAnd(part.trimmingCharacters(in: .whitespaces), context: context) {
                    if result {
                        return true
                    }
                }
            }
            return false
        }

        return try evaluateLogicalAnd(expression, context: context)
    }

    /// Evaluate && expressions
    private func evaluateLogicalAnd(_ expression: String, context: Context) throws -> Bool? {
        let parts = splitByOperator(expression, operator: "&&")

        if parts.count > 1 {
            for part in parts {
                if let result = try evaluateComparison(part.trimmingCharacters(in: .whitespaces), context: context) {
                    if !result {
                        return false
                    }
                } else {
                    return false
                }
            }
            return true
        }

        return try evaluateComparison(expression, context: context)
    }

    /// Evaluate comparison expressions (==, !=, <, >, <=, >=)
    private func evaluateComparison(_ expression: String, context: Context) throws -> Bool? {
        // Try each comparison operator
        let operators = ["==", "!=", "<=", ">=", "<", ">"]

        for op in operators {
            if let range = expression.range(of: op) {
                let left = String(expression[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let right = String(expression[range.upperBound...]).trimmingCharacters(in: .whitespaces)

                let leftValue = resolveValue(left, context: context)
                let rightValue = resolveValue(right, context: context)

                return compare(leftValue, op: op, rightValue)
            }
        }

        // Handle negation
        if expression.hasPrefix("!") {
            let inner = String(expression.dropFirst()).trimmingCharacters(in: .whitespaces)
            if let result = try evaluatePrimary(inner, context: context) {
                return !result
            }
        }

        return try evaluatePrimary(expression, context: context)
    }

    /// Evaluate primary expressions (literals, variables, function calls)
    private func evaluatePrimary(_ expression: String, context: Context) throws -> Bool? {
        let trimmed = expression.trimmingCharacters(in: .whitespaces)

        // Handle parentheses
        if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") {
            let inner = String(trimmed.dropFirst().dropLast())
            return try evaluateExpression(inner, context: context)
        }

        // Handle boolean literals
        if trimmed == "true" {
            return true
        }
        if trimmed == "false" {
            return false
        }

        // Handle success() function - checks if all previous jobs succeeded
        if trimmed == "success()" {
            return context.jobStatuses.values.allSatisfy { $0 == "completed" || $0 == "skipped" }
        }

        // Handle failure() function - checks if any previous job failed
        if trimmed == "failure()" {
            return context.jobStatuses.values.contains { $0 == "failed" }
        }

        // Handle always() function - always returns true
        if trimmed == "always()" {
            return true
        }

        // Handle cancelled() function - checks if workflow was cancelled
        if trimmed == "cancelled()" {
            return context.jobStatuses.values.contains { $0 == "cancelled" }
        }

        // Handle variable reference - truthy check
        if let value = context.resolve(trimmed) {
            return isTruthy(value)
        }

        // If we can't parse it, it's an error
        return nil
    }

    /// Resolve a value (variable or literal)
    private func resolveValue(_ value: String, context: Context) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)

        // Handle quoted strings
        if (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) ||
           (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) {
            return String(trimmed.dropFirst().dropLast())
        }

        // Handle variable reference
        if let resolved = context.resolve(trimmed) {
            return resolved
        }

        // Return as literal
        return trimmed
    }

    /// Compare two values with an operator
    private func compare(_ left: String, op: String, _ right: String) -> Bool {
        switch op {
        case "==":
            return left == right
        case "!=":
            return left != right
        case "<":
            if let l = Double(left), let r = Double(right) {
                return l < r
            }
            return left < right
        case ">":
            if let l = Double(left), let r = Double(right) {
                return l > r
            }
            return left > right
        case "<=":
            if let l = Double(left), let r = Double(right) {
                return l <= r
            }
            return left <= right
        case ">=":
            if let l = Double(left), let r = Double(right) {
                return l >= r
            }
            return left >= right
        default:
            return false
        }
    }

    /// Check if a value is truthy
    private func isTruthy(_ value: String) -> Bool {
        let lower = value.lowercased()
        if lower == "false" || lower == "0" || lower.isEmpty || lower == "null" || lower == "none" {
            return false
        }
        return true
    }

    /// Split expression by operator, respecting quotes
    private func splitByOperator(_ expression: String, operator op: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var inQuote: Character? = nil
        var i = expression.startIndex

        while i < expression.endIndex {
            let char = expression[i]

            // Handle quotes
            if char == "'" || char == "\"" {
                if inQuote == char {
                    inQuote = nil
                } else if inQuote == nil {
                    inQuote = char
                }
                current.append(char)
                i = expression.index(after: i)
                continue
            }

            // Check for operator (only if not in quotes)
            if inQuote == nil {
                let remaining = expression[i...]
                if remaining.hasPrefix(op) {
                    parts.append(current)
                    current = ""
                    i = expression.index(i, offsetBy: op.count)
                    continue
                }
            }

            current.append(char)
            i = expression.index(after: i)
        }

        if !current.isEmpty {
            parts.append(current)
        }

        return parts
    }
}

// MARK: - Expression Errors

public enum ExpressionError: Error, LocalizedError {
    case invalidExpression(String)
    case undefinedVariable(String)
    case typeMismatch(String)

    public var errorDescription: String? {
        switch self {
        case .invalidExpression(let expr):
            return "Invalid expression: \(expr)"
        case .undefinedVariable(let name):
            return "Undefined variable: \(name)"
        case .typeMismatch(let message):
            return "Type mismatch: \(message)"
        }
    }
}

// MARK: - Expression Interpolation

public extension ExpressionEvaluator {
    /// Interpolate expressions in a string, replacing ${{ ... }} with evaluated values
    func interpolate(_ text: String, context: Context) throws -> String {
        var result = text
        let pattern = #"\$\{\{\s*([^}]+)\s*\}\}"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        // Process matches in reverse order to preserve indices
        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: text),
                  let exprRange = Range(match.range(at: 1), in: text) else {
                continue
            }

            let expression = String(text[exprRange])
            let value = try evaluateToString(expression, context: context)
            result.replaceSubrange(matchRange, with: value)
        }

        return result
    }
}
