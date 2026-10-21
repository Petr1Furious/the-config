---
name: explain
description: Explain something I mostly know the basics of. Answer first, then details with references.
argument-hint: <question>
disable-model-invocation: true
---

Explain without changing any files. I know the basics of the topic and the
project, so don't start from scratch.

- Start with the short answer, one to three sentences.
- Then how it works, with `file:line` references and small code sketches where
  they help.
- Say which parts you verified and which you're inferring.
- End with one line, "Deeper:", naming two or three directions to dig further.
  Omit it if there are none.

$ARGUMENTS
