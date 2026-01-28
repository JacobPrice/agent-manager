"""Base class for LLM providers."""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass
class ProviderConfig:
    """Configuration for an LLM provider."""

    working_directory: Path
    allowed_tools: list[str] = field(default_factory=list)
    max_turns: int = 10
    max_budget_usd: float = 1.0
    context: str = ""
    permission_mode: str | None = None  # "acceptEdits", "bypassPermissions", etc.
    model: str | None = None  # "opus", "sonnet", "haiku", or full model ID


@dataclass
class LLMResponse:
    """Response from an LLM provider."""

    success: bool
    result: str
    input_tokens: int | None = None
    output_tokens: int | None = None
    cost: float | None = None
    raw_output: str | None = None
    error: str | None = None
    session_id: str | None = None  # For session continuation
    metadata: dict[str, Any] = field(default_factory=dict)

    @property
    def total_tokens(self) -> int | None:
        """Total tokens used."""
        if self.input_tokens is not None and self.output_tokens is not None:
            return self.input_tokens + self.output_tokens
        return None


class LLMProvider(ABC):
    """Abstract base class for LLM providers.

    Implement this class to add support for new LLM backends:
    - ClaudeCLIProvider: Shells out to `claude` CLI (current)
    - AnthropicSDKProvider: Direct API calls via Anthropic SDK (future)
    - OllamaProvider: Local models via Ollama (future)
    - OpenAIProvider: OpenAI API (future)
    """

    @property
    @abstractmethod
    def name(self) -> str:
        """Name of this provider."""
        ...

    @abstractmethod
    async def execute(
        self,
        prompt: str,
        config: ProviderConfig,
        log_file: Path | None = None,
    ) -> LLMResponse:
        """Execute a prompt and return the response.

        Args:
            prompt: The prompt to send to the LLM
            config: Configuration for this execution
            log_file: Optional file to write logs to

        Returns:
            LLMResponse with the result
        """
        ...

    @abstractmethod
    def execute_sync(
        self,
        prompt: str,
        config: ProviderConfig,
        log_file: Path | None = None,
    ) -> LLMResponse:
        """Synchronous version of execute.

        For providers that don't support async natively.
        """
        ...

    def validate_config(self, config: ProviderConfig) -> list[str]:
        """Validate configuration. Returns list of error messages."""
        errors = []

        if config.max_turns < 1:
            errors.append("max_turns must be at least 1")

        if config.max_budget_usd <= 0:
            errors.append("max_budget_usd must be positive")

        return errors
