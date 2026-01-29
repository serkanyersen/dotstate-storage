---
name: Gemini-Large-Codebase-Analysis
description: Use this skill when you need to analyze large codebases, multiple files totaling over 100KB, entire project directories, or when your current context window is insufficient for the analysis task. Invoke Gemini CLI to leverage its massive context window for comprehensive codebase analysis, architecture review, implementation verification, and cross-file pattern searching.
---

# Gemini CLI for Large Codebase Analysis

When analyzing large codebases or multiple files that might exceed context limits, use the Gemini CLI with its massive context window.

## When to Use Gemini CLI

Use `gemini` when:
- Analyzing entire codebases or large directories
- Comparing multiple large files
- Need to understand project-wide patterns or architecture
- Current context window is insufficient for the task
- Working with files totaling more than 100KB
- Verifying if specific features, patterns, or security measures are implemented
- Checking for the presence of certain coding patterns across the entire codebase
- Need comprehensive analysis that would require reading many files

## Basic Syntax

```bash
gemini "Your prompt here @path/to/file_or_directory"
```

The `@` syntax includes files and directories in your Gemini prompts. Paths are relative to the current working directory.

## File and Directory Inclusion Examples

**Single file analysis:**
```bash
gemini "@src/main.py Explain this file's purpose and structure"
```

**Multiple files:**
```bash
gemini "@package.json @src/index.js Analyze the dependencies used in the code"
```

**Entire directory:**
```bash
gemini "@src/ Summarize the architecture of this codebase"
```

**Multiple directories:**
```bash
gemini "@src/ @tests/ Analyze test coverage for the source code"
```

**Current directory and all subdirectories:**
```bash
gemini "@./ Give me an overview of this entire project"
```

**Using --all_files flag:**
```bash
gemini --all_files "Analyze the project structure and dependencies"
```

## Implementation Verification Examples

**Check if a feature is implemented:**
```bash
gemini "@src/ @lib/ Has dark mode been implemented in this codebase? Show me the relevant files and functions"
```

**Verify authentication implementation:**
```bash
gemini "@src/ @middleware/ Is JWT authentication implemented? List all auth-related endpoints and middleware"
```

**Check for specific patterns:**
```bash
gemini "@src/ Are there any React hooks that handle WebSocket connections? List them with file paths"
```

**Verify error handling:**
```bash
gemini "@src/ @api/ Is proper error handling implemented for all API endpoints? Show examples of try-catch blocks"
```

**Check for rate limiting:**
```bash
gemini "@backend/ @middleware/ Is rate limiting implemented for the API? Show the implementation details"
```

**Verify caching strategy:**
```bash
gemini "@src/ @lib/ @services/ Is Redis caching implemented? List all cache-related functions and their usage"
```

**Check for security measures:**
```bash
gemini "@src/ @api/ Are SQL injection protections implemented? Show how user inputs are sanitized"
```

**Verify test coverage for features:**
```bash
gemini "@src/payment/ @tests/ Is the payment processing module fully tested? List all test cases"
```

## Architecture Analysis Examples

**Get project overview:**
```bash
gemini "@./ Provide a high-level architecture overview including main components, data flow, and dependencies"
```

**Analyze dependencies:**
```bash
gemini "@package.json @Cargo.toml @requirements.txt List all dependencies and their purposes"
```

**Find dead code:**
```bash
gemini "@src/ Identify any functions or modules that appear to be unused"
```

**Review API design:**
```bash
gemini "@src/api/ @src/routes/ Document all API endpoints with their methods, parameters, and return types"
```

## Important Notes

- Paths in `@` syntax are relative to your current working directory when invoking gemini
- The CLI includes file contents directly in the context
- No need for `--yolo` flag for read-only analysis
- Gemini's context window can handle entire codebases that would overflow Claude's context
- When checking implementations, be specific about what you're looking for to get accurate results
- Output is returned directly - pipe to a file if you need to save it

## Practical Workflow

1. **Identify context-heavy tasks** - If you need to analyze more than a few files or understand project-wide patterns
2. **Formulate specific questions** - Clear, targeted prompts yield better results
3. **Use appropriate scope** - Start with specific directories before expanding to entire codebase
4. **Capture results** - Use the output to inform your local work in Claude Code
