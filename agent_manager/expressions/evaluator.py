"""Expression evaluator for GitHub Actions-style expressions."""

from __future__ import annotations

import re
from dataclasses import dataclass, field


class ExpressionError(Exception):
    """Error evaluating an expression."""

    pass


@dataclass
class ExpressionContext:
    """Context for expression evaluation."""

    # Job outputs keyed by job name
    job_outputs: dict[str, dict[str, str]] = field(default_factory=dict)

    # Job statuses keyed by job name
    job_statuses: dict[str, str] = field(default_factory=dict)

    # Step outputs keyed by step name (for within-job step evaluation)
    step_outputs: dict[str, dict[str, str]] = field(default_factory=dict)

    # Step statuses keyed by step name
    step_statuses: dict[str, str] = field(default_factory=dict)

    # Workflow-level variables
    variables: dict[str, str] = field(default_factory=dict)

    # Current job context (for ${{ job.output_dir }} etc.)
    current_job: dict[str, str] = field(default_factory=dict)

    def set_outputs(self, job: str, outputs: dict[str, str]) -> None:
        """Set outputs for a job."""
        self.job_outputs[job] = outputs

    def set_status(self, job: str, status: str) -> None:
        """Set status for a job."""
        self.job_statuses[job] = status

    def set_step_outputs(self, step: str, outputs: dict[str, str]) -> None:
        """Set outputs for a step."""
        self.step_outputs[step] = outputs

    def set_step_status(self, step: str, status: str) -> None:
        """Set status for a step."""
        self.step_statuses[step] = status

    def clear_steps(self) -> None:
        """Clear step context (when starting a new job)."""
        self.step_outputs.clear()
        self.step_statuses.clear()

    def set_current_job(self, output_dir: str) -> None:
        """Set the current job context."""
        self.current_job = {"output_dir": output_dir}

    def clear_current_job(self) -> None:
        """Clear the current job context."""
        self.current_job.clear()

    def resolve(self, path: str) -> str | None:
        """Resolve a variable path like 'jobs.lint.outputs.has_errors'."""
        parts = path.split(".")

        # Handle job.X pattern (current job context, e.g., job.output_dir)
        if len(parts) == 2 and parts[0] == "job":
            key = parts[1]
            return self.current_job.get(key)

        # Handle jobs.X.outputs.Y pattern
        if len(parts) == 4 and parts[0] == "jobs" and parts[2] == "outputs":
            job_name = parts[1]
            output_name = parts[3]
            return self.job_outputs.get(job_name, {}).get(output_name)

        # Handle jobs.X.status pattern
        if len(parts) == 3 and parts[0] == "jobs" and parts[2] == "status":
            job_name = parts[1]
            return self.job_statuses.get(job_name)

        # Handle steps.X.outputs.Y pattern (for within-job step references)
        if len(parts) == 4 and parts[0] == "steps" and parts[2] == "outputs":
            step_name = parts[1]
            output_name = parts[3]
            return self.step_outputs.get(step_name, {}).get(output_name)

        # Handle steps.X.status pattern
        if len(parts) == 3 and parts[0] == "steps" and parts[2] == "status":
            step_name = parts[1]
            return self.step_statuses.get(step_name)

        # Handle simple variable
        return self.variables.get(path)


