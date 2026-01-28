"""Extract declared outputs from Claude responses."""

from __future__ import annotations

import json
import re


class OutputExtractor:
    """Extracts declared outputs from Claude's response text."""

    def extract(
        self,
        response: str,
        declared_outputs: list[str] | None,
    ) -> dict[str, str]:
        """Extract outputs from a Claude response.

        Args:
            response: The raw text response from Claude
            declared_outputs: The list of output names to extract

        Returns:
            Dictionary of output name to extracted value
        """
        if not declared_outputs:
            return {}

        results: dict[str, str] = {}

        # Try multiple extraction strategies
        for output in declared_outputs:
            value = (
                self._extract_structured_output(output, response)
                or self._extract_tagged_output(output, response)
                or self._extract_key_value_output(output, response)
                or self._extract_inline_output(output, response)
            )
            if value:
                results[output] = value

        return results

    def _extract_structured_output(self, name: str, response: str) -> str | None:
        """Extract output from structured format like <output name="key">value</output>."""
        pattern = rf'<output\s+name\s*=\s*["\']?{re.escape(name)}["\']?\s*>(.*?)</output>'
        match = re.search(pattern, response, re.IGNORECASE | re.DOTALL)
        if match:
            return match.group(1).strip()
        return None

    def _extract_tagged_output(self, name: str, response: str) -> str | None:
        """Extract output from simple tagged format like <key>value</key>."""
        pattern = rf'<{re.escape(name)}>(.*?)</{re.escape(name)}>'
        match = re.search(pattern, response, re.IGNORECASE | re.DOTALL)
        if match:
            return match.group(1).strip()
        return None

    def _extract_key_value_output(self, name: str, response: str) -> str | None:
        """Extract output from key-value format like 'key: value' or '**key**: value'."""
        patterns = [
            # **key**: value
            rf'\*\*{re.escape(name)}\*\*\s*:\s*(.+?)(?:\n|$)',
            # key: value (at start of line)
            rf'(?:^|\n){re.escape(name)}\s*:\s*(.+?)(?:\n|$)',
            # - key: value
            rf'[-•]\s*{re.escape(name)}\s*:\s*(.+?)(?:\n|$)',
        ]

        for pattern in patterns:
            match = re.search(pattern, response, re.IGNORECASE)
            if match:
                value = match.group(1).strip()
                if value:
                    return value

        return None

    def _extract_inline_output(self, name: str, response: str) -> str | None:
        """Extract output from inline mentions like 'the result is X'."""
        patterns = [
            # the name is value
            rf'the\s+{re.escape(name)}\s+is\s+[`"\']?(.+?)[`"\']?(?:\.|,|\n|$)',
            # name = value
            rf'{re.escape(name)}\s*=\s*[`"\']?(.+?)[`"\']?(?:\.|,|\n|$)',
            # name: `value`
            rf'{re.escape(name)}:\s*`(.+?)`',
        ]

        for pattern in patterns:
            match = re.search(pattern, response, re.IGNORECASE)
            if match:
                value = match.group(1).strip()
                # Sanity check on length
                if value and len(value) < 500:
                    return value

        return None

    def extract_from_json(self, response: str) -> dict[str, str] | None:
        """Extract all outputs from a JSON block in the response."""
        # Look for JSON blocks
        patterns = [
            r'```json\s*\n(.*?)\n```',
            r'\{[^{}]*"outputs"[^{}]*\}',
        ]

        for pattern in patterns:
            match = re.search(pattern, response, re.DOTALL)
            if not match:
                continue

            json_str = match.group(1) if match.lastindex else match.group(0)

            try:
                data = json.loads(json_str)

                # Look for an "outputs" key or treat the whole thing as outputs
                outputs = data.get("outputs", data) if isinstance(data, dict) else None
                if not isinstance(outputs, dict):
                    continue

                # Convert values to strings
                return {
                    k: str(v) if v is not None else ""
                    for k, v in outputs.items()
                }
            except json.JSONDecodeError:
                continue

        return None

    @staticmethod
    def output_instructions(outputs: list[str]) -> str:
        """Generate prompt text instructing Claude how to format outputs."""
        if not outputs:
            return ""

        output_tags = "\n".join(f"<{o}>your value here</{o}>" for o in outputs)
        output_list = "\n".join(f"- {o}" for o in outputs)

        return f"""

IMPORTANT: At the end of your response, provide the following outputs in this exact format:

{output_tags}

Required outputs:
{output_list}
"""
