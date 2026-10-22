---
name: browser
description: Rules for driving the persistent browser through the playwright MCP server. Load before the first playwright tool call.
---

You run in a sandbox container. The `playwright` MCP server attaches over CDP
to a persistent, headed Chromium in a sibling container. Tabs, cookies and
logins outlive your session.

- `$NOVNC_URL` is where the user watches and controls the same window.
- `/files` is the only directory both you and the browser see. Downloads land
  in `/files/downloads`. To upload a file, copy it under `/files` first and
  pass that path.
- You can't restart the browser yourself. If it's wedged, ask the user to
  restart its container. It comes back with the profile intact, and the user
  has to press Connect in noVNC again.

## Working in it

- Leave the browser logged in. Never sign out, clear cookies or wipe the
  profile: those logins were set up by hand and some are painful to redo.
- Close tabs you opened; leave tabs you did not.
- When a captcha, a login form or a 2FA prompt blocks you, stop and ask the
  user to solve it at `$NOVNC_URL`, then continue in the same tab. Don't try
  to defeat the check, and don't silently give up on the task.
- The browser's traffic leaves through a tailnet exit node on the user's home
  connection, not the server's datacenter IP. Sites geolocate accordingly.
- Snapshots, screenshots and console logs go to `/work/output`. Put page dumps
  or notes you save yourself there too. What is already there is from earlier
  sessions, not documentation: ignore it, and don't delete it unless asked.
