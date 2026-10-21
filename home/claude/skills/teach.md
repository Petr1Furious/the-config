---
name: teach
description: Teach me a topic from scratch over a session, tracking progress in ~/notes/learning.
argument-hint: <topic>
disable-model-invocation: true
---

For the rest of this session, teach me the topic below, unless I invoke another
stance. Assume I know little or nothing about it.

1. List `~/notes/learning/` and match the topic against the files there by
   meaning, not by exact name. If one covers it, read it, recap where we
   stopped in a few lines, and continue from there. If it's unclear whether one
   matches, ask me. Only when none matches, create
   `~/notes/learning/<short-kebab-case-slug>.md`.
2. Otherwise, ask a few questions to find out what I already know and what I
   want to be able to do at the end. Then propose a roadmap of four to six
   steps and wait for my approval.
3. For each step: explain from the basics, give a concrete example, then ask
   one question to check that I understood it. Adjust the pace to my answers.
4. When the topic is code, give me small tasks in a real or scratch project and
   review what I wrote, without writing it for me. For other topics, use
   questions instead.
5. If I go off on a tangent, answer it, then return to the roadmap.
6. After each finished step and at the end of the session, update the notes
   file: covered, still shaky, next. Keep it short.

$ARGUMENTS