class ExpressionEvaluator:
    """Evaluates GitHub Actions-style expressions.

    Supports:
    - Variable references: jobs.lint.outputs.has_errors
    - Comparisons: ==, !=, <, >, <=, >=
    - Logical operators: &&, ||, !
    - Functions: success(), failure(), always(), cancelled()
    - String literals: 'value' or "value"
    """

    def evaluate(self, expression: str, context: ExpressionContext) -> bool:
        """Evaluate an expression string and return boolean result."""
        expr = self._extract_expression(expression)

        if not expr:
            return True  # Empty expression defaults to true

        return self._evaluate_logical_or(expr, context)

    def evaluate_to_string(self, expression: str, context: ExpressionContext) -> str:
        """Evaluate an expression and return its string value."""
        expr = self._extract_expression(expression)

        if not expr:
            return ""

        # If it's a simple variable reference, return its value
        value = context.resolve(expr)
        if value is not None:
            return value

        # Otherwise evaluate as expression and return string
        result = self._evaluate_logical_or(expr, context)
        return "true" if result else "false"

    def interpolate(self, text: str, context: ExpressionContext) -> str:
        """Interpolate expressions in a string, replacing ${{ ... }} with values."""
        pattern = r"\$\{\{\s*([^}]+)\s*\}\}"

        def replace(match: re.Match[str]) -> str:
            expr = match.group(1).strip()
            return self.evaluate_to_string(expr, context)

        return re.sub(pattern, replace, text)

    def _extract_expression(self, expression: str) -> str:
        """Extract the expression from ${{ ... }} wrapper."""
        expr = expression.strip()

        # Remove ${{ and }} wrapper if present
        if expr.startswith("${{") and expr.endswith("}}"):
            expr = expr[3:-2]

        return expr.strip()

    def _evaluate_logical_or(self, expression: str, context: ExpressionContext) -> bool:
        """Evaluate || expressions."""
        parts = self._split_by_operator(expression, "||")

        if len(parts) > 1:
            return any(self._evaluate_logical_and(p.strip(), context) for p in parts)

        return self._evaluate_logical_and(expression, context)

    def _evaluate_logical_and(self, expression: str, context: ExpressionContext) -> bool:
        """Evaluate && expressions."""
        parts = self._split_by_operator(expression, "&&")

        if len(parts) > 1:
            return all(self._evaluate_comparison(p.strip(), context) for p in parts)

        return self._evaluate_comparison(expression, context)

    def _evaluate_comparison(self, expression: str, context: ExpressionContext) -> bool:
        """Evaluate comparison expressions."""
        operators = ["==", "!=", "<=", ">=", "<", ">"]

        for op in operators:
            if op in expression:
                idx = expression.find(op)
                left = expression[:idx].strip()
                right = expression[idx + len(op):].strip()

                left_value = self._resolve_value(left, context)
                right_value = self._resolve_value(right, context)

                return self._compare(left_value, op, right_value)

        # Handle negation
        if expression.startswith("!"):
            inner = expression[1:].strip()
            return not self._evaluate_primary(inner, context)

        return self._evaluate_primary(expression, context)

    def _evaluate_primary(self, expression: str, context: ExpressionContext) -> bool:
        """Evaluate primary expressions (literals, variables, functions)."""
        expr = expression.strip()

        # Handle parentheses
        if expr.startswith("(") and expr.endswith(")"):
            return self._evaluate_logical_or(expr[1:-1], context)

        # Handle boolean literals
        if expr.lower() == "true":
            return True
        if expr.lower() == "false":
            return False

        # Handle built-in functions
        if expr == "success()":
            return all(
                s in ("completed", "skipped")
                for s in context.job_statuses.values()
            )

        if expr == "failure()":
            return any(s == "failed" for s in context.job_statuses.values())

        if expr == "always()":
            return True

        if expr == "cancelled()":
            return any(s == "cancelled" for s in context.job_statuses.values())

        # Handle variable reference - truthy check
        value = context.resolve(expr)
        if value is not None:
            return self._is_truthy(value)

        # Unknown expression - default to false
        return False

    def _resolve_value(self, value: str, context: ExpressionContext) -> str:
        """Resolve a value (variable or literal)."""
        value = value.strip()

        # Handle quoted strings
        if (value.startswith("'") and value.endswith("'")) or \
           (value.startswith('"') and value.endswith('"')):
            return value[1:-1]

        # Handle variable reference
        resolved = context.resolve(value)
        if resolved is not None:
            return resolved

        # Return as literal
        return value

    def _compare(self, left: str, op: str, right: str) -> bool:
        """Compare two values with an operator."""
        if op == "==":
            return left == right
        if op == "!=":
            return left != right

        # Try numeric comparison
        try:
            left_num = float(left)
            right_num = float(right)

            if op == "<":
                return left_num < right_num
            if op == ">":
                return left_num > right_num
            if op == "<=":
                return left_num <= right_num
            if op == ">=":
                return left_num >= right_num
        except ValueError:
            # Fall back to string comparison
            if op == "<":
                return left < right
            if op == ">":
                return left > right
            if op == "<=":
                return left <= right
            if op == ">=":
                return left >= right

        return False

    def _is_truthy(self, value: str) -> bool:
        """Check if a value is truthy."""
        lower = value.lower()
        return lower not in ("false", "0", "", "null", "none")

    def _split_by_operator(self, expression: str, operator: str) -> list[str]:
        """Split expression by operator, respecting quotes."""
        parts: list[str] = []
        current = ""
        in_quote: str | None = None
        i = 0

        while i < len(expression):
            char = expression[i]

            # Handle quotes
            if char in ("'", '"'):
                if in_quote == char:
                    in_quote = None
                elif in_quote is None:
                    in_quote = char
                current += char
                i += 1
                continue

            # Check for operator (only if not in quotes)
            if in_quote is None and expression[i:].startswith(operator):
                parts.append(current)
                current = ""
                i += len(operator)
                continue

            current += char
            i += 1

        if current:
            parts.append(current)

        return parts
